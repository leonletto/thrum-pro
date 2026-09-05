#!/usr/bin/env bash
#
# install-plugin.sh — install the Thrum codex plugin end-to-end.
#
# Codex 0.130.0's `codex plugin marketplace add` registers third-party
# marketplaces but does NOT auto-populate the per-plugin cache at
# ~/.codex/plugins/cache/<marketplace>/<plugin>/<version>/. Without that
# cache codex can't load the plugin's hooks. This script handles the full
# install: register marketplace → stage cache → enable plugin → enable the
# plugin_hooks feature.
#
# After this script runs cleanly, the user must:
#   1. Restart codex (or launch a fresh session).
#   2. On first launch codex shows: "3 hooks need review before they can run.
#      Open /hooks to review them."
#   3. Run `/hooks` in codex, press Enter on each event row (PreToolUse,
#      SessionStart, Stop), press `t` to trust, then Escape back.
#   4. Restart codex one more time. The SessionStart hook will fire and
#      auto-load the thrum prime briefing.
#
# Environment overrides:
#   THRUM_INSTALL_REF        Git ref to install (default: latest release tag if available, else "main")
#   THRUM_INSTALL_REPO       Repo source (default: "leonletto/thrum-pro")
#
# Idempotent: safe to run multiple times. Re-running pulls the latest revision
# of the configured ref and re-stages the cache.

set -uo pipefail

MARKETPLACE_NAME="thrum-marketplace"
PLUGIN_NAME="thrum"
REPO="${THRUM_INSTALL_REPO:-leonletto/thrum-pro}"
REF="${THRUM_INSTALL_REF:-main}"
CODEX_HOME="${CODEX_HOME:-${HOME}/.codex}"
CONFIG="${CODEX_HOME}/config.toml"
STAGED_ROOT="${CODEX_HOME}/.tmp/marketplaces/${MARKETPLACE_NAME}"
SOURCE_DIR="${STAGED_ROOT}/codex-plugin/plugins/${PLUGIN_NAME}"
MANIFEST="${SOURCE_DIR}/.codex-plugin/plugin.json"

say() { printf '→ %s\n' "$*"; }
die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

# 1. Prereqs
command -v codex >/dev/null || die "codex CLI not found on PATH. Install codex first (https://github.com/openai/codex)."
command -v jq    >/dev/null || die "jq not found on PATH. Install: brew install jq"
[[ -f "${CONFIG}" ]] || die "codex config not found at ${CONFIG}. Run codex at least once to create it."

# 2. Register or refresh the marketplace.
if grep -q "^\\[marketplaces.${MARKETPLACE_NAME}\\]" "${CONFIG}"; then
  say "Marketplace ${MARKETPLACE_NAME} already registered; pulling latest revision."
  codex plugin marketplace upgrade "${MARKETPLACE_NAME}" >/dev/null \
    || die "codex plugin marketplace upgrade failed"
else
  say "Registering marketplace ${MARKETPLACE_NAME} from ${REPO}..."
  codex plugin marketplace add "${REPO}" >/dev/null \
    || die "codex plugin marketplace add failed"
fi

# 3. Confirm the plugin payload is in the staged marketplace.
[[ -f "${MANIFEST}" ]] || die "expected plugin manifest at ${MANIFEST} after marketplace add; codex may have changed its layout."
VERSION=$(jq -r '.version' "${MANIFEST}")
[[ -n "${VERSION}" && "${VERSION}" != "null" ]] || die "could not read version from ${MANIFEST}"
say "Plugin version: ${VERSION}"

# 4. Stage cache (the step codex 0.130.0 doesn't do automatically).
CACHE_DIR="${CODEX_HOME}/plugins/cache/${MARKETPLACE_NAME}/${PLUGIN_NAME}/${VERSION}"
say "Staging cache: ${CACHE_DIR}"
rm -rf "${CACHE_DIR}"
mkdir -p "${CACHE_DIR}"
cp -R "${SOURCE_DIR}/." "${CACHE_DIR}/"

