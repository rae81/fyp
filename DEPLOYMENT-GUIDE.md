# DFIR Dual-Blockchain Complete Deployment Guide

## Overview

This guide covers the complete deployment of a Dual Hyperledger Fabric blockchain system with:
- **SGX Enclave Root CA** storing orderer private keys
- **Dynamic mTLS certificates** issued through certificate chain
- **6 Fabric CA servers** (one per organization)
- **Container-based registration workaround** for authentication issues
- **Automated deployment scripts** for reproducible deployments

## Architecture

### Certificate Chain
```
SGX Enclave Root CA (sealed private key in enclave)
    ↓ signs
Fabric CA Intermediates (6 CAs)
    ↓ signs
Identity Certificates (orderers, peers, users, admins)
```

### Organizations

**HOT Blockchain (hotchannel):**
- LawEnforcementMSP - peer0.lawenforcement.hot.coc.com:7051
- ForensicLabMSP - peer0.forensiclab.hot.coc.com:8051
- CourtMSP - (client-only, no peer)
- AuditorMSP - (read-only access from cold chain)

**COLD Blockchain (coldchannel):**
- AuditorMSP - peer0.auditor.cold.coc.com:9051
- CourtMSP - (client-only, no peer)

### Fabric CA Servers

| CA Name | Port | Organization | Purpose |
|---------|------|--------------|---------|
| ca-lawenforcement | 7054 | LawEnforcement | Issues certs for law enforcement |
| ca-forensiclab | 8054 | ForensicLab | Issues certs for forensic lab |
| ca-auditor | 9054 | Auditor | Issues certs for auditors |
| ca-court | 10054 | Court | Issues certs for court (shared org) |
| ca-orderer-hot | 11054 | Hot Orderer | Issues certs for hot blockchain orderer |
| ca-orderer-cold | 12054 | Cold Orderer | Issues certs for cold blockchain orderer |

## Prerequisites

- Docker & Docker Compose
- Hyperledger Fabric 2.5 binaries (fabric-ca-client, configtxgen)
- Git
- SGX-enabled machine (or simulator mode)
- Minimum 8GB RAM, 20GB disk space

## Quick Start (One Command)

Pull latest code and run the master deployment script:

```bash
cd ~/Dual-hyperledger-Blockchain

# Pull latest changes
git checkout claude/dual-blockchain-mhz83hrxszs5xzzr-01KVuAGXoDLYAaEFYTTtR3PL
git pull

# Run complete deployment (handles everything)
./deploy-complete-dfir-system.sh
```

This master script handles all 7 deployment phases automatically.

## Manual Deployment (Step-by-Step)

If you prefer manual control or need to debug specific phases:

### Phase 1: Infrastructure Startup

```bash
# Start Enclave Root CA and all 6 Fabric CAs
./bootstrap-complete-system.sh

# Wait for CAs to be fully ready
sleep 30
```

### Phase 2: Identity Registration

```bash
# Register identities INSIDE CA containers
# This workaround bypasses authentication issues
./scripts/register-identities-in-containers.sh
```

**Why this works:**
- Bootstrap admin credentials work inside containers
- Avoids authentication failures from host
- Identities are registered with passwords (e.g., `orderer.hot.coc.com:orderer.hot.coc.compw`)

### Phase 3: Identity Enrollment

```bash
# Enroll identities FROM HOST to get dynamic mTLS certificates
./scripts/enroll-all-identities.sh
```

**What happens:**
- Enrollment requests go through Fabric CA
- Fabric CA signs certificates using intermediate cert
- Intermediate cert is signed by Enclave Root CA
- Result: Full chain from Enclave Root CA → Fabric CA → Identity

**Certificate locations:**
- Orderers: `organizations/ordererOrganizations/{org}/orderers/{orderer}/`
- Peers: `organizations/peerOrganizations/{org}/peers/{peer}/`
- Users: `organizations/peerOrganizations/{org}/users/{user}/`

### Phase 4: Channel Artifacts

```bash
# Generate genesis blocks and anchor peer configs
./scripts/regenerate-channel-artifacts.sh
```

**Generated files:**
- `hot-blockchain/channel-artifacts/hotchannel.block`
- `hot-blockchain/channel-artifacts/LawEnforcementMSPanchors.tx`
- `hot-blockchain/channel-artifacts/ForensicLabMSPanchors.tx`
- `cold-blockchain/channel-artifacts/coldchannel.block`
- `cold-blockchain/channel-artifacts/AuditorMSPanchors.tx`

### Phase 5: Update Docker Compose

```bash
# Update docker-compose files to use organizations/ instead of crypto-config/
./scripts/update-docker-compose-for-dynamic-mtls.sh
```

**What it updates:**
- Replaces `crypto-config` with `organizations`
- Updates volume mounts for orderers, peers, CLI containers
- Updates environment variables for certificate paths

### Phase 6: Start Blockchain Network

```bash
# Start orderers and peers
docker-compose -f docker-compose-hot.yml -f docker-compose-cold.yml up -d

# Wait for network to initialize
sleep 45
```

**Verify containers:**
```bash
docker ps
```

