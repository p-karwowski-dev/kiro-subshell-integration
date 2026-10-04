---
inclusion: always
---

# Shell exit codes are unreliable for slow or silent commands

The agent shell runner sometimes reports `exitCode: -1` for commands that
actually succeeded. The command ran and did the right thing; only the reported
exit code (and sometimes the stdout) is lost.

`-1` here means "completion not observed," not "command failed." A real failure
reports its true non-zero code (e.g. `1`), so treat `-1` as unknown, never as a
confirmed error.

## When it happens

A command returns `-1` despite succeeding when it:

- pauses between its last output and completion (e.g. a trailing `sleep`), or
- produces no terminal output near the end (e.g. `> file`, `| tail`, `> /dev/null`).

Fast, continuously-streaming commands report correct exit codes, including
genuine failures.

## Workaround — write commands so completion is detectable

- Keep commands streaming and fast-finishing. Avoid a trailing `sleep`, and
  avoid redirecting or paging the final stage (`> file`, `| tail`, `> /dev/null`).
- End a command with a streamed sentinel that is **not** redirected, then read it
  from stdout instead of trusting the reported exit code:

  ```zsh
  <command>; printf 'DONE rc=%d\n' $?
  ```

  Parse `rc=` from stdout. If you see `DONE rc=0`, the command succeeded even if
  the tool reports `exitCode: -1`.
- For commands that are unavoidably slow or quiet, write output to a file, then
  read that file in a **separate, fast** command rather than relying on the first
  command's reported result.

## When you get `-1`

Do not conclude the command failed. Confirm the real outcome another way:
re-read the affected file, check `git status`, or re-run with the streamed
`rc=` sentinel above. Only a true non-zero code (not `-1`) indicates failure.
