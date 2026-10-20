#!/usr/bin/env bash
# opencode-plugin-refresh.sh: force OpenCode to refetch the npm plugin
# opencode-thrum-pro and verify the refetch BY EFFECT.
#
# `opencode plugin opencode-thrum-pro --global -f` prints "Installed" and exits 0
# but reuses an existing packages/opencode-thrum-pro@latest cache dir, so a stale
# copy stays stale. The cache key is the spec string, so this checks that npm
# serves the latest tarball, moves exactly that one dir aside, reinstalls, compares
# the cached version with npm's latest, and restores the old dir on any failure.
# (A pinned install, opencode-thrum-pro@X, would write the pin into the config and
# freeze future rolls, so it is deliberately not used.)
#
# Usage: scripts/opencode-plugin-refresh.sh
# Env:   XDG_CACHE_HOME           (default $HOME/.cache)
#        OPENCODE_CMD             (default opencode)
#        NPM_CMD                  (default npm)
#        OPENCODE_REFRESH_TIMEOUT (seconds, default 120; used only if timeout(1) exists)
# Exit:  0 refreshed and verified; 1 on an unfetchable tarball (cache untouched),
#        install failure, npm failure, a missing cached package.json, or a version
#        mismatch (previous copy restored). Restart OpenCode to load it.
# Bash 3.2 / BSD portable.
set -u

oc="${OPENCODE_CMD:-opencode}"
npm_cmd="${NPM_CMD:-npm}"
secs="${OPENCODE_REFRESH_TIMEOUT:-120}"
d="${XDG_CACHE_HOME:-$HOME/.cache}/opencode/packages/opencode-thrum-pro@latest"

# Resolve npm latest and prove its tarball is served BEFORE touching the cache:
# right after a publish, `npm view` reports the new version minutes before the
# tarball stops 404ing, and an install then would leave no package at all.
want="$("$npm_cmd" view opencode-thrum-pro version 2>/dev/null)"
nrc=$?
want="$(printf '%s' "$want" | tr -d '[:space:]')"
if [ "$nrc" -ne 0 ] || [ -z "$want" ]; then
  echo "opencode-plugin-refresh: npm view opencode-thrum-pro version failed (rc=$nrc)" >&2
  exit 1
fi
if ! "$npm_cmd" pack "opencode-thrum-pro@$want" --dry-run >/dev/null 2>&1; then
  echo "opencode-plugin-refresh: tarball for opencode-thrum-pro@$want not fetchable yet; cache left as is, retry in a few minutes" >&2
  exit 1
fi

tmo=""
if command -v timeout >/dev/null 2>&1; then
  tmo="timeout $secs"
elif command -v gtimeout >/dev/null 2>&1; then
  tmo="gtimeout $secs"
fi

# Move the current dir aside and put it back if the refresh fails, so a failed
# install never leaves the box without the plugin.
old=""
if [ -d "$d" ]; then
  old="$d.refresh-old.$$"
  mv "$d" "$old" || { echo "opencode-plugin-refresh: cannot move $d aside" >&2; exit 1; }
fi
fail() {
  echo "opencode-plugin-refresh: $1" >&2
  if [ -n "$old" ]; then
    if [ -e "$d" ]; then rm -r "${d:?}" || { echo "opencode-plugin-refresh: cannot remove failed $d; previous copy kept at $old" >&2; exit 1; }; fi
    mv "$old" "$d" && echo "opencode-plugin-refresh: restored the previous copy" >&2 \
      || echo "opencode-plugin-refresh: restore failed; previous copy kept at $old" >&2
  fi
  exit 1
}

# shellcheck disable=SC2086
$tmo "$oc" plugin opencode-thrum-pro --global -f
rc=$?
[ "$rc" -eq 0 ] || fail "opencode plugin install failed (rc=$rc)"

pj="$d/node_modules/opencode-thrum-pro/package.json"
[ -f "$pj" ] || fail "missing $pj after install"
have="$(awk -F'"' '$2 == "version" {print $4; exit}' "$pj")"
[ "$have" = "$want" ] || fail "cached version '$have' != npm latest '$want'"

if [ -n "$old" ]; then
  rm -r "${old:?}" || echo "opencode-plugin-refresh: could not remove previous copy $old" >&2
fi
echo "opencode-plugin-refresh: opencode-thrum-pro $have cached (matches npm latest); restart OpenCode to load it"
exit 0
