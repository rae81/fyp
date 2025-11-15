#!/bin/bash
# Regenerate channel artifacts with AuditorMSP and CourtMSP

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

echo "=== Regenerating HOT blockchain channel artifacts ==="

# Create channel-artifacts directory if it doesn't exist
mkdir -p "$PROJECT_ROOT/hot-blockchain/channel-artifacts"

# Generate channel genesis block (Fabric 2.5 uses channel participation, not system channel)
# Mount project root so ../organizations/ paths work correctly
docker run --rm -v "$PROJECT_ROOT:/work" -w /work/hot-blockchain \
  hyperledger/fabric-tools:2.5 \
  configtxgen -configPath /work/hot-blockchain \
  -profile HotChainChannel \
  -outputBlock channel-artifacts/hotchannel.block \
  -channelID hotchannel

# Generate anchor peer updates
docker run --rm -v "$PROJECT_ROOT:/work" -w /work/hot-blockchain \
  hyperledger/fabric-tools:2.5 \
  configtxgen -configPath /work/hot-blockchain \
  -profile HotChainChannel \
  -outputAnchorPeersUpdate channel-artifacts/LawEnforcementMSPanchors.tx \
  -channelID hotchannel \
  -asOrg LawEnforcementMSP

docker run --rm -v "$PROJECT_ROOT:/work" -w /work/hot-blockchain \
  hyperledger/fabric-tools:2.5 \
  configtxgen -configPath /work/hot-blockchain \
  -profile HotChainChannel \
  -outputAnchorPeersUpdate channel-artifacts/ForensicLabMSPanchors.tx \
  -channelID hotchannel \
  -asOrg ForensicLabMSP

echo -e "\n=== Regenerating COLD blockchain channel artifacts ==="

# Create channel-artifacts directory if it doesn't exist
mkdir -p "$PROJECT_ROOT/cold-blockchain/channel-artifacts"

# Generate channel genesis block
# Mount project root so ../organizations/ paths work correctly
docker run --rm -v "$PROJECT_ROOT:/work" -w /work/cold-blockchain \
  hyperledger/fabric-tools:2.5 \
  configtxgen -configPath /work/cold-blockchain \
  -profile ColdChainChannel \
  -outputBlock channel-artifacts/coldchannel.block \
  -channelID coldchannel

# Generate anchor peer update for Auditor
docker run --rm -v "$PROJECT_ROOT:/work" -w /work/cold-blockchain \
  hyperledger/fabric-tools:2.5 \
  configtxgen -configPath /work/cold-blockchain \
  -profile ColdChainChannel \
  -outputAnchorPeersUpdate channel-artifacts/AuditorMSPanchors.tx \
  -channelID coldchannel \
  -asOrg AuditorMSP

echo -e "\n=== Verifying new channel artifacts ==="
ls -lh "$PROJECT_ROOT/hot-blockchain/channel-artifacts/"
ls -lh "$PROJECT_ROOT/cold-blockchain/channel-artifacts/"

echo -e "\n=== Channel artifacts regenerated with AuditorMSP and CourtMSP! ==="
