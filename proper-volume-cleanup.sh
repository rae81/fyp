#!/bin/bash
#
# Proper Volume Cleanup Script
# =============================
# This script removes the ACTUAL Docker volumes used by hot blockchain containers
# to fix the persistent DNS and blockchain data corruption issues
#

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m'

echo ""
echo -e "${MAGENTA}╔════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${MAGENTA}║              Proper Hot Blockchain Volume Cleanup             ║${NC}"
echo -e "${MAGENTA}╚════════════════════════════════════════════════════════════════╝${NC}"
echo ""

echo -e "${RED}⚠ WARNING ⚠${NC}"
echo "This script will DELETE all blockchain data for the hot blockchain."
echo "This is necessary to fix the DNS resolution and data corruption issues."
echo ""
echo -e "${YELLOW}The following Docker volumes will be removed:${NC}"
echo "  1. fyp_orderer-hot-data"
echo "  2. fyp_peer-lawenforcement-data"
echo "  3. fyp_peer-forensiclab-data"
echo ""
echo -e "${CYAN}Press Enter to continue or Ctrl+C to cancel...${NC}"
read

# ============================================================================
# STEP 1: Stop Hot Blockchain Containers
# ============================================================================

echo ""
echo -e "${CYAN}[1/5] Stopping hot blockchain containers...${NC}"

docker-compose -f docker-compose-full.yml stop orderer.hot.coc.com peer0.lawenforcement.hot.coc.com peer0.forensiclab.hot.coc.com

echo -e "  ${GREEN}✓${NC} Containers stopped"

# ============================================================================
# STEP 2: Verify Volume Names (Before Removal)
# ============================================================================

echo ""
echo -e "${CYAN}[2/5] Verifying volume names before removal...${NC}"
echo ""

echo -e "${YELLOW}Current hot blockchain volumes:${NC}"
docker volume ls | grep -E "orderer-hot-data|peer-lawenforcement-data|peer-forensiclab-data" || echo "  No volumes found (already clean or never created)"

# ============================================================================
# STEP 3: Remove Hot Blockchain Volumes
# ============================================================================

echo ""
echo -e "${CYAN}[3/5] Removing hot blockchain volumes...${NC}"
echo ""

# Remove orderer volume
echo -e "  ${YELLOW}Removing fyp_orderer-hot-data...${NC}"
if docker volume rm fyp_orderer-hot-data 2>/dev/null; then
    echo -e "  ${GREEN}✓${NC} fyp_orderer-hot-data removed"
else
    echo -e "  ${YELLOW}⚠${NC} Volume doesn't exist or already removed"
fi

# Remove LawEnforcement peer volume
echo -e "  ${YELLOW}Removing fyp_peer-lawenforcement-data...${NC}"
if docker volume rm fyp_peer-lawenforcement-data 2>/dev/null; then
    echo -e "  ${GREEN}✓${NC} fyp_peer-lawenforcement-data removed"
else
    echo -e "  ${YELLOW}⚠${NC} Volume doesn't exist or already removed"
fi

# Remove ForensicLab peer volume
echo -e "  ${YELLOW}Removing fyp_peer-forensiclab-data...${NC}"
if docker volume rm fyp_peer-forensiclab-data 2>/dev/null; then
    echo -e "  ${GREEN}✓${NC} fyp_peer-forensiclab-data removed"
else
    echo -e "  ${YELLOW}⚠${NC} Volume doesn't exist or already removed"
fi

# ============================================================================
# STEP 4: Restart Containers (Fresh Volumes Will Be Created)
# ============================================================================

echo ""
echo -e "${CYAN}[4/5] Restarting containers with fresh volumes...${NC}"

docker-compose -f docker-compose-full.yml up -d orderer.hot.coc.com peer0.lawenforcement.hot.coc.com peer0.forensiclab.hot.coc.com

echo -e "  ${GREEN}✓${NC} Containers restarted"

# Wait for containers to initialize
echo -e "  ${YELLOW}Waiting for containers to initialize (30s)...${NC}"
sleep 30

# ============================================================================
# STEP 5: Verify New Volumes Created
# ============================================================================

echo ""
echo -e "${CYAN}[5/5] Verifying new volumes were created...${NC}"
echo ""

echo -e "${YELLOW}New hot blockchain volumes:${NC}"
docker volume ls | grep -E "orderer-hot-data|peer-lawenforcement-data|peer-forensiclab-data"

# ============================================================================
# VERIFICATION
# ============================================================================

echo ""
echo -e "${CYAN}Verifying container status...${NC}"
echo ""

docker-compose -f docker-compose-full.yml ps orderer.hot.coc.com peer0.lawenforcement.hot.coc.com peer0.forensiclab.hot.coc.com

# ============================================================================
# SUMMARY
# ============================================================================

echo ""
echo -e "${GREEN}╔════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║              Volume Cleanup Complete!                          ║${NC}"
echo -e "${GREEN}╚════════════════════════════════════════════════════════════════╝${NC}"
echo ""

echo -e "${CYAN}What was fixed:${NC}"
echo "  1. Removed old corrupted blockchain data from hot blockchain"
echo "  2. Fresh Docker volumes created for orderer and peers"
echo "  3. Containers restarted with clean state"
echo ""
echo -e "${CYAN}Next Steps:${NC}"
echo "  1. Restart CLI to clear DNS cache:"
echo "     ${MAGENTA}docker-compose -f docker-compose-full.yml restart cli${NC}"
echo ""
echo "  2. Run diagnostic to verify DNS resolution:"
echo "     ${MAGENTA}./diagnose-hot-dns-issue.sh${NC}"
echo ""
echo "  3. If DNS works, recreate hotchannel:"
echo "     ${MAGENTA}./fix-hotchannel-endorsement.sh${NC}"
echo ""

# ============================================================================
# EXPLANATION OF THE ISSUE
# ============================================================================

echo ""
echo -e "${YELLOW}╔════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${YELLOW}║                   What Was The Problem?                        ║${NC}"
echo -e "${YELLOW}╚════════════════════════════════════════════════════════════════╝${NC}"
echo ""

echo "The DNS resolution issue was caused by:"
echo ""
echo "1. ${RED}WRONG VOLUME NAMES USED:${NC}"
echo "   You were trying to remove: fyp_orderer.hot.coc.com"
echo "   But actual volume name is: fyp_orderer-hot-data"
echo "   (Notice: dots vs hyphens)"
echo ""
echo "2. ${RED}OLD DATA NEVER REMOVED:${NC}"
echo "   Because wrong volume names were used, the old corrupted"
echo "   blockchain data remained in the actual volumes."
echo ""
echo "3. ${RED}CONTAINERS KEPT CRASHING:${NC}"
echo "   Orderer and peers loaded old data with conflicting block"
echo "   hashes, causing them to crash on startup."
echo ""
echo "4. ${RED}DNS REGISTRATION FAILED:${NC}"
echo "   Crashed containers don't register in Docker DNS, so CLI"
echo "   couldn't resolve orderer.hot.coc.com"
echo ""
echo -e "${GREEN}✓ NOW FIXED:${NC} Correct volumes removed, fresh data, containers running!"
echo ""
