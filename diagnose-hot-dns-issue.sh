#!/bin/bash
#
# Comprehensive Hot Blockchain DNS Diagnostic Script
# Identifies why CLI cannot resolve hot blockchain container hostnames
#

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m'

echo ""
echo -e "${MAGENTA}╔════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${MAGENTA}║          Hot Blockchain DNS Resolution Diagnostic             ║${NC}"
echo -e "${MAGENTA}╚════════════════════════════════════════════════════════════════╝${NC}"
echo ""

# ============================================================================
# CHECK 1: Verify Hot Blockchain Containers Are Running
# ============================================================================

echo -e "${CYAN}[1/7] Checking hot blockchain container status...${NC}"
echo ""

check_container() {
    local name=$1
    local description=$2

    if docker ps --format '{{.Names}}' | grep -q "^${name}$"; then
        STATUS=$(docker ps --filter "name=^${name}$" --format "{{.Status}}")
        echo -e "  ${GREEN}✓${NC} $description is running: $STATUS"
        return 0
    else
        echo -e "  ${RED}✗${NC} $description is NOT running"

        # Check if it exists but is stopped
        if docker ps -a --format '{{.Names}}' | grep -q "^${name}$"; then
            STATUS=$(docker ps -a --filter "name=^${name}$" --format "{{.Status}}")
            echo -e "     Container exists but stopped: $STATUS"
        else
            echo -e "     ${YELLOW}Container does not exist at all!${NC}"
        fi
        return 1
    fi
}

HOT_ORDERER_RUNNING=0
LAWENF_PEER_RUNNING=0
FORENSIC_PEER_RUNNING=0

if check_container "orderer.hot.coc.com" "Hot Orderer"; then
    HOT_ORDERER_RUNNING=1
fi

if check_container "peer0.lawenforcement.hot.coc.com" "LawEnforcement Peer"; then
    LAWENF_PEER_RUNNING=1
fi

if check_container "peer0.forensiclab.hot.coc.com" "ForensicLab Peer"; then
    FORENSIC_PEER_RUNNING=1
fi

# ============================================================================
# CHECK 2: Verify Network Assignment
# ============================================================================

echo ""
echo -e "${CYAN}[2/7] Checking network assignments...${NC}"
echo ""

check_network() {
    local name=$1
    local expected_ip=$2
    local description=$3

    if docker ps --format '{{.Names}}' | grep -q "^${name}$"; then
        NETWORK_INFO=$(docker inspect "$name" --format='{{range $k, $v := .NetworkSettings.Networks}}{{$k}}: {{$v.IPAddress}}{{end}}')

        if echo "$NETWORK_INFO" | grep -q "fyp_dfir-network"; then
            IP=$(docker inspect "$name" --format='{{range $k, $v := .NetworkSettings.Networks}}{{if eq $k "fyp_dfir-network"}}{{$v.IPAddress}}{{end}}{{end}}')
            echo -e "  ${GREEN}✓${NC} $description on fyp_dfir-network: $IP"

            if [ ! -z "$expected_ip" ] && [ "$IP" != "$expected_ip" ]; then
                echo -e "     ${YELLOW}⚠${NC} Expected $expected_ip but got $IP"
            fi
        else
            echo -e "  ${RED}✗${NC} $description NOT on fyp_dfir-network"
            echo -e "     Networks: $NETWORK_INFO"
        fi
    fi
}

check_network "orderer.hot.coc.com" "172.20.0.50" "Hot Orderer"
check_network "peer0.lawenforcement.hot.coc.com" "172.20.0.60" "LawEnforcement Peer"
check_network "peer0.forensiclab.hot.coc.com" "172.20.0.61" "ForensicLab Peer"
check_network "cli" "172.20.0.100" "CLI"

# ============================================================================
# CHECK 3: Test DNS Resolution from CLI
# ============================================================================

echo ""
echo -e "${CYAN}[3/7] Testing DNS resolution from CLI container...${NC}"
echo ""

