#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'
umask 077

readonly SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
readonly REPO_ROOT="$(cd -- "${SCRIPT_DIR}/.." && pwd -P)"
readonly LOCK_FILE="${REPO_ROOT}/flake.lock"
readonly PACKAGE_FILE="${REPO_ROOT}/packages/orca-ide/default.nix"
readonly ORCA_UPDATER="${SCRIPT_DIR}/update-orca-ide.sh"

MODE=""
JSON=false
ORCA_VERSION=""
ORCA_DIGEST=""
TMP_DIR=""
LOCK_STAGE=""
TRANSACTION_ACTIVE=false
LOCK_PUBLISHED=false
PACKAGE_PUBLISHED=false
LOCK_PUBLISHED_SHA=""
PACKAGE_PUBLISHED_SHA=""
LOCK_BACKUP=""
PACKAGE_BACKUP=""

usage() {
  cat <<'EOF'
Usage:
  scripts/update-pins.sh --check [--json]
  scripts/update-pins.sh --apply [--json]
  scripts/update-pins.sh --apply --orca-version VERSION \
    --orca-asset-digest sha256:<64-lowercase-hex> [--json]
EOF
}

log() { printf 'update-pins: %s\n' "$*" >&2; }
die() { log "error: $*"; exit 1; }

sha256_file() {
  local digest
  digest="$(sha256sum -- "$1")"
  printf '%s\n' "${digest%% *}"
}

restore_if_unchanged() {
  local destination="$1"
  local backup="$2"
  local published_sha="$3"
  local label="$4"
  [[ -f "${destination}" && "$(sha256_file "${destination}")" == "${published_sha}" ]] || {
    log "rollback conflict: ${label} changed concurrently; it was not overwritten"
    return 1
  }
  local rollback
  rollback="$(mktemp "${destination}.rollback.XXXXXX")"
  cp --preserve=mode -- "${backup}" "${rollback}"
  mv -f -- "${rollback}" "${destination}"
}

cleanup() {
  local status=$?
  trap - EXIT
  if ((status != 0)) && [[ "${TRANSACTION_ACTIVE}" == true ]]; then
    log "rolling back known transaction files"
    if [[ "${LOCK_PUBLISHED}" == true ]]; then
      restore_if_unchanged "${LOCK_FILE}" "${LOCK_BACKUP}" "${LOCK_PUBLISHED_SHA}" "flake.lock" || true
    fi
    if [[ "${PACKAGE_PUBLISHED}" == true ]]; then
      restore_if_unchanged "${PACKAGE_FILE}" "${PACKAGE_BACKUP}" "${PACKAGE_PUBLISHED_SHA}" "Orca package" || true
    fi
  fi
  [[ -z "${LOCK_STAGE}" || ! -e "${LOCK_STAGE}" ]] || rm -f -- "${LOCK_STAGE}"
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
    --orca-version)
      [[ $# -ge 2 && -z "${ORCA_VERSION}" ]] || die "--orca-version requires one value"
      ORCA_VERSION="$2"
      shift 2
      ;;
    --orca-asset-digest)
      [[ $# -ge 2 && -z "${ORCA_DIGEST}" ]] || die "--orca-asset-digest requires one value"
      ORCA_DIGEST="$2"
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
[[ -z "${ORCA_VERSION}" && -z "${ORCA_DIGEST}" ]] || \
  [[ -n "${ORCA_VERSION}" && -n "${ORCA_DIGEST}" ]] || \
  die "--orca-version and --orca-asset-digest are all-or-nothing"
if [[ -n "${ORCA_VERSION}" ]]; then
  [[ "${MODE}" == apply ]] || die "reviewed Orca arguments require --apply"
  [[ "${ORCA_VERSION}" =~ ^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$ ]] || die "malformed Orca version"
  [[ "${ORCA_DIGEST}" =~ ^sha256:[0-9a-f]{64}$ ]] || die "malformed Orca asset digest"
fi

[[ -f "${REPO_ROOT}/flake.nix" && -f "${LOCK_FILE}" && -f "${PACKAGE_FILE}" ]] || die "repository root detection failed"
[[ -x "${ORCA_UPDATER}" ]] || die "Orca updater is not executable: ${ORCA_UPDATER}"
for command_name in cmp git jq mktemp nix sha256sum; do
  command -v "${command_name}" >/dev/null 2>&1 || die "required command not found: ${command_name}"
done

require_clean_tree() {
  local status
  status="$(git -C "${REPO_ROOT}" status --porcelain=v1 --untracked-files=all)"
  [[ -z "${status}" ]] || die "an exactly clean worktree is required"
}

expected_status() {
  local expect_package="$1"
  local status
  status="$(git -C "${REPO_ROOT}" status --porcelain=v1 --untracked-files=all)"
  if [[ "${expect_package}" == true ]]; then
    [[ "${status}" == " M packages/orca-ide/default.nix" ]]
  else
    [[ -z "${status}" ]]
  fi
}

validate_diff_set() {
  local expect_lock="$1"
  local expect_package="$2"
  local -a actual=()
  local path saw_lock=false saw_package=false
  mapfile -t actual < <(git -C "${REPO_ROOT}" diff --name-only --)
  [[ -z "$(git -C "${REPO_ROOT}" ls-files --others --exclude-standard)" ]] || die "unexpected untracked files appeared"
  for path in "${actual[@]}"; do
    case "${path}" in
      flake.lock) saw_lock=true ;;
      packages/orca-ide/default.nix) saw_package=true ;;
      *) die "unexpected changed path: ${path}" ;;
    esac
  done
  [[ "${saw_lock}" == "${expect_lock}" ]] || die "flake.lock diff-set conflict"
  [[ "${saw_package}" == "${expect_package}" ]] || die "Orca package diff-set conflict"
}

