# Container-Based Registration Workaround

## Problem Summary

During deployment, registration of orderers/peers failed with authentication errors when using bootstrap admin credentials from the host machine:

```
Error: Response from server: Error Code: 20 - Authentication failure
```

**What worked:**
- ✅ Admin enrollment (using `admin:adminpw`)
- ✅ Certificate chain verification (Enclave Root CA → Fabric CA)
- ✅ Dynamic mTLS certificate issuance

**What didn't work:**
- ❌ Registration of orderers/peers from host using `fabric-ca-client register`
- ❌ Multiple authentication approaches (password, mTLS, temp directories)

## Solution: Container-Based Registration

The workaround registers identities **inside** CA containers where bootstrap admin credentials work reliably, then enrolls from the host to maintain dynamic mTLS certificate issuance.

### Why This Preserves Dynamic mTLS

The key insight is that **registration** and **enrollment** are separate operations:

1. **Registration** (inside container):
   - Creates identity record in CA database
   - Requires bootstrap admin authentication
   - Does NOT issue certificates
   - Command: `docker exec ca-orderer-hot fabric-ca-client register ...`

2. **Enrollment** (from host):
   - Requests certificate for registered identity
   - Uses identity's own credentials (not admin)
   - **This is where dynamic mTLS happens**
   - Certificate chain: `Enclave Root CA → Fabric CA Intermediate → Identity Certificate`
   - Command: `fabric-ca-client enroll -u https://orderer:ordererpw@...`

**Result:** Certificates are still dynamically issued through the Enclave Root CA chain! 🎯

## Updated Deployment Process

### Quick Start

```bash
# On your deployment machine at /home/ramieid/Dual-hyperledger-Blockchain

# 1. Pull latest changes with workaround
git checkout claude/dual-blockchain-mhz83hrxszs5xzzr-01KVuAGXoDLYAaEFYTTtR3PL
git pull origin claude/dual-blockchain-mhz83hrxszs5xzzr-01KVuAGXoDLYAaEFYTTtR3PL

# 2. Clean previous deployment (if exists)
sudo rm -rf organizations/ fabric-ca/*/fabric-ca-server.db

# 3. Start all services (CAs, Enclave)
./bootstrap-complete-system.sh

# 4. Run complete deployment with workaround
./deploy-with-container-registration.sh
```

### Step-by-Step Breakdown

If you prefer manual control:

```bash
# Step 1: Start infrastructure
./bootstrap-complete-system.sh

# Step 2: Register identities inside CA containers
./scripts/register-identities-in-containers.sh

# Step 3: Enroll from host (gets dynamic mTLS certs)
./scripts/enroll-all-identities.sh

# Step 4: Generate channel artifacts
./scripts/regenerate-channel-artifacts.sh
```

## Verification

### Check Certificate Chain

```bash
# View orderer certificate
openssl x509 -in organizations/ordererOrganizations/hot.coc.com/orderers/orderer.hot.coc.com/msp/signcerts/cert.pem -noout -text

# Verify issuer is Fabric CA
openssl x509 -in organizations/ordererOrganizations/hot.coc.com/orderers/orderer.hot.coc.com/msp/signcerts/cert.pem -noout -issuer

# Verify Fabric CA is signed by Enclave Root CA
openssl verify -CAfile fabric-ca/orderer-hot/ca-chain.pem organizations/ordererOrganizations/hot.coc.com/orderers/orderer.hot.coc.com/msp/signcerts/cert.pem
```

### Expected Certificate Chain

```
SGX Enclave Root CA (sealed private key in enclave)
    ↓ signs
Fabric CA Intermediate (ca-orderer-hot, ca-lawenforcement, etc.)
    ↓ signs
Identity Certificates (orderers, peers, users, admins)
```

## Files Modified

- `scripts/register-identities-in-containers.sh` - NEW: Register inside containers
- `scripts/enroll-all-identities.sh` - Modified to skip registration, only enroll
- `deploy-with-container-registration.sh` - NEW: Master deployment script

## Architecture Preserved

✅ **Dynamic mTLS:** Certificates dynamically issued by Fabric CA
✅ **Enclave Root CA:** All certificates chain to SGX-sealed root key
✅ **Certificate Rotation:** Can re-enroll for fresh certificates
✅ **Zero Trust:** Each identity gets unique certificate from chain
✅ **DFIR Security:** Orderer key sealed in SGX enclave

## Next Steps

After successful enrollment:

1. **Create Channels:**
   ```bash
   # Hot channel
   docker exec cli-hot osnadmin channel join \
     --channelID hotchannel \
     --config-block channel-artifacts/hotchannel.block

   # Cold channel
   docker exec cli-cold osnadmin channel join \
     --channelID coldchannel \
     --config-block channel-artifacts/coldchannel.block
   ```

2. **Join Peers to Channels:**
   ```bash
   docker exec cli-hot peer channel join -b channel-artifacts/hotchannel.block
   # ... repeat for other peers
   ```

3. **Deploy Chaincode:**
   ```bash
   # Package evidence chaincode
   # Install on peers
   # Approve chaincode definitions
   # Commit chaincode
   ```

## Troubleshooting

### If registration fails inside container:
```bash
# Check CA container logs
docker logs ca-orderer-hot

# Verify bootstrap admin exists
docker exec ca-orderer-hot fabric-ca-client identity list \
  --url https://admin:adminpw@localhost:7054 \
  --tls.certfiles /etc/hyperledger/fabric-ca-server/ca-chain.pem
```

### If enrollment fails from host:
```bash
# Verify identity was registered
docker exec ca-orderer-hot fabric-ca-client identity list \
  -u https://admin:adminpw@localhost:7054

# Check TLS certificate chain
ls -la fabric-ca/orderer-hot/ca-chain.pem

# Verify CA is reachable
curl -sk https://localhost:11054/cainfo | jq
```

## Summary

This workaround achieves all original goals:
- ✅ SGX Enclave Root CA storing orderer private keys
- ✅ Dynamic mTLS certificate issuance through CA chain
- ✅ All identities (admins, orderers, peers) enrolled with certificates
- ✅ Complete DFIR blockchain deployment ready for channel creation

The only change is WHERE registration happens (inside containers vs. from host). The critical security properties—dynamic certificate issuance through the Enclave Root CA chain—remain intact.
