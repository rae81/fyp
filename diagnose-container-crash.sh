#!/bin/bash
#
# Comprehensive Diagnosis of Container Crash Issue
#

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m'

echo ""
echo -e "${MAGENTA}╔════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${MAGENTA}║       Comprehensive Container Crash Diagnosis                 ║${NC}"
echo -e "${MAGENTA}╚════════════════════════════════════════════════════════════════╝${NC}"
echo ""

# ============================================================================
# CHECK 1: Container Status and Exit Codes
# ============================================================================

echo -e "${CYAN}[1/5] Checking container status...${NC}"
echo ""

echo -e "${YELLOW}Hot Blockchain Containers:${NC}"
docker ps -a --filter "name=hot" --format "table {{.Names}}\t{{.Status}}" 2>/dev/null || echo "No containers found"

echo ""
echo -e "${YELLOW}For comparison - Cold Blockchain (working):${NC}"
docker ps -a --filter "name=cold" --format "table {{.Names}}\t{{.Status}}" 2>/dev/null || echo "No containers found"

# ============================================================================
# CHECK 2: Container Logs - Look for Error Messages
# ============================================================================

echo ""
echo -e "${CYAN}[2/5] Analyzing container logs for errors...${NC}"
echo ""

check_logs() {
    local container=$1
    local description=$2

    echo -e "${YELLOW}${description}:${NC}"

    # Check if container exists
    if docker ps -a --format '{{.Names}}' | grep -q "^${container}$"; then
        # Get last 30 lines and look for errors
        LOGS=$(docker logs "$container" 2>&1 | tail -30)

        # Look for specific error patterns
        if echo "$LOGS" | grep -qi "error\|fatal\|panic\|failed"; then
            echo -e "  ${RED}✗ Found errors in logs:${NC}"
            echo "$LOGS" | grep -i "error\|fatal\|panic\|failed" | head -10 | sed 's/^/    /'
        else
            echo -e "  ${GREEN}✓ No obvious errors found${NC}"
            echo "$LOGS" | tail -5 | sed 's/^/    /'
        fi
    else
        echo -e "  ${RED}✗ Container does not exist${NC}"
    fi
    echo ""
}

check_logs "orderer.hot.coc.com" "Hot Orderer"
check_logs "peer0.lawenforcement.hot.coc.com" "LawEnforcement Peer"
check_logs "peer0.forensiclab.hot.coc.com" "ForensicLab Peer"

# Compare with working cold orderer
echo -e "${CYAN}For comparison - Cold Orderer (working):${NC}"
check_logs "orderer.cold.coc.com" "Cold Orderer"

# ============================================================================
# CHECK 3: Verify Required Files Exist
# ============================================================================

echo ""
echo -e "${CYAN}[3/5] Verifying required certificate files exist...${NC}"
echo ""

check_files() {
    local base_path=$1
    local description=$2

    echo -e "${YELLOW}${description}:${NC}"

    # Check MSP directory
    if [ -d "$base_path/msp" ]; then
        echo -e "  ${GREEN}✓${NC} MSP directory exists"

        # Check for required MSP subdirectories
        for dir in cacerts admincerts signcerts keystore; do
            if [ -d "$base_path/msp/$dir" ]; then
                FILE_COUNT=$(ls -1 "$base_path/msp/$dir" 2>/dev/null | wc -l)
                echo -e "    ${GREEN}✓${NC} msp/$dir exists ($FILE_COUNT files)"
            else
                echo -e "    ${RED}✗${NC} msp/$dir MISSING"
            fi
        done
    else
        echo -e "  ${RED}✗${NC} MSP directory MISSING: $base_path/msp"
    fi

    # Check TLS directory
    if [ -d "$base_path/tls" ]; then
        echo -e "  ${GREEN}✓${NC} TLS directory exists"

        # Check for required TLS files
        for file in ca.crt server.crt server.key; do
            if [ -f "$base_path/tls/$file" ]; then
                SIZE=$(stat -f%z "$base_path/tls/$file" 2>/dev/null || stat -c%s "$base_path/tls/$file" 2>/dev/null)
                echo -e "    ${GREEN}✓${NC} tls/$file exists (${SIZE} bytes)"
            else
                echo -e "    ${RED}✗${NC} tls/$file MISSING"
            fi
        done
    else
        echo -e "  ${RED}✗${NC} TLS directory MISSING: $base_path/tls"
    fi
    echo ""
}

