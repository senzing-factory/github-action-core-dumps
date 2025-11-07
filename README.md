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

## Usage

```console
name: core dump test

on: [push]

jobs:
  core-dump-test:
    runs-on: ${{ matrix.os }}
    strategy:
      fail-fast: false
      matrix:
        os: [ubuntu-latest, macos-latest]

    steps:
      - name: Enable core dumps
        uses: senzing-factory/github-action-core-dumps@v1
        with:
          enable-core-dumps: true

      - name: Run pytest
        run: |
          pytest tests/ --verbose --capture=no --cov=src --cov-append

      - if: ${{ always() }}
        name: Analyze core dumps
        uses: senzing-factory/github-action-core-dumps@v1
        with:
          analyze-core-dumps: true
```
