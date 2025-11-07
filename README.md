# github-action-core-dumps

Composite action for enabling, analyzing, and uploading core dumps.

## Overview

This action is broken into two parts:

1. Enabling core dumps.
   - Configures the system to log core dumps.
   - Set `enable-core-dumps: true`
   - This should be run **_before_** any testing or build that might result in a core dump.
1. Analyzing / Uploading core dumps.
   - Run analysis with gdb and upload if any core dumps are found.
   - Use: `if: ${{ always() }}` to ensure dump checks even if a prior step fails.
   - Set `analyze-core-dumps: true`
   - This should be run **_after_** any testing or build that might result in a core dump.

Currently supports:

- **Go** - uses info goroutines and optionally delve if available
- **Native/C/C++** - standard bt full backtrace
- **Python** - uses py-bt for Python-specific stack traces

## Usage

[.github/workflows/core-dump-test.yaml]

```console
name: core dump test

on: [push]

permissions: {}

jobs:
  core-dump-test-c:
    runs-on: ${{ matrix.os }}
    permissions:
      contents: read
    strategy:
      fail-fast: false
      matrix:
        os: [ubuntu-latest, macos-latest]

    steps:
      - uses: actions/checkout@v5
        with:
          persist-credentials: false

      - name: Enable core dumps
        uses: senzing-factory/github-action-core-dumps@v1
        with:
          enable-core-dumps: "true"

      - name: Intentionally force a segfault (C)
        run: |
          ulimit -c unlimited
          cd "${GITHUB_WORKSPACE}/test"
          gcc -g segfault.c -o segfault
          ./segfault

      - if: always()
        name: Analyze core dumps
        uses: senzing-factory/github-action-core-dumps@v1
        with:
          analyze-core-dumps: "true"
          core-file-suffix: c-${{ matrix.os }}

  core-dump-test-python:
    runs-on: ${{ matrix.os }}
    permissions:
      contents: read
    strategy:
      fail-fast: false
      matrix:
        os: [ubuntu-latest, macos-latest]

    steps:
      - uses: actions/checkout@v5
        with:
          persist-credentials: false

      - name: Setup Python
        uses: actions/setup-python@v5

      - name: Enable core dumps
        uses: senzing-factory/github-action-core-dumps@v1
        with:
          enable-core-dumps: "true"

      - name: Intentionally force a segfault (Python)
        run: |
          ulimit -c unlimited
          python3 -c "import os, signal; os.kill(os.getpid(), signal.SIGSEGV)"

      - if: always()
        name: Analyze core dumps
        uses: senzing-factory/github-action-core-dumps@v1
        with:
          analyze-core-dumps: "true"
          core-file-suffix: python-${{ matrix.os }}

  core-dump-test-go:
    runs-on: ${{ matrix.os }}
    permissions:
      contents: read
    strategy:
      fail-fast: false
      matrix:
        os: [ubuntu-latest, macos-latest]

    steps:
      - uses: actions/checkout@v5
        with:
          persist-credentials: false

      - name: Setup Go
        uses: actions/setup-go@v5
        with:
          go-version: "stable"

      - name: Enable core dumps
        uses: senzing-factory/github-action-core-dumps@v1
        with:
          enable-core-dumps: "true"

      - name: Intentionally force a segfault (Go)
        run: |
          ulimit -c unlimited
          cd "${GITHUB_WORKSPACE}/test"
          # Build the binary first, then run it
          # Build with debug symbols and no optimizations
          # Build with debug symbols and no optimizations for better debugging
          go build -gcflags='all=-N -l' -o segfault segfault.go
          GOTRACEBACK=crash ./segfault

      - if: always()
        name: Analyze core dumps
        uses: senzing-factory/github-action-core-dumps@v1
        with:
          analyze-core-dumps: "true"
          core-file-suffix: go-${{ matrix.os }}
```

[.github/workflows/core-dump-test.yaml]: .github/workflows/core-dump-test.yaml