test_dns() {
    local hostname=$1
    local description=$2

    if docker exec cli getent hosts "$hostname" > /dev/null 2>&1; then
        IP=$(docker exec cli getent hosts "$hostname" | awk '{print $1}')
        echo -e "  ${GREEN}✓${NC} $description ($hostname) resolves to $IP"
        return 0
    else
        echo -e "  ${RED}✗${NC} $description ($hostname) FAILS to resolve"
        return 1
    fi
}

test_dns "orderer.hot.coc.com" "Hot Orderer"
test_dns "peer0.lawenforcement.hot.coc.com" "LawEnforcement Peer"
test_dns "peer0.forensiclab.hot.coc.com" "ForensicLab Peer"

# Compare with cold blockchain (should work)
echo ""
echo -e "${YELLOW}For comparison - Cold blockchain:${NC}"
test_dns "orderer.cold.coc.com" "Cold Orderer"
test_dns "peer0.auditor.cold.coc.com" "Auditor Peer"

# ============================================================================
# CHECK 4: Inspect Docker Network for All Containers
# ============================================================================

echo ""
echo -e "${CYAN}[4/7] Inspecting fyp_dfir-network for all registered containers...${NC}"
echo ""

echo -e "${YELLOW}Hot Blockchain Containers:${NC}"
docker network inspect fyp_dfir-network --format='{{range .Containers}}{{.Name}}: {{.IPv4Address}}{{println}}{{end}}' | grep -E "hot|lawenforcement|forensiclab" | sort || echo "  No hot blockchain containers found in network"

echo ""
echo -e "${YELLOW}Cold Blockchain Containers (working reference):${NC}"
docker network inspect fyp_dfir-network --format='{{range .Containers}}{{.Name}}: {{.IPv4Address}}{{println}}{{end}}' | grep -E "cold|auditor" | sort

# ============================================================================
# CHECK 5: Check Container Logs for Errors
# ============================================================================

echo ""
echo -e "${CYAN}[5/7] Checking container logs for startup errors...${NC}"
echo ""

check_logs() {
    local name=$1
    local description=$2

    if docker ps --format '{{.Names}}' | grep -q "^${name}$"; then
        echo -e "${YELLOW}Last 20 lines from $description:${NC}"
        docker logs "$name" --tail 20 2>&1 | sed 's/^/  /'
        echo ""
    fi
}

if [ $HOT_ORDERER_RUNNING -eq 1 ]; then
    check_logs "orderer.hot.coc.com" "Hot Orderer"
fi

if [ $LAWENF_PEER_RUNNING -eq 1 ]; then
    check_logs "peer0.lawenforcement.hot.coc.com" "LawEnforcement Peer"
fi

if [ $FORENSIC_PEER_RUNNING -eq 1 ]; then
    check_logs "peer0.forensiclab.hot.coc.com" "ForensicLab Peer"
fi

# ============================================================================
# CHECK 6: Verify Docker Compose Configuration
# ============================================================================

echo ""
echo -e "${CYAN}[6/7] Verifying docker-compose-full.yml configuration...${NC}"
echo ""

# Check if containers have container_name defined
echo -e "${YELLOW}Checking container_name definitions:${NC}"

if grep -q "container_name: orderer.hot.coc.com" docker-compose-full.yml; then
    echo -e "  ${GREEN}✓${NC} orderer.hot.coc.com has container_name defined"
else
    echo -e "  ${RED}✗${NC} orderer.hot.coc.com container_name NOT defined"
fi

if grep -q "container_name: peer0.lawenforcement.hot.coc.com" docker-compose-full.yml; then
    echo -e "  ${GREEN}✓${NC} peer0.lawenforcement.hot.coc.com has container_name defined"
else
    echo -e "  ${RED}✗${NC} peer0.lawenforcement.hot.coc.com container_name NOT defined"
fi

if grep -q "container_name: peer0.forensiclab.hot.coc.com" docker-compose-full.yml; then
    echo -e "  ${GREEN}✓${NC} peer0.forensiclab.hot.coc.com has container_name defined"
else
    echo -e "  ${RED}✗${NC} peer0.forensiclab.hot.coc.com container_name NOT defined"