require_clean_tree
lock_baseline_sha="$(sha256_file "${LOCK_FILE}")"
package_baseline_sha="$(sha256_file "${PACKAGE_FILE}")"
TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/update-pins.XXXXXX")"
LOCK_BACKUP="${TMP_DIR}/flake.lock.original"
PACKAGE_BACKUP="${TMP_DIR}/default.nix.original"
lock_candidate="${TMP_DIR}/flake.lock.candidate"
flake_log="${TMP_DIR}/flake-update.log"
cp --preserve=mode -- "${LOCK_FILE}" "${LOCK_BACKUP}"
cp --preserve=mode -- "${PACKAGE_FILE}" "${PACKAGE_BACKUP}"

log "preparing a private flake.lock candidate"
if ! nix flake update --flake "${REPO_ROOT}" \
  --reference-lock-file "${LOCK_FILE}" \
  --output-lock-file "${lock_candidate}" >"${flake_log}" 2>&1; then
  while IFS= read -r line; do printf 'update-pins: nix: %s\n' "${line}" >&2; done <"${flake_log}"
  die "failed to prepare the flake.lock candidate"
fi
jq -e '.version == 7 and (.nodes | type == "object") and (.root | type == "string")' "${lock_candidate}" >/dev/null || die "invalid flake.lock candidate"
lock_changed=false
cmp -s -- "${LOCK_FILE}" "${lock_candidate}" || lock_changed=true

orca_check_json="$("${ORCA_UPDATER}" --check --json)"
jq -e '.schema == 1 and .mode == "check"' <<<"${orca_check_json}" >/dev/null || die "invalid Orca metadata-check output"

orca_requested=false
orca_changed=false
orca_apply_json='null'
[[ -z "${ORCA_VERSION}" ]] || orca_requested=true

