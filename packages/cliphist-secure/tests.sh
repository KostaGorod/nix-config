#!/usr/bin/env bash
set -euo pipefail

fail() {
  printf 'test failure: %s\n' "$*" >&2
  exit 1
}

assert_file_mode() {
  local expected="$1"
  local path="$2"
  local actual

  actual="$(stat -c '%a' -- "$path")"
  [[ "$actual" == "$expected" ]] || fail "$path has mode $actual, expected $expected"
}

work="$PWD/test-work"
rm -rf -- "$work"
mkdir -p -- "$work/bin" "$work/home" "$work/runtime" "$work/state"

export HOME="$work/home"
export XDG_RUNTIME_DIR="$work/runtime"
export XDG_STATE_HOME="$work/state"
export TEST_ROOT="$work"
export TEST_LOG="$work/backend-args"
export TEST_STDIN="$work/backend-stdin"
export TEST_ENV="$work/backend-env"
export TEST_KEY="$work/keyring-secret"

cat >"$work/bin/cliphist" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >>"$TEST_LOG"
printf '%s\n' "${CLIPHIST_DB_PATH:-unset}" >"$TEST_ENV"
cat >"$TEST_STDIN"
EOF

cat >"$work/bin/mountpoint" <<'EOF'
#!/usr/bin/env bash
[[ -e "$XDG_RUNTIME_DIR/.cliphist-mounted" ]]
EOF

cat >"$work/bin/systemctl" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
[[ "${FAIL_SYSTEMCTL:-0}" != 1 ]] || exit 1
touch "$XDG_RUNTIME_DIR/.cliphist-mounted"
EOF

cat >"$work/bin/secret-tool" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
case "$1" in
  lookup)
    [[ -f "$TEST_KEY" ]] || exit 1
    cat "$TEST_KEY"
    ;;
  store)
    cat >"$TEST_KEY"
    ;;
  *)
    exit 2
    ;;
esac
EOF

cat >"$work/bin/openssl" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
[[ "$*" == 'rand -hex 32' ]]
printf '%064d\n' 0
EOF

cat >"$work/bin/gocryptfs" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
master_key=''
IFS= read -r master_key || true
[[ "$master_key" =~ ^[0-9a-fA-F]{64}$ ]]
if [[ " $* " == *' -init '* ]]; then
  second_key=''
  third_key=''
  IFS= read -r second_key
  IFS= read -r third_key
  [[ "$second_key" == "$master_key" ]]
  [[ "$third_key" == "$master_key" ]]
  cipher_dir="${@: -1}"
  touch "$cipher_dir/gocryptfs.conf"
  exit 0
fi
exit 2
EOF

cat >"$work/bin/fusermount" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
rm -f -- "$XDG_RUNTIME_DIR/.cliphist-mounted"
EOF

for fake in "$work/bin/"*; do
  content="$(<"$fake")"
  content="#!$(command -v bash)"$'\n'"${content#*$'\n'}"
  printf '%s\n' "$content" >"$fake"
  chmod 0755 -- "$fake"
done

render_script() {
  local source="$1"
  local destination="$2"
  local content

  content="$(<"$source")"
  content="${content//@bash@/$(command -v bash)}"
  content="${content//@cliphist@/$work/bin/cliphist}"
  content="${content//@mountpoint@/$work/bin/mountpoint}"
  content="${content//@systemctl@/$work/bin/systemctl}"
  content="${content//@install@/$(command -v install)}"
  content="${content//@chmod@/$(command -v chmod)}"
  content="${content//@rm@/$(command -v rm)}"
  content="${content//@rmdir@/$(command -v rmdir)}"
  content="${content//@stat@/$(command -v stat)}"
  content="${content//@find@/$(command -v find)}"
  content="${content//@grep@/$(command -v grep)}"
  content="${content//@secret_tool@/$work/bin/secret-tool}"
  content="${content//@openssl@/$work/bin/openssl}"
  content="${content//@gocryptfs@/$work/bin/gocryptfs}"
  content="${content//@fusermount@/$work/bin/fusermount}"
  content="${content//@sleep@/$(command -v sleep)}"

  printf '%s\n' "$content" >"$destination"
  chmod 0755 -- "$destination"
}

cliphist_script="$work/cliphist"
vault_script="$work/cliphist-vault"
render_script ./cliphist "$cliphist_script"
render_script ./cliphist-vault "$vault_script"

