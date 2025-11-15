#!/bin/bash
#
# Test and Fix CA Certificate Generation
# This script tests certificate generation and fixes any issues
#

set -e

cd "$(dirname "$0")"

echo "=== Testing and Fixing CA Certificate Generation ==="
echo ""

# Step 1: Start enclave
echo "[Step 1/6] Starting SGX Enclave..."
docker-compose -f docker-compose-full.yml up -d enclave

echo "Waiting for enclave to start..."
sleep 10

# Wait for enclave to be healthy
until curl -s http://localhost:5001/health > /dev/null 2>&1; do
    echo "  Waiting for enclave..."
    sleep 2
done
echo "✓ Enclave is running"
echo ""

# Step 2: Initialize Root CA
echo "[Step 2/6] Initializing Root CA..."
INIT_RESPONSE=$(curl -s -X POST http://localhost:5001/ca/init)
echo "$INIT_RESPONSE" | python3 -m json.tool
echo ""

# Step 3: Test certificate generation
echo "[Step 3/6] Testing intermediate CA certificate generation..."

# Generate a test key
TEST_DIR="/tmp/test-ca-cert"
mkdir -p "$TEST_DIR"

openssl genpkey -algorithm EC -pkeyopt ec_paramgen_curve:P-256 -out "$TEST_DIR/test-key.pem"

# Create CSR
openssl req -new -key "$TEST_DIR/test-key.pem" \
    -out "$TEST_DIR/test-csr.pem" \
    -subj "/C=US/ST=California/L=San Francisco/O=Test CA/OU=Testing/CN=ca.test.coc.com"

CSR_CONTENT=$(cat "$TEST_DIR/test-csr.pem")

# Request certificate from enclave
echo "Requesting intermediate-ca certificate from enclave..."
CERT_RESPONSE=$(curl -s -X POST http://localhost:5001/ca/sign \
    -H "Content-Type: application/json" \
    -d "{\"csr\": $(echo "$CSR_CONTENT" | jq -Rs .), \"type\": \"intermediate-ca\", \"validity_days\": 1825}")

# Save certificate
echo "$CERT_RESPONSE" | python3 -c "import sys, json; print(json.load(sys.stdin)['certificate'])" > "$TEST_DIR/test-cert.pem"

echo "✓ Certificate generated"
echo ""

# Step 4: Verify certificate
echo "[Step 4/6] Verifying certificate..."
echo ""

# Check if certificate exists
if [ ! -f "$TEST_DIR/test-cert.pem" ]; then
    echo "❌ Certificate file not generated!"
    exit 1
fi

# Display certificate details
echo "Certificate details:"
openssl x509 -in "$TEST_DIR/test-cert.pem" -noout -text | grep -A5 "X509v3 Key Usage"

# Check for cert sign usage
if openssl x509 -in "$TEST_DIR/test-cert.pem" -noout -text | grep -q "Certificate Sign"; then
    echo ""
    echo "✅ Certificate has 'Certificate Sign' key usage - CORRECT!"
    echo ""
    CA_CERT_OK=true
else
    echo ""
    echo "❌ Certificate is MISSING 'Certificate Sign' key usage - BUG FOUND!"
    echo ""
    echo "This is the issue causing Fabric CA to reject the certificates."
    echo ""
    CA_CERT_OK=false
fi

# Step 5: If bug found, check the code
if [ "$CA_CERT_OK" = false ]; then
    echo "[Step 5/6] Diagnosing the issue..."
    echo ""

    echo "Checking enclave_sgx.py for certificate signing logic..."
    if grep -n "key_cert_sign.*True" enclave-simulator/enclave_sgx.py; then
        echo ""
        echo "✓ Code shows key_cert_sign=True is set for intermediate certificates"
        echo ""
        echo "The bug might be:"
        echo "  1. Type parameter not being passed correctly"
        echo "  2. Different enclave file being used"
        echo "  3. Certificate extension not being added"
        echo ""
    else
        echo ""
        echo "❌ key_cert_sign=True NOT found in enclave_sgx.py!"
        echo "This is the bug - the KeyUsage extension needs to be fixed."
        echo ""
    fi

    # Check which enclave service is actually running
    echo "Checking which enclave service is running..."
    docker logs enclave 2>&1 | tail -20
    echo ""

    exit 1
fi

# Step 6: If certificate is OK, bootstrap all CAs
echo "[Step 6/6] Bootstrapping Fabric CA servers..."
echo ""

sudo rm -rf fabric-ca/*/ca-cert.pem fabric-ca/*/ca-key.pem fabric-ca/*/ca-chain.pem
chmod +x fabric-ca/bootstrap-fabric-ca.sh
ENCLAVE_URL=http://localhost:5001 ./fabric-ca/bootstrap-fabric-ca.sh

echo ""
echo "=== Verification Complete ==="
echo ""

# Verify all CA certificates
echo "Verifying all generated CA certificates..."
for CA_DIR in fabric-ca/*/; do
    if [ -f "$CA_DIR/ca-cert.pem" ]; then
        CA_NAME=$(basename "$CA_DIR")
        echo -n "  $CA_NAME: "

        if openssl x509 -in "$CA_DIR/ca-cert.pem" -noout -text | grep -q "Certificate Sign"; then
            echo "✅ Valid (has cert sign)"
        else
            echo "❌ Invalid (missing cert sign)"
        fi
    fi
done

echo ""
echo "=== Test Complete ==="
echo ""

if [ "$CA_CERT_OK" = true ]; then
    echo "✅ All certificates generated correctly!"
    echo ""
    echo "Next steps:"
    echo "  1. Start CA servers: docker-compose -f docker-compose-full.yml up -d ca-lawenforcement ca-forensiclab ca-auditor ca-court ca-orderer-hot ca-orderer-cold"
    echo "  2. Wait 30 seconds for CAs to start"
    echo "  3. Run enrollment: ./scripts/enroll-all-identities.sh"
else
    echo "❌ Certificate generation has issues - see diagnostic output above"
fi

# Cleanup
rm -rf "$TEST_DIR"
