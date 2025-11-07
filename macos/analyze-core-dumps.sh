#!/usr/bin/env bash
set -e

ls -ltc /cores

# Find core dump
CORE_FILE=$(find /cores -maxdepth 1 -type f -regex '.*/core\.[^.]+\.[0-9]+' -newer /tmp/core_dump_start_marker 2>/dev/null)

if [ -n "$CORE_FILE" ]; then
  echo "[INFO] Found core dump: $CORE_FILE"
  echo "[INFO] run lldb"
  lldb -c "$CORE_FILE" -o "bt all" -o "quit" > backtrace.txt 2>&1
  cat backtrace.txt
else
  echo "[INFO] No core dump found"
  ulimit -a | grep core
fi