Expected containers:
- orderer.hot.coc.com
- orderer.cold.coc.com
- peer0.lawenforcement.hot.coc.com
- peer0.forensiclab.hot.coc.com
- peer0.auditor.cold.coc.com
- cli (hot blockchain CLI)
- cli-cold (cold blockchain CLI)
- CouchDB instances

### Phase 7: Create Channels

```bash
# Join orderers and peers to channels
./scripts/create-channels-with-dynamic-mtls.sh
```

**What it does:**
1. Joins hot orderer to hotchannel using osnadmin API
2. Fetches genesis block
3. Joins Law Enforcement peer to hotchannel
4. Joins Forensic Lab peer to hotchannel
5. Updates anchor peers for both orgs
6. Joins cold orderer to coldchannel
7. Joins Auditor peer to coldchannel
8. Updates Auditor anchor peer

## Verification

### Check Channel Status

```bash
# Hot blockchain channels
docker exec cli peer channel list

# Cold blockchain channels
docker exec cli-cold peer channel list
```

Expected output:
```
Channels peers has joined:
hotchannel
```

### Verify Certificate Chain

```bash
# View orderer certificate
openssl x509 -in organizations/ordererOrganizations/hot.coc.com/orderers/orderer.hot.coc.com/msp/signcerts/cert.pem -noout -text

# Check issuer
openssl x509 -in organizations/ordererOrganizations/hot.coc.com/orderers/orderer.hot.coc.com/msp/signcerts/cert.pem -noout -issuer

# Verify chain
openssl verify -CAfile fabric-ca/orderer-hot/ca-chain.pem organizations/ordererOrganizations/hot.coc.com/orderers/orderer.hot.coc.com/msp/signcerts/cert.pem
```

### Check Container Logs

```bash
# Orderer logs
docker logs orderer.hot.coc.com

# Peer logs
docker logs peer0.lawenforcement.hot.coc.com

# CLI logs
docker logs cli
```

### Test Network Connectivity

```bash
# From hot blockchain CLI
docker exec cli peer node status

# From cold blockchain CLI
docker exec cli-cold peer node status
```

## Troubleshooting

### Issue: "CA containers not running"

**Solution:**
```bash
./bootstrap-complete-system.sh
docker ps | grep ca-
```

Wait 30 seconds for CAs to be fully ready.

### Issue: "Authentication failure" during registration

**Solution:**
This is why we use the container-based workaround! Registration runs INSIDE containers:
```bash
./scripts/register-identities-in-containers.sh
```

### Issue: "Channel artifacts generation failed"

**Check paths:**
```bash
# Verify organization-level MSP directories exist
ls -la organizations/peerOrganizations/*/msp/cacerts/
ls -la organizations/ordererOrganizations/*/msp/cacerts/
```

**Common fix:**
Re-run enrollment to create org-level MSP:
```bash
./scripts/enroll-all-identities.sh
```

### Issue: "Orderer failed to join channel"

**Check orderer logs:**
```bash
docker logs orderer.hot.coc.com 2>&1 | tail -50
```

**Common causes:**
- Orderer not running: `docker-compose up -d`
- Certificate path incorrect: verify `organizations/` structure
- Port conflict: check if 7050, 7053 are available

### Issue: "Peer failed to join channel"

**Verify peer is running:**
```bash
docker exec cli peer node status
```

**Check certificate paths:**
```bash
docker exec cli ls -la /opt/gopath/src/github.com/hyperledger/fabric/peer/organizations/peerOrganizations/lawenforcement.hot.coc.com/
```

## Directory Structure

```
Dual-hyperledger-Blockchain/
├── organizations/                    # Dynamic mTLS certificates (NEW)
│   ├── peerOrganizations/
│   │   ├── lawenforcement.hot.coc.com/
│   │   │   ├── msp/                 # Org-level MSP
│   │   │   ├── peers/
│   │   │   │   └── peer0.lawenforcement.hot.coc.com/
│   │   │   │       ├── msp/         # Peer MSP
│   │   │   │       └── tls/         # Peer TLS certs
│   │   │   └── users/
│   │   │       └── Admin@lawenforcement.hot.coc.com/
│   │   ├── forensiclab.hot.coc.com/
│   │   ├── auditor.cold.coc.com/
│   │   └── court.coc.com/           # Shared organization
│   └── ordererOrganizations/
│       ├── hot.coc.com/
│       │   ├── msp/
│       │   ├── orderers/
│       │   │   └── orderer.hot.coc.com/
│       │   └── users/
│       └── cold.coc.com/
├── fabric-ca/                       # Fabric CA configs & data
│   ├── lawenforcement/
│   ├── forensiclab/
│   ├── auditor/
│   ├── court/
│   ├── orderer-hot/
│   │   ├── ca-chain.pem            # Full chain (intermediate + root)
│   │   └── fabric-ca-server-config.yaml
│   └── orderer-cold/
├── hot-blockchain/
│   └── channel-artifacts/
│       ├── hotchannel.block        # Genesis block
│       ├── LawEnforcementMSPanchors.tx
│       └── ForensicLabMSPanchors.tx
├── cold-blockchain/
│   └── channel-artifacts/
│       ├── coldchannel.block
│       └── AuditorMSPanchors.tx
├── scripts/
│   ├── register-identities-in-containers.sh  # Registration workaround
│   ├── enroll-all-identities.sh              # Enrollment for dynamic mTLS
│   ├── regenerate-channel-artifacts.sh       # Generate genesis blocks
│   ├── update-docker-compose-for-dynamic-mtls.sh
│   └── create-channels-with-dynamic-mtls.sh  # Channel creation
├── deploy-complete-dfir-system.sh   # MASTER SCRIPT (all-inclusive)
├── bootstrap-complete-system.sh     # Start infrastructure
├── DEPLOYMENT-WORKAROUND.md         # Container-based registration docs
└── DEPLOYMENT-GUIDE.md              # This file
```