fi

# Check for hostname definitions
echo ""
echo -e "${YELLOW}Checking hostname definitions:${NC}"

HOT_ORDERER_HOSTNAME=$(grep -A5 "orderer.hot.coc.com:" docker-compose-full.yml | grep "hostname:" | awk '{print $2}' | head -1)
if [ ! -z "$HOT_ORDERER_HOSTNAME" ]; then
    echo -e "  Hot Orderer hostname: ${CYAN}$HOT_ORDERER_HOSTNAME${NC}"
else
    echo -e "  ${YELLOW}⚠${NC} Hot Orderer has no hostname defined"
fi

LAWENF_HOSTNAME=$(grep -A5 "peer0.lawenforcement.hot.coc.com:" docker-compose-full.yml | grep "hostname:" | awk '{print $2}' | head -1)
if [ ! -z "$LAWENF_HOSTNAME" ]; then
    echo -e "  LawEnforcement Peer hostname: ${CYAN}$LAWENF_HOSTNAME${NC}"
else
    echo -e "  ${YELLOW}⚠${NC} LawEnforcement Peer has no hostname defined"
fi

FORENSIC_HOSTNAME=$(grep -A5 "peer0.forensiclab.hot.coc.com:" docker-compose-full.yml | grep "hostname:" | awk '{print $2}' | head -1)
if [ ! -z "$FORENSIC_HOSTNAME" ]; then
    echo -e "  ForensicLab Peer hostname: ${CYAN}$FORENSIC_HOSTNAME${NC}"
else
    echo -e "  ${YELLOW}⚠${NC} ForensicLab Peer has no hostname defined"
fi

# ============================================================================
# CHECK 7: Test Direct IP Connectivity
# ============================================================================

echo ""
echo -e "${CYAN}[7/7] Testing direct IP connectivity from CLI...${NC}"
echo ""

test_ip() {
    local ip=$1
    local port=$2
    local description=$3

    if docker exec cli timeout 2 sh -c "cat < /dev/null > /dev/tcp/$ip/$port" 2>/dev/null; then
        echo -e "  ${GREEN}✓${NC} $description ($ip:$port) is REACHABLE"
        return 0
    else
        echo -e "  ${RED}✗${NC} $description ($ip:$port) is UNREACHABLE"
        return 1
    fi
}

# Get actual IPs from network
HOT_ORDERER_IP=$(docker inspect orderer.hot.coc.com --format='{{range $k, $v := .NetworkSettings.Networks}}{{if eq $k "fyp_dfir-network"}}{{$v.IPAddress}}{{end}}{{end}}' 2>/dev/null)
LAWENF_IP=$(docker inspect peer0.lawenforcement.hot.coc.com --format='{{range $k, $v := .NetworkSettings.Networks}}{{if eq $k "fyp_dfir-network"}}{{$v.IPAddress}}{{end}}{{end}}' 2>/dev/null)
FORENSIC_IP=$(docker inspect peer0.forensiclab.hot.coc.com --format='{{range $k, $v := .NetworkSettings.Networks}}{{if eq $k "fyp_dfir-network"}}{{$v.IPAddress}}{{end}}{{end}}' 2>/dev/null)

if [ ! -z "$HOT_ORDERER_IP" ]; then
    test_ip "$HOT_ORDERER_IP" "7053" "Hot Orderer Admin"
else
    echo -e "  ${RED}✗${NC} Cannot get Hot Orderer IP"
fi

if [ ! -z "$LAWENF_IP" ]; then
    test_ip "$LAWENF_IP" "7051" "LawEnforcement Peer"
else
    echo -e "  ${RED}✗${NC} Cannot get LawEnforcement Peer IP"
fi

if [ ! -z "$FORENSIC_IP" ]; then
    test_ip "$FORENSIC_IP" "8051" "ForensicLab Peer"
else
    echo -e "  ${RED}✗${NC} Cannot get ForensicLab Peer IP"
fi

# ============================================================================
# DIAGNOSIS AND RECOMMENDATIONS
# ============================================================================

