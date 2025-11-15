#!/bin/bash
# Create and join channels using Fabric 2.5 channel participation API

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

echo "=== Step 1: Join HOT CHANNEL to orderer using osnadmin ==="
docker exec cli osnadmin channel join \
  --channelID hotchannel \
  --config-block /opt/gopath/src/github.com/hyperledger/fabric/peer/channel-artifacts/hotchannel.block \
  -o orderer.hot.coc.com:7053 \
  --ca-file /opt/gopath/src/github.com/hyperledger/fabric/peer/crypto/ordererOrganizations/hot.coc.com/orderers/orderer.hot.coc.com/msp/tlscacerts/tlsca.hot.coc.com-cert.pem \
  --client-cert /opt/gopath/src/github.com/hyperledger/fabric/peer/crypto/ordererOrganizations/hot.coc.com/orderers/orderer.hot.coc.com/tls/server.crt \
  --client-key /opt/gopath/src/github.com/hyperledger/fabric/peer/crypto/ordererOrganizations/hot.coc.com/orderers/orderer.hot.coc.com/tls/server.key

sleep 3

echo -e "\n=== Step 2: Join LawEnforcement peer to hotchannel ==="
docker exec cli peer channel join \
  -b /opt/gopath/src/github.com/hyperledger/fabric/peer/channel-artifacts/hotchannel.block

echo -e "\n=== Step 3: Join ForensicLab peer to hotchannel ==="
docker exec -e CORE_PEER_LOCALMSPID=ForensicLabMSP \
  -e CORE_PEER_ADDRESS=peer0.forensiclab.hot.coc.com:8051 \
  -e CORE_PEER_MSPCONFIGPATH=/opt/gopath/src/github.com/hyperledger/fabric/peer/crypto/peerOrganizations/forensiclab.hot.coc.com/users/Admin@forensiclab.hot.coc.com/msp \
  -e CORE_PEER_TLS_ROOTCERT_FILE=/opt/gopath/src/github.com/hyperledger/fabric/peer/crypto/peerOrganizations/forensiclab.hot.coc.com/peers/peer0.forensiclab.hot.coc.com/tls/ca.crt \
  cli peer channel join \
  -b /opt/gopath/src/github.com/hyperledger/fabric/peer/channel-artifacts/hotchannel.block

echo -e "\n=== Step 4: Join COLD CHANNEL to orderer using osnadmin ==="
docker exec cli-cold osnadmin channel join \
  --channelID coldchannel \
  --config-block /opt/gopath/src/github.com/hyperledger/fabric/peer/channel-artifacts/coldchannel.block \
  -o orderer.cold.coc.com:7153 \
  --ca-file /opt/gopath/src/github.com/hyperledger/fabric/peer/crypto/ordererOrganizations/cold.coc.com/orderers/orderer.cold.coc.com/msp/tlscacerts/tlsca.cold.coc.com-cert.pem \
  --client-cert /opt/gopath/src/github.com/hyperledger/fabric/peer/crypto/ordererOrganizations/cold.coc.com/orderers/orderer.cold.coc.com/tls/server.crt \
  --client-key /opt/gopath/src/github.com/hyperledger/fabric/peer/crypto/ordererOrganizations/cold.coc.com/orderers/orderer.cold.coc.com/tls/server.key

sleep 3

echo -e "\n=== Step 5: Join Auditor peer to coldchannel ==="
docker exec cli-cold peer channel join \
  -b /opt/gopath/src/github.com/hyperledger/fabric/peer/channel-artifacts/coldchannel.block

echo -e "\n=== Step 6: Update anchor peers ==="
docker exec cli peer channel update \
  -o orderer.hot.coc.com:7050 \
  -c hotchannel \
  -f /opt/gopath/src/github.com/hyperledger/fabric/peer/channel-artifacts/LawEnforcementMSPanchors.tx \
  --tls --cafile /opt/gopath/src/github.com/hyperledger/fabric/peer/crypto/ordererOrganizations/hot.coc.com/orderers/orderer.hot.coc.com/msp/tlscacerts/tlsca.hot.coc.com-cert.pem

docker exec -e CORE_PEER_LOCALMSPID=ForensicLabMSP \
  -e CORE_PEER_ADDRESS=peer0.forensiclab.hot.coc.com:8051 \
  -e CORE_PEER_MSPCONFIGPATH=/opt/gopath/src/github.com/hyperledger/fabric/peer/crypto/peerOrganizations/forensiclab.hot.coc.com/users/Admin@forensiclab.hot.coc.com/msp \
  -e CORE_PEER_TLS_ROOTCERT_FILE=/opt/gopath/src/github.com/hyperledger/fabric/peer/crypto/peerOrganizations/forensiclab.hot.coc.com/peers/peer0.forensiclab.hot.coc.com/tls/ca.crt \
  cli peer channel update \
  -o orderer.hot.coc.com:7050 \
  -c hotchannel \
  -f /opt/gopath/src/github.com/hyperledger/fabric/peer/channel-artifacts/ForensicLabMSPanchors.tx \
  --tls --cafile /opt/gopath/src/github.com/hyperledger/fabric/peer/crypto/ordererOrganizations/hot.coc.com/orderers/orderer.hot.coc.com/msp/tlscacerts/tlsca.hot.coc.com-cert.pem

docker exec cli-cold peer channel update \
  -o orderer.cold.coc.com:7150 \
  -c coldchannel \
  -f /opt/gopath/src/github.com/hyperledger/fabric/peer/channel-artifacts/AuditorMSPanchors.tx \
  --tls --cafile /opt/gopath/src/github.com/hyperledger/fabric/peer/crypto/ordererOrganizations/cold.coc.com/orderers/orderer.cold.coc.com/msp/tlscacerts/tlsca.cold.coc.com-cert.pem

echo -e "\n=== Step 7: Verify channel membership ==="
echo "Hot channel peers:"
docker exec cli peer channel list

echo -e "\nCold channel peers:"
docker exec cli-cold peer channel list

echo -e "\n=== Channel creation complete! ==="
echo "hotchannel: LawEnforcementMSP, ForensicLabMSP, CourtMSP (client-only), AuditorMSP (client-only)"
echo "coldchannel: AuditorMSP, CourtMSP (client-only)"
