# ==============================================================================
# KIRO SUB-AGENT SHELL INTEGRATION WORKAROUND
# Loaded for ALL Zsh subshells (including non-interactive sub-agent runs)
# ==============================================================================
export VSCODE_SHELL_INTEGRATION=1

# Absolute path to Kiro's internal VS Code shell integration script
kiro_script="/Applications/Kiro.app/Contents/Resources/app/out/vs/workbench/contrib/terminal/browser/media/shellIntegration-rc.zsh"

if [[ -f "$kiro_script" ]]; then
    # Option A: Source the native Kiro hook engine if present
    source "$kiro_script" 2>/dev/null
else
    # Option B: Fallback to dummy stubs if the app path changes or is unreadable
    if ! typeset -f __vsc_precmd >/dev/null 2>&1; then
        __vsc_precmd() { return 0; }
    fi

    if ! typeset -f __vsc_preexec >/dev/null 2>&1; then
        __vsc_preexec() { return 0; }
    fi
fi

unset kiro_script