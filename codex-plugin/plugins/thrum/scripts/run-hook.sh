#!/usr/bin/env bash
# Run a Codex hook through the native gateway, falling back only when the
# installed Thrum binary cannot understand the hook command or ABI.
set -u

abi=${1:-}
adapter=${2:-}
operation=${3:-}

case "${adapter}:${operation}" in
  codex:ensure-permission-activation) legacy_script=ensure-permission-activation.sh ;;
  codex:inject-prime-context) legacy_script=inject-prime-context.sh ;;
  codex:block-sync-worktree-cd) legacy_script=block-sync-worktree-cd.sh ;;
  codex:block-tls-key-exfil) legacy_script=block-tls-key-exfil.sh ;;
  codex:stop-check-messages) legacy_script=stop-check-messages.sh ;;
  *)
    printf 'Thrum Codex hook: unsupported adapter/operation %s/%s\n' "$adapter" "$operation" >&2
    exit 1
    ;;
esac

plugin_root=${PLUGIN_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}
legacy_path="${plugin_root}/scripts/${legacy_script}"

warn_compatibility() {
  printf 'WARNING: Thrum Codex hook gateway compatibility mode (%s/%s, %s): %s. During binary/plugin version skew, a guard is fail-open only if its bundled legacy handler is unavailable; install matching versions to close that compatibility window.\n' \
    "$abi" "$adapter" "$operation" "$1" >&2
}

run_legacy() {
  if [[ -f "$legacy_path" && -r "$legacy_path" ]]; then
    warn_compatibility "$1; using bundled ${legacy_script}"
    set +e
    /bin/bash "$legacy_path" <"$tmpdir/input"
    legacy_status=$?
    exit "$legacy_status"
  fi
  warn_compatibility "$1; bundled ${legacy_script} is unavailable, so this hook is fail-open until matching Thrum/plugin versions are installed"
  cat >/dev/null || true
  exit 0
}

tmpdir=$(mktemp -d "${TMPDIR:-/tmp}/thrum-codex-hook.XXXXXX") || {
  printf 'Thrum Codex hook: could not create a private output directory for %s\n' "$operation" >&2
  exit 1
}
cleanup() {
  rm -f "$tmpdir/input" "$tmpdir/stdout" "$tmpdir/stderr"
  rmdir "$tmpdir" 2>/dev/null || true
}
trap cleanup EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM

if ! cat >"$tmpdir/input"; then
  printf 'Thrum Codex hook: could not read input for %s\n' "$operation" >&2
  exit 1
fi

thrum hook run --abi "$abi" --adapter "$adapter" --operation "$operation" \
  <"$tmpdir/input" >"$tmpdir/stdout" 2>"$tmpdir/stderr"
gateway_status=$?

if [[ $gateway_status -eq 0 ]]; then
  cat "$tmpdir/stdout"
  cat "$tmpdir/stderr" >&2
  exit 0
fi

gateway_error=$(cat "$tmpdir/stderr")
# A missing or non-executable command is binary/plugin skew only when Bash
# emitted its own invocation diagnostic; a native handler can also return 126/127.
if [[ $gateway_status -eq 127 && "$gateway_error" =~ run-hook\.sh:\ line\ [0-9]+:\ thrum:\ command\ not\ found ]]; then
  run_legacy 'installed Thrum gateway executable is missing from PATH'
fi
if [[ $gateway_status -eq 126 && "$gateway_error" =~ run-hook\.sh:\ line\ [0-9]+:\ .*thrum:\ Permission\ denied ]]; then
  run_legacy 'installed Thrum gateway executable is not executable'
fi

# Only classify expected compatibility diagnostics from the CLI, and never
# reinterpret a native guard denial (exit 2) as a compatibility failure.
if [[ $gateway_status -eq 1 ]]; then
  case "$gateway_error" in
    *'unknown command "hook" for "thrum"'*|*'unknown command "run" for "thrum hook"'*)
      run_legacy 'installed Thrum does not provide hook run'
      ;;
  esac
  if [[ "$gateway_error" == *"Thrum hook gateway rejected "* && "$gateway_error" == *'unsupported hook ABI "'* ]]; then
    run_legacy "installed Thrum does not support ABI ${abi}"
  fi
fi

cat "$tmpdir/stdout"
cat "$tmpdir/stderr" >&2
exit "$gateway_status"
