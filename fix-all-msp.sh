#!/bin/bash
#
# Fix ALL MSP Configurations (Orderers + Peers)
# Adds admin certs and config.yaml to enable NodeOU classification
#

set -e

cd "$(dirname "$0")"

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${GREEN}=========================================${NC}"
echo -e "${GREEN}  Fixing ALL MSP Configurations${NC}"
echo -e "${GREEN}=========================================${NC}"
echo ""

# Function to create config.yaml for orderer orgs
create_orderer_config_yaml() {
    local msp_dir=$1
    local ca_file=$2

    cat > "$msp_dir/config.yaml" <<EOF
NodeOUs:
  Enable: true
  ClientOUIdentifier:
    Certificate: cacerts/$ca_file
    OrganizationalUnitIdentifier: client
  PeerOUIdentifier:
    Certificate: cacerts/$ca_file
    OrganizationalUnitIdentifier: peer
  AdminOUIdentifier:
    Certificate: cacerts/$ca_file
    OrganizationalUnitIdentifier: admin
  OrdererOUIdentifier:
    Certificate: cacerts/$ca_file
    OrganizationalUnitIdentifier: orderer
EOF
}

# Function to create config.yaml for peer orgs
create_peer_config_yaml() {
    local msp_dir=$1
    local ca_file=$2

    cat > "$msp_dir/config.yaml" <<EOF
NodeOUs:
  Enable: true
  ClientOUIdentifier:
    Certificate: cacerts/$ca_file
    OrganizationalUnitIdentifier: client
  PeerOUIdentifier:
    Certificate: cacerts/$ca_file
    OrganizationalUnitIdentifier: peer
  AdminOUIdentifier:
    Certificate: cacerts/$ca_file
    OrganizationalUnitIdentifier: admin
  OrdererOUIdentifier:
    Certificate: cacerts/$ca_file
    OrganizationalUnitIdentifier: orderer
EOF
}

echo -e "${YELLOW}[1/5] Configuring HOT orderer MSPs...${NC}"

# Hot orderer - orderer MSP
HOT_ORDERER_MSP="organizations/ordererOrganizations/hot.coc.com/orderers/orderer.hot.coc.com/msp"
if [ -d "$HOT_ORDERER_MSP" ]; then
    CA_FILE=$(ls "$HOT_ORDERER_MSP/cacerts/" | head -1)
    create_orderer_config_yaml "$HOT_ORDERER_MSP" "$CA_FILE"

    mkdir -p "$HOT_ORDERER_MSP/admincerts"
    cp "organizations/ordererOrganizations/hot.coc.com/users/Admin@hot.coc.com/msp/signcerts/cert.pem" \
       "$HOT_ORDERER_MSP/admincerts/" 2>/dev/null || true
    echo "  [OK] Hot orderer MSP configured"
else
    echo "  [FAIL] Hot orderer MSP directory not found"
fi

# Hot orderer - org-level MSP
HOT_ORG_MSP="organizations/ordererOrganizations/hot.coc.com/msp"
if [ -d "$HOT_ORG_MSP" ]; then
    CA_FILE=$(ls "$HOT_ORG_MSP/cacerts/" | head -1)
    create_orderer_config_yaml "$HOT_ORG_MSP" "$CA_FILE"

    mkdir -p "$HOT_ORG_MSP/admincerts"
    cp "organizations/ordererOrganizations/hot.coc.com/users/Admin@hot.coc.com/msp/signcerts/cert.pem" \
       "$HOT_ORG_MSP/admincerts/" 2>/dev/null || true
    echo "  [OK] Hot org-level MSP configured"
fi
echo ""

echo -e "${YELLOW}[2/5] Configuring COLD orderer MSPs...${NC}"

# Cold orderer - orderer MSP
COLD_ORDERER_MSP="organizations/ordererOrganizations/cold.coc.com/orderers/orderer.cold.coc.com/msp"
if [ -d "$COLD_ORDERER_MSP" ]; then
    CA_FILE=$(ls "$COLD_ORDERER_MSP/cacerts/" | head -1)
    create_orderer_config_yaml "$COLD_ORDERER_MSP" "$CA_FILE"

    mkdir -p "$COLD_ORDERER_MSP/admincerts"
    cp "organizations/ordererOrganizations/cold.coc.com/users/Admin@cold.coc.com/msp/signcerts/cert.pem" \
       "$COLD_ORDERER_MSP/admincerts/" 2>/dev/null || true
    echo "  [OK] Cold orderer MSP configured"