# 5. Enable the plugin in config.toml.
if ! grep -q "^\\[plugins\\.\"${PLUGIN_NAME}@${MARKETPLACE_NAME}\"\\]" "${CONFIG}"; then
  say "Enabling [plugins.\"${PLUGIN_NAME}@${MARKETPLACE_NAME}\"] in ${CONFIG}"
  printf '\n[plugins."%s@%s"]\nenabled = true\n' "${PLUGIN_NAME}" "${MARKETPLACE_NAME}" >> "${CONFIG}"
else
  say "Plugin already enabled in ${CONFIG}"
fi

# 6. Enable features.plugin_hooks.
if grep -q '^plugin_hooks[[:space:]]*=[[:space:]]*true' "${CONFIG}"; then
  say "features.plugin_hooks already enabled"
elif grep -q '^\[features\]' "${CONFIG}"; then
  python3 - "${CONFIG}" <<'PY'
import os, re, sys, tempfile
path = sys.argv[1]
content = open(path).read()
content = re.sub(r'(\[features\]\n)', r'\1plugin_hooks = true\n', content, count=1)

# Write atomically: temp file in the SAME directory as the target (same
# filesystem, so the rename is atomic), then os.replace() over the target.
# Preserves the original file's permissions.
config_dir = os.path.dirname(path) or "."
orig_mode = None
if os.path.exists(path):
    orig_mode = os.stat(path).st_mode

tmp_fd, tmp_path = tempfile.mkstemp(dir=config_dir, suffix=".tmp")
try:
    with os.fdopen(tmp_fd, "w") as f:
        f.write(content)
    if orig_mode is not None:
        os.chmod(tmp_path, orig_mode)
    os.replace(tmp_path, path)
except BaseException:
    try:
        os.remove(tmp_path)
    except OSError:
        pass
    raise
PY
  say "Added plugin_hooks = true under [features] in ${CONFIG}"
else
  printf '\n[features]\nplugin_hooks = true\n' >> "${CONFIG}"
  say "Added [features] block with plugin_hooks = true to ${CONFIG}"
fi

# 7. Ensure the thrum-workspace permission profile covers this repo's
#    redirect-resolved audit-log dir (no-op skip if not run from a thrum repo).
#    ensure-permission-profile.sh exits 0 for its own documented benign skip
#    (no .thrum/ found — nothing to do), so a nonzero exit here is always a
#    GENUINE failure (I/O error, malformed redirect, etc.), never the skip
#    case. Fail closed on it, mirroring this file's own `|| die "..."` idiom
#    used everywhere else (see steps 2, 3-6) — a failing profile setup must
#    never be swallowed into a "✓ Plugin installed" success banner.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -f "${SCRIPT_DIR}/ensure-permission-profile.sh" ]]; then
  bash "${SCRIPT_DIR}/ensure-permission-profile.sh" \
    || die "ensure-permission-profile.sh failed; the thrum-workspace permission profile was NOT applied. Add it manually (see INSTALL.md's \"Sandbox permission profile\" section) or fix the reported error and re-run this installer."
fi

cat <<EOF

✓ Plugin installed at ${CACHE_DIR}

Next steps (interactive — only the user can do these):
  1. Restart your codex agent (run \`codex\` in a fresh shell, or restart your IDE).
  2. Codex will show: "⚠ 3 hooks need review before they can run. Open /hooks to review them."
  3. Run /hooks in codex:
     - Press Enter on PreToolUse → 't' to trust → Escape
     - Arrow down to SessionStart → Enter → 't' → Escape
     - Arrow down to Stop → Enter → 't' → Escape, Escape
  4. Restart codex again. SessionStart hook will auto-load the thrum prime briefing.

To upgrade later, re-run the one-shot installer (idempotent):
    bash <(curl -fsSL https://raw.githubusercontent.com/${REPO}/${REF}/codex-plugin/plugins/thrum/scripts/install-plugin.sh)

To uninstall:
    codex plugin marketplace remove ${MARKETPLACE_NAME}
    rm -rf ${CACHE_DIR%/*}
    # then edit ${CONFIG} to remove [plugins."${PLUGIN_NAME}@${MARKETPLACE_NAME}"]
EOF
