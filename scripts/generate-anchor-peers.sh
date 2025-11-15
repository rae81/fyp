#!/bin/bash
# Generate anchor peer update transactions

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

echo "=========================================="
echo "Generating Anchor Peer Transactions"
echo "=========================================="
echo ""

cd "$PROJECT_ROOT"

# Create channel-artifacts directory if it doesn't exist
mkdir -p channel-artifacts

# Generate anchor peer transactions for HOT blockchain
echo "[1/3] Generating Law Enforcement anchor peer transaction..."
export FABRIC_CFG_PATH="$PROJECT_ROOT/hot-blockchain"
configtxgen -profile HotChainChannel \
    -outputAnchorPeersUpdate ./channel-artifacts/LawEnforcementMSPanchors.tx \
    -channelID hotchannel \
    -asOrg LawEnforcementMSP
echo "✓ LawEnforcementMSPanchors.tx created"
echo ""

echo "[2/3] Generating Forensic Lab anchor peer transaction..."
configtxgen -profile HotChainChannel \
    -outputAnchorPeersUpdate ./channel-artifacts/ForensicLabMSPanchors.tx \
    -channelID hotchannel \
    -asOrg ForensicLabMSP
echo "✓ ForensicLabMSPanchors.tx created"
echo ""

# Generate anchor peer transaction for COLD blockchain
echo "[3/3] Generating Auditor anchor peer transaction..."
export FABRIC_CFG_PATH="$PROJECT_ROOT/cold-blockchain"
configtxgen -profile ColdChainChannel \
    -outputAnchorPeersUpdate ./channel-artifacts/AuditorMSPanchors.tx \
    -channelID coldchannel \
    -asOrg AuditorMSP
echo "✓ AuditorMSPanchors.tx created"
echo ""

echo "=========================================="
echo "✓ All anchor peer transactions generated"
echo "=========================================="
echo ""
ls -lh channel-artifacts/*.tx
