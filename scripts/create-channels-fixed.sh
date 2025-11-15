#!/bin/bash

###############################################################################
# Create Fabric channels and join peers - Fixed version
###############################################################################

set -e

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${GREEN}==========================================${NC}"
echo -e "${GREEN}   Creating Fabric Channels${NC}"
echo -e "${GREEN}==========================================${NC}"
echo ""

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

# Wait for CLI to be ready
echo -e "${YELLOW}[1/6] Checking if containers are ready...${NC}"
wait_for_peer "Law Enforcement peer"
echo ""

# Create Hot Channel
echo -e "${YELLOW}[2/6] Creating hotchannel...${NC}"
docker exec cli peer channel create \
    -o orderer.hot.coc.com:7050 \
    -c hotchannel \
    -f /opt/gopath/src/github.com/hyperledger/fabric/peer/channel-artifacts/hotchannel.block \
    --outputBlock /tmp/hotchannel.block \
    --tls \
    --cafile /opt/gopath/src/github.com/hyperledger/fabric/peer/crypto/ordererOrganizations/hot.coc.com/orderers/orderer.hot.coc.com/msp/tlscacerts/tlsca.hot.coc.com-cert.pem \
    --timeout 30s || {
    echo -e "${YELLOW}Channel may already exist, continuing...${NC}"
}
echo -e "${GREEN}✓ hotchannel created${NC}"
echo ""

# Join Law Enforcement peer to Hot Channel
echo -e "${YELLOW}[3/6] Joining Law Enforcement peer to hotchannel...${NC}"
docker exec \
    -e CORE_PEER_LOCALMSPID=LawEnforcementMSP \
    -e CORE_PEER_ADDRESS=peer0.lawenforcement.hot.coc.com:7051 \
    -e CORE_PEER_MSPCONFIGPATH=/opt/gopath/src/github.com/hyperledger/fabric/peer/crypto/peerOrganizations/lawenforcement.hot.coc.com/users/Admin@lawenforcement.hot.coc.com/msp \
    -e CORE_PEER_TLS_ROOTCERT_FILE=/opt/gopath/src/github.com/hyperledger/fabric/peer/crypto/peerOrganizations/lawenforcement.hot.coc.com/peers/peer0.lawenforcement.hot.coc.com/tls/ca.crt \
    cli peer channel join -b /tmp/hotchannel.block
echo -e "${GREEN}✓ Law Enforcement peer joined hotchannel${NC}"
echo ""

# Join Forensic Lab peer to Hot Channel
echo -e "${YELLOW}[4/6] Joining Forensic Lab peer to hotchannel...${NC}"
docker exec \
    -e CORE_PEER_LOCALMSPID=ForensicLabMSP \
    -e CORE_PEER_ADDRESS=peer0.forensiclab.hot.coc.com:8051 \
    -e CORE_PEER_MSPCONFIGPATH=/opt/gopath/src/github.com/hyperledger/fabric/peer/crypto/peerOrganizations/forensiclab.hot.coc.com/users/Admin@forensiclab.hot.coc.com/msp \
    -e CORE_PEER_TLS_ROOTCERT_FILE=/opt/gopath/src/github.com/hyperledger/fabric/peer/crypto/peerOrganizations/forensiclab.hot.coc.com/peers/peer0.forensiclab.hot.coc.com/tls/ca.crt \
    cli peer channel join -b /tmp/hotchannel.block
echo -e "${GREEN}✓ Forensic Lab peer joined hotchannel${NC}"
echo ""

# Create Cold Channel
echo -e "${YELLOW}[5/6] Creating coldchannel...${NC}"
docker exec cli-cold peer channel create \
    -o orderer.cold.coc.com:7150 \
    -c coldchannel \
    -f /opt/gopath/src/github.com/hyperledger/fabric/peer/channel-artifacts/coldchannel.block \
    --outputBlock /tmp/coldchannel.block \
    --tls \
    --cafile /opt/gopath/src/github.com/hyperledger/fabric/peer/crypto/ordererOrganizations/cold.coc.com/orderers/orderer.cold.coc.com/msp/tlscacerts/tlsca.cold.coc.com-cert.pem \
    --timeout 30s || {
    echo -e "${YELLOW}Channel may already exist, continuing...${NC}"
}
echo -e "${GREEN}✓ coldchannel created${NC}"
echo ""

# Join Archive peer to Cold Channel
echo -e "${YELLOW}[6/6] Joining Archive peer to coldchannel...${NC}"
docker exec \
    -e CORE_PEER_LOCALMSPID=ArchiveMSP \
    -e CORE_PEER_ADDRESS=peer0.archive.cold.coc.com:9051 \
    -e CORE_PEER_MSPCONFIGPATH=/opt/gopath/src/github.com/hyperledger/fabric/peer/crypto/peerOrganizations/archive.cold.coc.com/users/Admin@archive.cold.coc.com/msp \
    -e CORE_PEER_TLS_ROOTCERT_FILE=/opt/gopath/src/github.com/hyperledger/fabric/peer/crypto/peerOrganizations/archive.cold.coc.com/peers/peer0.archive.cold.coc.com/tls/ca.crt \
    cli-cold peer channel join -b /tmp/coldchannel.block
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
