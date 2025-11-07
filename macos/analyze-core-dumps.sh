#!/usr/bin/env bash
set -e

ls -ltc /cores

# Find core dump
CORE_FILE=$(find /cores -maxdepth 1 -type f -name "core.*.*" -newer /tmp/core_dump_start_marker 2>/dev/null | head -n 1)

if [ -n "$CORE_FILE" ]; then
  echo "[INFO] Found core dump: $CORE_FILE"
  
  # Determine the executable from the core dump
  EXEC_PATH=$(otool -L "$CORE_FILE" 2>/dev/null | head -2 | tail -1 | awk '{print $1}')
  
  # Try to extract executable info from core dump metadata
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
      echo "[INFO] Python crash detected, using lldb with Python support"
      lldb -c "$CORE_FILE" \
        -o "bt all" \
        -o "frame variable" \
        -o "script import sys; print('Python version:', sys.version)" \
        -o "quit" > backtrace.txt 2>&1
      ;;
      
    go)
      echo "[INFO] Go crash detected, using Go-specific analysis"
      lldb -c "$CORE_FILE" \
        -o "bt all" \
        -o "thread list" \
        -o "quit" > backtrace.txt 2>&1
      
      # Also try using delve if available (Go debugger)
      if command -v dlv &> /dev/null; then
        echo "[INFO] Using delve for enhanced Go analysis"
        printf '%s\n' "goroutines" "bt" "exit" | \
          dlv core "$EXEC_PATH" "$CORE_FILE" --check-go-version=false >> backtrace.txt 2>&1
      fi
      ;;
      
    *)
      echo "[INFO] Native crash detected, using standard backtrace"
      lldb -c "$CORE_FILE" \
        -o "bt all" \
        -o "quit" > backtrace.txt 2>&1
      ;;
  esac
  
  echo "[INFO] Backtrace analysis complete"
  cat backtrace.txt
else
  echo "[INFO] No core dump found"
  ulimit -a | grep core
fi