# Sensitive input is rejected before mounting or invoking cliphist.
printf 'password-manager-secret' | CLIPBOARD_STATE=sensitive "$cliphist_script" store
[[ ! -e "$TEST_LOG" ]] || fail 'sensitive event reached cliphist'
[[ ! -e "$XDG_RUNTIME_DIR/.cliphist-mounted" ]] || fail 'sensitive event mounted the vault'

# Initial vault setup stores a key, initializes gocryptfs, and purges legacy data once.
mkdir -p -- "$HOME/.cache/cliphist"
printf 'legacy-secret' >"$HOME/.cache/cliphist/db"
"$vault_script" init
[[ -s "$TEST_KEY" ]] || fail 'master key was not stored'
[[ -e "$XDG_STATE_HOME/cliphist-vault/cipher/gocryptfs.conf" ]] || fail 'gocryptfs was not initialized'
[[ ! -e "$HOME/.cache/cliphist/db" ]] || fail 'legacy database was not purged'
[[ -e "$XDG_STATE_HOME/cliphist-vault/.legacy-purged-v1" ]] || fail 'migration marker was not created'
assert_file_mode 700 "$XDG_STATE_HOME/cliphist-vault"
assert_file_mode 700 "$XDG_STATE_HOME/cliphist-vault/cipher"
assert_file_mode 700 "$XDG_RUNTIME_DIR/cliphist-vault"
assert_file_mode 700 "$XDG_RUNTIME_DIR/cliphist-vault/plain"
assert_file_mode 600 "$XDG_STATE_HOME/cliphist-vault/.legacy-purged-v1"

# Re-running initialization preserves the existing vault and key.
key_before="$(<"$TEST_KEY")"
"$vault_script" init
[[ "$(<"$TEST_KEY")" == "$key_before" ]] || fail 'master key changed during reinitialization'

# Capture controls are private to the runtime session.
touch "$XDG_RUNTIME_DIR/.cliphist-mounted"
"$cliphist_script" capture pause
[[ "$("$cliphist_script" capture status)" == paused ]] || fail 'capture did not pause'
assert_file_mode 600 "$XDG_RUNTIME_DIR/cliphist-vault/control/capture-paused"
printf 'paused-secret' | "$cliphist_script" store
[[ ! -e "$TEST_LOG" ]] || fail 'paused event reached cliphist'
"$cliphist_script" capture resume
[[ "$("$cliphist_script" capture status)" == active ]] || fail 'capture did not resume'

# Normal storage is routed to the fixed encrypted database with bounded retention.
printf 'ordinary-text' | CLIPHIST_DB_PATH=/tmp/plaintext "$cliphist_script" store
[[ "$(<"$TEST_STDIN")" == ordinary-text ]] || fail 'clipboard payload was not forwarded'
[[ "$(<"$TEST_ENV")" == unset ]] || fail 'database-path environment override reached cliphist'
expected_args="-config-path /dev/null -db-path $XDG_RUNTIME_DIR/cliphist-vault/plain/db -max-items 200 store"
[[ "$(<"$TEST_LOG")" == "$expected_args" ]] || fail 'cliphist received unexpected arguments'

# Caller attempts to replace the database path are rejected.
if "$cliphist_script" list -db-path /tmp/plaintext 2>/dev/null; then
  fail 'caller-controlled database path was accepted'
fi

# Missing vault plus failed systemd activation must fail closed.
rm -f -- "$XDG_RUNTIME_DIR/.cliphist-mounted"
if FAIL_SYSTEMCTL=1 "$cliphist_script" list 2>/dev/null; then
  fail 'missing vault did not fail closed'
fi

# Existing ciphertext without its key must not be reinitialized or overwritten.
rm -f -- "$TEST_KEY"
if "$vault_script" init 2>/dev/null; then
  fail 'vault initialized without its existing key'
fi
[[ -e "$XDG_STATE_HOME/cliphist-vault/cipher/gocryptfs.conf" ]] || fail 'existing vault was overwritten'

grep -F -- '-masterkey=stdin' "$vault_script" >/dev/null || fail 'master key is not passed through stdin'
if grep -E -- '-masterkey=("|\$|\{)' "$vault_script" >/dev/null; then
  fail 'master key may be exposed as a command-line argument'
fi
