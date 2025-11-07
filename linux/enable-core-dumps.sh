#!/usr/bin/env bash
set -ex

echo "[INFO] enable linux core dumps"
# Create core dump directory
sudo mkdir -p /tmp/coredumps
sudo chmod 1777 /tmp/coredumps

# Set unlimited core dump size globally
echo "* soft core unlimited" | sudo tee -a /etc/security/limits.conf
echo "* hard core unlimited" | sudo tee -a /etc/security/limits.conf

# Also set for current session
ulimit -c unlimited

# Configure core dump pattern to use specific directory
echo "/tmp/coredumps/core.%e.%p.%t" | sudo tee /proc/sys/kernel/core_pattern

# Export to GITHUB_ENV so it persists
echo "ULIMIT_CORE=unlimited" >> "$GITHUB_ENV"

# Verify settings
echo "[INFO] Core dump settings:"
ulimit -a | grep core
cat /proc/sys/kernel/core_pattern

touch /tmp/core_dump_start_marker

echo 'ulimit -c unlimited' >> ~/.bashrc
echo "BASH_ENV=$HOME/.bashrc" >> "$GITHUB_ENV"
