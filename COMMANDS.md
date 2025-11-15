# Commands Reference Guide

## 1. Clone/Update Repository

```bash
cd ~/blockchain-projects/
rm -rf Dual-hyperledger-Blockchain
git clone https://github.com/omar-kaaki/Dual-hyperledger-Blockchain.git
cd Dual-hyperledger-Blockchain
git checkout claude/dual-blockchain-01LQXXJ5gH5AVRmuZ2ppzG5M
```

## 2. Verify CA is Working

### Check all 6 CA servers are running:
```bash
docker ps --filter "name=ca-" --format "table {{.Names}}\t{{.Status}}"
```

### Test CA connectivity (all 6 ports):
```bash
for PORT in 7054 8054 9054 10054 11054 12054; do
  echo -n "Port $PORT: "
  curl -sk https://localhost:$PORT/cainfo | jq -r '.result.CAName' 2>/dev/null && echo "[OK]" || echo "[FAIL]"
done
```

### Check certificate chain from Enclave Root CA:
```bash
# Verify Root CA certificate exists
ls -lh fabric-ca/root-ca.pem

# Check an intermediate CA certificate
openssl x509 -in fabric-ca/ca-lawenforcement/ca-cert.pem -text -noout | grep -A3 "Issuer"
# Should show: CN=DFIR SGX Root CA

# Verify certificate has "Certificate Sign" key usage
openssl x509 -in fabric-ca/ca-lawenforcement/ca-cert.pem -text -noout | grep "Certificate Sign"
```

### Check organizations directory structure:
```bash
tree -L 4 organizations/
```

## 3. Check for Errors

### View all container statuses:
```bash
docker ps -a --format "table {{.Names}}\t{{.Status}}"
```

### Check orderer logs for errors:
```bash
docker logs orderer.hot.coc.com 2>&1 | tail -50
docker logs orderer.cold.coc.com 2>&1 | tail -50
```

### Check peer logs for errors:
```bash
docker logs peer0.lawenforcement.hot.coc.com 2>&1 | tail -50
docker logs peer0.forensiclab.hot.coc.com 2>&1 | tail -50
docker logs peer0.auditor.cold.coc.com 2>&1 | tail -50
```

### Check CA server logs:
```bash
docker logs ca-lawenforcement 2>&1 | tail -30
docker logs ca-forensiclab 2>&1 | tail -30
docker logs ca-auditor 2>&1 | tail -30
docker logs ca-court 2>&1 | tail -30
docker logs ca-orderer-hot 2>&1 | tail -30
docker logs ca-orderer-cold 2>&1 | tail -30
```

### Check for specific error patterns:
```bash
# MSP configuration errors
docker logs orderer.hot.coc.com 2>&1 | grep -i "msp\|admin"

# Certificate errors
docker logs orderer.hot.coc.com 2>&1 | grep -i "certificate\|tls"

# All failed containers
docker ps -a --filter "status=exited" --format "table {{.Names}}\t{{.Status}}"
```

## 4. Run Deployment

### Full automated deployment:
```bash
./complete-ca-deployment.sh
```

### Manual step-by-step (if needed):
```bash
# 1. Test and bootstrap CAs
./test-and-fix-ca.sh

# 2. Register identities
./scripts/register-identities-in-containers.sh

# 3. Enroll identities
./scripts/enroll-all-identities.sh

# 4. Generate channel artifacts
./scripts/regenerate-channel-artifacts.sh

# 5. Fix MSP configurations
./fix-all-msp.sh

# 6. Create channels
./scripts/create-channels-with-dynamic-mtls.sh
```

## 5. Verify Everything is Working

### Check all containers are running:
```bash
docker ps | grep -E "orderer|peer|ca-" | wc -l
# Should show: 15 containers (6 CAs + 2 orderers + 3 peers + 2 CLI + 3 CouchDB)
```

### Verify channels were created:
```bash
docker exec cli peer channel list
docker exec cli-cold peer channel list
```

### Check orderer is serving channels:
```bash
docker exec cli osnadmin channel list -o orderer.hot.coc.com:7053 \
  --ca-file /opt/gopath/src/github.com/hyperledger/fabric/peer/organizations/ordererOrganizations/hot.coc.com/orderers/orderer.hot.coc.com/tls/ca.crt \
  --client-cert /opt/gopath/src/github.com/hyperledger/fabric/peer/organizations/ordererOrganizations/hot.coc.com/orderers/orderer.hot.coc.com/tls/server.crt \
  --client-key /opt/gopath/src/github.com/hyperledger/fabric/peer/organizations/ordererOrganizations/hot.coc.com/orderers/orderer.hot.coc.com/tls/server.key
```

## 6. Troubleshooting Commands

### Restart all containers:
```bash
docker-compose -f docker-compose-hot.yml -f docker-compose-cold.yml restart
```

### Clean and restart from scratch:
```bash
docker-compose -f docker-compose-full.yml down -v
docker-compose -f docker-compose-hot.yml down -v
docker-compose -f docker-compose-cold.yml down -v
sudo rm -rf organizations/ fabric-ca/*/fabric-ca-server.db
./complete-ca-deployment.sh
```

### Check disk space:
```bash
df -h
docker system df
```

### View real-time logs:
```bash
# Hot orderer
docker logs -f orderer.hot.coc.com

# Law Enforcement peer
docker logs -f peer0.lawenforcement.hot.coc.com
```
