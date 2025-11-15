# 🔐 Complete CA-Based Deployment Guide

## Why Use CA Instead of Cryptogen?

| Feature | **CA-Based (Secure)** | Cryptogen (Quick) |
|---------|----------------------|-------------------|
| **Dynamic Certificates** | ✅ Yes | ❌ No (static) |
| **Certificate Rotation** | ✅ Automatic | ❌ Manual regeneration |
| **SGX Enclave Root CA** | ✅ Yes | ❌ No |
| **Zero Trust Security** | ✅ Full chain verification | ⚠️ Pre-generated trust |
| **DFIR Compliance** | ✅ Audit trail | ⚠️ Limited |
| **Production Ready** | ✅ Yes | ❌ Development only |

**TL;DR**: CA-based = Production-grade security, Cryptogen = Quick testing

---

## 🚀 Complete CA Deployment (Step-by-Step)

### Prerequisites

```bash
cd ~/blockchain-projects/Dual-hyperledger-Blockchain

# Pull latest changes
git pull origin claude/dual-blockchain-01LQXXJ5gH5AVRmuZ2ppzG5M

# Stop everything
docker-compose -f docker-compose-full.yml down -v
docker-compose -f docker-compose-hot.yml down -v
docker-compose -f docker-compose-cold.yml down -v

# Clean everything
sudo rm -rf organizations/
sudo rm -rf fabric-ca/
sudo rm -rf hot-blockchain/crypto-config/
sudo rm -rf cold-blockchain/crypto-config/
sudo rm -rf hot-blockchain/channel-artifacts/
sudo rm -rf cold-blockchain/channel-artifacts/
```

---

### Step 1: Test Certificate Generation

Before deploying, let's test if the enclave generates proper certificates:

```bash
# Make test script executable
chmod +x test-and-fix-ca.sh

# Run test
./test-and-fix-ca.sh
```

**This script will:**
1. Start the SGX enclave
2. Initialize the Root CA
3. Generate a test intermediate CA certificate
4. **Verify it has "Certificate Sign" key usage**
5. If valid, bootstrap all 6 Fabric CA servers
6. Verify all CA certificates

**Expected Output:**
```
✅ Certificate has 'Certificate Sign' key usage - CORRECT!
✓ All CA certificates generated correctly!
```

**If you see this error:**
```
❌ Certificate is MISSING 'Certificate Sign' key usage - BUG FOUND!
```

Then there's a bug in the enclave certificate generation. See "Troubleshooting" below.

---

### Step 2: Start CA Servers

If Step 1 passed:

```bash
# Start all CA servers
docker-compose -f docker-compose-full.yml up -d \
  ca-lawenforcement \
  ca-forensiclab \
  ca-auditor \
  ca-court \
  ca-orderer-hot \
  ca-orderer-cold

# Wait for CAs to fully start (IMPORTANT!)
echo "Waiting 60 seconds for CAs to initialize..."
sleep 60
```

---

### Step 3: Verify CA Servers Are Running

```bash
# Check CA containers
docker ps | grep ca-

# Test each CA (all should respond)
for PORT in 7054 8054 9054 10054 11054 12054; do
  echo -n "Port $PORT: "
  curl -sk https://localhost:$PORT/cainfo | jq -r '.result.CAName' || echo "FAILED"
done
```

**Expected Output:**
```
Port 7054: ca-lawenforcement
Port 8054: ca-forensiclab
Port 9054: ca-auditor
Port 10054: ca-court
Port 11054: ca-orderer-hot
Port 12054: ca-orderer-cold
```

**If any CA shows "FAILED":**
```bash
# Check logs
docker logs ca-lawenforcement 2>&1 | tail -50

# If you see "cert sign" error, the certificate bug needs to be fixed
```

---

### Step 4: Register Identities (Inside Containers)

This is the **container-based registration workaround** that bypasses authentication issues:

```bash
# Make script executable
chmod +x scripts/register-identities-in-containers.sh

# Run registration
./scripts/register-identities-in-containers.sh
```

**What this does:**
- Runs `fabric-ca-client register` **INSIDE** each CA container
- Bypasses host authentication issues
- Creates identity records in CA databases
- **Does NOT issue certificates yet**

**Expected Output:**
```
✓ Registered orderer.hot.coc.com
✓ Registered orderer.cold.coc.com
✓ Registered peer0.lawenforcement.hot.coc.com
✓ Registered peer0.forensiclab.hot.coc.com
... (many more)
```

---

### Step 5: Enroll Identities (From Host)

This is where **dynamic mTLS certificates** are issued:

```bash
# Make script executable
chmod +x scripts/enroll-all-identities.sh

# Run enrollment
./scripts/enroll-all-identities.sh
```

**What this does:**
- Requests certificates for all registered identities
- Fabric CA signs certificates using its intermediate cert
- Intermediate cert is signed by Enclave Root CA
- **Result**: Full chain `Enclave Root CA → Fabric CA → Identity`

