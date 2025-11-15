#!/bin/bash

# Add CourtMSP to running hotchannel and coldchannel
# This script performs channel configuration updates to add Court as a member organization

set -e

# Get the script directory and project root
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PROJECT_ROOT="$( cd "$SCRIPT_DIR/.." && pwd )"

YELLOW='\033[1;33m'
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Adding CourtMSP to Blockchain Channels${NC}"
echo -e "${GREEN}========================================${NC}"

# ==============================================================================
# ADD COURTMSP TO HOTCHANNEL
# ==============================================================================

echo -e "\n${YELLOW}Step 1: Adding CourtMSP to hotchannel...${NC}"

# Generate CourtMSP definition
echo -e "${YELLOW}Generating CourtMSP config...${NC}"
docker exec cli configtxgen -printOrg CourtMSP \
    -configPath /opt/gopath/src/github.com/hyperledger/fabric/peer \
    -profile HotChainChannel \
    > /tmp/court-hot.json 2>/dev/null || {
    echo -e "${YELLOW}Generating from config directory...${NC}"
    cd "$PROJECT_ROOT/hot-blockchain"
    docker run --rm \
        -v $(pwd):/data \
        -w /data \
        hyperledger/fabric-tools:latest \
        configtxgen -configPath /data -printOrg CourtMSP > /tmp/court-hot.json
}

# Fetch current channel config
echo -e "${YELLOW}Fetching hotchannel config...${NC}"
docker exec cli peer channel fetch config /tmp/config_block.pb \
    -o orderer.hot.coc.com:7050 \
    --ordererTLSHostnameOverride orderer.hot.coc.com \
    --tls --cafile /opt/gopath/src/github.com/hyperledger/fabric/peer/crypto/ordererOrganizations/hot.coc.com/orderers/orderer.hot.coc.com/msp/tlscacerts/tlsca.hot.coc.com-cert.pem \
    -c hotchannel

# Decode to JSON
docker exec cli configtxlator proto_decode \
    --input /tmp/config_block.pb \
    --type common.Block | jq .data.data[0].payload.data.config > /tmp/hot_config.json

# Add CourtMSP
jq -s '.[0] * {"channel_group":{"groups":{"Application":{"groups": {"CourtMSP":.[1]}}}}}' \
    /tmp/hot_config.json /tmp/court-hot.json > /tmp/hot_modified_config.json

# Create config update
docker exec cli configtxlator proto_encode --input /tmp/hot_config.json --type common.Config --output /tmp/hot_config.pb
docker exec cli configtxlator proto_encode --input /tmp/hot_modified_config.json --type common.Config --output /tmp/hot_modified_config.pb
docker exec cli configtxlator compute_update \
    --channel_id hotchannel \
    --original /tmp/hot_config.pb \
    --updated /tmp/hot_modified_config.pb \
    --output /tmp/hot_config_update.pb

# Decode update
docker exec cli configtxlator proto_decode \
    --input /tmp/hot_config_update.pb \
    --type common.ConfigUpdate | jq . > /tmp/hot_config_update.json

# Wrap in envelope
echo '{"payload":{"header":{"channel_header":{"channel_id":"hotchannel", "type":2}},"data":{"config_update":'$(cat /tmp/hot_config_update.json)'}}}' | jq . > /tmp/hot_config_update_in_envelope.json

docker exec cli configtxlator proto_encode \
    --input /tmp/hot_config_update_in_envelope.json \
    --type common.Envelope \
    --output /tmp/hot_config_update_in_envelope.pb

# Sign with LawEnforcement
echo -e "${YELLOW}Signing with LawEnforcementMSP...${NC}"
docker exec cli peer channel signconfigtx -f /tmp/hot_config_update_in_envelope.pb

# Sign and submit with ForensicLab
echo -e "${YELLOW}Submitting update with ForensicLabMSP...${NC}"
docker exec \
    -e CORE_PEER_MSPCONFIGPATH=/opt/gopath/src/github.com/hyperledger/fabric/peer/crypto/peerOrganizations/forensiclab.hot.coc.com/users/Admin@forensiclab.hot.coc.com/msp \
    -e CORE_PEER_ADDRESS=peer0.forensiclab.hot.coc.com:8051 \
    -e CORE_PEER_LOCALMSPID=ForensicLabMSP \
    -e CORE_PEER_TLS_ROOTCERT_FILE=/opt/gopath/src/github.com/hyperledger/fabric/peer/crypto/peerOrganizations/forensiclab.hot.coc.com/peers/peer0.forensiclab.hot.coc.com/tls/ca.crt \
    cli peer channel update \
    -f /tmp/hot_config_update_in_envelope.pb \
    -c hotchannel \
    -o orderer.hot.coc.com:7050 \
    --ordererTLSHostnameOverride orderer.hot.coc.com \
    --tls --cafile /opt/gopath/src/github.com/hyperledger/fabric/peer/crypto/ordererOrganizations/hot.coc.com/orderers/orderer.hot.coc.com/msp/tlscacerts/tlsca.hot.coc.com-cert.pem

