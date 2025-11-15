#!/bin/bash

# Blockchain Functionality Verification Script
# Tests all components of the Dual Hyperledger Blockchain system

echo "==========================================="
echo "   Blockchain Functionality Verification"
echo "==========================================="
echo ""

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

# Test counters
TOTAL_TESTS=0
PASSED_TESTS=0
FAILED_TESTS=0

# Test result tracking
print_test() {
    echo -n "[TEST] $1 "
}

pass_test() {
    echo -e "${GREEN}✅ PASS${NC}"
    PASSED_TESTS=$((PASSED_TESTS + 1))
    TOTAL_TESTS=$((TOTAL_TESTS + 1))
}

fail_test() {
    echo -e "${RED}❌ FAIL${NC}"
    if [ -n "$1" ]; then
        echo -e "${RED}Expected: $1${NC}"
        echo -e "${RED}Got: $2${NC}"
    fi
    FAILED_TESTS=$((FAILED_TESTS + 1))
    TOTAL_TESTS=$((TOTAL_TESTS + 1))
}

print_section() {
    echo ""
    echo -e "${BLUE}==========================================${NC}"
    echo -e "${BLUE}SECTION $1: $2${NC}"
    echo -e "${BLUE}==========================================${NC}"
    echo ""
}

# SECTION 1: Container Health Checks
print_section "1" "Container Health Checks"

# Test CLI containers
print_test "Hot CLI container is running"
if docker ps --format '{{.Names}}' | grep -q "^cli$"; then
    pass_test
else
    fail_test
fi

print_test "Cold CLI container is running"
if docker ps --format '{{.Names}}' | grep -q "^cli-cold$"; then
    pass_test
else
    fail_test
fi

# Test Peer containers
print_test "Hot Law Enforcement peer is running"
if docker ps --format '{{.Names}}' | grep -q "^peer0.lawenforcement.hot.coc.com$"; then
    pass_test
else
    fail_test
fi

print_test "Hot Forensic Lab peer is running"
if docker ps --format '{{.Names}}' | grep -q "^peer0.forensiclab.hot.coc.com$"; then
    pass_test
else
    fail_test
fi

print_test "Cold Archive peer is running"
if docker ps --format '{{.Names}}' | grep -q "^peer0.archive.cold.coc.com$"; then
    pass_test
else
    fail_test
fi

# Test Orderer containers
print_test "Hot Orderer is running"
if docker ps --format '{{.Names}}' | grep -q "^orderer.hot.coc.com$"; then
    pass_test
else
    fail_test
fi

print_test "Cold Orderer is running"
if docker ps --format '{{.Names}}' | grep -q "^orderer.cold.coc.com$"; then
    pass_test
else
    fail_test
fi

# Test Storage containers
print_test "IPFS node is running"
if docker ps --format '{{.Names}}' | grep -q "^ipfs-node$"; then
    pass_test
else
    fail_test
fi

print_test "MySQL database is running"
if docker ps --format '{{.Names}}' | grep -q "^mysql-coc$"; then
    pass_test
else
    fail_test
fi

# SECTION 2: Channel Connectivity
print_section "2" "Channel Connectivity"

# Test Hot blockchain channel
print_test "Hot blockchain - channel list"
HOT_CHANNEL=$(docker exec cli peer channel list 2>&1)
if echo "$HOT_CHANNEL" | grep -q "hotchannel"; then
    pass_test
else
    fail_test "hotchannel" "$HOT_CHANNEL"
fi

# Test Cold blockchain channel
print_test "Cold blockchain - channel list"
COLD_CHANNEL=$(docker exec cli-cold peer channel list 2>&1)
if echo "$COLD_CHANNEL" | grep -q "coldchannel"; then
    pass_test
else
    fail_test "coldchannel" "$COLD_CHANNEL"
fi

# SECTION 3: Chaincode Deployment
print_section "3" "Chaincode Deployment"

