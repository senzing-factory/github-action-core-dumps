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
    EXEC_PATH=$(gdb -batch -c "$CORE_FILE" -ex "info proc exe" 2>/dev/null | grep "exe = " | sed "s/.*exe = '\([^']*\)'.*/\1/" || true)
  
    # If still not found, try parsing the core file name
    if [ -z "$EXEC_PATH" ] || [ ! -f "$EXEC_PATH" ]; then
      CORE_NAME=$(basename "$CORE_FILE")
      echo "[INFO] Attempting to extract program name from core filename: $CORE_NAME"
    
      # Extract program name from core.PROGRAM.PID.TIMESTAMP format
      if [[ "$CORE_NAME" =~ ^core\.([^.]+)\.([0-9]+)\.([0-9]+)$ ]]; then
        PROG_NAME="${BASH_REMATCH[1]}"
        echo "[INFO] Extracted program name: $PROG_NAME"
      
        # Try to find the executable
        if [[ "$PROG_NAME" == "python"* ]] || [[ "$PROG_NAME" == "Python"* ]]; then
          EXEC_PATH=$(which python3 2>/dev/null || which python 2>/dev/null)
        elif [[ "$PROG_NAME" == "segfault" ]]; then
          # Check common locations
          if [ -f "${GITHUB_WORKSPACE}/test/segfault" ]; then
            EXEC_PATH="${GITHUB_WORKSPACE}/test/segfault"
          else
            EXEC_PATH=$(which segfault 2>/dev/null || echo "")
          fi
        else
          EXEC_PATH=$(which "$PROG_NAME" 2>/dev/null || echo "")
        fi
      fi
    fi
  
    # Final fallback
    if [ -z "$EXEC_PATH" ] || [ ! -f "$EXEC_PATH" ]; then
      echo "[WARN] Using fallback executable path"
      EXEC_PATH="${GITHUB_WORKSPACE}/test/segfault"
    fi
  fi

  echo "[INFO] Analyzing core dump with executable: $EXEC_PATH"

  # Detect executable type by actually examining the binary
  EXEC_TYPE="native"
  if [[ "$EXEC_PATH" == *"python"* ]] || [[ "$EXEC_PATH" == *"Python"* ]]; then
    EXEC_TYPE="python"
  elif [ -f "$EXEC_PATH" ]; then
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

  echo "[INFO] Detected executable type: $EXEC_TYPE"

  # Only install delve if we detected Go
  if [ "$EXEC_TYPE" == "go" ]; then
    if command -v go &> /dev/null; then
      if ! command -v dlv &> /dev/null; then
        echo "[INFO] Installing delve for Go analysis"
        go install github.com/go-delve/delve/cmd/dlv@latest
        export PATH="$HOME/go/bin:$PATH"
      fi
    else
      echo "[WARN] Go not found, skipping delve installation"
    fi
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
      if command -v dlv &> /dev/null && [ -f "$EXEC_PATH" ]; then
        echo "[INFO] Using delve for enhanced Go analysis"
        printf '%s\n' "goroutines" "bt" "exit" | \
          dlv core "$EXEC_PATH" "$CORE_FILE" --check-go-version=false >> backtrace.txt 2>&1 || true
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
else
  echo "[INFO] No core dump found"
  echo "[INFO] Checking system limits:"
  ulimit -a
fi