# Check hot blockchain files
check_files "organizations/ordererOrganizations/hot.coc.com/orderers/orderer.hot.coc.com" "Hot Orderer Files"
check_files "organizations/peerOrganizations/lawenforcement.hot.coc.com/peers/peer0.lawenforcement.hot.coc.com" "LawEnforcement Peer Files"
check_files "organizations/peerOrganizations/forensiclab.hot.coc.com/peers/peer0.forensiclab.hot.coc.com" "ForensicLab Peer Files"

# Compare with cold blockchain (working)
echo -e "${CYAN}For comparison - Cold Blockchain (working):${NC}"
check_files "organizations/ordererOrganizations/cold.coc.com/orderers/orderer.cold.coc.com" "Cold Orderer Files"

# ============================================================================
# CHECK 4: Check Docker Volume Mounts
# ============================================================================

echo ""
echo -e "${CYAN}[4/5] Verifying Docker volume mounts...${NC}"
echo ""

check_mounts() {
    local container=$1
    local description=$2

    echo -e "${YELLOW}${description}:${NC}"

    if docker ps -a --format '{{.Names}}' | grep -q "^${container}$"; then
        docker inspect "$container" --format='{{range .Mounts}}{{.Source}} -> {{.Destination}}{{println}}{{end}}' | grep -E "organizations|production" | sed 's/^/  /'
    else
        echo -e "  ${RED}Container not found${NC}"
    fi
    echo ""
}

check_mounts "orderer.hot.coc.com" "Hot Orderer Mounts"
check_mounts "peer0.lawenforcement.hot.coc.com" "LawEnforcement Peer Mounts"

# ============================================================================
# CHECK 5: Try Starting a Container in Foreground to See Immediate Error
# ============================================================================

echo ""
echo -e "${CYAN}[5/5] Attempting to start orderer in foreground mode...${NC}"
echo -e "${YELLOW}This will show immediate startup errors:${NC}"
echo ""

# Stop the container first
docker stop orderer.hot.coc.com 2>/dev/null

# Try to start it and capture output
echo -e "${YELLOW}Starting orderer.hot.coc.com (will timeout after 5 seconds)...${NC}"
timeout 5 docker start -a orderer.hot.coc.com 2>&1 || true

# ============================================================================
# SUMMARY AND RECOMMENDATIONS
# ============================================================================

echo ""
echo -e "${MAGENTA}╔════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${MAGENTA}║                    Diagnosis Summary                           ║${NC}"
echo -e "${MAGENTA}╚════════════════════════════════════════════════════════════════╝${NC}"
echo ""

# Check what the actual issue is
if ! docker ps -a --format '{{.Names}}' | grep -q "orderer.hot.coc.com"; then
    echo -e "${RED}ISSUE: Hot blockchain containers don't exist${NC}"
    echo ""
    echo "Run: docker-compose -f docker-compose-full.yml up -d"
elif docker logs orderer.hot.coc.com 2>&1 | tail -20 | grep -qi "no such file"; then
    echo -e "${RED}ISSUE: Missing certificate or configuration files${NC}"
    echo ""
    echo "Possible causes:"
    echo "  1. Certificates not generated"
    echo "  2. Files in wrong location"
    echo "  3. Incorrect volume mount paths in docker-compose-full.yml"
    echo ""
    echo "Check the file existence section above to see what's missing"
elif docker logs orderer.hot.coc.com 2>&1 | tail -20 | grep -qi "permission denied"; then
    echo -e "${RED}ISSUE: Permission denied accessing files${NC}"
    echo ""
    echo "Fix with: sudo chown -R \$USER:$USER organizations/"
elif docker logs orderer.hot.coc.com 2>&1 | tail -20 | grep -qi "unexpected Previous block hash"; then
    echo -e "${RED}ISSUE: Blockchain data corruption (should be fixed by volume removal)${NC}"
    echo ""
    echo "This is strange since volumes were just removed. Try:"
    echo "  docker volume prune -f"
    echo "  docker-compose -f docker-compose-full.yml up -d --force-recreate"
else
    echo -e "${YELLOW}Run the following to see full logs:${NC}"
    echo "  docker logs orderer.hot.coc.com 2>&1 | less"
    echo "  docker logs peer0.lawenforcement.hot.coc.com 2>&1 | less"
fi

echo ""