# Test Hot blockchain chaincode installation
print_test "Hot blockchain - chaincode installed"
HOT_INSTALLED=$(docker exec cli peer lifecycle chaincode queryinstalled 2>&1)
if echo "$HOT_INSTALLED" | grep -q "dfir"; then
    pass_test
else
    fail_test "dfir" "$HOT_INSTALLED"
fi

# Test Cold blockchain chaincode installation
print_test "Cold blockchain - chaincode installed"
COLD_INSTALLED=$(docker exec cli-cold peer lifecycle chaincode queryinstalled 2>&1)
if echo "$COLD_INSTALLED" | grep -q "dfir"; then
    pass_test
else
    fail_test "dfir" "$COLD_INSTALLED"
fi

# Test Hot blockchain chaincode commit
print_test "Hot blockchain - chaincode committed"
HOT_COMMITTED=$(docker exec cli peer lifecycle chaincode querycommitted -C hotchannel 2>&1)
if echo "$HOT_COMMITTED" | grep -q "dfir"; then
    pass_test
else
    fail_test "dfir" "$HOT_COMMITTED"
fi

# Test Cold blockchain chaincode commit
print_test "Cold blockchain - chaincode committed"
COLD_COMMITTED=$(docker exec cli-cold peer lifecycle chaincode querycommitted -C coldchannel 2>&1)
if echo "$COLD_COMMITTED" | grep -q "dfir"; then
    pass_test
else
    fail_test "dfir" "$COLD_COMMITTED"
fi

# SECTION 4: Blockchain Transaction Test
print_section "4" "Blockchain Transaction Test"

# Get initial block height for Hot blockchain
echo "[INFO] Getting Hot blockchain initial state..."
HOT_INITIAL=$(docker exec cli peer channel getinfo -c hotchannel 2>/dev/null | grep -oP '(?<="height":)\d+' || echo "0")
echo "Hot blockchain height: $HOT_INITIAL"

# Get initial block height for Cold blockchain
echo "[INFO] Getting Cold blockchain initial state..."
COLD_INITIAL=$(docker exec cli-cold peer channel getinfo -c coldchannel 2>/dev/null | grep -oP '(?<="height":)\d+' || echo "0")
echo "Cold blockchain height: $COLD_INITIAL"

echo ""
print_test "Creating test evidence on Hot blockchain..."
TEST_ID="TEST-$(date +%s)"
CREATE_RESULT=$(docker exec cli peer chaincode invoke \
    -o orderer.hot.coc.com:7050 \
    --ordererTLSHostnameOverride orderer.hot.coc.com \
    --tls --cafile /opt/gopath/src/github.com/hyperledger/fabric/peer/crypto/ordererOrganizations/hot.coc.com/orderers/orderer.hot.coc.com/msp/tlscacerts/tlsca.hot.coc.com-cert.pem \
    -C hotchannel \
    -n dfir \
    --peerAddresses peer0.lawenforcement.hot.coc.com:7051 \
    --tlsRootCertFiles /opt/gopath/src/github.com/hyperledger/fabric/peer/crypto/peerOrganizations/lawenforcement.hot.coc.com/peers/peer0.lawenforcement.hot.coc.com/tls/ca.crt \
    -c "{\"function\":\"CreateEvidenceSimple\",\"Args\":[\"$TEST_ID\",\"TEST-CASE-001\",\"test\",\"Verification test evidence\",\"abc123\",\"ipfs://test\",\"{}\"]}" 2>&1)

if echo "$CREATE_RESULT" | grep -q "Chaincode invoke successful"; then
    pass_test
else
    echo -e "${RED}❌ Transaction failed${NC}"
    TOTAL_TESTS=$((TOTAL_TESTS + 1))
    FAILED_TESTS=$((FAILED_TESTS + 1))
fi

# Wait for block creation
echo ""
echo "[INFO] Waiting 5 seconds for block creation..."
sleep 5

