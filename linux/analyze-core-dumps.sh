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
    echo "[WARN] Could not determine executable from core dump, attempting to extract from core"
  
    # Try to get the executable from the core dump using gdb
    EXEC_PATH=$(gdb -batch -c "$CORE_FILE" -ex "info proc exe" 2>/dev/null | grep "exe = " | sed "s/.*exe = '\([^']*\)'.*/\1/")
  
    # If still not found, try reading from core dump directly
    if [ -z "$EXEC_PATH" ] || [ ! -f "$EXEC_PATH" ]; then
      # Look for common patterns in the core file name
      CORE_NAME=$(basename "$CORE_FILE")
      if [[ "$CORE_NAME" == *"python"* ]]; then
        EXEC_PATH=$(which python3 2>/dev/null || which python 2>/dev/null)
      elif [[ "$CORE_NAME" == core.*.* ]]; then
        # Extract program name from core.PROGRAM.PID.TIMESTAMP format
        PROG_NAME=$(echo "$CORE_NAME" | cut -d'.' -f2)
        EXEC_PATH=$(which "$PROG_NAME" 2>/dev/null)
      fi
    fi

    # Special case for Go programs run with 'go run'
    if [[ "$CORE_NAME" == *"go-build"* ]] || [[ "$CORE_NAME" == *"exe"* ]]; then
      echo "[INFO] Detected Go temporary executable from 'go run'"
      EXEC_TYPE="go"
      # For go run, we can't recover the binary, but we know it's Go
    fi
  
    # Final fallback
    if [ -z "$EXEC_PATH" ] || [ ! -f "$EXEC_PATH" ]; then
      echo "[WARN] Using fallback executable path"
      EXEC_PATH="${GITHUB_WORKSPACE}/test/segfault"
    fi
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
