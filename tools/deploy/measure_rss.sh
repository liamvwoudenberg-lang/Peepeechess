#!/usr/bin/env bash
# Start a command, sample its peak resident memory (VmHWM) from /proc until it exits, print the peak in MiB.
#   tools/deploy/measure_rss.sh SECONDS cmd args...   (the command is killed after SECONDS if still running)
set -u
secs="$1"; shift
"$@" > /dev/null 2>&1 &
pid=$!
peak=0
end=$((SECONDS + secs))
while kill -0 "$pid" 2>/dev/null && [ $SECONDS -lt $end ]; do
  hwm=$(awk '/VmHWM/ {print $2}' "/proc/$pid/status" 2>/dev/null || echo 0)
  [ "${hwm:-0}" -gt "$peak" ] && peak=$hwm
  sleep 0.2
done
kill "$pid" 2>/dev/null; wait "$pid" 2>/dev/null
echo "peak_rss_mib=$((peak / 1024))"