# Check if new block was created
print_test "Verifying new block was created..."
HOT_NEW=$(docker exec cli peer channel getinfo -c hotchannel 2>/dev/null | grep -oP '(?<="height":)\d+' || echo "0")
echo "Hot blockchain new height: $HOT_NEW"

if [ "$HOT_NEW" -gt "$HOT_INITIAL" ]; then
    pass_test
else
    fail_test "Height > $HOT_INITIAL" "Height = $HOT_NEW (no new blocks created)"
fi

# Query the evidence back
print_test "Querying test evidence from blockchain..."
QUERY_RESULT=$(docker exec cli peer chaincode query \
    -C hotchannel \
    -n dfir \
    -c "{\"function\":\"ReadEvidenceSimple\",\"Args\":[\"$TEST_ID\"]}" 2>&1)

if echo "$QUERY_RESULT" | grep -q "$TEST_ID"; then
    pass_test
else
    fail_test "Evidence with ID $TEST_ID" "Could not retrieve evidence"
fi

# SECTION 5: Storage Services
print_section "5" "Storage Services"

# Test IPFS
print_test "IPFS API is responding"
IPFS_TEST=$(curl -s -X POST http://localhost:5001/api/v0/version 2>&1)
if echo "$IPFS_TEST" | grep -q "Version"; then
    pass_test
else
    fail_test
fi

# Test MySQL
print_test "MySQL database is accessible"
# Check if mysql client is installed on host, otherwise use docker exec
if command -v mysql &> /dev/null; then
    MYSQL_TEST=$(mysql -h localhost -P 3306 -u cocuser -pcocpassword --ssl-mode=DISABLED -e "SELECT 1" 2>&1)
    if echo "$MYSQL_TEST" | grep -q "1"; then
        pass_test
    else
        # Try via docker exec as fallback
        MYSQL_TEST=$(docker exec mysql-coc mysql -u cocuser -pcocpassword -e "SELECT 1" 2>&1)
        if echo "$MYSQL_TEST" | grep -q "1"; then
            pass_test
        else
            fail_test
        fi
    fi
else
    # No mysql client on host, use docker exec
    MYSQL_TEST=$(docker exec mysql-coc mysql -u cocuser -pcocpassword -e "SELECT 1" 2>&1)
    if echo "$MYSQL_TEST" | grep -q "1"; then
        pass_test
    else
        fail_test
    fi
fi

# Print Summary
echo ""
echo -e "${BLUE}==========================================${NC}"
echo -e "${BLUE}VERIFICATION SUMMARY${NC}"
echo -e "${BLUE}==========================================${NC}"
echo ""
echo "Total Tests: $TOTAL_TESTS"
echo -e "${GREEN}Passed: $PASSED_TESTS${NC}"
echo -e "${RED}Failed: $FAILED_TESTS${NC}"
echo ""

# Final result
if [ $FAILED_TESTS -eq 0 ]; then
    echo -e "${GREEN}==========================================${NC}"
    echo -e "${GREEN}✅ ALL TESTS PASSED!${NC}"
    echo -e "${GREEN}==========================================${NC}"
    echo ""
    echo "Your blockchain system is fully operational!"
    echo ""
    echo "Next steps:"
    echo "  • Access dashboard: http://localhost:5000"
    echo "  • IPFS WebUI: https://webui.ipfs.io/#/files"
    echo "  • phpMyAdmin: http://localhost:8081"
    echo ""
    exit 0
else
    echo -e "${RED}==========================================${NC}"
    echo -e "${RED}⚠ SOME TESTS FAILED${NC}"
    echo -e "${RED}==========================================${NC}"
    echo ""
    echo "Issues detected. Please check:"
    echo ""
    echo "  • Are all containers running? (docker ps)"
    echo "  • Is chaincode deployed? (./deploy-chaincode.sh)"
    echo "  • Check logs: docker logs cli"
    echo ""
    exit 1
fi
