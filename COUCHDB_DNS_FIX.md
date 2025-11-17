# CouchDB DNS Resolution Fix

## Problem

After deploying the dual blockchain system, peer containers show errors like:

```
WARN [couchdb] handleRequest -> Attempt 7 of 11 returned error:
Get "http://couchdb0:5984/": dial tcp: lookup couchdb0 on 127.0.0.11:53: no such host
```

This means the peer containers cannot resolve CouchDB hostnames via Docker's internal DNS.

## Root Cause

The issue can occur due to:

1. **CouchDB containers not running** - Peers started before CouchDB was ready
2. **Network misconfiguration** - Containers on different Docker networks
3. **Stale DNS cache** - Docker's embedded DNS server has stale entries
4. **Startup order** - docker-compose dependencies not properly enforced

## Quick Fix

### Option 1: Use Automated Script (Recommended)

```bash
cd ~/ramifyp/fyp
./diagnose-and-fix-network.sh
```

This script will automatically:
- Detect network issues
- Start missing CouchDB containers
- Verify DNS resolution
- Restart peers if needed
- Show network topology

### Option 2: Manual Fix

```bash
# 1. Check if CouchDB containers exist and are running
docker ps -a | grep couchdb

# Expected output: 3 running CouchDB containers (couchdb0, couchdb1, couchdb2)
# If not running, proceed to step 2

# 2. Start CouchDB containers
docker-compose -f docker-compose-full.yml up -d couchdb0 couchdb1 couchdb2

# 3. Wait for CouchDB to initialize
sleep 15

# 4. Verify CouchDB is accessible
curl http://localhost:5984
# Should return: {"couchdb":"Welcome","version":"3.3.x",...}

# 5. Restart peer containers
docker-compose -f docker-compose-full.yml restart \
    peer0.lawenforcement.hot.coc.com \
    peer0.forensiclab.hot.coc.com \
    peer0.auditor.cold.coc.com

# 6. Wait for peers to reconnect
sleep 20

# 7. Check peer logs
docker logs peer0.lawenforcement.hot.coc.com 2>&1 | tail -30
```

## Verification

After applying the fix, verify that:

### 1. CouchDB is accessible from host

```bash
curl http://localhost:5984
curl http://localhost:6984  # couchdb1
curl http://localhost:7984  # couchdb2
```

All should return CouchDB welcome messages.

### 2. CouchDB is accessible from within peer containers

```bash
docker exec peer0.lawenforcement.hot.coc.com curl http://couchdb0:5984
```

Should return CouchDB info, not DNS errors.

### 3. Peer logs show no CouchDB errors

```bash
docker logs peer0.lawenforcement.hot.coc.com 2>&1 | tail -50 | grep -i couchdb
```

Should not show "no such host" or connection errors.

### 4. All containers are on the same network

```bash
docker network inspect fyp_dfir-network | grep -A 3 "Containers"
```

Should list all CouchDB containers, peers, orderers, and CAs.

## Network Architecture

The `docker-compose-full.yml` configures:

```
Network: fyp_dfir-network (172.20.0.0/16)
├── Enclave (172.20.0.10)
├── CAs (172.20.0.20-25)
├── CouchDB containers
│   ├── couchdb0 (172.20.0.40) → peer0.lawenforcement
│   ├── couchdb1 (172.20.0.41) → peer0.forensiclab
│   └── couchdb2 (172.20.0.42) → peer0.auditor
├── Orderers (172.20.0.50-51)
└── Peers (172.20.0.60-62)
```

Each peer is configured to use a specific CouchDB instance:
- **peer0.lawenforcement** → `CORE_LEDGER_STATE_COUCHDBCONFIG_COUCHDBADDRESS=couchdb0:5984`
- **peer0.forensiclab** → `CORE_LEDGER_STATE_COUCHDBCONFIG_COUCHDBADDRESS=couchdb1:5984`
- **peer0.auditor** → `CORE_LEDGER_STATE_COUCHDBCONFIG_COUCHDBADDRESS=couchdb2:5984`

## Common Issues

### Issue: "network fyp_dfir-network not found"

**Solution:**
```bash
docker-compose -f docker-compose-full.yml up --no-start
# This creates the network without starting containers
```

### Issue: CouchDB port conflict

**Solution:**
```bash
# Check what's using CouchDB ports
sudo lsof -i :5984
sudo lsof -i :6984
sudo lsof -i :7984

# Kill conflicting processes or change ports in docker-compose-full.yml
```

### Issue: Peers still can't connect after fix

**Solution:**
```bash
# Complete restart with network recreation
docker-compose -f docker-compose-full.yml down
docker network rm fyp_dfir-network
docker-compose -f docker-compose-full.yml up -d
```

### Issue: "Error response from daemon: endpoint with name X already exists in network"

**Solution:**
```bash
# Disconnect and reconnect the container
docker network disconnect fyp_dfir-network <container_name>
docker network connect fyp_dfir-network <container_name>
```

## Diagnostic Commands

```bash
# View all containers and their networks
docker inspect $(docker ps -q) --format='{{.Name}}: {{range $k,$v := .NetworkSettings.Networks}}{{$k}} {{end}}'

# Test DNS resolution from peer
docker exec peer0.lawenforcement.hot.coc.com nslookup couchdb0

# Check CouchDB logs
docker logs couchdb0 2>&1 | tail -50

# View Docker DNS configuration
docker inspect peer0.lawenforcement.hot.coc.com | grep -A 10 "Dns"

# Show network topology
docker network inspect fyp_dfir-network --format='{{json .Containers}}' | jq
```

## Prevention

To prevent this issue in future deployments:

1. **Always start CouchDB before peers**
   ```bash
   docker-compose -f docker-compose-full.yml up -d couchdb0 couchdb1 couchdb2
   sleep 15
   docker-compose -f docker-compose-full.yml up -d peer0.lawenforcement.hot.coc.com peer0.forensiclab.hot.coc.com peer0.auditor.cold.coc.com
   ```

2. **Use the master deployment script** which handles proper ordering:
   ```bash
   ./deploy-everything-kali.sh
   ```

3. **Add health checks** to docker-compose for CouchDB (future improvement):
   ```yaml
   healthcheck:
     test: ["CMD", "curl", "-f", "http://localhost:5984"]
     interval: 10s
     timeout: 5s
     retries: 5
   ```

## Related Files

- `fix-couchdb-dns.sh` - Quick DNS fix script
- `diagnose-and-fix-network.sh` - Comprehensive diagnostic tool
- `docker-compose-full.yml` - Main container orchestration
- `deploy-everything-kali.sh` - Master deployment script

## Next Steps After Fix

Once CouchDB connectivity is working:

1. **Create channels**
   ```bash
   ./scripts/create-channels-with-dynamic-mtls.sh
   ```

2. **Deploy chaincode**
   ```bash
   ./deploy-chaincode.sh
   ```

3. **Start IPFS and MySQL**
   ```bash
   docker-compose -f docker-compose-storage.yml up -d
   ```

4. **Verify complete system**
   ```bash
   docker ps | grep -E "orderer|peer|ca-|couchdb|ipfs|mysql" | wc -l
   # Should show ~18 containers
   ```
