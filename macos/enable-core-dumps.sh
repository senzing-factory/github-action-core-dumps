#!/usr/bin/env bash
set -e

echo "[INFO] enable macos core dumps"
ulimit -c unlimited
sudo mkdir -p /cores
sudo chmod 1777 /cores
sudo sysctl kern.coredump=1
sudo sysctl kern.corefile=/cores/core.%N.%P
echo "Core dump settings:"
ulimit -a | grep core
sysctl kern.corefile
sysctl kern.coredump

touch /tmp/core_dump_start_marker
