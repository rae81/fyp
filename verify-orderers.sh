#!/bin/bash

# Script to verify and fix orderer channel participation
# Run this if transactions are timing out

echo "==========================================="
echo "   Orderer Channel Verification & Fix"
echo "==========================================="
echo ""

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

# Check if orderers are in channels
echo -e "${YELLOW}Checking if orderers are in channels...${NC}"
echo ""

echo "Hot Orderer (orderer.hot.coc.com) channels:"
docker exec cli osnadmin channel list \
    -o orderer.hot.coc.com:7053 \
    --ca-file /opt/gopath/src/github.com/hyperledger/fabric/peer/crypto/ordererOrganizations/hot.coc.com/orderers/orderer.hot.coc.com/msp/tlscacerts/tlsca.hot.coc.com-cert.pem \
    --client-cert /opt/gopath/src/github.com/hyperledger/fabric/peer/crypto/ordererOrganizations/hot.coc.com/orderers/orderer.hot.coc.com/tls/server.crt \
    --client-key /opt/gopath/src/github.com/hyperledger/fabric/peer/crypto/ordererOrganizations/hot.coc.com/orderers/orderer.hot.coc.com/tls/server.key \
    2>&1

HOT_IN_CHANNEL=$?

echo ""
echo "Cold Orderer (orderer.cold.coc.com) channels:"
docker exec cli-cold osnadmin channel list \
    -o orderer.cold.coc.com:7153 \
    --ca-file /opt/gopath/src/github.com/hyperledger/fabric/peer/crypto/ordererOrganizations/cold.coc.com/orderers/orderer.cold.coc.com/msp/tlscacerts/tlsca.cold.coc.com-cert.pem \
    --client-cert /opt/gopath/src/github.com/hyperledger/fabric/peer/crypto/ordererOrganizations/cold.coc.com/orderers/orderer.cold.coc.com/tls/server.crt \
    --client-key /opt/gopath/src/github.com/hyperledger/fabric/peer/crypto/ordererOrganizations/cold.coc.com/orderers/orderer.cold.coc.com/tls/server.key \
    2>&1

COLD_IN_CHANNEL=$?

echo ""
echo "==========================================="
echo ""

# If orderers not in channels, join them
if [ $HOT_IN_CHANNEL -ne 0 ] || ! docker exec cli osnadmin channel list -o orderer.hot.coc.com:7053 \
    --ca-file /opt/gopath/src/github.com/hyperledger/fabric/peer/crypto/ordererOrganizations/hot.coc.com/orderers/orderer.hot.coc.com/msp/tlscacerts/tlsca.hot.coc.com-cert.pem \
    --client-cert /opt/gopath/src/github.com/hyperledger/fabric/peer/crypto/ordererOrganizations/hot.coc.com/orderers/orderer.hot.coc.com/tls/server.crt \
    --client-key /opt/gopath/src/github.com/hyperledger/fabric/peer/crypto/ordererOrganizations/hot.coc.com/orderers/orderer.hot.coc.com/tls/server.key 2>&1 | grep -q "hotchannel"; then

    echo -e "${YELLOW}Hot orderer not in hotchannel. Joining...${NC}"
    docker exec cli osnadmin channel join \
        --channelID hotchannel \
        --config-block /opt/gopath/src/github.com/hyperledger/fabric/peer/channel-artifacts/hotchannel.block \
        -o orderer.hot.coc.com:7053 \
        --ca-file /opt/gopath/src/github.com/hyperledger/fabric/peer/crypto/ordererOrganizations/hot.coc.com/orderers/orderer.hot.coc.com/msp/tlscacerts/tlsca.hot.coc.com-cert.pem \
        --client-cert /opt/gopath/src/github.com/hyperledger/fabric/peer/crypto/ordererOrganizations/hot.coc.com/orderers/orderer.hot.coc.com/tls/server.crt \
        --client-key /opt/gopath/src/github.com/hyperledger/fabric/peer/crypto/ordererOrganizations/hot.coc.com/orderers/orderer.hot.coc.com/tls/server.key

    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✓ Hot orderer joined hotchannel${NC}"
    else
        echo -e "${RED}✗ Failed to join hot orderer${NC}"
    fi
else
    echo -e "${GREEN}✓ Hot orderer already in hotchannel${NC}"
fi

echo ""

if [ $COLD_IN_CHANNEL -ne 0 ] || ! docker exec cli-cold osnadmin channel list -o orderer.cold.coc.com:7153 \
    --ca-file /opt/gopath/src/github.com/hyperledger/fabric/peer/crypto/ordererOrganizations/cold.coc.com/orderers/orderer.cold.coc.com/msp/tlscacerts/tlsca.cold.coc.com-cert.pem \
    --client-cert /opt/gopath/src/github.com/hyperledger/fabric/peer/crypto/ordererOrganizations/cold.coc.com/orderers/orderer.cold.coc.com/tls/server.crt \
    --client-key /opt/gopath/src/github.com/hyperledger/fabric/peer/crypto/ordererOrganizations/cold.coc.com/orderers/orderer.cold.coc.com/tls/server.key 2>&1 | grep -q "coldchannel"; then

    echo -e "${YELLOW}Cold orderer not in coldchannel. Joining...${NC}"
    docker exec cli-cold osnadmin channel join \
        --channelID coldchannel \
        --config-block /opt/gopath/src/github.com/hyperledger/fabric/peer/channel-artifacts/coldchannel.block \
        -o orderer.cold.coc.com:7153 \
        --ca-file /opt/gopath/src/github.com/hyperledger/fabric/peer/crypto/ordererOrganizations/cold.coc.com/orderers/orderer.cold.coc.com/msp/tlscacerts/tlsca.cold.coc.com-cert.pem \
        --client-cert /opt/gopath/src/github.com/hyperledger/fabric/peer/crypto/ordererOrganizations/cold.coc.com/orderers/orderer.cold.coc.com/tls/server.crt \
        --client-key /opt/gopath/src/github.com/hyperledger/fabric/peer/crypto/ordererOrganizations/cold.coc.com/orderers/orderer.cold.coc.com/tls/server.key

    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✓ Cold orderer joined coldchannel${NC}"
    else
        echo -e "${RED}✗ Failed to join cold orderer${NC}"
    fi
else
    echo -e "${GREEN}✓ Cold orderer already in coldchannel${NC}"
fi

echo ""
echo "==========================================="
echo -e "${GREEN}   Verification Complete!${NC}"
echo "==========================================="
echo ""
echo "Now try running transactions again:"
echo "  1. ./verify-blockchain.sh"
echo "  2. Or create evidence via web dashboard"
echo ""