**Expected Output:**
```
✓ Enrolled admin@lawenforcement.hot.coc.com
✓ Enrolled peer0.lawenforcement.hot.coc.com
✓ Enrolled orderer.hot.coc.com
... (many more)
```

**Certificates saved to:**
```
organizations/
├── peerOrganizations/
│   ├── lawenforcement.hot.coc.com/
│   │   ├── peers/peer0.lawenforcement.hot.coc.com/
│   │   │   ├── msp/signcerts/cert.pem  ← Signed by CA
│   │   │   └── tls/server.crt          ← TLS cert
│   │   └── users/Admin@lawenforcement.hot.coc.com/
│   │       └── msp/signcerts/cert.pem
│   └── ...
└── ordererOrganizations/
    └── hot.coc.com/
        └── orderers/orderer.hot.coc.com/
            ├── msp/signcerts/cert.pem
            └── tls/server.crt
```

---

### Step 6: Generate Channel Artifacts

```bash
# Make script executable
chmod +x scripts/regenerate-channel-artifacts.sh

# Generate genesis blocks and anchor peer configs
./scripts/regenerate-channel-artifacts.sh
```

**What this creates:**
```
hot-blockchain/channel-artifacts/
├── hotchannel.block                      ← Genesis block
├── LawEnforcementMSPanchors.tx           ← Anchor peer config
└── ForensicLabMSPanchors.tx

cold-blockchain/channel-artifacts/
├── coldchannel.block
└── AuditorMSPanchors.tx
```

---

### Step 7: Update Docker Compose Files

```bash
# Make script executable
chmod +x scripts/update-docker-compose-for-dynamic-mtls.sh

# Update paths from crypto-config/ to organizations/
./scripts/update-docker-compose-for-dynamic-mtls.sh
```

---

### Step 8: Start Blockchain Network

```bash
# Start orderers, peers, and CouchDB
docker-compose -f docker-compose-hot.yml -f docker-compose-cold.yml up -d

# Wait for network to initialize
echo "Waiting 60 seconds for network to stabilize..."
sleep 60
```

**Check containers:**
```bash
docker ps

# Should see:
# - orderer.hot.coc.com
# - orderer.cold.coc.com
# - peer0.lawenforcement.hot.coc.com
# - peer0.forensiclab.hot.coc.com
# - peer0.auditor.cold.coc.com
# - cli, cli-cold
# - couchdb0, couchdb1, couchdb2
```

---

### Step 9: Create Channels

```bash
# Make script executable
chmod +x scripts/create-channels-with-dynamic-mtls.sh

# Create and join channels
./scripts/create-channels-with-dynamic-mtls.sh
```

**What this does:**
1. Joins hot orderer to hotchannel
2. Joins Law Enforcement peer to hotchannel
3. Joins Forensic Lab peer to hotchannel
4. Updates anchor peers for hot chain
5. Joins cold orderer to coldchannel
6. Joins Auditor peer to coldchannel
7. Updates anchor peer for cold chain

**Verify:**
```bash
# Check channels
docker exec cli peer channel list
# Should show: hotchannel

docker exec cli-cold peer channel list
# Should show: coldchannel
```

---

### Step 10: Deploy Chaincode

```bash
# Make script executable
chmod +x deploy-chaincode.sh

# Deploy to both blockchains
./deploy-chaincode.sh
```

---

## ✅ Verification

### Verify Certificate Chain

```bash
# Check orderer certificate was issued by Fabric CA
openssl x509 -in organizations/ordererOrganizations/hot.coc.com/orderers/orderer.hot.coc.com/msp/signcerts/cert.pem -noout -issuer

# Should show: issuer=O=DFIR Blockchain, OU=LAWENFORCEMENTMSP, CN=ca.lawenforcement.coc.com

# Verify full chain
openssl verify -CAfile fabric-ca/orderer-hot/ca-chain.pem \
  organizations/ordererOrganizations/hot.coc.com/orderers/orderer.hot.coc.com/msp/signcerts/cert.pem

# Should show: OK
```

### Verify Blockchain

```bash
# Check blockchain heights
docker exec cli peer channel getinfo -c hotchannel
docker exec cli-cold peer channel getinfo -c coldchannel

# Both should show height > 0

# Query chaincode
docker exec cli peer chaincode query \
  -C hotchannel \
  -n dfir \
  -c '{"function":"GetPRVConfig","Args":[]}'

# Should return PRV config with enclave measurements
```

---

## 🔧 Troubleshooting

### Issue 1: Certificate Sign Key Usage Missing

**Symptoms:**
```
Error: Invalid certificate in file '/etc/hyperledger/fabric-ca-server/ca-cert.pem': The 'cert sign' key usage is required
```

**Diagnosis:**
```bash
./test-and-fix-ca.sh
```

