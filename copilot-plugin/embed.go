// Package copilotplugin embeds the shipped GitHub Copilot CLI plugin asset
// (plugin.json, hooks.json, scripts/session-start.sh) into the thrum binary
// so it can be materialized into the user-scoped runtime dir
// (paths.CopilotPluginUserDir()) at first launch, without requiring a repo
// checkout on the installed machine.
package copilotplugin

import "embed"

//go:embed plugin.json hooks.json scripts
var FS embed.FS