## Next Steps After Deployment

### 1. Deploy Chaincode

```bash
# Package evidence chaincode
peer lifecycle chaincode package evidence.tar.gz \
  --path ./chaincode/evidence \
  --lang golang \
  --label evidence_1.0

# Install on hot blockchain peers
docker exec cli peer lifecycle chaincode install evidence.tar.gz

# Approve and commit (detailed steps in chaincode deployment guide)
```

### 2. Test Evidence Submission

```bash
# Submit evidence from Law Enforcement
docker exec cli peer chaincode invoke \
  -C hotchannel \
  -n evidence \
  -c '{"function":"SubmitEvidence","Args":[...]}'
```

### 3. Query from Auditor

```bash
# Read evidence from cold blockchain
docker exec cli-cold peer chaincode query \
  -C coldchannel \
  -n evidence \
  -c '{"function":"QueryEvidence","Args":[...]}'
```

## Important Files

| File | Purpose |
|------|---------|
| `deploy-complete-dfir-system.sh` | **MASTER SCRIPT** - Runs entire deployment |
| `bootstrap-complete-system.sh` | Starts Enclave Root CA + 6 Fabric CAs |
| `scripts/register-identities-in-containers.sh` | Container-based registration workaround |
| `scripts/enroll-all-identities.sh` | Enrollment for dynamic mTLS certificates |
| `scripts/regenerate-channel-artifacts.sh` | Generates genesis blocks and anchor peer configs |
| `scripts/update-docker-compose-for-dynamic-mtls.sh` | Updates docker-compose for new cert paths |
| `scripts/create-channels-with-dynamic-mtls.sh` | Creates channels and joins peers |
| `DEPLOYMENT-WORKAROUND.md` | Detailed explanation of container-based registration |

## Security Considerations

1. **Enclave Root CA**: Private key sealed in SGX enclave, never exposed
2. **Dynamic mTLS**: All certificates issued on-demand through CA chain
3. **Certificate Rotation**: Can re-enroll identities for fresh certificates
4. **Zero Trust**: Each identity gets unique certificate from chain
5. **DFIR Security**: Orderer keys protected by enclave attestation

## Performance Tuning

### For Production

Edit `docker-compose-hot.yml` and `docker-compose-cold.yml`:

```yaml
# Increase orderer batch timeout for better throughput
- ORDERER_GENERAL_BATCHTIMEOUT=2s  # Default: 2s, Production: 500ms

# Increase batch size
- ORDERER_GENERAL_BATCHSIZE_MAXMESSAGECOUNT=500  # Default: 10

# Enable Raft snapshot
- ORDERER_CONSENSUS_WALDIR=/var/hyperledger/production/orderer/etcdraft/wal
- ORDERER_CONSENSUS_SNAPDIR=/var/hyperledger/production/orderer/etcdraft/snapshot
```

### For Development

Keep defaults for easier debugging and log analysis.

## Backup and Recovery

### Backup

```bash
# Backup certificates
tar -czf organizations-backup-$(date +%Y%m%d).tar.gz organizations/

# Backup channel artifacts
tar -czf channel-artifacts-backup-$(date +%Y%m%d).tar.gz \
  hot-blockchain/channel-artifacts/ \
  cold-blockchain/channel-artifacts/

# Backup CA databases
tar -czf fabric-ca-backup-$(date +%Y%m%d).tar.gz fabric-ca/*/fabric-ca-server.db
```

### Recovery

```bash
# Restore certificates
tar -xzf organizations-backup-YYYYMMDD.tar.gz

# Restore channel artifacts
tar -xzf channel-artifacts-backup-YYYYMMDD.tar.gz

# Restore CA databases
tar -xzf fabric-ca-backup-YYYYMMDD.tar.gz
```

## Contributing

When making changes to deployment scripts:
1. Test on clean environment
2. Update this guide with any new steps
3. Commit with descriptive messages
4. Document any workarounds in DEPLOYMENT-WORKAROUND.md

## Support

For issues or questions:
1. Check container logs: `docker logs <container-name>`
2. Review DEPLOYMENT-WORKAROUND.md for authentication issues
3. Verify certificate paths in `organizations/` directory
4. Check network connectivity between containers

## License

[Your License Here]

## Acknowledgments

- Hyperledger Fabric community
- SGX Enclave integration team
- Container-based registration workaround inspiration
