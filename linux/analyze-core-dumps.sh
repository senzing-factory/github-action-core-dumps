#!/usr/bin/env bash
set -e

# Install Python debug symbols and GDB
sudo apt-get -qq update
sudo apt-get install -yqq python3-dbg gdb

# Find core dump
CORE_FILE=$(find /tmp/coredumps -maxdepth 1 -type f -regex '.*/core\.[^.]+\.[0-9]+\.[0-9]+' -newer /tmp/core_dump_start_marker)

if [ -n "$CORE_FILE" ]; then
  echo "[INFO] Found core dump: $CORE_FILE"

  # Determine the executable from the core dump
  EXEC_PATH=$(file "$CORE_FILE" | sed -n "s/.*from '\([^']*\)'.*/\1/p")

  if [ -z "$EXEC_PATH" ] || [ ! -f "$EXEC_PATH" ]; then
    echo "[WARN] Could not determine executable from core dump"
    EXEC_PATH="${GITHUB_WORKSPACE}/test/segfault"  # Fallback for test
  fi

  echo "[INFO] Analyzing core dump with executable: $EXEC_PATH"

  # Detect executable type
  EXEC_TYPE="native"
  if [[ "$EXEC_PATH" == *"python"* ]] || file "$EXEC_PATH" | grep -q "Python"; then
    EXEC_TYPE="python"
  elif file "$EXEC_PATH" | grep -q "Go "; then
    EXEC_TYPE="go"
  fi

  echo "[INFO] Detected executable type: $EXEC_TYPE"

  # Check if Go is available (needed for go install)
  if command -v go &> /dev/null; then
    if ! command -v dlv &> /dev/null; then
      echo "[INFO] Installing delve for Go analysis"
      go install github.com/go-delve/delve/cmd/dlv@latest
      export PATH="$HOME/go/bin:$PATH"
    fi
  else
    echo "[WARN] Go not found, skipping delve installation"
  fi

  # Analyze based on type
  case "$EXEC_TYPE" in
    python)
      echo "[INFO] Python crash detected, using py-bt"
      gdb -batch \
        -ex "set pagination off" \
        -ex "thread apply all bt full" \
        -ex "thread apply all py-bt" \
        "$EXEC_PATH" "$CORE_FILE" > backtrace.txt 2>&1
      ;;
    
    go)
      echo "[INFO] Go crash detected, using Go-specific analysis"
      # Go binaries have runtime info built-in
      gdb -batch \
        -ex "set pagination off" \
        -ex "thread apply all bt full" \
        -ex "info goroutines" \
        "$EXEC_PATH" "$CORE_FILE" > backtrace.txt 2>&1
    
      # Also try using delve if available (Go debugger)
      if command -v dlv &> /dev/null; then
        echo "[INFO] Using delve for enhanced Go analysis"
        printf '%s\n' "goroutines" "bt" "exit" | \
          dlv core "$EXEC_PATH" "$CORE_FILE" --check-go-version=false >> backtrace.txt 2>&1
      fi
      ;;
    
    *)
      echo "[INFO] Native crash detected, using standard backtrace"
      gdb -batch \
        -ex "set pagination off" \
        -ex "thread apply all bt full" \
        "$EXEC_PATH" "$CORE_FILE" > backtrace.txt 2>&1
      ;;
  esac

  echo "[INFO] Backtrace analysis complete"

  echo "[INFO] cat backtrace.txt"
  cat backtrace.txt
else
  echo "[INFO] No core dump found"
  echo "[INFO] Checking system limits:"
  ulimit -a
fi
