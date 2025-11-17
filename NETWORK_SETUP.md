# Single Network Setup for DFIR Blockchain System

## Overview

All containers now run on a **single Docker network** (`fyp_dfir-network` with subnet `172.20.0.0/16`) for simplified demo and development.

## Network Architecture

```
fyp_dfir-network (172.20.0.0/16)
├── Enclave (172.20.0.10)
├── CAs (172.20.0.20-25)
├── IPFS Nodes (172.20.0.30-31)
├── CouchDB (172.20.0.40-42)
├── Hot Orderer (172.20.0.50)
├── Hot Peers (172.20.0.60-61)
├── Cold Orderer (172.20.0.70)
├── Cold Peer (172.20.0.80)
├── CLI - Hot (172.20.0.100)
└── CLI - Cold (172.20.0.101)
```

## Changes Made

### 1. **Added CLI Containers to docker-compose-full.yml**

Previously, CLI containers were defined in separate compose files (`docker-compose-hot.yml` and `docker-compose-cold.yml`) on different networks. This caused DNS resolution issues.

**Now:** Both `cli` and `cli-cold` are in `docker-compose-full.yml` on `fyp_dfir-network` with static IPs:
- `cli`: 172.20.0.100
- `cli-cold`: 172.20.0.101

### 2. **Simplified Channel Recreation Script**

Removed unnecessary network connection commands from `fix-hotchannel-endorsement.sh` since all containers are already on the same network.

## Container Hostnames

All containers can reach each other by hostname:

### Hot Blockchain
- `orderer.hot.coc.com` - Hot orderer
- `peer0.lawenforcement.hot.coc.com` - Law Enforcement peer
- `peer0.forensiclab.hot.coc.com` - Forensic Lab peer
- `cli` - CLI for hot blockchain operations

### Cold Blockchain
- `orderer.cold.coc.com` - Cold orderer
- `peer0.auditor.cold.coc.com` - Auditor peer
- `cli-cold` - CLI for cold blockchain operations

### Shared Services
- `enclave` - SGX Enclave (Root CA)
- `ca.lawenforcement.hot.coc.com` - Law Enforcement CA
- `ca.forensiclab.hot.coc.com` - Forensic Lab CA
- `ca.auditor.cold.coc.com` - Auditor CA
- `ca.court.coc.com` - Court CA
- `ca.orderer.hot.coc.com` - Hot Orderer CA
- `ca.orderer.cold.coc.com` - Cold Orderer CA
- `couchdb0`, `couchdb1`, `couchdb2` - State databases
- `ipfs.hot.coc.com`, `ipfs.cold.coc.com` - IPFS nodes

## Usage

### Start All Services

```bash
docker-compose -f docker-compose-full.yml up -d
```

This starts:
- ✅ Enclave
- ✅ All 6 CAs
- ✅ 2 IPFS nodes
- ✅ 3 CouchDB instances
- ✅ Hot blockchain (orderer + 2 peers)
- ✅ Cold blockchain (orderer + 1 peer)
- ✅ CLI and CLI-cold

### Verify Connectivity

```bash
# Test from CLI to hot orderer
docker exec cli ping -c 2 orderer.hot.coc.com

# Test from CLI to hot peers
docker exec cli ping -c 2 peer0.lawenforcement.hot.coc.com
docker exec cli ping -c 2 peer0.forensiclab.hot.coc.com

# Test from CLI-cold to cold orderer
docker exec cli-cold ping -c 2 orderer.cold.coc.com

# Test from CLI-cold to cold peer
docker exec cli-cold ping -c 2 peer0.auditor.cold.coc.com
```

### Check All Containers

```bash
docker-compose -f docker-compose-full.yml ps
```

**Expected: 18 containers running**

### View Logs

```bash
# All containers
docker-compose -f docker-compose-full.yml logs -f

# Specific container
docker logs -f orderer.hot.coc.com
docker logs -f peer0.lawenforcement.hot.coc.com
docker logs -f cli
```

## DNS Resolution

Docker's embedded DNS server (`127.0.0.11:53`) automatically resolves container hostnames within the `fyp_dfir-network`.

Example from inside CLI:
```bash
$ docker exec cli getent hosts orderer.hot.coc.com
172.20.0.50     orderer.hot.coc.com

$ docker exec cli getent hosts peer0.forensiclab.hot.coc.com
172.20.0.61     peer0.forensiclab.hot.coc.com
```

## Benefits of Single Network

1. **Simplified Setup**: One `docker-compose up` starts everything
2. **No DNS Issues**: All containers can reach each other by hostname
3. **Easy Debugging**: Simple network topology
4. **Demo Ready**: Perfect for presentations and testing
5. **No Manual Network Connections**: Everything configured declaratively

## For Production

For production deployment, consider:
- **Network Isolation**: Separate networks for hot/cold chains
- **Firewall Rules**: Restrict cross-chain communication
- **mTLS**: Already implemented via Fabric CAs
- **Network Policies**: Define explicit allow/deny rules

But for **development and demo** on Kali Linux, the single network is ideal!

## Troubleshooting

### Container Can't Resolve Hostname

```bash
# Check container is on the network
docker inspect <container_name> | grep NetworkMode

# Restart container
docker-compose -f docker-compose-full.yml restart <container_name>
```

### CLI Not Found

```bash
# Ensure you're using docker-compose-full.yml
docker-compose -f docker-compose-full.yml up -d cli cli-cold
```

### Port Conflicts

If ports are already in use:
```bash
# Check what's using the port
sudo netstat -tulpn | grep <port>

# Stop conflicting service or change port in docker-compose-full.yml
```

---

**Last Updated:** November 17, 2025
**Session:** claude/dual-blockchain-copy-01JqBne3N3BgWq2Jh7ymGVe1
