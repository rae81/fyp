#!/bin/bash

# Script to copy core.yaml files to all peer directories
# This fixes the "core.yaml not found" error

echo "==========================================="
echo "   Copying core.yaml to Peer Directories"
echo "==========================================="
echo ""

GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

# Source core.yaml from fabric-samples
SOURCE_CORE_YAML="fabric-samples/test-network/compose/docker/peercfg/core.yaml"

if [ ! -f "$SOURCE_CORE_YAML" ]; then
    echo -e "${RED}❌ Source core.yaml not found at: $SOURCE_CORE_YAML${NC}"
    exit 1
fi

echo "Source: $SOURCE_CORE_YAML"
echo ""

# Hot Blockchain - Law Enforcement Peer
DEST1="hot-blockchain/crypto-config/peerOrganizations/lawenforcement.hot.coc.com/peers/peer0.lawenforcement.hot.coc.com/core.yaml"
if [ -d "$(dirname "$DEST1")" ]; then
    cp "$SOURCE_CORE_YAML" "$DEST1"
    echo -e "${GREEN}✓${NC} Copied to Law Enforcement peer"
else
    echo -e "${RED}✗${NC} Law Enforcement peer directory not found"
fi

# Hot Blockchain - Forensic Lab Peer
DEST2="hot-blockchain/crypto-config/peerOrganizations/forensiclab.hot.coc.com/peers/peer0.forensiclab.hot.coc.com/core.yaml"
if [ -d "$(dirname "$DEST2")" ]; then
    cp "$SOURCE_CORE_YAML" "$DEST2"
    echo -e "${GREEN}✓${NC} Copied to Forensic Lab peer"
else
    echo -e "${RED}✗${NC} Forensic Lab peer directory not found"
fi

# Cold Blockchain - Archive Peer
DEST3="cold-blockchain/crypto-config/peerOrganizations/archive.cold.coc.com/peers/peer0.archive.cold.coc.com/core.yaml"
if [ -d "$(dirname "$DEST3")" ]; then
    cp "$SOURCE_CORE_YAML" "$DEST3"
    echo -e "${GREEN}✓${NC} Copied to Archive peer"
else
    echo -e "${RED}✗${NC} Archive peer directory not found"
fi

echo ""
echo -e "${GREEN}✓ core.yaml files copied successfully${NC}"
echo ""
echo "Next steps:"
echo "  1. Run ./restart-blockchain.sh to restart with fixed configuration"
echo "  2. Verify peers are running: docker ps | grep peer"
echo ""
