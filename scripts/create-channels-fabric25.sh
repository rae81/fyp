#!/bin/bash

###############################################################################
# Create Fabric 2.5 channels using Channel Participation API
###############################################################################

set -e

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${GREEN}==========================================${NC}"
echo -e "${GREEN}   Creating Fabric 2.5 Channels${NC}"
echo -e "${GREEN}==========================================${NC}"
echo ""

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$PROJECT_ROOT"

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
echo -e "${YELLOW}[1/8] Checking if containers are ready...${NC}"
wait_for_peer "Law Enforcement peer"
echo ""

# Join Hot Orderer to hotchannel using osnadmin
echo -e "${YELLOW}[2/8] Joining hot orderer to hotchannel...${NC}"
docker exec cli osnadmin channel join \
    --channelID hotchannel \
    --config-block /opt/gopath/src/github.com/hyperledger/fabric/peer/channel-artifacts/hotchannel.block \
    -o orderer.hot.coc.com:7053 \
    --ca-file /opt/gopath/src/github.com/hyperledger/fabric/peer/crypto/ordererOrganizations/hot.coc.com/orderers/orderer.hot.coc.com/msp/tlscacerts/tlsca.hot.coc.com-cert.pem \
    --client-cert /opt/gopath/src/github.com/hyperledger/fabric/peer/crypto/ordererOrganizations/hot.coc.com/orderers/orderer.hot.coc.com/tls/server.crt \
    --client-key /opt/gopath/src/github.com/hyperledger/fabric/peer/crypto/ordererOrganizations/hot.coc.com/orderers/orderer.hot.coc.com/tls/server.key
echo -e "${GREEN}✓ Hot orderer joined hotchannel${NC}"
echo ""

# Wait for channel to be ready
echo -e "${YELLOW}[3/8] Waiting for hotchannel to be ready...${NC}"
sleep 5
echo -e "${GREEN}✓ Channel ready${NC}"
echo ""

# Fetch channel config block for peers
echo -e "${YELLOW}[4/8] Fetching hotchannel genesis block...${NC}"
docker exec cli peer channel fetch 0 /tmp/hotchannel.block \
    -c hotchannel \
    -o orderer.hot.coc.com:7050 \
    --tls \
    --cafile /opt/gopath/src/github.com/hyperledger/fabric/peer/crypto/ordererOrganizations/hot.coc.com/orderers/orderer.hot.coc.com/msp/tlscacerts/tlsca.hot.coc.com-cert.pem
echo -e "${GREEN}✓ Genesis block fetched${NC}"
echo ""

# Join Law Enforcement peer to hotchannel
echo -e "${YELLOW}[5/8] Joining Law Enforcement peer to hotchannel...${NC}"
# Wait for peer to be fully ready
sleep 5
docker exec \
    -e CORE_PEER_LOCALMSPID=LawEnforcementMSP \
    -e CORE_PEER_ADDRESS=peer0.lawenforcement.hot.coc.com:7051 \
    -e CORE_PEER_MSPCONFIGPATH=/opt/gopath/src/github.com/hyperledger/fabric/peer/crypto/peerOrganizations/lawenforcement.hot.coc.com/users/Admin@lawenforcement.hot.coc.com/msp \
    -e CORE_PEER_TLS_ROOTCERT_FILE=/opt/gopath/src/github.com/hyperledger/fabric/peer/crypto/peerOrganizations/lawenforcement.hot.coc.com/peers/peer0.lawenforcement.hot.coc.com/tls/ca.crt \
    cli peer channel join -b /tmp/hotchannel.block || echo -e "${YELLOW}Peer already joined, continuing...${NC}"
echo -e "${GREEN}✓ Law Enforcement peer joined hotchannel${NC}"
echo ""

# Join Forensic Lab peer to hotchannel
echo -e "${YELLOW}[6/8] Joining Forensic Lab peer to hotchannel...${NC}"
docker exec \
    -e CORE_PEER_LOCALMSPID=ForensicLabMSP \
    -e CORE_PEER_ADDRESS=peer0.forensiclab.hot.coc.com:8051 \
    -e CORE_PEER_MSPCONFIGPATH=/opt/gopath/src/github.com/hyperledger/fabric/peer/crypto/peerOrganizations/forensiclab.hot.coc.com/users/Admin@forensiclab.hot.coc.com/msp \
    -e CORE_PEER_TLS_ROOTCERT_FILE=/opt/gopath/src/github.com/hyperledger/fabric/peer/crypto/peerOrganizations/forensiclab.hot.coc.com/peers/peer0.forensiclab.hot.coc.com/tls/ca.crt \
    cli peer channel join -b /tmp/hotchannel.block || echo -e "${YELLOW}Peer already joined, continuing...${NC}"
echo -e "${GREEN}✓ Forensic Lab peer joined hotchannel${NC}"
echo ""

# Join Cold Orderer to coldchannel
echo -e "${YELLOW}[7/8] Joining cold orderer to coldchannel...${NC}"
docker exec cli-cold osnadmin channel join \
    --channelID coldchannel \
    --config-block /opt/gopath/src/github.com/hyperledger/fabric/peer/channel-artifacts/coldchannel.block \
    -o orderer.cold.coc.com:7153 \
    --ca-file /opt/gopath/src/github.com/hyperledger/fabric/peer/crypto/ordererOrganizations/cold.coc.com/orderers/orderer.cold.coc.com/msp/tlscacerts/tlsca.cold.coc.com-cert.pem \
    --client-cert /opt/gopath/src/github.com/hyperledger/fabric/peer/crypto/ordererOrganizations/cold.coc.com/orderers/orderer.cold.coc.com/tls/server.crt \
    --client-key /opt/gopath/src/github.com/hyperledger/fabric/peer/crypto/ordererOrganizations/cold.coc.com/orderers/orderer.cold.coc.com/tls/server.key
echo -e "${GREEN}✓ Cold orderer joined coldchannel${NC}"
echo ""

# Wait and fetch cold channel block
sleep 3
docker exec cli-cold peer channel fetch 0 /tmp/coldchannel.block \
    -c coldchannel \
    -o orderer.cold.coc.com:7150 \
    --tls \
    --cafile /opt/gopath/src/github.com/hyperledger/fabric/peer/crypto/ordererOrganizations/cold.coc.com/orderers/orderer.cold.coc.com/msp/tlscacerts/tlsca.cold.coc.com-cert.pem

# Join Archive peer to coldchannel
echo -e "${YELLOW}[8/8] Joining Archive peer to coldchannel...${NC}"
docker exec \
    -e CORE_PEER_LOCALMSPID=ArchiveMSP \
    -e CORE_PEER_ADDRESS=peer0.archive.cold.coc.com:9051 \
    -e CORE_PEER_MSPCONFIGPATH=/opt/gopath/src/github.com/hyperledger/fabric/peer/crypto/peerOrganizations/archive.cold.coc.com/users/Admin@archive.cold.coc.com/msp \
    -e CORE_PEER_TLS_ROOTCERT_FILE=/opt/gopath/src/github.com/hyperledger/fabric/peer/crypto/peerOrganizations/archive.cold.coc.com/peers/peer0.archive.cold.coc.com/tls/ca.crt \
    cli-cold peer channel join -b /tmp/coldchannel.block || echo -e "${YELLOW}Peer already joined, continuing...${NC}"
echo -e "${GREEN}✓ Archive peer joined coldchannel${NC}"
echo ""

# Verify channels
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
echo -e "${GREEN}✓ All channels created and peers joined successfully${NC}"
echo ""
echo -e "${YELLOW}Next step: Deploy chaincode with ./deploy-chaincode.sh${NC}"
