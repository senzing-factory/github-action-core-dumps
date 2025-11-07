# ============================================================================
# macOS analyze-core-dumps.sh
# ============================================================================

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
    elif [[ "$PROG_NAME" == "pytest" ]] || [[ "$PROG_NAME" == "py.test" ]]; then
      # pytest is a Python wrapper, get the actual Python interpreter
      EXEC_PATH=$(which python3 2>/dev/null || which python 2>/dev/null)
      echo "[INFO] Detected pytest wrapper, using Python interpreter: $EXEC_PATH"
    elif [[ "$PROG_NAME" == "segfault" ]]; then
      # Check common locations
      if [ -f "${GITHUB_WORKSPACE}/test/segfault" ]; then
        EXEC_PATH="${GITHUB_WORKSPACE}/test/segfault"
      else
        EXEC_PATH=$(which segfault 2>/dev/null)
      fi
    else
      EXEC_PATH=$(which "$PROG_NAME" 2>/dev/null)
      
      # If we found a script wrapper, try to get the actual interpreter
      if [ -f "$EXEC_PATH" ] && head -n 1 "$EXEC_PATH" 2>/dev/null | grep -q "^#!.*python"; then
        echo "[INFO] Detected Python wrapper script, extracting interpreter"
        EXEC_PATH=$(which python3 2>/dev/null || which python 2>/dev/null)
      fi
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
  
  # Detect executable type by actually examining the binary
  EXEC_TYPE="native"
  if [[ "$EXEC_PATH" == *"python"* ]] || [[ "$EXEC_PATH" == *"Python"* ]]; then
    EXEC_TYPE="python"
  elif [ -f "$EXEC_PATH" ]; then
    # Check if it's a Python script wrapper
    if head -n 1 "$EXEC_PATH" 2>/dev/null | grep -q "^#!.*python"; then
      echo "[INFO] Detected Python wrapper script"
      EXEC_TYPE="python"
      # Replace with actual Python interpreter if we have a script
      ACTUAL_PYTHON=$(which python3 2>/dev/null || which python 2>/dev/null)
      if [ -n "$ACTUAL_PYTHON" ]; then
        echo "[INFO] Using Python interpreter: $ACTUAL_PYTHON"
        EXEC_PATH="$ACTUAL_PYTHON"
      fi
    else
      # Check the actual binary contents
      FILE_OUTPUT=$(file "$EXEC_PATH" 2>/dev/null)
      if echo "$FILE_OUTPUT" | grep -q "Python"; then
        EXEC_TYPE="python"
      elif echo "$FILE_OUTPUT" | grep -q "Go "; then
        EXEC_TYPE="go"
      # Check for Go-specific strings in the binary
      elif strings "$EXEC_PATH" 2>/dev/null | grep -q "^go1\.[0-9]"; then
        EXEC_TYPE="go"
      fi
    fi
  fi
  
  echo "[INFO] Detected executable type: $EXEC_TYPE"
  
  # Only install delve if we detected Go
  if [ "$EXEC_TYPE" == "go" ]; then
    if command -v go &> /dev/null; then
      if ! command -v dlv &> /dev/null; then
        echo "[INFO] Installing delve for Go analysis"
        go install github.com/go-delve/delve/cmd/dlv@latest > /dev/null 2>&1 || echo "[WARN] Failed to install delve"
        export PATH="$HOME/go/bin:$PATH"
      fi
    else
      echo "[WARN] Go not found, skipping delve installation"
    fi
  fi
  
  # Analyze based on type
  case "$EXEC_TYPE" in
    python)
      echo "[INFO] Python crash detected, using lldb with Python support"
      lldb -c "$CORE_FILE" \
        -o "bt all" \
        -o "frame variable" \
        -o "script import sys; print('Python version:', sys.version)" \
        -o "quit" > backtrace.txt 2>&1 || echo "[WARN] LLDB failed with exit code $?"
      ;;
      
    go)
      echo "[INFO] Go crash detected, using Go-specific analysis"
      
      # Try standard LLDB backtrace
      if lldb -c "$CORE_FILE" \
        -o "bt all" \
        -o "thread list" \
        -o "quit" > backtrace.txt 2>&1; then
        echo "[INFO] LLDB standard backtrace completed successfully"
      else
        echo "[WARN] LLDB standard backtrace failed with exit code $?"
      fi
      
      # Also try using delve if available (Go debugger)
      if command -v dlv &> /dev/null && [ -f "$EXEC_PATH" ]; then
        echo "[INFO] Using delve for enhanced Go analysis"
        echo "=== Delve Analysis ===" >> backtrace.txt
        if printf '%s\n' "goroutines" "bt" "exit" | \
          dlv core "$EXEC_PATH" "$CORE_FILE" --check-go-version=false >> backtrace.txt 2>&1; then
          echo "[INFO] Delve analysis completed successfully"
        else
          echo "[INFO] Delve analysis failed (binary may need to be compiled with: go build -gcflags='all=-N -l')"
        fi
      fi
      ;;
      
    *)
      echo "[INFO] Native crash detected, using standard backtrace"
      lldb -c "$CORE_FILE" \
        -o "bt all" \
        -o "quit" > backtrace.txt 2>&1 || echo "[WARN] LLDB failed with exit code $?"
      ;;
  esac
  
  echo "[INFO] Backtrace analysis complete"
  echo "[INFO] Backtrace output:"
  cat backtrace.txt || echo "[WARN] No backtrace file generated"
else
  echo "[INFO] No core dump found"
  ulimit -a | grep core
fi
