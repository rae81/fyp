# Complete Setup Guide for Kali Linux

## DFIR Dual Blockchain System - Installation & Testing Guide

This guide will walk you through cloning, deploying, and testing the complete dual blockchain system on Kali Linux.

---

## 📋 Table of Contents

1. [Prerequisites](#prerequisites)
2. [Clone the Repository](#clone-the-repository)
3. [Install Dependencies](#install-dependencies)
4. [Deploy the System](#deploy-the-system)
5. [Verify All Components](#verify-all-components)
6. [Test All Functionalities](#test-all-functionalities)
7. [Access Points](#access-points)
8. [Troubleshooting](#troubleshooting)

---

## 🔧 Prerequisites

### System Requirements
- **OS**: Kali Linux (2020.1+) or any Debian-based distribution
- **RAM**: 8GB minimum (16GB recommended)
- **Disk**: 20GB free space
- **CPU**: 4 cores minimum
- **Network**: Internet connection for downloads

---

## 📥 Clone the Repository

### Step 1: Create a Project Directory

```bash
# Create a new directory for the project
mkdir -p ~/blockchain-projects
cd ~/blockchain-projects
```

### Step 2: Clone Your Repository

```bash
# Clone the repository with your specific branch
git clone https://github.com/omar-kaaki/Dual-hyperledger-Blockchain.git
cd Dual-hyperledger-Blockchain

# Checkout the deployed branch
git checkout claude/dual-blockchain-01LQXXJ5gH5AVRmuZ2ppzG5M
```

### Step 3: Verify Clone

```bash
# Check that all files are present
ls -la

# You should see:
# - docker-compose-full.yml
# - bootstrap-complete-system.sh
# - deploy-chaincode.sh
# - hot-blockchain/
# - cold-blockchain/
# - webapp/
# - enclave-simulator/
# etc.
```

---

## 📦 Install Dependencies

### Step 1: Update System

```bash
sudo apt-get update
sudo apt-get upgrade -y
```

### Step 2: Install Docker & Docker Compose

```bash
# Install Docker
sudo apt-get install -y docker.io docker-compose

# Verify installation
docker --version
docker-compose --version

# Add user to docker group (optional - allows running docker without sudo)
sudo usermod -aG docker $USER
newgrp docker

# Test docker (should work without sudo)
docker ps
```

### Step 3: Install Python 3 & Dependencies

```bash
# Python 3 is usually pre-installed on Kali, but verify
python3 --version

# Install pip
sudo apt-get install -y python3-pip

# Install required Python packages
pip3 install flask mysql-connector-python requests cryptography
```

### Step 4: Install Additional Tools

```bash
# Install jq (JSON processor)
sudo apt-get install -y jq

# Install OpenSSL (usually pre-installed)
sudo apt-get install -y openssl

# Verify installations
jq --version
openssl version
```

### Step 5: Verify Prerequisites

```bash
# Run a quick check
echo "Docker: $(docker --version)"
echo "Docker Compose: $(docker-compose --version)"
echo "Python: $(python3 --version)"
echo "jq: $(jq --version)"
echo "OpenSSL: $(openssl version)"
echo "Available Disk Space: $(df -h . | tail -1 | awk '{print $4}')"
```

---

## 🚀 Deploy the System

You have **three deployment options**:

### Option 1: Automated Complete Deployment (Recommended)

This runs a comprehensive deployment and testing script:

```bash
cd ~/blockchain-projects/Dual-hyperledger-Blockchain

# Make script executable
chmod +x deploy-and-test-complete-system.sh

# Run deployment and testing
./deploy-and-test-complete-system.sh
```

This script will:
- ✅ Check all prerequisites
- ✅ Clean previous deployments (optional)
- ✅ Deploy SGX Enclave Simulator
- ✅ Bootstrap Fabric CA servers
- ✅ Start all blockchain components
- ✅ Deploy chaincode to both chains
- ✅ Run comprehensive tests
- ✅ Provide a detailed report

**Duration**: 10-15 minutes

---

### Option 2: Bootstrap System Only

If you want manual control over testing:

```bash
cd ~/blockchain-projects/Dual-hyperledger-Blockchain

# Make scripts executable
chmod +x bootstrap-complete-system.sh
chmod +x deploy-chaincode.sh

# Run bootstrap (starts everything)
./bootstrap-complete-system.sh

# Wait for system to stabilize (30 seconds)
sleep 30

# Deploy chaincode
./deploy-chaincode.sh
```

**Duration**: 8-10 minutes

---

### Option 3: Simple Quick Start (Legacy Method)

For the simpler version without SGX enclave:

```bash
cd ~/blockchain-projects/Dual-hyperledger-Blockchain

# Clean any previous deployment
docker-compose -f docker-compose-full.yml down -v

# Start all services
docker-compose -f docker-compose-full.yml up -d

# Wait for services to initialize
sleep 30

# Check all containers are running
docker ps

# Deploy chaincode
chmod +x deploy-chaincode.sh
./deploy-chaincode.sh
```

---

## ✅ Verify All Components

After deployment, verify each component is working:

### 1. Check Running Containers

```bash
# List all running containers
docker ps

# You should see at least these containers:
# - sgx-enclave (or enclave)
# - orderer.hot.coc.com
# - orderer.cold.coc.com
# - peer0.lawenforcement.hot.coc.com
# - peer0.forensiclab.hot.coc.com
# - peer0.auditor.cold.coc.com
# - ipfs-hot
# - ipfs-cold
# - couchdb0, couchdb1, couchdb2
# - ca-lawenforcement, ca-forensiclab, ca-auditor, ca-court
# - ca-orderer-hot, ca-orderer-cold
```

### 2. Test SGX Enclave Simulator

```bash
# Check enclave health
curl http://localhost:5001/health

# Get enclave information
curl http://localhost:5001/enclave/info | jq

# Expected output:
# {
#   "mr_enclave": "...",
#   "mr_signer": "...",
#   "security_version": 1
# }
```

### 3. Test Fabric CA Servers

```bash
# Test each CA server
curl -sk https://localhost:7054/cainfo | jq .result.CAName  # LawEnforcement
curl -sk https://localhost:8054/cainfo | jq .result.CAName  # ForensicLab
curl -sk https://localhost:9054/cainfo | jq .result.CAName  # Auditor
curl -sk https://localhost:10054/cainfo | jq .result.CAName # Court
curl -sk https://localhost:11054/cainfo | jq .result.CAName # Orderer-Hot
curl -sk https://localhost:12054/cainfo | jq .result.CAName # Orderer-Cold
```

### 4. Test Blockchain Orderers

```bash
# Check hot orderer logs
docker logs orderer.hot.coc.com 2>&1 | tail -20

# Check cold orderer logs
docker logs orderer.cold.coc.com 2>&1 | tail -20

# Should see: "Beginning to serve requests"
```

### 5. Test Peers

```bash
# Check hot blockchain peer
docker logs peer0.lawenforcement.hot.coc.com 2>&1 | tail -20

# Check cold blockchain peer
docker logs peer0.auditor.cold.coc.com 2>&1 | tail -20

# Should see: "Starting peer"
```

### 6. Test IPFS Nodes

```bash
# Test IPFS Hot node
curl http://localhost:5003/api/v0/version | jq

# Test IPFS Cold node
curl http://localhost:5002/api/v0/version | jq

# Expected output:
# {
#   "Version": "0.x.x",
#   "Commit": "...",
#   "System": "amd64/linux"
# }
```

### 7. Test CouchDB State Databases

```bash
# Test each CouchDB instance
curl http://admin:adminpw@localhost:5984/ | jq .couchdb  # CouchDB 0
curl http://admin:adminpw@localhost:6984/ | jq .couchdb  # CouchDB 1
curl http://admin:adminpw@localhost:7984/ | jq .couchdb  # CouchDB 2

# Expected output: "Welcome"
```

### 8. Verify Channels

```bash
# Check hot channel
docker exec cli peer channel list

# Should show: "hotchannel"

# Check cold channel
docker exec cli-cold peer channel list

# Should show: "coldchannel"
```

### 9. Verify Chaincode Installation

```bash
# Check hot blockchain chaincode
docker exec cli peer lifecycle chaincode queryinstalled

# Check cold blockchain chaincode
docker exec cli-cold peer lifecycle chaincode queryinstalled

# Should show: "Package ID: dfir_..."
```

### 10. Verify Chaincode Initialization

```bash
# Query PRV config from hot chain
docker exec cli peer chaincode query \
  -C hotchannel \
  -n dfir \
  -c '{"function":"GetPRVConfig","Args":[]}' | jq

# Query PRV config from cold chain
docker exec cli-cold peer chaincode query \
  -C coldchannel \
  -n dfir \
  -c '{"function":"GetPRVConfig","Args":[]}' | jq

# Expected output:
# {
#   "public_key": "...",
#   "mr_enclave": "...",
#   "mr_signer": "..."
# }
```

---

## 🧪 Test All Functionalities

### Test 1: Create Investigation on Hot Blockchain

```bash
# Create a test investigation
docker exec cli peer chaincode invoke \
  -o orderer.hot.coc.com:7050 \
  --ordererTLSHostnameOverride orderer.hot.coc.com \
  --tls --cafile /opt/gopath/src/github.com/hyperledger/fabric/peer/crypto/ordererOrganizations/hot.coc.com/orderers/orderer.hot.coc.com/msp/tlscacerts/tlsca.hot.coc.com-cert.pem \
  -C hotchannel \
  -n dfir \
  --peerAddresses peer0.lawenforcement.hot.coc.com:7051 \
  --tlsRootCertFiles /opt/gopath/src/github.com/hyperledger/fabric/peer/crypto/peerOrganizations/lawenforcement.hot.coc.com/peers/peer0.lawenforcement.hot.coc.com/tls/ca.crt \
  -c '{"function":"CreateInvestigation","Args":["INV-001","CASE-001","Cybercrime Investigation","Investigation of data breach incident"]}'

# Expected output: "status:200"
```

### Test 2: Upload Evidence to IPFS

```bash
# Create a test evidence file
cat > /tmp/test-evidence.txt << EOF
DIGITAL EVIDENCE FILE
=====================
Case ID: CASE-001
Evidence ID: EVD-001
Timestamp: $(date)
Description: Test evidence file for blockchain verification
Hash: $(echo "test data" | sha256sum | awk '{print $1}')
EOF

# Upload to IPFS Hot node
IPFS_RESULT=$(curl -s -X POST -F file=@/tmp/test-evidence.txt "http://localhost:5003/api/v0/add")
IPFS_HASH=$(echo $IPFS_RESULT | jq -r '.Hash')

echo "Evidence uploaded to IPFS: $IPFS_HASH"

# Verify retrieval
curl "http://localhost:8080/ipfs/$IPFS_HASH"

# Should display the file content
```

### Test 3: Create Evidence on Blockchain with IPFS Reference

```bash
# Calculate file hash
EVIDENCE_HASH=$(sha256sum /tmp/test-evidence.txt | awk '{print $1}')

# Create evidence on blockchain
docker exec cli peer chaincode invoke \
  -o orderer.hot.coc.com:7050 \
  --ordererTLSHostnameOverride orderer.hot.coc.com \
  --tls --cafile /opt/gopath/src/github.com/hyperledger/fabric/peer/crypto/ordererOrganizations/hot.coc.com/orderers/orderer.hot.coc.com/msp/tlscacerts/tlsca.hot.coc.com-cert.pem \
  -C hotchannel \
  -n dfir \
  --peerAddresses peer0.lawenforcement.hot.coc.com:7051 \
  --tlsRootCertFiles /opt/gopath/src/github.com/hyperledger/fabric/peer/crypto/peerOrganizations/lawenforcement.hot.coc.com/peers/peer0.lawenforcement.hot.coc.com/tls/ca.crt \
  -c "{\"function\":\"CreateEvidence\",\"Args\":[\"EVD-001\",\"CASE-001\",\"digital\",\"Test laptop hard drive\",\"$EVIDENCE_HASH\",\"$IPFS_HASH\",\"IPFS-Hot\",\"Evidence Lab A\",\"{}\"]}"

# Expected output: "status:200"
```

### Test 4: Read Evidence from Blockchain

```bash
# Query evidence
docker exec cli peer chaincode query \
  -C hotchannel \
  -n dfir \
  -c '{"function":"ReadEvidence","Args":["EVD-001"]}' | jq

# Expected output: JSON object with evidence details
```

### Test 5: Transfer Custody

```bash
# Transfer custody of evidence
docker exec cli peer chaincode invoke \
  -o orderer.hot.coc.com:7050 \
  --ordererTLSHostnameOverride orderer.hot.coc.com \
  --tls --cafile /opt/gopath/src/github.com/hyperledger/fabric/peer/crypto/ordererOrganizations/hot.coc.com/orderers/orderer.hot.coc.com/msp/tlscacerts/tlsca.hot.coc.com-cert.pem \
  -C hotchannel \
  -n dfir \
  --peerAddresses peer0.lawenforcement.hot.coc.com:7051 \
  --tlsRootCertFiles /opt/gopath/src/github.com/hyperledger/fabric/peer/crypto/peerOrganizations/lawenforcement.hot.coc.com/peers/peer0.lawenforcement.hot.coc.com/tls/ca.crt \
  -c '{"function":"TransferCustody","Args":["EVD-001","ForensicLabInvestigator","Transfer for analysis","Forensic Lab B","{\"reason\":\"Detailed analysis required\"}"]}'

# Expected output: "status:200"
```

### Test 6: Get Custody History

```bash
# Query custody history
docker exec cli peer chaincode query \
  -C hotchannel \
  -n dfir \
  -c '{"function":"GetCustodyHistory","Args":["EVD-001"]}' | jq

# Expected output: Array of custody transfer records
```

### Test 7: Archive Investigation to Cold Blockchain

```bash
# Archive investigation from hot to cold chain
docker exec cli-cold peer chaincode invoke \
  -o orderer.cold.coc.com:8050 \
  --ordererTLSHostnameOverride orderer.cold.coc.com \
  --tls --cafile /opt/gopath/src/github.com/hyperledger/fabric/peer/crypto/ordererOrganizations/cold.coc.com/orderers/orderer.cold.coc.com/msp/tlscacerts/tlsca.cold.coc.com-cert.pem \
  -C coldchannel \
  -n dfir \
  --peerAddresses peer0.auditor.cold.coc.com:9051 \
  --tlsRootCertFiles /opt/gopath/src/github.com/hyperledger/fabric/peer/crypto/peerOrganizations/auditor.cold.coc.com/peers/peer0.auditor.cold.coc.com/tls/ca.crt \
  -c '{"function":"ArchiveInvestigation","Args":["INV-001","hot-tx-id-123","Archive for long-term storage"]}'

# Expected output: "status:200"
```

### Test 8: Verify Blockchain Heights

```bash
# Check hot blockchain height
docker exec cli peer channel getinfo -c hotchannel

# Check cold blockchain height
docker exec cli-cold peer channel getinfo -c coldchannel

# Both should show block heights > 0
```

### Test 9: Test RBAC Policies

```bash
# Test investigator permissions (should succeed)
docker exec cli peer chaincode query \
  -C hotchannel \
  -n dfir \
  -c '{"function":"ReadInvestigation","Args":["INV-001"]}' | jq

# Test read-only access from auditor peer
docker exec -e CORE_PEER_ADDRESS=peer0.forensiclab.hot.coc.com:8051 cli \
  peer chaincode query \
  -C hotchannel \
  -n dfir \
  -c '{"function":"ReadInvestigation","Args":["INV-001"]}' | jq
```

### Test 10: Test Attestation Verification

```bash
# Generate attestation quote
curl -X POST http://localhost:5001/attestation/generate-quote | jq

# Verify the quote
QUOTE=$(curl -s -X POST http://localhost:5001/attestation/generate-quote)
echo $QUOTE | curl -X POST http://localhost:5001/attestation/verify \
  -H "Content-Type: application/json" \
  -d @- | jq

# Expected: {"valid": true}
```

---

## 🌐 Access Points

Once the system is deployed, you can access these services:

### Core Services

| Service | URL | Credentials |
|---------|-----|-------------|
| **SGX Enclave Simulator** | http://localhost:5001 | N/A |
| **IPFS Hot (API)** | http://localhost:5003 | N/A |
| **IPFS Hot (Gateway)** | http://localhost:8080 | N/A |
| **IPFS Cold (API)** | http://localhost:5002 | N/A |
| **IPFS Cold (Gateway)** | http://localhost:8081 | N/A |

### Fabric CA Servers

| Service | URL | Admin Credentials |
|---------|-----|-------------------|
| **LawEnforcement CA** | https://localhost:7054 | admin:adminpw |
| **ForensicLab CA** | https://localhost:8054 | admin:adminpw |
| **Auditor CA** | https://localhost:9054 | admin:adminpw |
| **Court CA** | https://localhost:10054 | admin:adminpw |
| **Orderer-Hot CA** | https://localhost:11054 | admin:adminpw |
| **Orderer-Cold CA** | https://localhost:12054 | admin:adminpw |

### State Databases

| Service | URL | Credentials |
|---------|-----|-------------|
| **CouchDB 0** | http://localhost:5984/_utils | admin:adminpw |
| **CouchDB 1** | http://localhost:6984/_utils | admin:adminpw |
| **CouchDB 2** | http://localhost:7984/_utils | admin:adminpw |

### Blockchain Orderers

- **Hot Orderer**: localhost:7050 (Admin API: 7053)
- **Cold Orderer**: localhost:8050 (Admin API: 8053)

### Blockchain Peers

- **LawEnforcement Peer**: localhost:7051
- **ForensicLab Peer**: localhost:8051
- **Auditor Peer**: localhost:9051

---

## 🛠️ Troubleshooting

### Issue 1: Containers Won't Start

**Symptoms**: `docker ps` shows no containers or some missing

**Solution**:
```bash
# Check Docker is running
sudo systemctl status docker

# Restart Docker
sudo systemctl restart docker

# Re-run deployment
./bootstrap-complete-system.sh
```

### Issue 2: Port Already in Use

**Symptoms**: Error like "port 5001 is already allocated"

**Solution**:
```bash
# Find process using port
lsof -i :5001

# Kill the process
sudo kill -9 <PID>

# Or stop all containers and restart
docker-compose -f docker-compose-full.yml down
./bootstrap-complete-system.sh
```

### Issue 3: Insufficient Permissions

**Symptoms**: "permission denied" errors

**Solution**:
```bash
# Add user to docker group
sudo usermod -aG docker $USER
newgrp docker

# Test docker without sudo
docker ps
```

### Issue 4: Chaincode Not Installing

**Symptoms**: "chaincode install failed"

**Solution**:
```bash
# Check peer logs
docker logs peer0.lawenforcement.hot.coc.com 2>&1 | tail -50

# Redeploy chaincode
./deploy-chaincode.sh
```

### Issue 5: IPFS Upload Fails

**Symptoms**: "connection refused" when uploading to IPFS

**Solution**:
```bash
# Check IPFS container
docker logs ipfs-hot

# Restart IPFS
docker restart ipfs-hot
docker restart ipfs-cold

# Wait 10 seconds
sleep 10

# Try upload again
```

### Issue 6: Certificate Errors

**Symptoms**: "TLS handshake failed" or "certificate verify failed"

**Solution**:
```bash
# Re-generate certificates
./bootstrap-complete-system.sh

# Verify certificate chain
openssl verify -CAfile fabric-ca/root-ca.pem fabric-ca/lawenforcement/ca-cert.pem
```

### View Logs for Debugging

```bash
# View all container logs
docker ps --format "{{.Names}}" | xargs -I {} sh -c 'echo "=== {} ===" && docker logs {} 2>&1 | tail -20'

# View specific container logs
docker logs -f <container-name>

# Examples:
docker logs -f sgx-enclave
docker logs -f orderer.hot.coc.com
docker logs -f peer0.lawenforcement.hot.coc.com
docker logs -f ipfs-hot
```

### Complete System Reset

If everything is broken, perform a nuclear reset:

```bash
# Stop all containers
docker-compose -f docker-compose-full.yml down -v

# Remove all Docker data
docker system prune -af --volumes

# Remove generated files
rm -rf organizations/
rm -rf hot-blockchain/crypto-config/
rm -rf cold-blockchain/crypto-config/
rm -rf enclave-data/
rm -rf ipfs-certs/
rm -rf fabric-ca/*/

# Start fresh
./bootstrap-complete-system.sh
```

---

## 📊 Verify System Health

Run this comprehensive health check:

```bash
# Quick health check script
cat > /tmp/health-check.sh << 'EOF'
#!/bin/bash
echo "=== DFIR Blockchain Health Check ==="
echo ""

echo "1. Docker Status:"
docker ps --format "table {{.Names}}\t{{.Status}}" | grep -E "(enclave|ca-|peer|orderer|ipfs|couchdb)"
echo ""

echo "2. Enclave Status:"
curl -s http://localhost:5001/health || echo "FAILED"
echo ""

echo "3. IPFS Status:"
curl -s http://localhost:5003/api/v0/version | jq -r '.Version' || echo "Hot: FAILED"
curl -s http://localhost:5002/api/v0/version | jq -r '.Version' || echo "Cold: FAILED"
echo ""

echo "4. Blockchain Heights:"
echo "Hot:  $(docker exec cli peer channel getinfo -c hotchannel 2>&1 | grep -oP 'height:\s*\K\d+')"
echo "Cold: $(docker exec cli-cold peer channel getinfo -c coldchannel 2>&1 | grep -oP 'height:\s*\K\d+')"
echo ""

echo "5. Chaincode Status:"
docker exec cli peer lifecycle chaincode querycommitted -C hotchannel 2>&1 | grep "Name: dfir" || echo "Hot: Not committed"
docker exec cli-cold peer lifecycle chaincode querycommitted -C coldchannel 2>&1 | grep "Name: dfir" || echo "Cold: Not committed"
echo ""

echo "=== Health Check Complete ==="
EOF

chmod +x /tmp/health-check.sh
/tmp/health-check.sh
```

---

## 🎉 Success Indicators

Your system is fully operational when you see:

✅ **All 15+ containers running** (`docker ps` shows at least 15 containers)
✅ **Enclave health endpoint** returns `{"status":"healthy"}`
✅ **Both IPFS nodes** respond to version requests
✅ **Both blockchains** have block height > 0
✅ **Chaincode committed** on both hot and cold chains
✅ **Evidence upload** to IPFS succeeds
✅ **Evidence creation** on blockchain succeeds
✅ **Custody transfers** succeed
✅ **Cross-chain archival** works
✅ **RBAC policies** enforce correctly

---

## 📚 Additional Resources

- **Architecture Documentation**: `docs/ARCHITECTURE.md`
- **Deployment Guide**: `docs/DEPLOYMENT.md`
- **Test Results**: `TEST_RESULTS.md`
- **Chaincode Documentation**: `CHAINCODE_DOCUMENTATION.md`
- **Verification Report**: `VERIFICATION_REPORT.md`

---

## 🚨 Important Notes

1. **This is a development/demo system** - Do not use in production without additional hardening
2. **Ports 5001-12054** must be available - Check for conflicts before deployment
3. **Docker must run with sufficient resources** - Allocate at least 8GB RAM to Docker
4. **First deployment takes 10-15 minutes** - Be patient during initialization
5. **Check logs if anything fails** - Most issues are revealed in container logs

---

## 🎯 Quick Reference Commands

```bash
# Start everything
./bootstrap-complete-system.sh

# Stop everything
docker-compose -f docker-compose-full.yml down

# View all containers
docker ps

# Check blockchain status
./verify-blockchain.sh

# Check orderers
./verify-orderers.sh

# Restart specific service
docker restart <container-name>

# View logs
docker logs -f <container-name>

# Clean everything
docker-compose -f docker-compose-full.yml down -v
docker system prune -af --volumes
```

---

**Setup Complete!** 🎊

You now have a fully functional dual blockchain system with:
- Hot blockchain for active investigations
- Cold blockchain for immutable archival
- SGX enclave simulator for attestation
- IPFS for distributed evidence storage
- Dynamic mTLS certificate issuance
- Comprehensive RBAC policies

Enjoy testing! 🚀
