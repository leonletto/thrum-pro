#!/usr/bin/env bash
set -euo pipefail

# Deploy cursor-plugin into a target .cursor/ directory.
# Usage: local-install.sh [--target <path>]

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --target) TARGET="$2"; shift 2 ;;
    *) echo "Unknown option: $1" >&2; exit 1 ;;
  esac
done

# Default to git repo root
if [ -z "$TARGET" ]; then
  TARGET="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
fi

CURSOR_DIR="$TARGET/.cursor"

echo "Installing cursor-plugin into $CURSOR_DIR"

# Create directories
mkdir -p "$CURSOR_DIR/rules" "$CURSOR_DIR/skills" "$CURSOR_DIR/commands" "$CURSOR_DIR/agents"

# Copy rules
cp "$SCRIPT_DIR/rules/"*.mdc "$CURSOR_DIR/rules/"

# Copy skills (if synced)
if [ -d "$SCRIPT_DIR/skills" ] && [ "$(ls -A "$SCRIPT_DIR/skills" 2>/dev/null)" ]; then
  cp -R "$SCRIPT_DIR/skills/"* "$CURSOR_DIR/skills/"
fi

# Copy commands (if synced)
if [ -d "$SCRIPT_DIR/commands" ] && [ "$(ls -A "$SCRIPT_DIR/commands" 2>/dev/null)" ]; then
  cp "$SCRIPT_DIR/commands/"*.md "$CURSOR_DIR/commands/"
fi

# Copy agents
if [ -d "$SCRIPT_DIR/agents" ] && [ "$(ls -A "$SCRIPT_DIR/agents" 2>/dev/null)" ]; then
  cp "$SCRIPT_DIR/agents/"*.md "$CURSOR_DIR/agents/"
fi

# Write hooks.json with resolved absolute paths. Parsed as JSON first (never
# sed and never raw-text replacement: install paths routinely contain spaces,
# R&D ampersands, quotes, backslashes, and $HOME/$(...) sequences, which raw
# replacement either corrupts or shell-expands). The install root is
# substituted inside each command string, the executable head is
# shell-LITERAL-quoted with shlex.quote so spaced paths survive word
# splitting AND $HOME/$(...)/backticks/quotes/backslashes survive shell
# expansion when the decoded command is executed (a double-quoted head would
# still expand them), and the manifest is re-serialized with json.dumps so
# the output is valid JSON whose decoded commands contain the literal root
# byte-for-byte. The tail after the first space (shipped args such as
# `2>/dev/null || true`) is preserved verbatim. Source uses the
# ${CURSOR_PLUGIN_ROOT} token (legacy __PLUGIN_ROOT__ also resolved so older
# copies keep installing); the runtime never sees an unexpanded token.
# Whether Cursor's own parser honors single-quote literal quoting under
# adversarial paths is vendor behavior, UNKNOWN natively — proven here only
# for POSIX shell argv identity (see dev-docs successor-batch reviews).
command -v python3 >/dev/null 2>&1 || { echo "ERROR: python3 required to resolve hooks.json install paths" >&2; exit 1; }
python3 - "$SCRIPT_DIR/hooks/hooks.json" "$CURSOR_DIR/hooks.json" "$SCRIPT_DIR" <<'PY'
import json, shlex, sys
src, dst, root = sys.argv[1], sys.argv[2], sys.argv[3]
with open(src, encoding="utf-8") as f:
    doc = json.load(f)
if not isinstance(doc, dict) or not isinstance(doc.get("hooks"), dict):
    print("ERROR: source hooks.json has no object 'hooks'", file=sys.stderr)
    sys.exit(1)
for key, entries in doc["hooks"].items():
    if not isinstance(entries, list):
        print("ERROR: hook event %r is not a list" % key, file=sys.stderr)
        sys.exit(1)
    for entry in entries:
        cmd = entry.get("command") if isinstance(entry, dict) else None
        if not isinstance(cmd, str) or "${CURSOR_PLUGIN_ROOT}" not in cmd and "__PLUGIN_ROOT__" not in cmd:
            continue
        head, sep, rest = cmd.partition(" ")
        resolved = head.replace("${CURSOR_PLUGIN_ROOT}", root).replace("__PLUGIN_ROOT__", root)
        entry["command"] = "%s%s%s" % (shlex.quote(resolved), sep, rest)
with open(dst, "w", encoding="utf-8") as f:
    json.dump(doc, f, indent=2)
    f.write("\n")
PY

# Write mcp.json for thrum MCP server
cat > "$CURSOR_DIR/mcp.json" <<'MCPEOF'
{
  "mcpServers": {
    "thrum": {
      "type": "command",
      "command": "thrum",
      "args": ["mcp", "serve"]
    }
  }
}
MCPEOF

# Add .cursor/ to .gitignore if not present
GITIGNORE="$TARGET/.gitignore"
if [ -f "$GITIGNORE" ]; then
  if ! grep -qx '.cursor/' "$GITIGNORE"; then
    echo '.cursor/' >> "$GITIGNORE"
    echo "Added .cursor/ to .gitignore"
  fi
else
  echo '.cursor/' > "$GITIGNORE"
  echo "Created .gitignore with .cursor/"
fi

echo "Done. Plugin installed at $CURSOR_DIR"