else
    echo "  ✗ Cold orderer MSP directory not found"
fi

# Cold orderer - org-level MSP
COLD_ORG_MSP="organizations/ordererOrganizations/cold.coc.com/msp"
if [ -d "$COLD_ORG_MSP" ]; then
    CA_FILE=$(ls "$COLD_ORG_MSP/cacerts/" | head -1)
    create_orderer_config_yaml "$COLD_ORG_MSP" "$CA_FILE"

    mkdir -p "$COLD_ORG_MSP/admincerts"
    cp "organizations/ordererOrganizations/cold.coc.com/users/Admin@cold.coc.com/msp/signcerts/cert.pem" \
       "$COLD_ORG_MSP/admincerts/" 2>/dev/null || true
    echo "  [OK] Cold org-level MSP configured"
fi
echo ""

echo -e "${YELLOW}[3/5] Configuring PEER organization MSPs...${NC}"

# Law Enforcement
for MSP_DIR in \
    "organizations/peerOrganizations/lawenforcement.hot.coc.com/msp" \
    "organizations/peerOrganizations/lawenforcement.hot.coc.com/peers/peer0.lawenforcement.hot.coc.com/msp" \
    "organizations/peerOrganizations/lawenforcement.hot.coc.com/users/Admin@lawenforcement.hot.coc.com/msp"; do

    if [ -d "$MSP_DIR" ]; then
        CA_FILE=$(ls "$MSP_DIR/cacerts/" 2>/dev/null | head -1)
        if [ -n "$CA_FILE" ]; then
            create_peer_config_yaml "$MSP_DIR" "$CA_FILE"
            mkdir -p "$MSP_DIR/admincerts"
            cp "organizations/peerOrganizations/lawenforcement.hot.coc.com/users/Admin@lawenforcement.hot.coc.com/msp/signcerts/cert.pem" \
               "$MSP_DIR/admincerts/" 2>/dev/null || true
        fi
    fi
done
echo "  [OK] LawEnforcement MSPs configured"

# Forensic Lab
for MSP_DIR in \
    "organizations/peerOrganizations/forensiclab.hot.coc.com/msp" \
    "organizations/peerOrganizations/forensiclab.hot.coc.com/peers/peer0.forensiclab.hot.coc.com/msp" \
    "organizations/peerOrganizations/forensiclab.hot.coc.com/users/Admin@forensiclab.hot.coc.com/msp"; do

    if [ -d "$MSP_DIR" ]; then
        CA_FILE=$(ls "$MSP_DIR/cacerts/" 2>/dev/null | head -1)
        if [ -n "$CA_FILE" ]; then
            create_peer_config_yaml "$MSP_DIR" "$CA_FILE"
            mkdir -p "$MSP_DIR/admincerts"
            cp "organizations/peerOrganizations/forensiclab.hot.coc.com/users/Admin@forensiclab.hot.coc.com/msp/signcerts/cert.pem" \
               "$MSP_DIR/admincerts/" 2>/dev/null || true
        fi
    fi
done
echo "  [OK] ForensicLab MSPs configured"

# Auditor
for MSP_DIR in \
    "organizations/peerOrganizations/auditor.cold.coc.com/msp" \
    "organizations/peerOrganizations/auditor.cold.coc.com/peers/peer0.auditor.cold.coc.com/msp" \
    "organizations/peerOrganizations/auditor.cold.coc.com/users/Admin@auditor.cold.coc.com/msp"; do

    if [ -d "$MSP_DIR" ]; then
        CA_FILE=$(ls "$MSP_DIR/cacerts/" 2>/dev/null | head -1)
        if [ -n "$CA_FILE" ]; then
            create_peer_config_yaml "$MSP_DIR" "$CA_FILE"
            mkdir -p "$MSP_DIR/admincerts"
            cp "organizations/peerOrganizations/auditor.cold.coc.com/users/Admin@auditor.cold.coc.com/msp/signcerts/cert.pem" \
               "$MSP_DIR/admincerts/" 2>/dev/null || true
        fi
    fi
