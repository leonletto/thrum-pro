# Updating the OpenCode plugin

To force OpenCode to refetch the newest `opencode-thrum-pro` and verify it, run
from the bundle root:

    bash opencode-plugin/scripts/opencode-plugin-refresh.sh

Then restart OpenCode. Manual fallback:

    rm -r "${XDG_CACHE_HOME:-$HOME/.cache}/opencode/packages/opencode-thrum-pro@latest"
    opencode plugin opencode-thrum-pro --global -f
