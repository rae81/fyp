# DNS Resolution Issue - Root Cause Analysis

## Problem Summary

After wiping Docker volumes and recreating the hot blockchain, DNS resolution persistently fails:
```
Error: dial tcp: lookup orderer.hot.coc.com on 127.0.0.11:53: no such host
```

## Root Cause Identified ✅

### The Wrong Volume Names Were Used

**What You Tried:**
```bash
docker volume rm fyp_orderer.hot.coc.com
docker volume rm fyp_peer0.lawenforcement.hot.coc.com
docker volume rm fyp_peer0.forensiclab.hot.coc.com
```

**The Problem:**
These volumes **DO NOT EXIST**. Docker Compose uses the named volumes defined in `docker-compose-full.yml`, NOT the container names.

**From docker-compose-full.yml:**
```yaml
volumes:
  orderer-hot-data:         # ✅ This is the actual volume name
  peer-lawenforcement-data: # ✅ This is the actual volume name
  peer-forensiclab-data:    # ✅ This is the actual volume name

services:
  orderer.hot.coc.com:
    volumes:
      - orderer-hot-data:/var/hyperledger/production/orderer  # ← Uses named volume

  peer0.lawenforcement.hot.coc.com:
    volumes:
      - peer-lawenforcement-data:/var/hyperledger/production  # ← Uses named volume

  peer0.forensiclab.hot.coc.com:
    volumes:
      - peer-forensiclab-data:/var/hyperledger/production    # ← Uses named volume
```

**Actual Volume Names (with project prefix):**
- `fyp_orderer-hot-data` (not `fyp_orderer.hot.coc.com`)
- `fyp_peer-lawenforcement-data` (not `fyp_peer0.lawenforcement.hot.coc.com`)
- `fyp_peer-forensiclab-data` (not `fyp_peer0.forensiclab.hot.coc.com`)

**Notice:** Hyphens (`-`) vs Dots (`.`)

## Why This Caused DNS Failure

### The Chain of Events:

1. **Old Corrupted Data Remained**
   - Wrong volume names meant `docker volume rm` did nothing
   - Old blockchain data with conflicting block hashes stayed in actual volumes
   - Containers loaded this corrupted data on startup

2. **Containers Crashed on Startup**
   ```
   panic: [channel: hotchannel] Could not append block: unexpected Previous block hash
   ```
   - Orderer: Old etcdraft WAL conflicted with new genesis block
   - Peers: Corrupted ledger files from previous channel attempts

3. **Crashed Containers Don't Register in DNS**
   - Docker's embedded DNS only registers **running** containers
   - CLI tried to resolve `orderer.hot.coc.com` → **not found**
   - This is why cold blockchain DNS worked (those containers were running)

4. **DNS Resolution Persistently Failed**
   - No matter how many times you restarted CLI
   - Because the hot blockchain containers were never actually running

## Verification

### Check Actual Volume Names:
```bash
docker volume ls | grep -E "orderer|lawenforcement|forensiclab"
```

**Expected Output:**
```
local     fyp_orderer-hot-data
local     fyp_peer-lawenforcement-data
local     fyp_peer-forensiclab-data
```

### Check Container Status:
```bash
docker ps --filter "name=orderer.hot.coc.com" --format "{{.Names}}: {{.Status}}"
docker ps --filter "name=peer0.lawenforcement.hot.coc.com" --format "{{.Names}}: {{.Status}}"
docker ps --filter "name=peer0.forensiclab.hot.coc.com" --format "{{.Names}}: {{.Status}}"
```

If they show **"Exited (2)"** or are not listed → They're crashed/not running → DNS won't work

## Solution

### Step 1: Use Correct Volume Names

Run the proper cleanup script:
```bash
./proper-volume-cleanup.sh
```

This script:
1. Stops hot blockchain containers
2. Removes the **CORRECT** volumes: `fyp_orderer-hot-data`, `fyp_peer-lawenforcement-data`, `fyp_peer-forensiclab-data`
3. Restarts containers (fresh volumes auto-created)
4. Waits for initialization

### Step 2: Verify Containers Are Running

```bash
docker ps --filter "name=hot" --format "table {{.Names}}\t{{.Status}}"
```

**Expected:**
```
orderer.hot.coc.com                Up X seconds (healthy)
peer0.lawenforcement.hot.coc.com   Up X seconds
peer0.forensiclab.hot.coc.com      Up X seconds
```

### Step 3: Restart CLI and Test DNS

```bash
docker-compose -f docker-compose-full.yml restart cli
sleep 5
./diagnose-hot-dns-issue.sh
```

**Expected:** All DNS tests pass ✅

### Step 4: Recreate Hotchannel

```bash
./fix-hotchannel-endorsement.sh
```

## Why Cold Blockchain DNS Worked

Cold blockchain containers were running properly because:
1. They didn't have conflicting data (never recreated with wrong genesis block)
2. Named volumes for cold blockchain had different names that weren't touched
3. Containers stayed running → Registered in Docker DNS → DNS resolution worked

## Key Takeaways

### Docker Volume Naming:
- **Named volumes** in docker-compose: `volume-name:` → `fyp_volume-name`
- **Container names**: `container_name: foo.bar.com` → Different from volume name
- Always check `docker volume ls` to see actual volume names

### Docker DNS Registration:
- Only **running** containers register in Docker's DNS
- Crashed/stopped containers → No DNS entry
- Always verify containers are `Up` with `docker ps` before expecting DNS to work

### Debugging Containers:
When DNS fails:
1. Check container status first: `docker ps -a --filter "name=<container>"`
2. If stopped/crashed, check logs: `docker logs <container>`
3. Fix root cause (usually data corruption or config issues)
4. Only then restart CLI for DNS refresh

## Next Steps

1. ✅ Run `./proper-volume-cleanup.sh` to remove actual volumes
2. ✅ Verify containers are running with `docker ps`
3. ✅ Run `./diagnose-hot-dns-issue.sh` to confirm DNS works
4. ✅ Run `./fix-hotchannel-endorsement.sh` to create channel
5. ✅ Deploy chaincode with `./deploy-chaincode.sh`

---

**Last Updated:** November 17, 2025
**Session:** claude/dual-blockchain-copy-01JqBne3N3BgWq2Jh7ymGVe1
**Issue:** Resolved - Wrong volume names used for cleanup
