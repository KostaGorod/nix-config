#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'
umask 077

readonly SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
readonly REPO_ROOT="$(cd -- "${SCRIPT_DIR}/.." && pwd -P)"
readonly PACKAGE_FILE="${REPO_ROOT}/packages/orca-ide/default.nix"
readonly API_BASE="https://api.github.com/repos/stablyai/orca"
readonly ASSET_NAME="orca-linux.AppImage"
readonly WARNING="GitHub's API digest and the Nix fixed-output hash protect integrity and reproducibility; Orca release tags/assets are not independently authenticated by a publisher signature."

MODE=""
JSON=false
VERSION=""
SUPPLIED_DIGEST=""
TMP_DIR=""
STAGE_FILE=""
PUBLISHED=false
PUBLISHED_SHA=""
ORIGINAL_BACKUP=""

usage() {
  cat <<'EOF'
Usage:
  scripts/update-orca-ide.sh --check [--json]
  scripts/update-orca-ide.sh --apply --version VERSION \
    --asset-digest sha256:<64-lowercase-hex> [--json]
EOF
}

log() { printf 'update-orca-ide: %s\n' "$*" >&2; }
die() { log "error: $*"; exit 1; }

sha256_file() {
  local digest rest
  read -r digest rest < <(sha256sum -- "$1")
  printf '%s\n' "${digest}"
}

restore_original_if_safe() {
  [[ "${PUBLISHED}" == true ]] || return 0
  if [[ -f "${PACKAGE_FILE}" && "$(sha256_file "${PACKAGE_FILE}")" == "${PUBLISHED_SHA}" ]]; then
    local rollback
    rollback="$(mktemp "${PACKAGE_FILE}.rollback.XXXXXX")"
    cp --preserve=mode -- "${ORIGINAL_BACKUP}" "${rollback}"
    mv -f -- "${rollback}" "${PACKAGE_FILE}"
    log "restored the original package after failure"
  else
    log "rollback skipped: a concurrent writer changed ${PACKAGE_FILE}"
  fi
}

cleanup() {
  local status=$?
  trap - EXIT
  if ((status != 0)); then restore_original_if_safe; fi
  [[ -z "${STAGE_FILE}" || ! -e "${STAGE_FILE}" ]] || rm -f -- "${STAGE_FILE}"
  [[ -z "${TMP_DIR}" || ! -d "${TMP_DIR}" ]] || rm -rf -- "${TMP_DIR}"
  exit "${status}"
}
trap cleanup EXIT
trap 'exit 130' HUP INT TERM

