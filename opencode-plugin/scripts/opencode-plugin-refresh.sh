#!/usr/bin/env bash
# opencode-plugin-refresh.sh: force OpenCode to refetch the npm plugin
# opencode-thrum-pro and verify the refetch BY EFFECT.
#
# `opencode plugin opencode-thrum-pro --global -f` prints "Installed" and exits 0
# but reuses an existing packages/opencode-thrum-pro@latest cache dir, so a stale
# copy stays stale. The cache key is the spec string, so this removes exactly that
# one dir, reinstalls, then compares the cached version with npm's latest.
# (A pinned install, opencode-thrum-pro@X, would write the pin into the config and
# freeze future rolls, so it is deliberately not used.)
#
# Usage: scripts/opencode-plugin-refresh.sh
# Env:   XDG_CACHE_HOME           (default $HOME/.cache)
#        OPENCODE_CMD             (default opencode)
#        NPM_CMD                  (default npm)
#        OPENCODE_REFRESH_TIMEOUT (seconds, default 120; used only if timeout(1) exists)
# Exit:  0 refreshed and verified; 1 on install failure, npm failure, a missing
#        cached package.json, or a version mismatch. Restart OpenCode to load it.
# Bash 3.2 / BSD portable.
set -u

oc="${OPENCODE_CMD:-opencode}"
npm_cmd="${NPM_CMD:-npm}"
secs="${OPENCODE_REFRESH_TIMEOUT:-120}"
d="${XDG_CACHE_HOME:-$HOME/.cache}/opencode/packages/opencode-thrum-pro@latest"

if [ -d "$d" ]; then
  rm -r "${d:?}" || { echo "opencode-plugin-refresh: cannot remove $d" >&2; exit 1; }
fi

tmo=""
if command -v timeout >/dev/null 2>&1; then
  tmo="timeout $secs"
elif command -v gtimeout >/dev/null 2>&1; then
  tmo="gtimeout $secs"
fi
# shellcheck disable=SC2086
$tmo "$oc" plugin opencode-thrum-pro --global -f
rc=$?
if [ "$rc" -ne 0 ]; then
  echo "opencode-plugin-refresh: opencode plugin install failed (rc=$rc)" >&2
  exit 1
fi

pj="$d/node_modules/opencode-thrum-pro/package.json"
if [ ! -f "$pj" ]; then
  echo "opencode-plugin-refresh: missing $pj after install" >&2
  exit 1
fi
have="$(awk -F'"' '$2 == "version" {print $4; exit}' "$pj")"

want="$("$npm_cmd" view opencode-thrum-pro version 2>/dev/null)"
nrc=$?
want="$(printf '%s' "$want" | tr -d '[:space:]')"
if [ "$nrc" -ne 0 ] || [ -z "$want" ]; then
  echo "opencode-plugin-refresh: npm view opencode-thrum-pro version failed (rc=$nrc)" >&2
  exit 1
fi

if [ "$have" != "$want" ]; then
  echo "opencode-plugin-refresh: cached version '$have' != npm latest '$want'" >&2
  exit 1
fi
echo "opencode-plugin-refresh: opencode-thrum-pro $have cached (matches npm latest); restart OpenCode to load it"
exit 0
