# Resolving Kiro IDE "Exit Code: -1" Sub-Agent Failures

## Issue #1 - missing non-interactive subshell integration

Kiro IDE sub-agent command orchestrations fail with a synthetic `Exit Code: -1` when non-interactive subshells lack the `VSCODE_SHELL_INTEGRATION` hooks (`__vsc_precmd`, `__vsc_preexec`) expected by the IDE's process runner. In consequence, the agent gets stuck trying to execute the command over and over again showing "working..." status.

### 1. Verification and Testing

To confirm whether your sub-agent failures stem from missing terminal integration hooks in non-interactive subshells, simulate the exact invocation environment Kiro uses for automated tasks.

Run this test command in your standard terminal once the error occurs:

```zsh
zsh -c 'echo "Integration: $VSCODE_SHELL_INTEGRATION"; typeset -f __vsc_precmd __vsc_preexec'
```

### 2. Diagnosing the Output

- The Issue is Present if: VSCODE_SHELL_INTEGRATION is blank/unset and typeset returns function \_\_vsc_precmd not found.
- The Issue is Resolved if: Integration: 1 is printed and both **vsc_precmd and **vsc_preexec output defined function bodies.

### 3. Workaround

Since Zsh skips ~/.zshrc during non-interactive execution (zsh -c "command"), inject the missing environment variables and hooks into ~/.zshenv, which Zsh always sources regardless of shell mode.

Add the following block to the top of your ~/.zshenv:

```zsh
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
```

### 4. Alternative Workaround

Agent can be informed about the problem and instructed how to deal with missing shell integration.
Place `shell-exit-code-workaround.md` steering file either on the project level or main Kiro folder (recommended) `./kiro/steering/shell-exit...md`.

### 5. Why Shell Commands Return Exit Code -1

**The Root Cause: Interactive Terminal IPC vs. Raw Subshells**

The central cause of this bug is not a broken underlying shell or a lack of permissions. The Zsh binary spawned by the sub-agent has full system access and executes commands normally. Instead, the failure lies in the event signaling bridge between the IDE's GUI process runner and the spawned child process.

Kiro handles terminal execution via two distinct architectures:

1. Integrated Interactive Terminals (PTY):
   When a user opens a terminal tab, Kiro allocates an interactive Pseudo-Terminal (PTY). Kiro explicitly injects shellIntegration-rc.zsh, which registers Zsh prompt hooks (**vsc_preexec right before command execution, and **vsc_precmd right after execution completes). These hooks emit invisible ANSI escape sequences (OSC 133) back to the IDE, allowing Kiro to track process lifecycles, command duration, and terminal prompt boundaries.

2. Sub-Agent Automated Subshells (Non-Interactive Headless Pipes):
   When an AI sub-agent executes a task (e.g., git status or npm test), it launches zsh -c "command" as a headless child process. Because it is non-interactive, Zsh automatically bypasses ~/.zshrc.

[Sub-Agent]
Spawns Headless Zsh ──>
Command Runs to Completion ──>
Kiro daemon waits for OSC 133
event from **vsc_precmd hook ──>
❌ **vsc_precmd is missing!
No completion event emitted. ──>
Kiro RPC Runner Times Out / Drops Pipe ──>
💥 Synthetic Failure: Exit Code -1

**Why -1 Is Returned**

Because Kiro's internal RPC daemon expects all managed processes to conform to the VS Code terminal integration contract, it listens for the OSC sequence emitted by \_\_vsc_precmd to confirm that a command has cleanly finished.

When a sub-agent runs without these hooks:

1. The shell command runs and completes successfully on the OS level.
2. The headless subshell exits without emitting the \_\_vsc_precmd completion signal.
3. Kiro's IPC observer waits for the signal, times out, assumes the execution channel hung or crashed unexpectedly, and outputs a synthetic -1 exit status.

By enforcing VSCODE_SHELL_INTEGRATION=1 and guaranteeing \_\_vsc_precmd exists inside ~/.zshenv, the subshell satisfies Kiro's event runner, enabling automated sub-agent tasks to complete without requiring IDE source code modifications.

---
---
---
---

## Issue #2 - Exit Code: -1 on commands longer than ~2s (not caused by missing shell integration hooks)

Any agent or sub-agent shell command that takes more than roughly two seconds is abandoned by the runner. Output is truncated at the cutoff and the call reports Exit Code: -1. The agent cannot tell that a build or test finished, so it retries the same command and sits in a "working..." state. Attempting to wait with sleep N makes it worse: the sleep consumes the whole budget, so everything after it never reports and output comes back empty.

```
sleep 55; cd ~/project && grep -E "EXIT=|Test Files" /tmp/t1.log; tail -4 /tmp/t1.log
Output:

Exit Code: -1
```

### 1. Measured behavior:

```
command	                                                    result
date; sleep 1; echo ok; date	                            full output, exit 0
date; sleep 2; echo ok; date	                            full output, exit -1
date; sleep 8; echo ok; date	                            truncated after first line, exit -1
date; for i in 1..6; do echo tick $i; sleep 1; done; date	truncated at tick 3, exit -1
date; python3 -c "<5s busy loop>"; date	                    truncated, exit -1
```

### 2. What this rules out

1. Not the sleep builtin or binary. A pure CPU busy-loop with no sleep call at all fails identically, so the trigger is wall-clock duration.
2. Not the tool's timeout parameter. Re-running the 8s case with an explicit 30s timeout produced the same truncation and -1.
3. Not missing __vsc_precmd / __vsc_preexec. The shell that fails already has the real hooks loaded and registered by Kiro's own injection, with VSCODE_INJECTION=1, KIRO_SHELL_INTEGRATION=1, TERM_PROGRAM=kiro, in an interactive shell:

```
precmd_functions=_omz_async_request omz_termsupport_precmd omz_termsupport_cwd __vsc_precmd
preexec_functions=omz_termsupport_preexec __vsc_preexec
```

### 3. Workaround

Steering file: exit-code-minus-1.md. Move the fix to the invocation level rather than the shell. Three rules: never wait in the foreground; background the build or test and poll with commands that each finish under two seconds; append an EXIT=$? sentinel so completion and the real status are read from the log rather than from the runner.