if [[ "${MODE}" == apply ]]; then
  [[ "$(sha256_file "${LOCK_FILE}")" == "${lock_baseline_sha}" ]] || die "flake.lock changed while its candidate was prepared"
  [[ "$(sha256_file "${PACKAGE_FILE}")" == "${package_baseline_sha}" ]] || die "Orca package changed while candidates were prepared"
  require_clean_tree
  TRANSACTION_ACTIVE=true

  if [[ "${orca_requested}" == true ]]; then
    orca_apply_json="$("${ORCA_UPDATER}" --apply --version "${ORCA_VERSION}" \
      --asset-digest "${ORCA_DIGEST}" --json)"
    PACKAGE_PUBLISHED_SHA="$(sha256_file "${PACKAGE_FILE}")"
    [[ "${PACKAGE_PUBLISHED_SHA}" != "${package_baseline_sha}" ]] || die "focused Orca update did not change the package"
    PACKAGE_PUBLISHED=true
    jq -e --arg version "${ORCA_VERSION}" --arg digest "${ORCA_DIGEST}" '
      .schema == 1 and .mode == "apply" and .changed == true and
      .candidate.version == $version and .candidate.api_digest == $digest
    ' <<<"${orca_apply_json}" >/dev/null || die "focused Orca update returned an unexpected result"
    orca_changed=true
  fi

  expected_status "${orca_changed}" || die "worktree changed before lock publication"
  [[ "$(sha256_file "${LOCK_FILE}")" == "${lock_baseline_sha}" ]] || die "flake.lock changed concurrently before publication"

  if [[ "${lock_changed}" == true ]]; then
    LOCK_STAGE="$(mktemp "${LOCK_FILE}.update.XXXXXX")"
    cp --preserve=mode -- "${lock_candidate}" "${LOCK_STAGE}"
    LOCK_PUBLISHED_SHA="$(sha256_file "${lock_candidate}")"
    mv -f -- "${LOCK_STAGE}" "${LOCK_FILE}"
    LOCK_STAGE=""
    LOCK_PUBLISHED=true
  fi

  jq -e '.version == 7 and (.nodes | type == "object")' "${LOCK_FILE}" >/dev/null
  validate_diff_set "${lock_changed}" "${orca_changed}"
  changed_paths=()
  [[ "${lock_changed}" == false ]] || changed_paths+=(flake.lock)
  [[ "${orca_changed}" == false ]] || changed_paths+=(packages/orca-ide/default.nix)
  if ((${#changed_paths[@]})); then git -C "${REPO_ROOT}" diff --check -- "${changed_paths[@]}"; fi
  TRANSACTION_ACTIVE=false
fi

changes_available="${lock_changed}"
[[ "$(jq -r '.available' <<<"${orca_check_json}")" == true ]] && changes_available=true
applied=false
if [[ "${MODE}" == apply && ( "${lock_changed}" == true || "${orca_changed}" == true ) ]]; then applied=true; fi

paths_json='[]'
if [[ "${MODE}" == apply ]]; then
  paths=()
  [[ "${lock_changed}" == false ]] || paths+=(flake.lock)
  [[ "${orca_changed}" == false ]] || paths+=(packages/orca-ide/default.nix)
  if ((${#paths[@]})); then paths_json="$(printf '%s\n' "${paths[@]}" | jq -R . | jq -s .)"; fi
fi

if [[ "${JSON}" == true ]]; then
  jq -n --arg mode "${MODE}" --argjson lock_changed "${lock_changed}" \
    --argjson orca_requested "${orca_requested}" --argjson orca_changed "${orca_changed}" \
    --argjson orca_check "${orca_check_json}" --argjson orca_apply "${orca_apply_json}" \
    --argjson changes_available "${changes_available}" --argjson applied "${applied}" \
    --argjson changed_paths "${paths_json}" '{
      schema: 1, mode: $mode,
      flake_lock: {changed: $lock_changed, candidate_was_private: true},
      orca: {requested: $orca_requested, changed: $orca_changed,
        check: $orca_check, apply: $orca_apply},
      changes_available: $changes_available, applied: $applied,
      changed_paths: $changed_paths
    }'
else
  printf 'Mode: %s\nFlake lock changed: %s\nOrca available: %s\nOrca requested: %s\nOrca changed: %s\nApplied: %s\nWarning: %s\n' \
    "${MODE}" "${lock_changed}" "$(jq -r '.available' <<<"${orca_check_json}")" \
    "${orca_requested}" "${orca_changed}" "${applied}" \
    "$(jq -r '.provenance_warning' <<<"${orca_check_json}")"
fi
