#!/usr/bin/with-contenv bash
set -e

echo "[Init] All initialization complete - signaling services to start..."

# Signal that all init scripts have completed
touch /tmp/.services-ready

echo "[Init] Services ready!"

exit 0
