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
#   THRUM_INSTALL_REF        Git ref to install (default: main)
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
CACHE_ROOT="${CODEX_HOME}/plugins/cache/${MARKETPLACE_NAME}/${PLUGIN_NAME}"
MIGRATION_MARKER="${HOME}/.thrum/hooks/codex-legacy-hook-migration-complete"
cache_stage=""

cleanup_cache_stage() {
  if [[ -n "${cache_stage}" && -d "${cache_stage}" ]]; then
    rm -r -- "${cache_stage}"
  fi
}
trap cleanup_cache_stage EXIT

write_migration_marker() {
  python3 - "${MIGRATION_MARKER}" <<'PY_MIGRATION_MARKER'
import os, sys, tempfile
from pathlib import Path

target = Path(sys.argv[1])
target.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
fd, temporary = tempfile.mkstemp(prefix='.codex-legacy-hook-migration.', dir=target.parent)
try:
    with os.fdopen(fd, 'w') as stream:
        stream.write('pre-prune migration gate satisfied or not required\n')
        stream.flush()
        os.fsync(stream.fileno())
    os.chmod(temporary, 0o600)
    os.replace(temporary, target)
    directory = os.open(target.parent, os.O_RDONLY)
    try:
        os.fsync(directory)
    finally:
        os.close(directory)
except BaseException:
    try:
        os.unlink(temporary)
    except OSError:
        pass
    raise
PY_MIGRATION_MARKER
}

say() { printf '→ %s\n' "$*"; }
die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

# 1. Prereqs
command -v codex >/dev/null || die "codex CLI not found on PATH. Install codex first (https://github.com/openai/codex)."
command -v jq    >/dev/null || die "jq not found on PATH. Install: brew install jq"
command -v python3 >/dev/null || die "python3 not found on PATH (needed to enable features.plugin_hooks in the Codex config). Install: apt install python3 / brew install python3"
[[ -f "${CONFIG}" ]] || die "codex config not found at ${CONFIG}. Run codex at least once to create it."

# Check the installer process PATH and provision every ABI registered by this
# binary before marketplace work. This does not prove Codex's runtime PATH.
command -v thrum >/dev/null || die "Missing hook gateway prerequisite: install a gateway-capable Thrum binary on the installer PATH. This is separate from native hook review."
thrum hook check \
  || die "Missing hook gateway prerequisite: the thrum on the installer PATH must support its registered ABIs and provision owned payloads before updating the marketplace."

# Native upgrade bypasses this installer and may prune cache directories.
# The owner must cover all native panes, including those outside Thrum's registry.
# No registry-only scan can certify zero legacy references.
migration_marker_required=0
if [[ -d "${CACHE_ROOT}" && ! -f "${MIGRATION_MARKER}" ]]; then
  if [[ "${THRUM_LEGACY_HOOK_MIGRATION_COMPLETE:-}" != "1" ]]; then
    die "Legacy hook migration needs owner sequencing before this cache-pruning update. Arrange normal exit or authorized continuity relaunch for every cache-bound pane, including native panes outside Thrum; then set THRUM_LEGACY_HOOK_MIGRATION_COMPLETE=1 for this run. Raw codex marketplace updates bypass this installer gate."
  fi
  migration_marker_required=1
elif [[ ! -f "${MIGRATION_MARKER}" ]]; then
  # With no existing plugin cache tree, this run has no legacy cache
  # generation to prune, whether the marketplace is fresh or registered.
  migration_marker_required=1
fi

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

# The marketplace operation above is the first step that may prune old cache
# generations. Record the completed one-time gate immediately after it succeeds.
if [[ "${migration_marker_required}" == "1" && ! -f "${MIGRATION_MARKER}" ]]; then
  write_migration_marker || die "could not persist Codex hook migration completion marker"
fi

# 3. Confirm the plugin payload is in the staged marketplace.
[[ -f "${MANIFEST}" ]] || die "expected plugin manifest at ${MANIFEST} after marketplace add; codex may have changed its layout."
VERSION=$(jq -r '.version' "${MANIFEST}")
[[ -n "${VERSION}" && "${VERSION}" != "null" ]] || die "could not read version from ${MANIFEST}"
say "Plugin version: ${VERSION}"

# 4. Stage cache (the step codex 0.130.0 doesn't do automatically).
CACHE_DIR="${CODEX_HOME}/plugins/cache/${MARKETPLACE_NAME}/${PLUGIN_NAME}/${VERSION}"
say "Staging cache: ${CACHE_DIR}"
# Validate the native manifest before enabling hooks or writing its enabled stanza.
thrum hook check --manifest "${SOURCE_DIR}/hooks/hooks.json" \
  || die "Codex hook manifest does not match the installed gateway descriptor; plugin remains disabled."
