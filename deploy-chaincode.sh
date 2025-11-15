#!/bin/bash

# Chaincode Deployment Script for Dual Hyperledger Blockchain
# Deploys DFIR chaincode to both Hot and Cold blockchains

echo "==========================================="
echo "   DFIR Chaincode Deployment"
echo "==========================================="
echo ""

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

# Chaincode configuration
CC_NAME="dfir"
CC_VERSION="1.0"
CC_SEQUENCE=1
CC_SRC_PATH="github.com/chaincode"

# Set environment
export PATH="${PWD}/fabric-samples/bin:$PATH"
export FABRIC_CFG_PATH="${PWD}/fabric-samples/config"

# Test counters
TOTAL_STEPS=10
CURRENT_STEP=0

print_step() {
    CURRENT_STEP=$((CURRENT_STEP + 1))
    echo -e "${YELLOW}[Step $CURRENT_STEP/$TOTAL_STEPS] $1${NC}"
}

check_result() {
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✓ $1${NC}"
        return 0
    else
        echo -e "${RED}❌ $1${NC}"
        return 1
    fi
}

# Step 1: Check containers
print_step "Checking blockchain containers..."
for container in cli cli-cold peer0.lawenforcement.hot.coc.com peer0.forensiclab.hot.coc.com peer0.archive.cold.coc.com; do
    if docker ps --format '{{.Names}}' | grep -q "^${container}$"; then
        echo "✓ Container $container is running"
    else
        echo -e "${RED}❌ Container $container not running${NC}"
        echo "Please run ./restart-blockchain.sh first"
        exit 1
    fi
done

# Step 2: Package Hot Blockchain Chaincode
print_step "Packaging Hot blockchain chaincode..."
docker exec cli peer lifecycle chaincode package dfir.tar.gz \
    --path /opt/gopath/src/${CC_SRC_PATH} \
    --lang golang \
    --label dfir_${CC_VERSION}
check_result "Hot chaincode packaged"

# Step 3: Install on Hot Blockchain - Law Enforcement Peer
print_step "Installing chaincode on Law Enforcement peer..."
docker exec cli peer lifecycle chaincode install dfir.tar.gz
check_result "Installed on Law Enforcement peer"

# Step 4: Install on Hot Blockchain - Forensic Lab Peer
print_step "Installing chaincode on Forensic Lab peer..."
docker exec \
    -e CORE_PEER_MSPCONFIGPATH=/opt/gopath/src/github.com/hyperledger/fabric/peer/crypto/peerOrganizations/forensiclab.hot.coc.com/users/Admin@forensiclab.hot.coc.com/msp \
    -e CORE_PEER_ADDRESS=peer0.forensiclab.hot.coc.com:8051 \
    -e CORE_PEER_LOCALMSPID=ForensicLabMSP \
    -e CORE_PEER_TLS_ROOTCERT_FILE=/opt/gopath/src/github.com/hyperledger/fabric/peer/crypto/peerOrganizations/forensiclab.hot.coc.com/peers/peer0.forensiclab.hot.coc.com/tls/ca.crt \
    cli peer lifecycle chaincode install dfir.tar.gz
check_result "Installed on Forensic Lab peer"

# Step 5: Query and save package ID for Hot blockchain
print_step "Querying Hot blockchain package ID..."
PACKAGE_ID=$(docker exec cli peer lifecycle chaincode queryinstalled 2>/dev/null | grep "dfir_${CC_VERSION}" | awk '{print $3}' | sed 's/,$//')
if [ -z "$PACKAGE_ID" ]; then
    echo -e "${RED}❌ Failed to get package ID${NC}"
    exit 1
fi
echo "Package ID: $PACKAGE_ID"
echo "$PACKAGE_ID" > chaincode_package_id.txt

# Step 6: Approve chaincode for Law Enforcement
print_step "Approving chaincode for Law Enforcement organization..."
docker exec cli peer lifecycle chaincode approveformyorg \
    -o orderer.hot.coc.com:7050 \
    --ordererTLSHostnameOverride orderer.hot.coc.com \
    --tls --cafile /opt/gopath/src/github.com/hyperledger/fabric/peer/crypto/ordererOrganizations/hot.coc.com/orderers/orderer.hot.coc.com/msp/tlscacerts/tlsca.hot.coc.com-cert.pem \
    --channelID hotchannel \
    --name ${CC_NAME} \
    --version ${CC_VERSION} \
    --package-id ${PACKAGE_ID} \
    --sequence ${CC_SEQUENCE}
check_result "Approved for Law Enforcement"

