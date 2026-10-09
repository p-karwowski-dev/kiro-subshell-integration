# Exit Code: -1

Synchronous calls fail because the runner abandons the call about two seconds in, so anything after a long-running step never gets to report and the caller gets empty output plus `-1`. The sub-agent then re-runs it, which is the "working..." loop.

## Fix

The fix is at the invocation level, not the shell level. For builds and tests:

Never wait in the foreground. No `sleep N` in a command, ever.

```
sleep 55; grep EXIT= /tmp/t1.log        # wrong
```

Start the build or test as a background process, then poll it with short commands that each finish in under two seconds.

```
nohup npm test > /tmp/t1.log 2>&1 &
tail -4 /tmp/t1.log
```

Append a sentinel so completion and the real exit status are read from the log, not from the runner, whose exit code is unreliable for anything that is not near-instant.

```
nohup sh -c 'npm test; echo "EXIT=$?"' > /tmp/t1.log 2>&1 &
grep -c 'EXIT=' /tmp/t1.log
grep 'EXIT=' /tmp/t1.log
```
