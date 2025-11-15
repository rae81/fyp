#!/bin/bash
# Regenerate channel artifacts with AuditorMSP and CourtMSP

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

echo "=== Regenerating HOT blockchain channel artifacts ==="
cd "$PROJECT_ROOT/hot-blockchain"

# Generate channel genesis block (Fabric 2.5 uses channel participation, not system channel)
docker run --rm -v "$(pwd):/work" -w /work \
  hyperledger/fabric-tools:2.5 \
  configtxgen -profile HotChainChannel \
  -outputBlock channel-artifacts/hotchannel.block \
  -channelID hotchannel

# Generate anchor peer updates
docker run --rm -v "$(pwd):/work" -w /work \
  hyperledger/fabric-tools:2.5 \
  configtxgen -profile HotChainChannel \
  -outputAnchorPeersUpdate channel-artifacts/LawEnforcementMSPanchors.tx \
  -channelID hotchannel \
  -asOrg LawEnforcement

docker run --rm -v "$(pwd):/work" -w /work \
  hyperledger/fabric-tools:2.5 \
  configtxgen -profile HotChainChannel \
  -outputAnchorPeersUpdate channel-artifacts/ForensicLabMSPanchors.tx \
  -channelID hotchannel \
  -asOrg ForensicLab

echo -e "\n=== Regenerating COLD blockchain channel artifacts ==="
cd "$PROJECT_ROOT/cold-blockchain"

# Generate channel genesis block
docker run --rm -v "$(pwd):/work" -w /work \
  hyperledger/fabric-tools:2.5 \
  configtxgen -profile ColdChainChannel \
  -outputBlock channel-artifacts/coldchannel.block \
  -channelID coldchannel

# Generate anchor peer update for Auditor
docker run --rm -v "$(pwd):/work" -w /work \
  hyperledger/fabric-tools:2.5 \
  configtxgen -profile ColdChainChannel \
  -outputAnchorPeersUpdate channel-artifacts/AuditorMSPanchors.tx \
  -channelID coldchannel \
  -asOrg Auditor

echo -e "\n=== Verifying new channel artifacts ==="
ls -lh "$PROJECT_ROOT/hot-blockchain/channel-artifacts/"
ls -lh "$PROJECT_ROOT/cold-blockchain/channel-artifacts/"

echo -e "\n=== Channel artifacts regenerated with AuditorMSP and CourtMSP! ==="
