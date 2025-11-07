#!/usr/bin/env bash
set -e

# Install Python debug symbols and GDB
sudo apt-get update
sudo apt-get install -y python3-dbg gdb

# Find core dump
CORE_FILE=$(find /tmp/coredumps -maxdepth 1 -type f -regex '.*/core\.[^.]+\.[0-9]+\.[0-9]+' -newer /tmp/core_dump_start_marker)

if [ -n "$CORE_FILE" ]; then
  echo "[INFO] Found core dump: $CORE_FILE"

  echo "[INFO] run gdb"
  # Get backtrace
  gdb -batch \
    -ex "set pagination off" \
    -ex "thread apply all bt full" -ex "thread apply all py-bt" \
    ./venv/bin/python "$CORE_FILE" > backtrace.txt 2>&1

  echo "[INFO] cat backtrace.txt"
  cat backtrace.txt
else
  echo "[INFO] No core dump found"
  echo "[INFO] Checking system limits:"
  ulimit -a
fi