done
echo "  [OK] Auditor MSPs configured"

# Court (client-only org)
for MSP_DIR in \
    "organizations/peerOrganizations/court.coc.com/msp" \
    "organizations/peerOrganizations/court.coc.com/users/Admin@court.coc.com/msp"; do

    if [ -d "$MSP_DIR" ]; then
        CA_FILE=$(ls "$MSP_DIR/cacerts/" 2>/dev/null | head -1)
        if [ -n "$CA_FILE" ]; then
            create_peer_config_yaml "$MSP_DIR" "$CA_FILE"
            mkdir -p "$MSP_DIR/admincerts"
            cp "organizations/peerOrganizations/court.coc.com/users/Admin@court.coc.com/msp/signcerts/cert.pem" \
               "$MSP_DIR/admincerts/" 2>/dev/null || true
        fi
    fi
done
echo "  [OK] Court MSPs configured"
echo ""

echo -e "${YELLOW}[4/5] Restarting all containers...${NC}"
docker restart orderer.hot.coc.com orderer.cold.coc.com \
    peer0.lawenforcement.hot.coc.com peer0.forensiclab.hot.coc.com \
    peer0.auditor.cold.coc.com cli cli-cold 2>/dev/null || true

echo "Waiting 20 seconds for all containers to restart..."
sleep 20
echo ""

echo -e "${YELLOW}[5/5] Verifying containers...${NC}"

ALL_OK=true

if docker ps | grep -q "orderer.hot.coc.com"; then
    echo -e "  ${GREEN}[OK]${NC} Hot orderer is running"
else
    echo -e "  ${RED}[FAIL]${NC} Hot orderer not running"
    ALL_OK=false
fi

if docker ps | grep -q "orderer.cold.coc.com"; then
    echo -e "  ${GREEN}[OK]${NC} Cold orderer is running"
else
    echo -e "  ${RED}[FAIL]${NC} Cold orderer not running"
    ALL_OK=false
fi

if docker ps | grep -q "peer0.lawenforcement.hot.coc.com"; then
    echo -e "  ${GREEN}[OK]${NC} Law Enforcement peer is running"
else
    echo -e "  ${RED}[FAIL]${NC} Law Enforcement peer not running"
    ALL_OK=false
fi

if docker ps | grep -q "peer0.forensiclab.hot.coc.com"; then
    echo -e "  ${GREEN}[OK]${NC} Forensic Lab peer is running"
else
    echo -e "  ${RED}[FAIL]${NC} Forensic Lab peer not running"
    ALL_OK=false
fi

if docker ps | grep -q "peer0.auditor.cold.coc.com"; then
    echo -e "  ${GREEN}[OK]${NC} Auditor peer is running"
else
    echo -e "  ${RED}[FAIL]${NC} Auditor peer not running"
    ALL_OK=false
fi

if docker ps | grep -q "cli"; then
    echo -e "  ${GREEN}[OK]${NC} CLI container is running"
else
    echo -e "  ${RED}[FAIL]${NC} CLI container not running"
    ALL_OK=false
fi

echo ""

if [ "$ALL_OK" = true ]; then
    echo -e "${GREEN}=========================================${NC}"
    echo -e "${GREEN}  All MSP Configurations Fixed!${NC}"
    echo -e "${GREEN}=========================================${NC}"
    echo ""
    echo -e "${YELLOW}Next step: Create channels${NC}"
    echo -e "  ./scripts/create-channels-with-dynamic-mtls.sh"
else
    echo -e "${RED}=========================================${NC}"
    echo -e "${RED}  Some containers still not running${NC}"
    echo -e "${RED}=========================================${NC}"
    echo ""
    echo "Check logs with:"
    echo "  docker logs orderer.hot.coc.com"
    echo "  docker logs peer0.lawenforcement.hot.coc.com"
fi
echo ""
