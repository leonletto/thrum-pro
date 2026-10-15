#!/usr/bin/env bash
# Run a Codex hook through the native gateway, falling back only when the
# installed Thrum binary cannot understand the hook command or ABI.
set -u

abi=${1:-}
adapter=${2:-}
operation=${3:-}
recorded_plugin_root=${4:-}

# Blocking operations are PreToolUse guards. Codex treats only exit 2 as a block,
# so for these any other failure to run a guard must become exit 2, not 0/1/126/127.
blocking=0
case "${adapter}:${operation}" in
  codex:ensure-permission-activation) legacy_script=ensure-permission-activation.sh ;;
  codex:inject-prime-context) legacy_script=inject-prime-context.sh ;;
  codex:block-sync-worktree-cd) legacy_script=block-sync-worktree-cd.sh; blocking=1 ;;
  codex:block-tls-key-exfil) legacy_script=block-tls-key-exfil.sh; blocking=1 ;;
  codex:stop-check-messages) legacy_script=stop-check-messages.sh ;;
  *)
    printf 'Thrum Codex hook: unsupported adapter/operation %s/%s\n' "$adapter" "$operation" >&2
    exit 1
    ;;
esac

warn_compatibility() {
  printf 'WARNING: Thrum Codex hook gateway compatibility mode (%s/%s, %s): %s. During binary/plugin version skew, a non-blocking hook is fail-open and a blocking guard is fail-closed (exit 2) if its bundled legacy handler is unavailable; install matching versions to close that compatibility window.\n' \
    "$abi" "$adapter" "$operation" "$1" >&2
}

run_legacy() {
  # Resolve the bundle only on compatibility fallback, never on the hot path.
  plugin_root=${recorded_plugin_root:-${PLUGIN_ROOT:-}}
  if [[ -z "$plugin_root" && -n "${BASH_SOURCE[0]:-}" ]]; then
    plugin_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
  fi
  legacy_path="${plugin_root}/scripts/${legacy_script}"
  if [[ -f "$legacy_path" && -r "$legacy_path" ]]; then
    warn_compatibility "$1; using bundled ${legacy_script}"
    set +e
    /bin/bash "$legacy_path" <"$tmpdir/input"
    legacy_status=$?
    if [[ $blocking -eq 1 && $legacy_status -ne 0 && $legacy_status -ne 2 ]]; then
      printf 'Thrum Codex hook: blocking guard %s failed to run (status %s); denying the tool call.\n' "$operation" "$legacy_status" >&2
      exit 2
    fi
    exit "$legacy_status"
  fi
  if [[ $blocking -eq 1 ]]; then
    warn_compatibility "$1; bundled ${legacy_script} is unavailable"
    printf 'Thrum Codex hook: blocking guard %s cannot run (no gateway and no bundled handler); denying the tool call. Install matching Thrum/plugin versions.\n' "$operation" >&2
    cat >/dev/null || true
    exit 2
  fi
  warn_compatibility "$1; bundled ${legacy_script} is unavailable, so this hook is fail-open until matching Thrum/plugin versions are installed"
  cat >/dev/null || true
  exit 0
}

tmpdir=$(mktemp -d "${TMPDIR:-/tmp}/thrum-codex-hook.XXXXXX") || {
  printf 'Thrum Codex hook: could not create a private output directory for %s\n' "$operation" >&2
  if [[ $blocking -eq 1 ]]; then exit 2; fi
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
  if [[ $blocking -eq 1 ]]; then exit 2; fi
  exit 1
fi

# Classify launch failures before invocation so native handler statuses never
# become missing-binary fallbacks, independently of Bash's diagnostic locale.
thrum_path=$(command -v thrum || true)
if [[ -z "$thrum_path" ]]; then
  run_legacy 'installed Thrum gateway executable is missing from PATH'
fi
if [[ ! -x "$thrum_path" ]]; then
  run_legacy 'installed Thrum gateway executable is not executable'
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
if [[ $blocking -eq 1 && $gateway_status -ne 2 ]]; then
  printf 'Thrum Codex hook: blocking guard %s gateway failed (status %s); denying the tool call.\n' "$operation" "$gateway_status" >&2
  exit 2
fi
exit "$gateway_status"
