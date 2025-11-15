# Deployment Status and Recovery Plan

## Current Issue

The orderers are not running because the **certificates don't exist**.

### Root Cause
The `organizations/` directory is missing, which means the enrollment step either:
1. Never completed successfully in the previous session
2. Was cleaned/deleted at some point

Without certificates in `organizations/ordererOrganizations/*/orderers/*/`, the orderer containers cannot start.

### What's Missing
```bash
organizations/
├── ordererOrganizations/
│   ├── hot.coc.com/orderers/orderer.hot.coc.com/
│   │   ├── msp/        ← MISSING
│   │   └── tls/        ← MISSING
│   └── cold.coc.com/orderers/orderer.cold.coc.com/
│       ├── msp/        ← MISSING
│       └── tls/        ← MISSING
└── peerOrganizations/
    └── ... (all MISSING)
```

Additionally, `fabric-ca/` directory is empty, meaning CA bootstrap also didn't complete.

## Solution: Complete CA Deployment Script

I've created `complete-ca-deployment.sh` which will execute all steps from beginning to end:

### What the Script Does

1. **Cleanup** - Stops all containers, cleans organizations/ and CA databases
2. **Test Certificates** - Runs test-and-fix-ca.sh to verify enclave generates valid certs
3. **Bootstrap CAs** - Creates certificates for all 6 Fabric CA servers
4. **Start CAs** - Brings up all CA containers and waits for initialization
5. **Verify CAs** - Tests connectivity to all 6 CA servers (ports 7054-12054)
6. **Register Identities** - Runs container-based registration for all identities
7. **Enroll Identities** - Issues certificates for orderers, peers, admins, users
8. **Verify Certificates** - Confirms organizations/ directory structure exists
9. **Generate Channel Artifacts** - Creates genesis blocks and anchor peer configs
10. **Update Docker Compose** - Ensures paths point to organizations/ not crypto-config/
11. **Start Blockchain** - Brings up orderers, peers, CouchDB (waits 90 seconds)
12. **Verify Orderers** - Checks orderers are actually running, shows logs if not
13. **Create Channels** - Joins orderers and peers to channels
14. **Verify Channels** - Lists channels on hot and cold blockchains

### Estimated Time
15-20 minutes (includes wait periods for CA and network initialization)

## How to Run

```bash
cd ~/blockchain-projects/Dual-hyperledger-Blockchain

# Run complete deployment
./complete-ca-deployment.sh
```

The script will:
- ✅ Stop and show you clear progress messages
- ✅ Exit with error if any step fails
- ✅ Verify each component before proceeding
- ✅ Show logs if something goes wrong

## Expected Output

If successful, you'll see:

```
==========================================
  Deployment Complete!
==========================================

Verifying channels:
Hot blockchain:
Channels peers has joined:
hotchannel

Cold blockchain:
Channels peers has joined:
coldchannel

Next step: Deploy chaincode
  ./deploy-chaincode.sh
```

## If It Fails

The script stops at the first error and shows diagnostics.

### Common Failure Points

**1. Certificate Test Fails (Step 2)**
```
❌ CA certificate test failed!
```
**Solution**: Enclave needs to be rebuilt
```bash
docker-compose -f docker-compose-full.yml build enclave --no-cache
```

**2. CA Servers Not Responding (Step 4)**
```
Port 7054: ✗ Not responding
```
**Solution**: Check CA logs
```bash
docker logs ca-lawenforcement
docker logs ca-forensiclab
# ... etc
```

Common CA issues:
- **"cert sign key usage required"** → Certificate bug, rebuild enclave
- **"address already in use"** → Port conflict, kill process on that port
- **"database locked"** → `sudo rm -rf fabric-ca/*/fabric-ca-server.db`

**3. Enrollment Fails (Step 6)**
```
❌ Organizations directory not created properly!
```
**Solution**: CA servers might not be ready
```bash
# Wait longer and retry just enrollment
sleep 60
./scripts/enroll-all-identities.sh
```

**4. Orderers Not Running (Step 11)**
```
✗ Hot orderer not running
```
The script will show orderer logs automatically. Common issues:
- Missing certificate files
- TLS handshake failures
- Genesis block not found

**Solution**: Check the logs shown, verify certificate paths

**5. Channel Creation Fails (Step 12)**
```
Error: orderer not accessible
```
**Solution**: Orderers not healthy
```bash
docker logs orderer.hot.coc.com 2>&1 | tail -50
docker logs orderer.cold.coc.com 2>&1 | tail -50
```

## Alternative: Quick Setup with Cryptogen

If CA deployment keeps failing and you need to get something working quickly:

```bash
cd ~/blockchain-projects/Dual-hyperledger-Blockchain

# Stop everything
docker-compose -f docker-compose-full.yml down -v
docker-compose -f docker-compose-hot.yml down -v
docker-compose -f docker-compose-cold.yml down -v

# Clean
sudo rm -rf organizations/ fabric-ca/

# Quick setup (2-3 minutes)
chmod +x scripts/quick-setup-cryptogen.sh
./scripts/quick-setup-cryptogen.sh

# Deploy chaincode
./deploy-chaincode.sh
```

**Trade-offs:**
- ✅ Fast and reliable
- ✅ Works immediately
- ❌ No dynamic certificate issuance
- ❌ No SGX enclave root CA
- ❌ No certificate rotation
- ⚠️ For testing only, not production

## Files Created

- `complete-ca-deployment.sh` - Full CA deployment automation
- `diagnose-orderers.sh` - Diagnostic tool to check orderer status
- This file (DEPLOYMENT_STATUS.md) - Status and recovery guide

## Next Steps After Successful Deployment

1. Deploy chaincode: `./deploy-chaincode.sh`
2. Test the system:
   ```bash
   # Query chaincode
   docker exec cli peer chaincode query \
     -C hotchannel -n dfir \
     -c '{"function":"GetPRVConfig","Args":[]}'
   ```
3. See full testing guide in CA_DEPLOYMENT_GUIDE.md

---

## Update: MSP Configuration Issue

After running `complete-ca-deployment.sh`, orderers may fail with:
```
Failed to setup local msp with config: administrators must be declared when no admin ou classification is set
```

**Quick Fix:**
```bash
./fix-orderer-msp.sh
```

This script:
1. Creates `config.yaml` files in orderer MSP directories with NodeOU enabled
2. Copies admin certificates to `admincerts/` folders
3. Restarts orderers
4. Verifies they're running

Then proceed with:
```bash
./scripts/create-channels-with-dynamic-mtls.sh
```

---

**Current Status**: Deployment script working, MSP fix script available

**Last Updated**: 2025-11-15
