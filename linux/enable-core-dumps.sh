#!/usr/bin/env bash
set -ex

echo "[INFO] enable linux core dumps"
# Create core dump directory
sudo mkdir -p /tmp/coredumps
sudo chmod 1777 /tmp/coredumps

# Set unlimited core dump size
ulimit -c unlimited

# Configure core dump pattern to use specific directory
echo "/tmp/coredumps/core.%e.%p.%t" | sudo tee /proc/sys/kernel/core_pattern

# Verify settings
echo "[INFO] Core dump settings:"
ulimit -a | grep core
cat /proc/sys/kernel/core_pattern

touch /tmp/core_dump_start_marker