echo -e "${GREEN}✓ CourtMSP added to hotchannel${NC}"

# ==============================================================================
# ADD COURTMSP TO COLDCHANNEL
# ==============================================================================

echo -e "\n${YELLOW}Step 2: Adding CourtMSP to coldchannel...${NC}"

# Generate CourtMSP definition for cold chain
echo -e "${YELLOW}Generating CourtMSP config for cold chain...${NC}"
cd "$PROJECT_ROOT/cold-blockchain"
docker run --rm \
    -v $(pwd):/data \
    -w /data \
    hyperledger/fabric-tools:latest \
    configtxgen -configPath /data -printOrg CourtMSP > /tmp/court-cold.json

# Fetch current channel config
echo -e "${YELLOW}Fetching coldchannel config...${NC}"
docker exec cli-cold peer channel fetch config /tmp/config_block_cold.pb \
    -o orderer.cold.coc.com:7150 \
    --ordererTLSHostnameOverride orderer.cold.coc.com \
    --tls --cafile /opt/gopath/src/github.com/hyperledger/fabric/peer/crypto/ordererOrganizations/cold.coc.com/orderers/orderer.cold.coc.com/msp/tlscacerts/tlsca.cold.coc.com-cert.pem \
    -c coldchannel

# Decode to JSON
docker exec cli-cold configtxlator proto_decode \
    --input /tmp/config_block_cold.pb \
    --type common.Block | jq .data.data[0].payload.data.config > /tmp/cold_config.json

# Add CourtMSP
jq -s '.[0] * {"channel_group":{"groups":{"Application":{"groups": {"CourtMSP":.[1]}}}}}' \
    /tmp/cold_config.json /tmp/court-cold.json > /tmp/cold_modified_config.json

# Create config update
docker exec cli-cold configtxlator proto_encode --input /tmp/cold_config.json --type common.Config --output /tmp/cold_config.pb
docker exec cli-cold configtxlator proto_encode --input /tmp/cold_modified_config.json --type common.Config --output /tmp/cold_modified_config.pb
docker exec cli-cold configtxlator compute_update \
    --channel_id coldchannel \
    --original /tmp/cold_config.pb \
    --updated /tmp/cold_modified_config.pb \
    --output /tmp/cold_config_update.pb

# Decode update
docker exec cli-cold configtxlator proto_decode \
    --input /tmp/cold_config_update.pb \
    --type common.ConfigUpdate | jq . > /tmp/cold_config_update.json

# Wrap in envelope
echo '{"payload":{"header":{"channel_header":{"channel_id":"coldchannel", "type":2}},"data":{"config_update":'$(cat /tmp/cold_config_update.json)'}}}' | jq . > /tmp/cold_config_update_in_envelope.json

docker exec cli-cold configtxlator proto_encode \
    --input /tmp/cold_config_update_in_envelope.json \
    --type common.Envelope \
    --output /tmp/cold_config_update_in_envelope.pb

# Sign and submit with ArchiveMSP
echo -e "${YELLOW}Submitting update with ArchiveMSP...${NC}"
docker exec cli-cold peer channel update \
    -f /tmp/cold_config_update_in_envelope.pb \
    -c coldchannel \
    -o orderer.cold.coc.com:7150 \
    --ordererTLSHostnameOverride orderer.cold.coc.com \
    --tls --cafile /opt/gopath/src/github.com/hyperledger/fabric/peer/crypto/ordererOrganizations/cold.coc.com/orderers/orderer.cold.coc.com/msp/tlscacerts/tlsca.cold.coc.com-cert.pem

echo -e "${GREEN}✓ CourtMSP added to coldchannel${NC}"

echo -e "\n${GREEN}========================================${NC}"
echo -e "${GREEN}CourtMSP successfully added to both channels!${NC}"
echo -e "${GREEN}========================================${NC}"
