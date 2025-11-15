#!/bin/bash
# Fix MSP configuration by adding admin certs and config.yaml

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
ORGS_DIR="$PROJECT_ROOT/organizations"

echo "==============================================="
echo "Fixing MSP Configuration"
echo "==============================================="

# Function to create config.yaml for MSP
create_msp_config() {
    local MSP_DIR=$1
    local ORG_NAME=$2

    cat > "$MSP_DIR/config.yaml" <<EOF
NodeOUs:
  Enable: false
EOF
    echo "  ✓ Created config.yaml for $ORG_NAME"
}

# Function to add admin certs to organization MSP
add_admin_certs() {
    local ORG_MSP_DIR=$1
    local ADMIN_CERT_SOURCE=$2
    local ORG_NAME=$3

    mkdir -p "$ORG_MSP_DIR/admincerts"
    cp "$ADMIN_CERT_SOURCE" "$ORG_MSP_DIR/admincerts/"
    echo "  ✓ Added admin cert for $ORG_NAME"
}

echo ""
echo "=== Fixing HOT Orderer Organization MSP ==="
HOT_ORD_MSP="$ORGS_DIR/ordererOrganizations/hot.coc.com/msp"
create_msp_config "$HOT_ORD_MSP" "hot orderer"
add_admin_certs "$HOT_ORD_MSP" \
    "$ORGS_DIR/ordererOrganizations/hot.coc.com/users/Admin@hot.coc.com/msp/signcerts/cert.pem" \
    "hot orderer"

echo ""
echo "=== Fixing COLD Orderer Organization MSP ==="
COLD_ORD_MSP="$ORGS_DIR/ordererOrganizations/cold.coc.com/msp"
create_msp_config "$COLD_ORD_MSP" "cold orderer"
add_admin_certs "$COLD_ORD_MSP" \
    "$ORGS_DIR/ordererOrganizations/cold.coc.com/users/Admin@cold.coc.com/msp/signcerts/cert.pem" \
    "cold orderer"

echo ""
echo "=== Fixing HOT Orderer Instance MSP ==="
HOT_ORD_INST_MSP="$ORGS_DIR/ordererOrganizations/hot.coc.com/orderers/orderer.hot.coc.com/msp"
create_msp_config "$HOT_ORD_INST_MSP" "hot orderer instance"
add_admin_certs "$HOT_ORD_INST_MSP" \
    "$ORGS_DIR/ordererOrganizations/hot.coc.com/users/Admin@hot.coc.com/msp/signcerts/cert.pem" \
    "hot orderer instance"

echo ""
echo "=== Fixing COLD Orderer Instance MSP ==="
COLD_ORD_INST_MSP="$ORGS_DIR/ordererOrganizations/cold.coc.com/orderers/orderer.cold.coc.com/msp"
create_msp_config "$COLD_ORD_INST_MSP" "cold orderer instance"
add_admin_certs "$COLD_ORD_INST_MSP" \
    "$ORGS_DIR/ordererOrganizations/cold.coc.com/users/Admin@cold.coc.com/msp/signcerts/cert.pem" \
    "cold orderer instance"

echo ""
echo "=== Fixing Peer Organization MSPs ==="

# Law Enforcement
LAW_ORG_MSP="$ORGS_DIR/peerOrganizations/lawenforcement.hot.coc.com/msp"
create_msp_config "$LAW_ORG_MSP" "lawenforcement"
add_admin_certs "$LAW_ORG_MSP" \
    "$ORGS_DIR/peerOrganizations/lawenforcement.hot.coc.com/users/Admin@lawenforcement.hot.coc.com/msp/signcerts/cert.pem" \
    "lawenforcement"

LAW_PEER_MSP="$ORGS_DIR/peerOrganizations/lawenforcement.hot.coc.com/peers/peer0.lawenforcement.hot.coc.com/msp"
create_msp_config "$LAW_PEER_MSP" "lawenforcement peer"
add_admin_certs "$LAW_PEER_MSP" \
    "$ORGS_DIR/peerOrganizations/lawenforcement.hot.coc.com/users/Admin@lawenforcement.hot.coc.com/msp/signcerts/cert.pem" \
    "lawenforcement peer"

# Forensic Lab
FLAB_ORG_MSP="$ORGS_DIR/peerOrganizations/forensiclab.hot.coc.com/msp"
create_msp_config "$FLAB_ORG_MSP" "forensiclab"
add_admin_certs "$FLAB_ORG_MSP" \
    "$ORGS_DIR/peerOrganizations/forensiclab.hot.coc.com/users/Admin@forensiclab.hot.coc.com/msp/signcerts/cert.pem" \
    "forensiclab"

FLAB_PEER_MSP="$ORGS_DIR/peerOrganizations/forensiclab.hot.coc.com/peers/peer0.forensiclab.hot.coc.com/msp"
create_msp_config "$FLAB_PEER_MSP" "forensiclab peer"
add_admin_certs "$FLAB_PEER_MSP" \
    "$ORGS_DIR/peerOrganizations/forensiclab.hot.coc.com/users/Admin@forensiclab.hot.coc.com/msp/signcerts/cert.pem" \
    "forensiclab peer"

# Auditor
AUD_ORG_MSP="$ORGS_DIR/peerOrganizations/auditor.cold.coc.com/msp"
create_msp_config "$AUD_ORG_MSP" "auditor"
add_admin_certs "$AUD_ORG_MSP" \
    "$ORGS_DIR/peerOrganizations/auditor.cold.coc.com/users/Admin@auditor.cold.coc.com/msp/signcerts/cert.pem" \
    "auditor"

AUD_PEER_MSP="$ORGS_DIR/peerOrganizations/auditor.cold.coc.com/peers/peer0.auditor.cold.coc.com/msp"
create_msp_config "$AUD_PEER_MSP" "auditor peer"
add_admin_certs "$AUD_PEER_MSP" \
    "$ORGS_DIR/peerOrganizations/auditor.cold.coc.com/users/Admin@auditor.cold.coc.com/msp/signcerts/cert.pem" \
    "auditor peer"

# Court
COURT_ORG_MSP="$ORGS_DIR/peerOrganizations/court.coc.com/msp"
create_msp_config "$COURT_ORG_MSP" "court"
add_admin_certs "$COURT_ORG_MSP" \
    "$ORGS_DIR/peerOrganizations/court.coc.com/users/Admin@court.coc.com/msp/signcerts/cert.pem" \
    "court"

echo ""
echo "=== Fixing Admin User MSP directories ==="

# Fix admin users for each organization
for USER_MSP in "$ORGS_DIR"/peerOrganizations/*/users/Admin@*/msp \
                "$ORGS_DIR"/ordererOrganizations/*/users/Admin@*/msp; do
    if [ -d "$USER_MSP" ]; then
        ORG_NAME=$(basename $(dirname $(dirname $(dirname "$USER_MSP"))))
        create_msp_config "$USER_MSP" "admin user for $ORG_NAME"

        # Add admin cert to admincerts directory
        CERT_FILE="$USER_MSP/signcerts/cert.pem"
        if [ -f "$CERT_FILE" ]; then
            mkdir -p "$USER_MSP/admincerts"
            cp "$CERT_FILE" "$USER_MSP/admincerts/"
            echo "  ✓ Added admincerts for admin user in $ORG_NAME"
        fi
    fi
done

echo ""
echo "==============================================="
echo "✓ MSP Configuration Fixed"
echo "==============================================="
echo ""
echo "Next: Restart the blockchain network"
echo "  docker-compose -f docker-compose-hot.yml -f docker-compose-cold.yml restart"