# Step 7: Approve chaincode for Forensic Lab
print_step "Approving chaincode for Forensic Lab organization..."
docker exec \
    -e CORE_PEER_MSPCONFIGPATH=/opt/gopath/src/github.com/hyperledger/fabric/peer/crypto/peerOrganizations/forensiclab.hot.coc.com/users/Admin@forensiclab.hot.coc.com/msp \
    -e CORE_PEER_ADDRESS=peer0.forensiclab.hot.coc.com:8051 \
    -e CORE_PEER_LOCALMSPID=ForensicLabMSP \
    -e CORE_PEER_TLS_ROOTCERT_FILE=/opt/gopath/src/github.com/hyperledger/fabric/peer/crypto/peerOrganizations/forensiclab.hot.coc.com/peers/peer0.forensiclab.hot.coc.com/tls/ca.crt \
    cli peer lifecycle chaincode approveformyorg \
    -o orderer.hot.coc.com:7050 \
    --ordererTLSHostnameOverride orderer.hot.coc.com \
    --tls --cafile /opt/gopath/src/github.com/hyperledger/fabric/peer/crypto/ordererOrganizations/hot.coc.com/orderers/orderer.hot.coc.com/msp/tlscacerts/tlsca.hot.coc.com-cert.pem \
    --channelID hotchannel \
    --name ${CC_NAME} \
    --version ${CC_VERSION} \
    --package-id ${PACKAGE_ID} \
    --sequence ${CC_SEQUENCE}
check_result "Approved for Forensic Lab"

# Step 8: Commit chaincode to Hot blockchain channel
print_step "Committing chaincode to Hot blockchain..."
docker exec cli peer lifecycle chaincode commit \
    -o orderer.hot.coc.com:7050 \
    --ordererTLSHostnameOverride orderer.hot.coc.com \
    --tls --cafile /opt/gopath/src/github.com/hyperledger/fabric/peer/crypto/ordererOrganizations/hot.coc.com/orderers/orderer.hot.coc.com/msp/tlscacerts/tlsca.hot.coc.com-cert.pem \
    --channelID hotchannel \
    --name ${CC_NAME} \
    --version ${CC_VERSION} \
    --sequence ${CC_SEQUENCE} \
    --peerAddresses peer0.lawenforcement.hot.coc.com:7051 \
    --tlsRootCertFiles /opt/gopath/src/github.com/hyperledger/fabric/peer/crypto/peerOrganizations/lawenforcement.hot.coc.com/peers/peer0.lawenforcement.hot.coc.com/tls/ca.crt \
    --peerAddresses peer0.forensiclab.hot.coc.com:8051 \
    --tlsRootCertFiles /opt/gopath/src/github.com/hyperledger/fabric/peer/crypto/peerOrganizations/forensiclab.hot.coc.com/peers/peer0.forensiclab.hot.coc.com/tls/ca.crt
check_result "Committed to Hot blockchain"

# Step 9: Deploy to Cold Blockchain
print_step "Deploying to Cold blockchain..."

# Package for cold blockchain
docker exec cli-cold peer lifecycle chaincode package dfir.tar.gz \
    --path /opt/gopath/src/${CC_SRC_PATH} \
    --lang golang \
    --label dfir_${CC_VERSION}

# Install on Archive peer
docker exec cli-cold peer lifecycle chaincode install dfir.tar.gz
check_result "Installed on Archive peer"

# Query package ID for cold blockchain
PACKAGE_ID_COLD=$(docker exec cli-cold peer lifecycle chaincode queryinstalled 2>/dev/null | grep "dfir_${CC_VERSION}" | awk '{print $3}' | sed 's/,$//')
if [ -z "$PACKAGE_ID_COLD" ]; then
    echo -e "${RED}❌ Failed to get cold blockchain package ID${NC}"
    exit 1
fi
echo "Cold Package ID: $PACKAGE_ID_COLD"

# Approve for Archive organization
docker exec cli-cold peer lifecycle chaincode approveformyorg \
    -o orderer.cold.coc.com:7150 \
    --ordererTLSHostnameOverride orderer.cold.coc.com \
    --tls --cafile /opt/gopath/src/github.com/hyperledger/fabric/peer/crypto/ordererOrganizations/cold.coc.com/orderers/orderer.cold.coc.com/msp/tlscacerts/tlsca.cold.coc.com-cert.pem \
    --channelID coldchannel \
    --name ${CC_NAME} \
    --version ${CC_VERSION} \
    --package-id ${PACKAGE_ID_COLD} \
    --sequence ${CC_SEQUENCE}
check_result "Approved for Archive organization"

# Commit to cold blockchain channel
docker exec cli-cold peer lifecycle chaincode commit \
    -o orderer.cold.coc.com:7150 \
    --ordererTLSHostnameOverride orderer.cold.coc.com \
    --tls --cafile /opt/gopath/src/github.com/hyperledger/fabric/peer/crypto/ordererOrganizations/cold.coc.com/orderers/orderer.cold.coc.com/msp/tlscacerts/tlsca.cold.coc.com-cert.pem \
    --channelID coldchannel \
    --name ${CC_NAME} \
    --version ${CC_VERSION} \
    --sequence ${CC_SEQUENCE} \
    --peerAddresses peer0.archive.cold.coc.com:9051 \
    --tlsRootCertFiles /opt/gopath/src/github.com/hyperledger/fabric/peer/crypto/peerOrganizations/archive.cold.coc.com/peers/peer0.archive.cold.coc.com/tls/ca.crt
