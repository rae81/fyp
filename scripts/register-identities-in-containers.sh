#!/bin/bash
# Register identities inside CA containers (workaround for authentication issue)
# This script runs registration commands INSIDE the CA containers where bootstrap admin credentials work
# After registration, enrollment from host will still get dynamic mTLS certificates from Enclave Root CA chain

set -e

echo "=============================================="
echo "Registering identities inside CA containers"
echo "=============================================="
echo ""

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Function to enroll admin in CA container (only once per container)
enroll_admin_in_container() {
    local CONTAINER_NAME=$1
    local CA_NAME=$2
    local CA_PORT=$3

    # Check if admin already enrolled in this container
    if docker exec $CONTAINER_NAME test -f /tmp/ca-admin/msp/signcerts/cert.pem 2>/dev/null; then
        return 0
    fi

    echo "  Enrolling admin in $CONTAINER_NAME..."
    # Add hosts entry so certificate hostname resolves to localhost
    # CA cert is issued for container hostname, we need to resolve it to 127.0.0.1
    docker exec $CONTAINER_NAME sh -c \
        "echo '127.0.0.1 $CONTAINER_NAME' >> /etc/hosts && \
        FABRIC_CA_CLIENT_HOME=/tmp/ca-admin fabric-ca-client enroll \
        -u https://admin:adminpw@$CONTAINER_NAME:$CA_PORT \
        --caname ca-$CA_NAME \
        --tls.certfiles /etc/hyperledger/fabric-ca-server/ca-chain.pem"

    if [ $? -eq 0 ]; then
        echo -e "  ${GREEN}✓ Admin enrolled${NC}"
        return 0
    else
        echo -e "  ${RED}✗ Admin enrollment failed${NC}"
        return 1
    fi
}

# Function to register identity inside CA container
register_in_container() {
    local CONTAINER_NAME=$1
    local CA_NAME=$2
    local CA_PORT=$3
    local IDENTITY_NAME=$4
    local IDENTITY_TYPE=$5

    # Ensure admin is enrolled first
    enroll_admin_in_container "$CONTAINER_NAME" "$CA_NAME" "$CA_PORT"
    if [ $? -ne 0 ]; then
        echo -e "${RED}✗ Cannot register - admin enrollment failed${NC}"
        return 1
    fi

    echo "Registering $IDENTITY_NAME in $CONTAINER_NAME..."

    # Register using the enrolled admin credentials (hosts entry already added during enrollment)
    docker exec $CONTAINER_NAME sh -c \
        "FABRIC_CA_CLIENT_HOME=/tmp/ca-admin fabric-ca-client register \
        --caname ca-$CA_NAME \
        --id.name $IDENTITY_NAME \
        --id.secret ${IDENTITY_NAME}pw \
        --id.type $IDENTITY_TYPE \
        --tls.certfiles /etc/hyperledger/fabric-ca-server/ca-chain.pem \
        -u https://$CONTAINER_NAME:$CA_PORT"

    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✓ Registered $IDENTITY_NAME successfully${NC}"
    else
        echo -e "${RED}✗ Failed to register $IDENTITY_NAME${NC}"
        return 1
    fi
    echo ""
}

echo "=== Registering Hot Orderer Identities ==="
register_in_container "ca-orderer-hot" "orderer-hot" "11054" "orderer.hot.coc.com" "orderer"

echo "=== Registering Cold Orderer Identities ==="
register_in_container "ca-orderer-cold" "orderer-cold" "12054" "orderer.cold.coc.com" "orderer"

echo "=== Registering Law Enforcement Identities ==="
register_in_container "ca-lawenforcement" "lawenforcement" "7054" "peer0.lawenforcement.hot.coc.com" "peer"
register_in_container "ca-lawenforcement" "lawenforcement" "7054" "user1" "client"

echo "=== Registering Forensic Lab Identities ==="
register_in_container "ca-forensiclab" "forensiclab" "8054" "peer0.forensiclab.hot.coc.com" "peer"
register_in_container "ca-forensiclab" "forensiclab" "8054" "user1" "client"

echo "=== Registering Auditor Identities ==="
register_in_container "ca-auditor" "auditor" "9054" "peer0.auditor.cold.coc.com" "peer"
register_in_container "ca-auditor" "auditor" "9054" "user1" "client"

echo "=== Registering Court Identities ==="
register_in_container "ca-court" "court" "10054" "user1" "client"

echo ""
echo "=============================================="
echo -e "${GREEN}Registration complete inside CA containers${NC}"
echo "=============================================="
echo ""
echo "Next: Run scripts/enroll-all-identities.sh to enroll and get dynamic mTLS certificates"
echo "       Certificates will be issued through: Enclave Root CA → Fabric CA → Identity Certs"
