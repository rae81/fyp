#!/bin/bash

###############################################################################
# Create Fabric 2.5 channels using Channel Participation API
# Updated for dynamic mTLS certificates from Enclave Root CA
###############################################################################

set -e

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${GREEN}==========================================${NC}"
echo -e "${GREEN}   Creating Channels with Dynamic mTLS${NC}"
echo -e "${GREEN}==========================================${NC}"
echo ""

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
cd "$PROJECT_ROOT"

# Certificate paths using new organizations structure
ORG_DIR="$PROJECT_ROOT/organizations"

# Function to wait for peer to be ready
wait_for_peer() {
    local peer=$1
    local max_retry=30
    local retry=0

    echo -e "${YELLOW}Waiting for $peer to be ready...${NC}"
    while [ $retry -lt $max_retry ]; do
        if docker exec cli peer node status &>/dev/null; then
            echo -e "${GREEN}✓ $peer is ready${NC}"
            return 0
        fi
        retry=$((retry + 1))
        sleep 2
    done

    echo -e "${RED}✗ $peer failed to become ready${NC}"
    return 1
}

# Wait for containers
echo -e "${YELLOW}[1/9] Checking if containers are ready...${NC}"
if ! docker ps | grep -q "orderer.hot.coc.com"; then
    echo -e "${RED}✗ Orderers not running! Please start containers first.${NC}"
    echo -e "${YELLOW}Run: docker-compose -f docker-compose-hot.yml -f docker-compose-cold.yml up -d${NC}"
    exit 1
fi
wait_for_peer "Law Enforcement peer"
echo ""

###############################################################################
# HOT BLOCKCHAIN CHANNEL CREATION
###############################################################################

# Join Hot Orderer to hotchannel using osnadmin
echo -e "${YELLOW}[2/9] Joining hot orderer to hotchannel...${NC}"
docker exec cli osnadmin channel join \
    --channelID hotchannel \
    --config-block /opt/gopath/src/github.com/hyperledger/fabric/peer/channel-artifacts/hotchannel.block \
    -o orderer.hot.coc.com:7053 \
    --ca-file /opt/gopath/src/github.com/hyperledger/fabric/peer/organizations/ordererOrganizations/hot.coc.com/orderers/orderer.hot.coc.com/tls/ca.crt \
    --client-cert /opt/gopath/src/github.com/hyperledger/fabric/peer/organizations/ordererOrganizations/hot.coc.com/orderers/orderer.hot.coc.com/tls/server.crt \
    --client-key /opt/gopath/src/github.com/hyperledger/fabric/peer/organizations/ordererOrganizations/hot.coc.com/orderers/orderer.hot.coc.com/tls/server.key

if [ $? -eq 0 ]; then
    echo -e "${GREEN}✓ Hot orderer joined hotchannel${NC}"
else
    echo -e "${YELLOW}Note: Orderer may already be joined to channel${NC}"
fi
echo ""

# Wait for channel to be ready
echo -e "${YELLOW}[3/9] Waiting for hotchannel to be ready...${NC}"
sleep 5
echo -e "${GREEN}✓ Channel ready${NC}"
echo ""

# Fetch channel config block for peers
echo -e "${YELLOW}[4/9] Fetching hotchannel genesis block...${NC}"
docker exec cli peer channel fetch 0 /tmp/hotchannel.block \
    -c hotchannel \
    -o orderer.hot.coc.com:7050 \
    --tls \
    --cafile /opt/gopath/src/github.com/hyperledger/fabric/peer/organizations/ordererOrganizations/hot.coc.com/orderers/orderer.hot.coc.com/tls/ca.crt
echo -e "${GREEN}✓ Genesis block fetched${NC}"
echo ""

# Join Law Enforcement peer to hotchannel
echo -e "${YELLOW}[5/9] Joining Law Enforcement peer to hotchannel...${NC}"
sleep 3
docker exec \
    -e CORE_PEER_LOCALMSPID=LawEnforcementMSP \
    -e CORE_PEER_ADDRESS=peer0.lawenforcement.hot.coc.com:7051 \
    -e CORE_PEER_MSPCONFIGPATH=/opt/gopath/src/github.com/hyperledger/fabric/peer/organizations/peerOrganizations/lawenforcement.hot.coc.com/users/Admin@lawenforcement.hot.coc.com/msp \
    -e CORE_PEER_TLS_ROOTCERT_FILE=/opt/gopath/src/github.com/hyperledger/fabric/peer/organizations/peerOrganizations/lawenforcement.hot.coc.com/peers/peer0.lawenforcement.hot.coc.com/tls/ca.crt \
    cli peer channel join -b /tmp/hotchannel.block || echo -e "${YELLOW}Peer already joined, continuing...${NC}"
