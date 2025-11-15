#!/bin/bash
#
# Fix Orderer MSP Configuration
# Adds admin certs and config.yaml to enable NodeOU classification
#

set -e

cd "$(dirname "$0")"

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${GREEN}=========================================${NC}"
echo -e "${GREEN}  Fixing Orderer MSP Configuration${NC}"
echo -e "${GREEN}=========================================${NC}"
echo ""

# Function to create config.yaml with NodeOU enabled
create_config_yaml() {
    local msp_dir=$1
    local org_name=$2

    cat > "$msp_dir/config.yaml" <<EOF
NodeOUs:
  Enable: true
  ClientOUIdentifier:
    Certificate: cacerts/localhost-11054-ca-orderer-hot.pem
    OrganizationalUnitIdentifier: client
  PeerOUIdentifier:
    Certificate: cacerts/localhost-11054-ca-orderer-hot.pem
    OrganizationalUnitIdentifier: peer
  AdminOUIdentifier:
    Certificate: cacerts/localhost-11054-ca-orderer-hot.pem
    OrganizationalUnitIdentifier: admin
  OrdererOUIdentifier:
    Certificate: cacerts/localhost-11054-ca-orderer-hot.pem
    OrganizationalUnitIdentifier: orderer
EOF
}

# Function to create config.yaml for cold orderer
create_config_yaml_cold() {
    local msp_dir=$1
    local org_name=$2

    cat > "$msp_dir/config.yaml" <<EOF
NodeOUs:
  Enable: true
  ClientOUIdentifier:
    Certificate: cacerts/localhost-12054-ca-orderer-cold.pem
    OrganizationalUnitIdentifier: client
  PeerOUIdentifier:
    Certificate: cacerts/localhost-12054-ca-orderer-cold.pem
    OrganizationalUnitIdentifier: peer
  AdminOUIdentifier:
    Certificate: cacerts/localhost-12054-ca-orderer-cold.pem
    OrganizationalUnitIdentifier: admin
  OrdererOUIdentifier:
    Certificate: cacerts/localhost-12054-ca-orderer-cold.pem
    OrganizationalUnitIdentifier: orderer
EOF
}

echo -e "${YELLOW}[1/4] Configuring HOT orderer MSP...${NC}"

# Hot orderer - orderer MSP
HOT_ORDERER_MSP="organizations/ordererOrganizations/hot.coc.com/orderers/orderer.hot.coc.com/msp"
if [ -d "$HOT_ORDERER_MSP" ]; then
    # Create config.yaml
    create_config_yaml "$HOT_ORDERER_MSP" "hot.coc.com"

    # Create admincerts directory and copy admin cert
    mkdir -p "$HOT_ORDERER_MSP/admincerts"
    if [ -f "organizations/ordererOrganizations/hot.coc.com/users/Admin@hot.coc.com/msp/signcerts/cert.pem" ]; then
        cp "organizations/ordererOrganizations/hot.coc.com/users/Admin@hot.coc.com/msp/signcerts/cert.pem" \
           "$HOT_ORDERER_MSP/admincerts/"
        echo "  ✓ Hot orderer MSP configured"
    else
        echo "  ✗ Admin cert not found!"
    fi
else
    echo "  ✗ Hot orderer MSP directory not found: $HOT_ORDERER_MSP"
fi

# Hot orderer - org-level MSP
HOT_ORG_MSP="organizations/ordererOrganizations/hot.coc.com/msp"
if [ -d "$HOT_ORG_MSP" ]; then
    create_config_yaml "$HOT_ORG_MSP" "hot.coc.com"

    mkdir -p "$HOT_ORG_MSP/admincerts"
    if [ -f "organizations/ordererOrganizations/hot.coc.com/users/Admin@hot.coc.com/msp/signcerts/cert.pem" ]; then
        cp "organizations/ordererOrganizations/hot.coc.com/users/Admin@hot.coc.com/msp/signcerts/cert.pem" \
           "$HOT_ORG_MSP/admincerts/"
        echo "  ✓ Hot org MSP configured"
    fi
else
    echo "  ✗ Hot org MSP directory not found: $HOT_ORG_MSP"
fi
echo ""

echo -e "${YELLOW}[2/4] Configuring COLD orderer MSP...${NC}"

# Cold orderer - orderer MSP
COLD_ORDERER_MSP="organizations/ordererOrganizations/cold.coc.com/orderers/orderer.cold.coc.com/msp"
if [ -d "$COLD_ORDERER_MSP" ]; then
    create_config_yaml_cold "$COLD_ORDERER_MSP" "cold.coc.com"

    mkdir -p "$COLD_ORDERER_MSP/admincerts"
    if [ -f "organizations/ordererOrganizations/cold.coc.com/users/Admin@cold.coc.com/msp/signcerts/cert.pem" ]; then
        cp "organizations/ordererOrganizations/cold.coc.com/users/Admin@cold.coc.com/msp/signcerts/cert.pem" \
           "$COLD_ORDERER_MSP/admincerts/"
        echo "  ✓ Cold orderer MSP configured"
    else
        echo "  ✗ Admin cert not found!"
    fi
else
    echo "  ✗ Cold orderer MSP directory not found: $COLD_ORDERER_MSP"
fi

# Cold orderer - org-level MSP
COLD_ORG_MSP="organizations/ordererOrganizations/cold.coc.com/msp"
if [ -d "$COLD_ORG_MSP" ]; then
    create_config_yaml_cold "$COLD_ORG_MSP" "cold.coc.com"

    mkdir -p "$COLD_ORG_MSP/admincerts"
    if [ -f "organizations/ordererOrganizations/cold.coc.com/users/Admin@cold.coc.com/msp/signcerts/cert.pem" ]; then
        cp "organizations/ordererOrganizations/cold.coc.com/users/Admin@cold.coc.com/msp/signcerts/cert.pem" \
           "$COLD_ORG_MSP/admincerts/"
        echo "  ✓ Cold org MSP configured"
    fi
else
    echo "  ✗ Cold org MSP directory not found: $COLD_ORG_MSP"
fi
echo ""

echo -e "${YELLOW}[3/4] Restarting orderers...${NC}"
docker restart orderer.hot.coc.com orderer.cold.coc.com
echo "Waiting 15 seconds for orderers to start..."
sleep 15
echo ""

echo -e "${YELLOW}[4/4] Verifying orderers...${NC}"
if docker ps | grep -q "orderer.hot.coc.com"; then
    echo -e "${GREEN}✓ Hot orderer is running${NC}"
else
    echo -e "✗ Hot orderer not running"
    echo "Logs:"
    docker logs orderer.hot.coc.com 2>&1 | tail -20
fi

if docker ps | grep -q "orderer.cold.coc.com"; then
    echo -e "${GREEN}✓ Cold orderer is running${NC}"
else
    echo -e "✗ Cold orderer not running"
    echo "Logs:"
    docker logs orderer.cold.coc.com 2>&1 | tail -20
fi
echo ""

echo -e "${GREEN}=========================================${NC}"
echo -e "${GREEN}  MSP Configuration Complete!${NC}"
echo -e "${GREEN}=========================================${NC}"
echo ""
echo -e "${YELLOW}Next step: Create channels${NC}"
echo -e "  ./scripts/create-channels-with-dynamic-mtls.sh"
echo ""