echo ""
echo -e "${MAGENTA}╔════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${MAGENTA}║                         Diagnosis                              ║${NC}"
echo -e "${MAGENTA}╚════════════════════════════════════════════════════════════════╝${NC}"
echo ""

# Determine the issue
if [ $HOT_ORDERER_RUNNING -eq 0 ] || [ $LAWENF_PEER_RUNNING -eq 0 ] || [ $FORENSIC_PEER_RUNNING -eq 0 ]; then
    echo -e "${RED}ISSUE: Hot blockchain containers are NOT running${NC}"
    echo ""
    echo -e "${YELLOW}Recommended Actions:${NC}"
    echo "  1. Check why containers are not running:"
    echo "     ${CYAN}docker-compose -f docker-compose-full.yml ps${NC}"
    echo ""
    echo "  2. View logs to see crash reason:"
    echo "     ${CYAN}docker-compose -f docker-compose-full.yml logs orderer.hot.coc.com${NC}"
    echo "     ${CYAN}docker-compose -f docker-compose-full.yml logs peer0.lawenforcement.hot.coc.com${NC}"
    echo ""
    echo "  3. Try starting containers individually:"
    echo "     ${CYAN}docker-compose -f docker-compose-full.yml up -d orderer.hot.coc.com${NC}"
    echo "     ${CYAN}docker-compose -f docker-compose-full.yml up -d peer0.lawenforcement.hot.coc.com${NC}"
    echo "     ${CYAN}docker-compose -f docker-compose-full.yml up -d peer0.forensiclab.hot.coc.com${NC}"

elif ! docker exec cli getent hosts orderer.hot.coc.com > /dev/null 2>&1; then
    # Containers running but DNS fails

    # Check if IP connectivity works
    if [ ! -z "$HOT_ORDERER_IP" ] && docker exec cli timeout 2 sh -c "cat < /dev/null > /dev/tcp/$HOT_ORDERER_IP/7053" 2>/dev/null; then
        echo -e "${YELLOW}ISSUE: Containers are running and reachable by IP, but DNS resolution fails${NC}"
        echo ""
        echo "This indicates a Docker DNS registration issue."
        echo ""
        echo -e "${YELLOW}Recommended Actions:${NC}"
        echo "  1. Restart Docker daemon to clear DNS cache:"
        echo "     ${CYAN}sudo systemctl restart docker${NC}"
        echo "     ${CYAN}docker-compose -f docker-compose-full.yml up -d${NC}"
        echo ""
        echo "  2. OR use IP addresses directly in fix script (workaround)"
        echo ""
        echo "  3. OR recreate containers with hostname field:"
        echo "     Add 'hostname: orderer.hot.coc.com' to each service in docker-compose-full.yml"

    else
        echo -e "${YELLOW}ISSUE: Docker DNS registration problem${NC}"
        echo ""
        echo -e "${YELLOW}Recommended Actions:${NC}"
        echo "  1. Verify containers have 'hostname' field in docker-compose-full.yml"
        echo "  2. Recreate containers to refresh DNS:"
        echo "     ${CYAN}docker-compose -f docker-compose-full.yml stop orderer.hot.coc.com peer0.lawenforcement.hot.coc.com peer0.forensiclab.hot.coc.com${NC}"
        echo "     ${CYAN}docker-compose -f docker-compose-full.yml rm -f orderer.hot.coc.com peer0.lawenforcement.hot.coc.com peer0.forensiclab.hot.coc.com${NC}"
        echo "     ${CYAN}docker-compose -f docker-compose-full.yml up -d orderer.hot.coc.com peer0.lawenforcement.hot.coc.com peer0.forensiclab.hot.coc.com${NC}"
        echo "     ${CYAN}sleep 10${NC}"
        echo "     ${CYAN}docker-compose -f docker-compose-full.yml restart cli${NC}"
    fi

else
    echo -e "${GREEN}DNS resolution is working!${NC}"
    echo "You can proceed with: ${CYAN}./fix-hotchannel-endorsement.sh${NC}"
fi

echo ""