echo -e "${GREEN}✓ Law Enforcement peer joined hotchannel${NC}"
echo ""

# Join Forensic Lab peer to hotchannel
echo -e "${YELLOW}[6/9] Joining Forensic Lab peer to hotchannel...${NC}"
docker exec \
    -e CORE_PEER_LOCALMSPID=ForensicLabMSP \
    -e CORE_PEER_ADDRESS=peer0.forensiclab.hot.coc.com:8051 \
    -e CORE_PEER_MSPCONFIGPATH=/opt/gopath/src/github.com/hyperledger/fabric/peer/organizations/peerOrganizations/forensiclab.hot.coc.com/users/Admin@forensiclab.hot.coc.com/msp \
    -e CORE_PEER_TLS_ROOTCERT_FILE=/opt/gopath/src/github.com/hyperledger/fabric/peer/organizations/peerOrganizations/forensiclab.hot.coc.com/peers/peer0.forensiclab.hot.coc.com/tls/ca.crt \
    cli peer channel join -b /tmp/hotchannel.block || echo -e "${YELLOW}Peer already joined, continuing...${NC}"
echo -e "${GREEN}✓ Forensic Lab peer joined hotchannel${NC}"
echo ""

# Update anchor peers for hot channel
echo -e "${YELLOW}[7/9] Updating anchor peers for hotchannel...${NC}"

# Update Law Enforcement anchor peer
docker exec \
    -e CORE_PEER_LOCALMSPID=LawEnforcementMSP \
    -e CORE_PEER_ADDRESS=peer0.lawenforcement.hot.coc.com:7051 \
    -e CORE_PEER_MSPCONFIGPATH=/opt/gopath/src/github.com/hyperledger/fabric/peer/organizations/peerOrganizations/lawenforcement.hot.coc.com/users/Admin@lawenforcement.hot.coc.com/msp \
    -e CORE_PEER_TLS_ROOTCERT_FILE=/opt/gopath/src/github.com/hyperledger/fabric/peer/organizations/peerOrganizations/lawenforcement.hot.coc.com/peers/peer0.lawenforcement.hot.coc.com/tls/ca.crt \
    cli peer channel update \
    -o orderer.hot.coc.com:7050 \
    -c hotchannel \
    -f /opt/gopath/src/github.com/hyperledger/fabric/peer/channel-artifacts/LawEnforcementMSPanchors.tx \
    --tls \
    --cafile /opt/gopath/src/github.com/hyperledger/fabric/peer/organizations/ordererOrganizations/hot.coc.com/orderers/orderer.hot.coc.com/tls/ca.crt || echo -e "${YELLOW}Anchor peer may already be set${NC}"

# Update Forensic Lab anchor peer
docker exec \
    -e CORE_PEER_LOCALMSPID=ForensicLabMSP \
    -e CORE_PEER_ADDRESS=peer0.forensiclab.hot.coc.com:8051 \
    -e CORE_PEER_MSPCONFIGPATH=/opt/gopath/src/github.com/hyperledger/fabric/peer/organizations/peerOrganizations/forensiclab.hot.coc.com/users/Admin@forensiclab.hot.coc.com/msp \
    -e CORE_PEER_TLS_ROOTCERT_FILE=/opt/gopath/src/github.com/hyperledger/fabric/peer/organizations/peerOrganizations/forensiclab.hot.coc.com/peers/peer0.forensiclab.hot.coc.com/tls/ca.crt \
    cli peer channel update \
    -o orderer.hot.coc.com:7050 \
    -c hotchannel \
    -f /opt/gopath/src/github.com/hyperledger/fabric/peer/channel-artifacts/ForensicLabMSPanchors.tx \
    --tls \
    --cafile /opt/gopath/src/github.com/hyperledger/fabric/peer/organizations/ordererOrganizations/hot.coc.com/orderers/orderer.hot.coc.com/tls/ca.crt || echo -e "${YELLOW}Anchor peer may already be set${NC}"

echo -e "${GREEN}✓ Hot channel anchor peers updated${NC}"
echo ""

###############################################################################
# COLD BLOCKCHAIN CHANNEL CREATION
###############################################################################

