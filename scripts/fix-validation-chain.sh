#!/bin/bash
# Fix MSP validation chain - remove intermediatecerts to keep single chain

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

echo "==============================================="
echo "Fixing MSP Validation Chain"
echo "==============================================="

cd "$PROJECT_ROOT"

# Remove intermediatecerts from all MSP directories
# This ensures only a single validation chain (cacerts)

echo "Removing intermediatecerts from orderer MSPs..."
find organizations/ordererOrganizations -type d -name "intermediatecerts" -exec rm -rf {} + 2>/dev/null || true

echo "Removing intermediatecerts from peer MSPs..."
find organizations/peerOrganizations -type d -name "intermediatecerts" -exec rm -rf {} + 2>/dev/null || true

echo "✓ Intermediate cert directories removed"

echo ""
echo "Restarting orderers and peers..."
docker-compose -f docker-compose-hot.yml -f docker-compose-cold.yml restart

echo ""
echo "Waiting for network to stabilize..."
sleep 10

echo ""
echo "==============================================="
echo "✓ MSP Validation Chain Fixed"
echo "==============================================="
