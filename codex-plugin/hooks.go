package codexplugin

import "fmt"

const (
	HookABI     = "thrum-hooks-v1"
	HookAdapter = "codex"
)

// HookOperation is the single Codex event-to-operation contract used by the
// gateway registry and checked against the native hooks.json manifest.
type HookOperation struct {
	Event         string
	Matcher       string
	Operation     string
	Script        string
	StatusMessage string
	Timeout       int
	Blocks        bool
}

var codexHookOperations = []HookOperation{
	{Event: "SessionStart", Matcher: "startup|resume|clear|compact", Operation: "ensure-permission-activation", Script: "ensure-permission-activation.sh", StatusMessage: "Ensuring thrum permission profile", Timeout: 15},
	{Event: "SessionStart", Matcher: "startup|resume|clear|compact", Operation: "inject-prime-context", Script: "inject-prime-context.sh", StatusMessage: "Loading Thrum prime context", Timeout: 30},
	{Event: "PreToolUse", Matcher: "Bash", Operation: "block-sync-worktree-cd", Script: "block-sync-worktree-cd.sh", Timeout: 5, Blocks: true},
	{Event: "PreToolUse", Matcher: "Bash", Operation: "block-tls-key-exfil", Script: "block-tls-key-exfil.sh", Timeout: 5, Blocks: true},
	{Event: "Stop", Operation: "stop-check-messages", Script: "stop-check-messages.sh", Timeout: 15},
}

// HookOperations returns a copy so callers cannot mutate the registered contract.
func HookOperations() []HookOperation {
	return append([]HookOperation(nil), codexHookOperations...)
}

// HookCommand renders the fixed native invocation for a registered operation.
func HookCommand(operation string) string {
	return fmt.Sprintf("${PLUGIN_ROOT}/scripts/run-hook.sh %s %s %s", HookABI, HookAdapter, operation)
}