If the test shows the certificate is missing "Certificate Sign", there's a bug in `enclave-simulator/enclave_sgx.py`.

**Check the code:**
```bash
# Line 261-270 should have key_cert_sign=True for intermediate certificates
grep -A10 "cert_type in.*intermediate" enclave-simulator/enclave_sgx.py
```

**Should see:**
```python
key_usage = x509.KeyUsage(
    digital_signature=True,
    key_cert_sign=True,      # ← This must be True!
    crl_sign=True,
    ...
)
```

**If key_cert_sign=False or missing**, edit the file and change it to `True`.

---

### Issue 2: CA Containers Keep Restarting

**Check logs:**
```bash
docker logs ca-lawenforcement 2>&1 | tail -50
```

**Common errors:**
- **"address already in use"** → Port conflict, stop other services
- **"database locked"** → Delete database: `sudo rm -rf fabric-ca/*/fabric-ca-server.db`
- **"permission denied"** → Fix permissions: `sudo chown -R $USER fabric-ca/`

---

### Issue 3: Enrollment Hangs/Timeout

**Increase timeout in enrollment script:**
```bash
# Edit scripts/enroll-all-identities.sh
# Find: max_attempts=30
# Change to: max_attempts=60
```

**Or wait longer before enrolling:**
```bash
# After starting CAs
sleep 120  # Wait 2 minutes instead of 30 seconds
./scripts/enroll-all-identities.sh
```

---

### Issue 4: Channels Won't Create

**Check orderer logs:**
```bash
docker logs orderer.hot.coc.com 2>&1 | tail -100
```

**Common issues:**
- Certificates not in correct location
- TLS handshake failures
- Genesis block not generated

**Fix:**
```bash
# Regenerate everything
./scripts/regenerate-channel-artifacts.sh
./scripts/update-docker-compose-for-dynamic-mtls.sh
docker-compose -f docker-compose-hot.yml restart orderer.hot.coc.com
sleep 30
./scripts/create-channels-with-dynamic-mtls.sh
```

---

## 🎯 Complete Reset and Retry

If everything is broken:

```bash
# Nuclear option - start completely fresh
docker-compose -f docker-compose-full.yml down -v
docker-compose -f docker-compose-hot.yml down -v
docker-compose -f docker-compose-cold.yml down -v

docker system prune -af --volumes

sudo rm -rf organizations/ fabric-ca/ hot-blockchain/crypto-config/ cold-blockchain/crypto-config/

# Start over from Step 1
./test-and-fix-ca.sh
```

---

## 📊 CA-Based vs Cryptogen Comparison

### When to Use Each

**Use CA-Based When:**
- ✅ Production deployment
- ✅ Need certificate rotation
- ✅ Require dynamic certificate issuance
- ✅ Need SGX enclave root CA
- ✅ DFIR compliance required
- ✅ Want full security features

**Use Cryptogen When:**
- ✅ Quick development testing
- ✅ Learning Hyperledger Fabric
- ✅ Demo/proof-of-concept
- ✅ CA setup is broken (temporarily)

---

## 🔐 Security Benefits of CA-Based Deployment

1. **Dynamic Certificate Issuance**
   - Certificates generated on-demand
   - No pre-shared certificates
   - Each identity gets unique cert from CA chain

2. **Certificate Rotation**
   - Can re-enroll for fresh certificates
   - Automatic expiry management
   - No manual regeneration needed

3. **SGX Enclave Root CA**
   - Root CA private key sealed in enclave
   - Never exposed outside enclave
   - Hardware-backed security (when using real SGX)

4. **Full Chain of Trust**
   ```
   SGX Enclave Root CA (sealed private key)
       ↓ signs
   Fabric CA Intermediate (6 CAs, one per org)
       ↓ signs
   Identity Certificates (orderers, peers, users, admins)
   ```

5. **Audit Trail**
   - All certificate issuance logged
   - Can track who enrolled when
   - Revocation support

6. **Zero Trust Architecture**
   - Each identity proves itself with unique cert
   - Mutual TLS between all components
   - No implicit trust

---

## 📝 Summary

**Deployment Steps:**
1. Test certificate generation → `./test-and-fix-ca.sh`
2. Start CA servers → `docker-compose up -d ca-*`
3. Register identities → `./scripts/register-identities-in-containers.sh`
4. Enroll identities → `./scripts/enroll-all-identities.sh`
5. Generate channel artifacts → `./scripts/regenerate-channel-artifacts.sh`
6. Update Docker Compose → `./scripts/update-docker-compose-for-dynamic-mtls.sh`
7. Start blockchain → `docker-compose up -d`
8. Create channels → `./scripts/create-channels-with-dynamic-mtls.sh`
9. Deploy chaincode → `./deploy-chaincode.sh`

**Time**: 15-20 minutes (vs 2-3 minutes for cryptogen)

**Result**: Production-grade dual blockchain with full security features!

---

**Last Updated**: 2025-11-15
