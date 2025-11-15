#!/bin/bash
###############################################################################
# Seal Orderer Private Keys in SGX Enclave Simulator
# Takes cryptogen-generated orderer keys and seals them securely
###############################################################################

set -e

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

echo -e "${GREEN}=========================================="
echo "Sealing Orderer Keys in SGX Enclave"
echo -e "==========================================${NC}"
echo ""

cd "$PROJECT_ROOT"

# Check if enclave simulator is running
if ! curl -s http://localhost:5000/health > /dev/null 2>&1; then
    echo -e "${YELLOW}Starting SGX Enclave Simulator...${NC}"
    cd enclave-simulator
    python3 enclave_sgx.py > /tmp/enclave.log 2>&1 &
    ENCLAVE_PID=$!
    echo $ENCLAVE_PID > /tmp/enclave.pid
    cd "$PROJECT_ROOT"

    # Wait for enclave to start
    sleep 3
    echo -e "${GREEN}✓ Enclave started (PID: $ENCLAVE_PID)${NC}"
else
    echo -e "${GREEN}✓ Enclave already running${NC}"
fi
echo ""

# Function to seal a private key
seal_key() {
    local key_path=$1
    local key_id=$2
    local org=$3

    echo -e "${YELLOW}Sealing key: $key_id${NC}"

    # Read the private key
    local key_content=$(cat "$key_path")

    # Seal the key in enclave using API
    local response=$(curl -s -X POST http://localhost:5000/seal-key \
        -H "Content-Type: application/json" \
        -d "{
            \"key_id\": \"$key_id\",
            \"key_data\": \"$key_content\",
            \"organization\": \"$org\"
        }")

    if echo "$response" | grep -q "success"; then
        echo -e "${GREEN}  ✓ Key sealed: $key_id${NC}"

        # Create backup of original key
        mkdir -p "$PROJECT_ROOT/sealed-keys-backup"
        cp "$key_path" "$PROJECT_ROOT/sealed-keys-backup/${key_id}.pem"

        # Delete plaintext key (security!)
        rm -f "$key_path"

        # Create a marker file indicating key is in enclave
        echo "SEALED_IN_ENCLAVE" > "${key_path}.sealed"
        echo "$key_id" >> "${key_path}.sealed"

        return 0
    else
        echo -e "${RED}  ✗ Failed to seal key: $key_id${NC}"
        echo "  Response: $response"
        return 1
    fi
}

# Seal Hot Orderer Keys
echo -e "${YELLOW}[1/4] Sealing hot orderer MSP signing key...${NC}"
HOT_ORDERER_MSP_KEY=$(find organizations/ordererOrganizations/hot.coc.com/orderers/orderer.hot.coc.com/msp/keystore -type f -name "*_sk" 2>/dev/null | head -1)
if [ -f "$HOT_ORDERER_MSP_KEY" ]; then
    seal_key "$HOT_ORDERER_MSP_KEY" "hot-orderer-msp" "hot.coc.com"
else
    echo -e "${RED}✗ Hot orderer MSP key not found${NC}"
fi
echo ""

echo -e "${YELLOW}[2/4] Sealing hot orderer TLS private key...${NC}"
HOT_ORDERER_TLS_KEY=$(find organizations/ordererOrganizations/hot.coc.com/orderers/orderer.hot.coc.com/tls -type f -name "*_sk" 2>/dev/null | head -1)
if [ -f "$HOT_ORDERER_TLS_KEY" ]; then
    seal_key "$HOT_ORDERER_TLS_KEY" "hot-orderer-tls" "hot.coc.com"
else
    echo -e "${RED}✗ Hot orderer TLS key not found${NC}"
fi
echo ""

# Seal Cold Orderer Keys
echo -e "${YELLOW}[3/4] Sealing cold orderer MSP signing key...${NC}"
COLD_ORDERER_MSP_KEY=$(find organizations/ordererOrganizations/cold.coc.com/orderers/orderer.cold.coc.com/msp/keystore -type f -name "*_sk" 2>/dev/null | head -1)
if [ -f "$COLD_ORDERER_MSP_KEY" ]; then
    seal_key "$COLD_ORDERER_MSP_KEY" "cold-orderer-msp" "cold.coc.com"
else
    echo -e "${RED}✗ Cold orderer MSP key not found${NC}"
fi
echo ""

echo -e "${YELLOW}[4/4] Sealing cold orderer TLS private key...${NC}"
COLD_ORDERER_TLS_KEY=$(find organizations/ordererOrganizations/cold.coc.com/orderers/orderer.cold.coc.com/tls -type f -name "*_sk" 2>/dev/null | head -1)
if [ -f "$COLD_ORDERER_TLS_KEY" ]; then
    seal_key "$COLD_ORDERER_TLS_KEY" "cold-orderer-tls" "cold.coc.com"
else
    echo -e "${RED}✗ Cold orderer TLS key not found${NC}"
fi
echo ""

echo -e "${GREEN}=========================================="
echo "✓ Orderer Keys Sealed in Enclave"
echo -e "==========================================${NC}"
echo ""
echo -e "${YELLOW}Sealed keys stored in enclave:${NC}"
echo "  - hot-orderer-msp"
echo "  - hot-orderer-tls"
echo "  - cold-orderer-msp"
echo "  - cold-orderer-tls"
echo ""
echo -e "${YELLOW}Plaintext keys deleted from filesystem${NC}"
echo -e "${YELLOW}Backups saved in: sealed-keys-backup/${NC}"
echo ""
echo -e "${GREEN}Next: Orderers will retrieve keys from enclave at runtime${NC}"
echo ""