while (($#)); do
  case "$1" in
    --check|--apply)
      [[ -z "${MODE}" ]] || die "choose exactly one mode"
      MODE="${1#--}"
      shift
      ;;
    --version)
      [[ $# -ge 2 && -z "${VERSION}" ]] || die "--version requires one value"
      VERSION="$2"
      shift 2
      ;;
    --asset-digest)
      [[ $# -ge 2 && -z "${SUPPLIED_DIGEST}" ]] || die "--asset-digest requires one value"
      SUPPLIED_DIGEST="$2"
      shift 2
      ;;
    --json)
      [[ "${JSON}" == false ]] || die "duplicate --json"
      JSON=true
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *) die "unrecognized argument: $1" ;;
  esac
done

[[ "${MODE}" == check || "${MODE}" == apply ]] || die "--check or --apply is required"
if [[ "${MODE}" == check ]]; then
  [[ -z "${VERSION}" && -z "${SUPPLIED_DIGEST}" ]] || die "--check accepts only --json"
else
  [[ -n "${VERSION}" && -n "${SUPPLIED_DIGEST}" ]] || die "--apply requires --version and --asset-digest"
  [[ "${VERSION}" =~ ^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$ ]] || die "malformed semantic version: ${VERSION}"
  [[ "${SUPPLIED_DIGEST}" =~ ^sha256:[0-9a-f]{64}$ ]] || die "malformed asset digest"
fi

[[ -f "${REPO_ROOT}/flake.nix" && -f "${PACKAGE_FILE}" ]] || die "repository root detection failed"
for command_name in curl git jq mktemp nix nix-instantiate sha256sum stat; do
  command -v "${command_name}" >/dev/null 2>&1 || die "required command not found: ${command_name}"
done

CURRENT_VERSION=""
CURRENT_HASH=""
read_current_package() {
  local line version_count=0 hash_count=0
  while IFS= read -r line || [[ -n "${line}" ]]; do
    if [[ "${line}" =~ ^[[:space:]]*version[[:space:]]*=[[:space:]]*\"([0-9]+\.[0-9]+\.[0-9]+)\"\;[[:space:]]*$ ]]; then
      CURRENT_VERSION="${BASH_REMATCH[1]}"
      ((version_count += 1))
    elif [[ "${line}" =~ ^[[:space:]]*hash[[:space:]]*=[[:space:]]*\"(sha256-[A-Za-z0-9+/=]+)\"\;[[:space:]]*$ ]]; then
      CURRENT_HASH="${BASH_REMATCH[1]}"
      ((hash_count += 1))
    fi
  done <"${PACKAGE_FILE}"
  [[ ${version_count} -eq 1 && ${hash_count} -eq 1 ]] || die "expected exactly one package version and source hash"
}
read_current_package

semver_gt() {
  local -a left right
  local index
  IFS=. read -r -a left <<<"$1"
  IFS=. read -r -a right <<<"$2"
  for index in 0 1 2; do
    if ((10#${left[index]} > 10#${right[index]})); then return 0; fi
    if ((10#${left[index]} < 10#${right[index]})); then return 1; fi
  done
  return 1
}

api_get() {
  local -a headers=(
    --header 'Accept: application/vnd.github+json'
    --header 'X-GitHub-Api-Version: 2022-11-28'
  )
  [[ -z "${GITHUB_TOKEN:-}" ]] || headers+=(--header "Authorization: Bearer ${GITHUB_TOKEN}")
  curl --proto '=https' --proto-redir '=https' --tlsv1.2 \
    --fail-with-body --silent --show-error --location --max-redirs 5 \
    --retry 3 --retry-all-errors "${headers[@]}" -- "$1"
}

validate_release() {
  local release_json="$1"
  local expected_tag="$2"
  local release_url="https://github.com/stablyai/orca/releases/tag/${expected_tag}"
  local asset_url="https://github.com/stablyai/orca/releases/download/${expected_tag}/${ASSET_NAME}"

  jq -e --arg tag "${expected_tag}" --arg release_url "${release_url}" \
    --arg asset "${ASSET_NAME}" --arg asset_url "${asset_url}" '
      .tag_name == $tag and .draft == false and .prerelease == false and
      .html_url == $release_url and
      ([.assets[] | select(.name == $asset and .state == "uploaded" and
        .browser_download_url == $asset_url)] | length) == 1
    ' <<<"${release_json}" >/dev/null || die "release/tag/asset identity validation failed"

  CANDIDATE_TAG="$(jq -er '.tag_name' <<<"${release_json}")"
  CANDIDATE_VERSION="${CANDIDATE_TAG#v}"
  RELEASE_URL="$(jq -er '.html_url' <<<"${release_json}")"
  ASSET_URL="$(jq -er --arg asset "${ASSET_NAME}" '.assets[] | select(.name == $asset) | .browser_download_url' <<<"${release_json}")"
  ASSET_SIZE="$(jq -er --arg asset "${ASSET_NAME}" '.assets[] | select(.name == $asset) | .size | select(type == "number" and . > 0)' <<<"${release_json}")"
  API_DIGEST="$(jq -er --arg asset "${ASSET_NAME}" '.assets[] | select(.name == $asset) | .digest | select(type == "string")' <<<"${release_json}")"
  [[ "${CANDIDATE_VERSION}" =~ ^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$ ]] || die "release tag is not stable semantic version"
  [[ "${API_DIGEST}" =~ ^sha256:[0-9a-f]{64}$ ]] || die "release asset lacks a valid API SHA-256 digest"
  NIX_SRI="$(nix hash convert --hash-algo sha256 --to sri "${API_DIGEST#sha256:}")"
}

if [[ "${MODE}" == check ]]; then
  release_json="$(api_get "${API_BASE}/releases/latest")"
  latest_tag="$(jq -er '.tag_name' <<<"${release_json}")"
  [[ "${latest_tag}" =~ ^v(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$ ]] || die "latest tag is not stable semantic version"
  validate_release "${release_json}" "${latest_tag}"
else
  validate_release "$(api_get "${API_BASE}/releases/tags/v${VERSION}")" "v${VERSION}"
  [[ "${API_DIGEST}" == "${SUPPLIED_DIGEST}" ]] || die "supplied digest does not match GitHub's API digest"
  semver_gt "${CANDIDATE_VERSION}" "${CURRENT_VERSION}" || die "same-version and downgrade updates are refused"
fi

AVAILABLE=false
semver_gt "${CANDIDATE_VERSION}" "${CURRENT_VERSION}" && AVAILABLE=true

emit_result() {
  local changed="$1"
  if [[ "${JSON}" == true ]]; then
    jq -n --arg mode "${MODE}" --arg current_version "${CURRENT_VERSION}" \
      --arg current_hash "${CURRENT_HASH}" --arg version "${CANDIDATE_VERSION}" \
      --arg tag "${CANDIDATE_TAG}" --arg release_url "${RELEASE_URL}" \
      --arg asset_url "${ASSET_URL}" --argjson asset_size "${ASSET_SIZE}" \
      --arg api_digest "${API_DIGEST}" --arg nix_sri "${NIX_SRI}" \
      --argjson available "${AVAILABLE}" --argjson changed "${changed}" \
      --arg warning "${WARNING}" '{
        schema: 1, mode: $mode,
        current: {version: $current_version, hash: $current_hash},
        candidate: {version: $version, tag: $tag, release_url: $release_url,
          asset_url: $asset_url, asset_size: $asset_size,
          api_digest: $api_digest, nix_sri: $nix_sri},
        available: $available, changed: $changed,
        provenance_warning: $warning
      }'
  else
    printf 'Current: %s (%s)\nCandidate: %s (%s)\nRelease: %s\nAsset: %s\nSize: %s\nDigest: %s\nNix SRI: %s\nAvailable: %s\nChanged: %s\nWarning: %s\n' \
      "${CURRENT_VERSION}" "${CURRENT_HASH}" "${CANDIDATE_VERSION}" "${CANDIDATE_TAG}" \
      "${RELEASE_URL}" "${ASSET_URL}" "${ASSET_SIZE}" "${API_DIGEST}" "${NIX_SRI}" \
      "${AVAILABLE}" "${changed}" "${WARNING}"
  fi
}

[[ "${MODE}" == apply ]] || { emit_result false; exit 0; }

status="$(git -C "${REPO_ROOT}" status --porcelain=v1 --untracked-files=all)"
[[ -z "${status}" ]] || die "--apply requires an exactly clean worktree"
package_baseline_sha="$(sha256_file "${PACKAGE_FILE}")"
TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/update-orca-ide.XXXXXX")"
ORIGINAL_BACKUP="${TMP_DIR}/default.nix.original"
asset_file="${TMP_DIR}/${ASSET_NAME}"
candidate_file="${TMP_DIR}/default.nix.candidate"
cp --preserve=mode -- "${PACKAGE_FILE}" "${ORIGINAL_BACKUP}"
install -m 0600 /dev/null "${asset_file}"

log "downloading the validated asset privately; it will not be executed"
curl --proto '=https' --proto-redir '=https' --tlsv1.2 --fail --silent --show-error \
  --location --max-redirs 5 --retry 3 --retry-all-errors --output "${asset_file}" -- "${ASSET_URL}"
chmod 0600 "${asset_file}"
[[ "$(stat --format='%s' "${asset_file}")" == "${ASSET_SIZE}" ]] || die "downloaded byte count does not match release metadata"
actual_hex="$(sha256_file "${asset_file}")"
[[ "sha256:${actual_hex}" == "${API_DIGEST}" && "sha256:${actual_hex}" == "${SUPPLIED_DIGEST}" ]] || die "downloaded SHA-256 does not match both trusted inputs"
[[ "$(nix hash convert --hash-algo sha256 --to sri "${actual_hex}")" == "${NIX_SRI}" ]] || die "derived SRI changed after download"

render_candidate() {
  local line version_count=0 hash_count=0
  while IFS= read -r line || [[ -n "${line}" ]]; do
    if [[ "${line}" =~ ^([[:space:]]*version[[:space:]]*=[[:space:]]*\")[0-9]+\.[0-9]+\.[0-9]+(\"\;[[:space:]]*)$ ]]; then
      printf '%s%s%s\n' "${BASH_REMATCH[1]}" "${CANDIDATE_VERSION}" "${BASH_REMATCH[2]}"
      ((version_count += 1))
    elif [[ "${line}" =~ ^([[:space:]]*hash[[:space:]]*=[[:space:]]*\")sha256-[A-Za-z0-9+/=]+(\"\;[[:space:]]*)$ ]]; then
      printf '%s%s%s\n' "${BASH_REMATCH[1]}" "${NIX_SRI}" "${BASH_REMATCH[2]}"
      ((hash_count += 1))
    else
      printf '%s\n' "${line}"
    fi
  done <"${PACKAGE_FILE}" >"${candidate_file}"
  [[ ${version_count} -eq 1 && ${hash_count} -eq 1 ]] || die "narrow version/hash rendering failed"
}
render_candidate
chmod --reference="${PACKAGE_FILE}" "${candidate_file}"
nix-instantiate --parse "${candidate_file}" >/dev/null

[[ "$(sha256_file "${PACKAGE_FILE}")" == "${package_baseline_sha}" ]] || die "package changed concurrently before publication"
[[ -z "$(git -C "${REPO_ROOT}" status --porcelain=v1 --untracked-files=all)" ]] || die "worktree changed concurrently before publication"
STAGE_FILE="$(mktemp "${PACKAGE_FILE}.update.XXXXXX")"
cp --preserve=mode -- "${candidate_file}" "${STAGE_FILE}"
PUBLISHED_SHA="$(sha256_file "${candidate_file}")"
mv -f -- "${STAGE_FILE}" "${PACKAGE_FILE}"
STAGE_FILE=""
PUBLISHED=true
nix-instantiate --parse "${PACKAGE_FILE}" >/dev/null
[[ "$(sha256_file "${PACKAGE_FILE}")" == "${PUBLISHED_SHA}" ]] || die "published package changed concurrently"
[[ "$(git -C "${REPO_ROOT}" status --porcelain=v1 --untracked-files=all)" == " M packages/orca-ide/default.nix" ]] || die "unexpected worktree changes after publication"
emit_result true
PUBLISHED=false