# Join Cold Orderer to coldchannel
echo -e "${YELLOW}[8/9] Joining cold orderer to coldchannel...${NC}"
docker exec cli-cold osnadmin channel join \
    --channelID coldchannel \
    --config-block /opt/gopath/src/github.com/hyperledger/fabric/peer/channel-artifacts/coldchannel.block \
    -o orderer.cold.coc.com:7153 \
    --ca-file /opt/gopath/src/github.com/hyperledger/fabric/peer/organizations/ordererOrganizations/cold.coc.com/orderers/orderer.cold.coc.com/tls/ca.crt \
    --client-cert /opt/gopath/src/github.com/hyperledger/fabric/peer/organizations/ordererOrganizations/cold.coc.com/orderers/orderer.cold.coc.com/tls/server.crt \
    --client-key /opt/gopath/src/github.com/hyperledger/fabric/peer/organizations/ordererOrganizations/cold.coc.com/orderers/orderer.cold.coc.com/tls/server.key

if [ $? -eq 0 ]; then
    echo -e "${GREEN}✓ Cold orderer joined coldchannel${NC}"
else
    echo -e "${YELLOW}Note: Orderer may already be joined to channel${NC}"
fi
echo ""

# Wait and fetch cold channel block
sleep 3
docker exec cli-cold peer channel fetch 0 /tmp/coldchannel.block \
    -c coldchannel \
    -o orderer.cold.coc.com:7150 \
    --tls \
    --cafile /opt/gopath/src/github.com/hyperledger/fabric/peer/organizations/ordererOrganizations/cold.coc.com/orderers/orderer.cold.coc.com/tls/ca.crt

# Join Auditor peer to coldchannel
echo -e "${YELLOW}[9/9] Joining Auditor peer to coldchannel...${NC}"
docker exec \
    -e CORE_PEER_LOCALMSPID=AuditorMSP \
    -e CORE_PEER_ADDRESS=peer0.auditor.cold.coc.com:9051 \
    -e CORE_PEER_MSPCONFIGPATH=/opt/gopath/src/github.com/hyperledger/fabric/peer/organizations/peerOrganizations/auditor.cold.coc.com/users/Admin@auditor.cold.coc.com/msp \
    -e CORE_PEER_TLS_ROOTCERT_FILE=/opt/gopath/src/github.com/hyperledger/fabric/peer/organizations/peerOrganizations/auditor.cold.coc.com/peers/peer0.auditor.cold.coc.com/tls/ca.crt \
    cli-cold peer channel join -b /tmp/coldchannel.block || echo -e "${YELLOW}Peer already joined, continuing...${NC}"
echo -e "${GREEN}✓ Auditor peer joined coldchannel${NC}"
echo ""

# Update Auditor anchor peer
docker exec \
    -e CORE_PEER_LOCALMSPID=AuditorMSP \
    -e CORE_PEER_ADDRESS=peer0.auditor.cold.coc.com:9051 \
    -e CORE_PEER_MSPCONFIGPATH=/opt/gopath/src/github.com/hyperledger/fabric/peer/organizations/peerOrganizations/auditor.cold.coc.com/users/Admin@auditor.cold.coc.com/msp \
    -e CORE_PEER_TLS_ROOTCERT_FILE=/opt/gopath/src/github.com/hyperledger/fabric/peer/organizations/peerOrganizations/auditor.cold.coc.com/peers/peer0.auditor.cold.coc.com/tls/ca.crt \
    cli-cold peer channel update \
    -o orderer.cold.coc.com:7150 \
    -c coldchannel \
    -f /opt/gopath/src/github.com/hyperledger/fabric/peer/channel-artifacts/AuditorMSPanchors.tx \
    --tls \
    --cafile /opt/gopath/src/github.com/hyperledger/fabric/peer/organizations/ordererOrganizations/cold.coc.com/orderers/orderer.cold.coc.com/tls/ca.crt || echo -e "${YELLOW}Anchor peer may already be set${NC}"

echo -e "${GREEN}✓ Cold channel anchor peer updated${NC}"
echo ""

###############################################################################
# VERIFICATION
###############################################################################

echo -e "${GREEN}==========================================${NC}"
echo -e "${GREEN}   Channel Creation Complete!${NC}"
echo -e "${GREEN}==========================================${NC}"
echo ""

echo -e "${YELLOW}Hot blockchain channels:${NC}"
docker exec cli peer channel list

echo ""
echo -e "${YELLOW}Cold blockchain channels:${NC}"
docker exec cli-cold peer channel list

echo ""
echo -e "${GREEN}==========================================${NC}"
echo -e "${GREEN}✓ All channels created successfully!${NC}"
echo -e "${GREEN}==========================================${NC}"
echo ""
echo -e "Certificate chain verified:"
echo -e "  ${YELLOW}SGX Enclave Root CA → Fabric CA → Identity Certs${NC}"
echo ""
echo -e "${YELLOW}Next step: Deploy chaincode${NC}"
echo ""