check_result "Committed to Cold blockchain"

# Step 10: Initialize chaincode with PRV configuration from Enclave
print_step "Initializing chaincode with enclave attestation..."

# Check if enclave measurements are available (from bootstrap script)
if [ -z "$MRENCLAVE" ] || [ -z "$MRSIGNER" ] || [ -z "$PUBLIC_KEY" ]; then
    echo -e "${YELLOW}⚠ Enclave measurements not provided, fetching from enclave...${NC}"

    # Fetch from enclave API
    ENCLAVE_INFO=$(curl -s http://localhost:5001/enclave/info)
    MRENCLAVE=$(echo "$ENCLAVE_INFO" | python3 -c "import sys, json; print(json.load(sys.stdin)['mr_enclave'])")
    MRSIGNER=$(echo "$ENCLAVE_INFO" | python3 -c "import sys, json; print(json.load(sys.stdin)['mr_signer'])")

    # Get public key from Root CA certificate
    curl -s http://localhost:5001/ca/certificate -o /tmp/enclave_root_ca.pem
    PUBLIC_KEY=$(openssl x509 -in /tmp/enclave_root_ca.pem -pubkey -noout | grep -v "BEGIN\|END" | tr -d '\n')
fi

echo "Using enclave measurements:"
echo "  MRENCLAVE: ${MRENCLAVE:0:32}..."
echo "  MRSIGNER:  ${MRSIGNER:0:32}..."
echo "  Public Key: ${PUBLIC_KEY:0:32}..."

# Initialize Hot blockchain with InitLedger
echo "Initializing Hot blockchain chaincode..."
docker exec cli peer chaincode invoke \
    -o orderer.hot.coc.com:7050 \
    --ordererTLSHostnameOverride orderer.hot.coc.com \
    --tls --cafile /opt/gopath/src/github.com/hyperledger/fabric/peer/crypto/ordererOrganizations/hot.coc.com/orderers/orderer.hot.coc.com/msp/tlscacerts/tlsca.hot.coc.com-cert.pem \
    -C hotchannel \
    -n ${CC_NAME} \
    --peerAddresses peer0.lawenforcement.hot.coc.com:7051 \
    --tlsRootCertFiles /opt/gopath/src/github.com/hyperledger/fabric/peer/crypto/peerOrganizations/lawenforcement.hot.coc.com/peers/peer0.lawenforcement.hot.coc.com/tls/ca.crt \
    -c "{\"function\":\"InitLedger\",\"Args\":[\"$PUBLIC_KEY\",\"$MRENCLAVE\",\"$MRSIGNER\"]}" \
    2>&1
check_result "Hot blockchain initialized with enclave attestation"

# Initialize Cold blockchain with InitLedger
echo "Initializing Cold blockchain chaincode..."
docker exec cli-cold peer chaincode invoke \
    -o orderer.cold.coc.com:7150 \
    --ordererTLSHostnameOverride orderer.cold.coc.com \
    --tls --cafile /opt/gopath/src/github.com/hyperledger/fabric/peer/crypto/ordererOrganizations/cold.coc.com/orderers/orderer.cold.coc.com/msp/tlscacerts/tlsca.cold.coc.com-cert.pem \
    -C coldchannel \
    -n ${CC_NAME} \
    --peerAddresses peer0.archive.cold.coc.com:9051 \
    --tlsRootCertFiles /opt/gopath/src/github.com/hyperledger/fabric/peer/crypto/peerOrganizations/archive.cold.coc.com/peers/peer0.archive.cold.coc.com/tls/ca.crt \
    -c "{\"function\":\"InitLedger\",\"Args\":[\"$PUBLIC_KEY\",\"$MRENCLAVE\",\"$MRSIGNER\"]}" \
    2>&1
check_result "Cold blockchain initialized with enclave attestation"

echo ""
echo -e "${GREEN}==========================================${NC}"
echo -e "${GREEN}   Chaincode Deployment Complete!${NC}"
echo -e "${GREEN}==========================================${NC}"
echo ""
echo "Chaincode Details:"
echo "  Name:     ${CC_NAME}"
echo "  Version:  ${CC_VERSION}"
echo "  Sequence: ${CC_SEQUENCE}"
echo ""
echo "Deployment Status:"
echo "  Hot Blockchain:  ✓ Deployed on hotchannel"
echo "  Cold Blockchain: ✓ Deployed on coldchannel"
echo ""
echo "Next Steps:"
echo "  1. Run ./verify-blockchain.sh to verify deployment"
echo "  2. Start webapp: cd webapp && python3 app_blockchain.py"
echo ""
