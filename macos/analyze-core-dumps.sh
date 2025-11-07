#!/usr/bin/env bash
set -e

ls -ltc /cores

# Find core dump
CORE_FILE=$(find /cores -maxdepth 1 -type f -name "core.*.*" -newer /tmp/core_dump_start_marker 2>/dev/null | head -n 1)

if [ -n "$CORE_FILE" ]; then
  echo "[INFO] Found core dump: $CORE_FILE"
  
  # Determine the executable from the core dump
  # Try to extract from core file name first
  CORE_NAME=$(basename "$CORE_FILE")
  EXEC_PATH=""
  
  # Extract program name from core.PROGRAM.PID format
  if [[ "$CORE_NAME" =~ ^core\.([^.]+)\.([0-9]+)$ ]]; then
    PROG_NAME="${BASH_REMATCH[1]}"
    echo "[INFO] Extracted program name from core: $PROG_NAME"
    
    # Try to find the executable
    if [[ "$PROG_NAME" == "Python" ]] || [[ "$PROG_NAME" == "python"* ]]; then
      EXEC_PATH=$(which python3 2>/dev/null || which python 2>/dev/null)
    elif [[ "$PROG_NAME" == "segfault" ]]; then
      # Check common locations
      if [ -f "${GITHUB_WORKSPACE}/test/segfault" ]; then
        EXEC_PATH="${GITHUB_WORKSPACE}/test/segfault"
      else
        EXEC_PATH=$(which segfault 2>/dev/null)
      fi
    else
      EXEC_PATH=$(which "$PROG_NAME" 2>/dev/null)
    fi
  fi
  
  # Try otool as backup
  if [ -z "$EXEC_PATH" ] || [ ! -f "$EXEC_PATH" ]; then
    EXEC_PATH=$(otool -L "$CORE_FILE" 2>/dev/null | head -2 | tail -1 | awk '{print $1}')
  fi
  
  # Final fallback
  if [ -z "$EXEC_PATH" ] || [ ! -f "$EXEC_PATH" ]; then
    echo "[WARN] Could not determine executable from core dump"
    EXEC_PATH="${GITHUB_WORKSPACE}/test/segfault"
  fi
  
  echo "[INFO] Analyzing core dump with executable: $EXEC_PATH"
  
  # Detect executable type
  EXEC_TYPE="native"
  if [[ "$EXEC_PATH" == *"python"* ]] || [[ "$EXEC_PATH" == *"Python"* ]] || file "$EXEC_PATH" | grep -q "Python"; then
    EXEC_TYPE="python"
  elif file "$EXEC_PATH" | grep -q "Go " || [[ "$PROG_NAME" == "segfault" && -f "${GITHUB_WORKSPACE}/test/segfault.go" ]]; then
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
      if command -v dlv &> /dev/null && [ -f "$EXEC_PATH" ]; then
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
