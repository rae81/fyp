#!/bin/bash
#
# Check Container Logs to Identify Crash Reason
#

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

echo ""
echo -e "${CYAN}╔════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║              Hot Blockchain Container Logs                     ║${NC}"
echo -e "${CYAN}╚════════════════════════════════════════════════════════════════╝${NC}"
echo ""

# Check orderer logs
echo -e "${YELLOW}Hot Orderer Logs (last 50 lines):${NC}"
echo -e "${CYAN}════════════════════════════════════════════════════════════════${NC}"
docker logs orderer.hot.coc.com 2>&1 | tail -50
echo ""

# Check LawEnforcement peer logs
echo -e "${YELLOW}LawEnforcement Peer Logs (last 50 lines):${NC}"
echo -e "${CYAN}════════════════════════════════════════════════════════════════${NC}"
docker logs peer0.lawenforcement.hot.coc.com 2>&1 | tail -50
echo ""

# Check ForensicLab peer logs
echo -e "${YELLOW}ForensicLab Peer Logs (last 50 lines):${NC}"
echo -e "${CYAN}════════════════════════════════════════════════════════════════${NC}"
docker logs peer0.forensiclab.hot.coc.com 2>&1 | tail -50
echo ""

# Check container status
echo -e "${CYAN}╔════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║                    Container Status                            ║${NC}"
echo -e "${CYAN}╚════════════════════════════════════════════════════════════════╝${NC}"
echo ""

docker ps -a --filter "name=orderer.hot.coc.com" --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
docker ps -a --filter "name=peer0.lawenforcement.hot.coc.com" --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
docker ps -a --filter "name=peer0.forensiclab.hot.coc.com" --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
echo ""
