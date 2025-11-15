#!/bin/bash

# Script to join orderers to channels using Channel Participation API
# Required for Fabric 2.3+ without system channel

echo "==========================================="
echo "   Orderer Channel Participation Setup"
echo "==========================================="
echo ""

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

# Function to join hot orderer to channel
join_hot_orderer_to_channel() {
    local ORDERER=$1
    local CHANNEL_NAME=$2

    echo -e "${YELLOW}Joining ${ORDERER} to ${CHANNEL_NAME}...${NC}"

    # Use osnadmin CLI to join channel (run from cli container)
    docker exec cli osnadmin channel join \
        --channelID ${CHANNEL_NAME} \
        --config-block /opt/gopath/src/github.com/hyperledger/fabric/peer/channel-artifacts/${CHANNEL_NAME}.block \
        -o ${ORDERER}:7053 \
        --ca-file /opt/gopath/src/github.com/hyperledger/fabric/peer/crypto/ordererOrganizations/hot.coc.com/orderers/orderer.hot.coc.com/msp/tlscacerts/tlsca.hot.coc.com-cert.pem \
        --client-cert /opt/gopath/src/github.com/hyperledger/fabric/peer/crypto/ordererOrganizations/hot.coc.com/orderers/orderer.hot.coc.com/tls/server.crt \
        --client-key /opt/gopath/src/github.com/hyperledger/fabric/peer/crypto/ordererOrganizations/hot.coc.com/orderers/orderer.hot.coc.com/tls/server.key \
        2>&1

    local RESULT=$?

    if [ $RESULT -eq 0 ]; then
        echo -e "${GREEN}✓${NC} ${ORDERER} joined ${CHANNEL_NAME}"
        return 0
    else
        # Check if orderer is already part of channel
        docker exec cli osnadmin channel list -o ${ORDERER}:7053 \
            --ca-file /opt/gopath/src/github.com/hyperledger/fabric/peer/crypto/ordererOrganizations/hot.coc.com/orderers/orderer.hot.coc.com/msp/tlscacerts/tlsca.hot.coc.com-cert.pem \
            --client-cert /opt/gopath/src/github.com/hyperledger/fabric/peer/crypto/ordererOrganizations/hot.coc.com/orderers/orderer.hot.coc.com/tls/server.crt \
            --client-key /opt/gopath/src/github.com/hyperledger/fabric/peer/crypto/ordererOrganizations/hot.coc.com/orderers/orderer.hot.coc.com/tls/server.key \
            2>&1 | grep -q ${CHANNEL_NAME}

        if [ $? -eq 0 ]; then
            echo -e "${GREEN}✓${NC} ${ORDERER} already in ${CHANNEL_NAME}"
            return 0
        else
            echo -e "${RED}✗${NC} Failed to join ${ORDERER} to ${CHANNEL_NAME}"
            return 1
        fi
    fi
}

# Function to join cold orderer to channel
join_cold_orderer_to_channel() {
    local ORDERER=$1
    local CHANNEL_NAME=$2

    echo -e "${YELLOW}Joining ${ORDERER} to ${CHANNEL_NAME}...${NC}"

    # Use osnadmin CLI to join channel (run from cli-cold container)
    docker exec cli-cold osnadmin channel join \
        --channelID ${CHANNEL_NAME} \
        --config-block /opt/gopath/src/github.com/hyperledger/fabric/peer/channel-artifacts/${CHANNEL_NAME}.block \
        -o ${ORDERER}:7153 \
        --ca-file /opt/gopath/src/github.com/hyperledger/fabric/peer/crypto/ordererOrganizations/cold.coc.com/orderers/orderer.cold.coc.com/msp/tlscacerts/tlsca.cold.coc.com-cert.pem \
        --client-cert /opt/gopath/src/github.com/hyperledger/fabric/peer/crypto/ordererOrganizations/cold.coc.com/orderers/orderer.cold.coc.com/tls/server.crt \
        --client-key /opt/gopath/src/github.com/hyperledger/fabric/peer/crypto/ordererOrganizations/cold.coc.com/orderers/orderer.cold.coc.com/tls/server.key \
        2>&1

    local RESULT=$?

    if [ $RESULT -eq 0 ]; then
        echo -e "${GREEN}✓${NC} ${ORDERER} joined ${CHANNEL_NAME}"
        return 0
    else
        # Check if orderer is already part of channel
        docker exec cli-cold osnadmin channel list -o ${ORDERER}:7153 \
            --ca-file /opt/gopath/src/github.com/hyperledger/fabric/peer/crypto/ordererOrganizations/cold.coc.com/orderers/orderer.cold.coc.com/msp/tlscacerts/tlsca.cold.coc.com-cert.pem \
            --client-cert /opt/gopath/src/github.com/hyperledger/fabric/peer/crypto/ordererOrganizations/cold.coc.com/orderers/orderer.cold.coc.com/tls/server.crt \
            --client-key /opt/gopath/src/github.com/hyperledger/fabric/peer/crypto/ordererOrganizations/cold.coc.com/orderers/orderer.cold.coc.com/tls/server.key \
            2>&1 | grep -q ${CHANNEL_NAME}

        if [ $? -eq 0 ]; then
            echo -e "${GREEN}✓${NC} ${ORDERER} already in ${CHANNEL_NAME}"
            return 0
        else
            echo -e "${RED}✗${NC} Failed to join ${ORDERER} to ${CHANNEL_NAME}"
            return 1
        fi
    fi
}

# Check if channel blocks exist
if [ ! -f "hot-blockchain/channel-artifacts/hotchannel.block" ]; then
    echo -e "${RED}Error: hotchannel.block not found${NC}"
    exit 1
fi

if [ ! -f "cold-blockchain/channel-artifacts/coldchannel.block" ]; then
    echo -e "${RED}Error: coldchannel.block not found${NC}"
    exit 1
fi

# Join Hot Orderer to hotchannel
echo ""
echo "=== Hot Blockchain Orderer ==="
join_hot_orderer_to_channel "orderer.hot.coc.com" "hotchannel"

# Join Cold Orderer to coldchannel
echo ""
echo "=== Cold Blockchain Orderer ==="
join_cold_orderer_to_channel "orderer.cold.coc.com" "coldchannel"

echo ""
echo -e "${GREEN}==========================================${NC}"
echo -e "${GREEN}   Orderer Channel Setup Complete${NC}"
echo -e "${GREEN}==========================================${NC}"
echo ""
echo "You can now run ./deploy-chaincode.sh"
echo ""