# Retain every existing cache root. Publish only a complete new version.
if [[ -d "${CACHE_DIR}" ]]; then
  [[ ! -L "${CACHE_DIR}" ]] || die "Existing cache version is a symlink; retain it and publish a new plugin version."
  python3 - "${SOURCE_DIR}" "${CACHE_DIR}" <<'PY_MATCH_SHIPPED'
import os, sys
from pathlib import Path

source, destination = map(Path, sys.argv[1:])
for path in source.rglob('*'):
    relative = path.relative_to(source)
    target = destination / relative
    if path.is_symlink():
        if not target.is_symlink() or os.readlink(path) != os.readlink(target):
            raise SystemExit(f"shipped symlink differs: {relative}")
    elif path.is_dir():
        if target.is_symlink() or not target.is_dir():
            raise SystemExit(f"shipped directory differs: {relative}")
    elif path.is_file():
        if target.is_symlink() or not target.is_file() or path.read_bytes() != target.read_bytes():
            raise SystemExit(f"shipped file differs: {relative}")
    else:
        raise SystemExit(f"unsupported shipped entry: {relative}")
PY_MATCH_SHIPPED
  [[ $? -eq 0 ]] \
    || die "Existing cache version differs from marketplace payload; retain it and publish a new plugin version."
else
  mkdir -p "$(dirname "${CACHE_DIR}")" "${CODEX_HOME}/.tmp" || die "could not create cache parent"
  python3 - "${CODEX_HOME}/.tmp" <<'PY_CLEAN_STALE'
import shutil, sys, time
from pathlib import Path

root = Path(sys.argv[1])
cutoff = time.time() - 3600
for path in root.glob('thrum-plugin-cache-publishing.*'):
    try:
        if path.is_dir() and path.stat().st_mtime < cutoff:
            shutil.rmtree(path)
    except FileNotFoundError:
        pass
PY_CLEAN_STALE
  cache_stage=$(mktemp -d "${CODEX_HOME}/.tmp/thrum-plugin-cache-publishing.XXXXXX") || die "could not stage cache"
  cp -R "${SOURCE_DIR}/." "${cache_stage}/" || die "could not copy complete plugin payload"
  # Rename the directory itself; shell mv can nest it into a concurrent winner.
  python3 - "${cache_stage}" "${CACHE_DIR}" <<'PY_CACHE_PUBLISH'
import errno, os, shutil, sys
from pathlib import Path

staging, destination = map(Path, sys.argv[1:])

def inventory(root):
    result = {}
    for path in root.rglob('*'):
        relative = str(path.relative_to(root))
        if path.is_symlink():
            result[relative] = ('symlink', os.readlink(path))
        elif path.is_dir():
            result[relative] = ('directory', None)
        elif path.is_file():
            result[relative] = ('file', path.read_bytes())
        else:
            raise RuntimeError('unexpected cache entry: ' + str(path))
    return result

def sync_tree(root):
    directories = [root]
    for path in root.rglob('*'):
        if path.is_symlink():
            continue
        if path.is_dir():
            directories.append(path)
        elif path.is_file():
            with path.open('rb') as stream:
                os.fsync(stream.fileno())
    for directory in sorted(directories, key=lambda path: len(path.parts), reverse=True):
        descriptor = os.open(directory, os.O_RDONLY | getattr(os, 'O_DIRECTORY', 0))
        try:
            os.fsync(descriptor)
        finally:
            os.close(descriptor)

try:
    sync_tree(staging)
    try:
        os.rename(staging, destination)
        descriptor = os.open(destination.parent, os.O_RDONLY | getattr(os, 'O_DIRECTORY', 0))
        try:
            os.fsync(descriptor)
        finally:
            os.close(descriptor)
    except OSError as error:
        if error.errno not in (errno.EEXIST, errno.ENOTEMPTY):
            raise
        if destination.is_symlink() or not destination.is_dir():
            raise RuntimeError('concurrent cache destination is not an owned directory')
        if inventory(staging) != inventory(destination):
            raise RuntimeError('concurrent cache winner differs; retain it and publish a new plugin version')
finally:
    # This path is the fresh mktemp directory owned by this installer only.
    if staging.exists():
        shutil.rmtree(staging)
PY_CACHE_PUBLISH
  [[ $? -eq 0 ]] || die "could not publish complete plugin payload; any concurrent winner was retained"

fi

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
    # Remove retained caches only after complete live-reference inventory.
    # then edit ${CONFIG} to remove [plugins."${PLUGIN_NAME}@${MARKETPLACE_NAME}"]
EOF
