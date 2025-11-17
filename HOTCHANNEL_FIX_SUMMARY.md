# Hotchannel Endorsement Policy Fix - Summary

## Problem Identified

The `hotchannel` was configured with **4 organizations** (LawEnforcement, ForensicLab, Court, Auditor) but only **2 organizations** were actively participating with peers. This caused `ENDORSEMENT_POLICY_FAILURE` during chaincode commits because:

- **ImplicitMeta MAJORITY Endorsement** policy required endorsements from at least 3 out of 4 orgs
- Only LawEnforcement and ForensicLab had peers to provide endorsements
- Court (no peer) and Auditor (on cold blockchain only) couldn't endorse

## Root Cause

In `hot-blockchain/configtx.yaml`, both channel profiles included all 4 organizations:

```yaml
Profiles:
  HotChainGenesis:
    Application:
      Organizations:
        - *LawEnforcement
        - *ForensicLab
        - *Court          # ❌ SHOULD NOT BE HERE
        - *Auditor        # ❌ SHOULD NOT BE HERE
```

## Solution Implemented

### 1. Fixed Configuration File ✅

**File:** `hot-blockchain/configtx.yaml`

**Changes:**
- Removed **Court** and **Auditor** from `HotChainGenesis` profile
- Removed **Court** and **Auditor** from `HotChainChannel` profile
- Updated `HotConsortium` to only include LawEnforcement and ForensicLab

**New configuration:**
```yaml
Profiles:
  HotChainGenesis:
    Application:
      Organizations:
        - *LawEnforcement  # ✅ Active participant with peer
        - *ForensicLab     # ✅ Active participant with peer
    Consortiums:
      HotConsortium:
        Organizations:
          - *LawEnforcement
          - *ForensicLab

  HotChainChannel:
    Application:
      Organizations:
        - *LawEnforcement
        - *ForensicLab
```

### 2. Created Recreation Script ✅

**File:** `fix-hotchannel-endorsement.sh`

This script automates the complete channel recreation process:

1. **Generate new genesis block** with only 2 organizations
2. **Verify** genesis block contains only ForensicLabMSP and LawEnforcementMSP
3. **Stop** orderer and peers
4. **Clean** old channel data from Docker volumes
5. **Replace** genesis block with new 2-org configuration
6. **Restart** all containers
7. **Join orderer** to channel using osnadmin
8. **Join peers** to recreated channel
9. **Verify** channel membership

## Architecture After Fix

### Hot Blockchain (hotchannel)

**Participating Organizations (2):**
- ✅ **LawEnforcementMSP** - Has peer, can endorse
- ✅ **ForensicLabMSP** - Has peer, can endorse

**Endorsement Policy:**
- `ImplicitMeta MAJORITY Endorsement`
- With 2 orgs: MAJORITY = 2 (both must endorse)
- ✅ This will succeed because both orgs have peers

### Cold Blockchain (coldchannel)

**Remains unchanged:**
- ✅ **AuditorMSP** - Single organization, single peer
- ✅ Endorsement policy: requires Auditor endorsement only

### Organization Access Rights

| Organization | Hot Channel | Cold Channel | Notes |
|--------------|-------------|--------------|-------|
| LawEnforcement | ✅ Full access (read/write/endorse) | ❌ No access | Active participant |
| ForensicLab | ✅ Full access (read/write/endorse) | ❌ No access | Active participant |
| Court | ✅ Read-only via API | ❌ No access | Client-only, no peer |
| Auditor | ✅ Read-only via API | ✅ Full access (read/write/endorse) | Has peer only on cold chain |

**Important Notes:**
- Court and Auditor can still **read** from hotchannel via the API layer
- They just cannot participate in blockchain-level endorsement
- This separation is correct for the DFIR architecture

## Next Steps

### Step 1: Recreate Hotchannel ⏳

Run the fix script to recreate hotchannel with 2-org configuration:

```bash
cd ~/ramifyp/fyp  # or wherever your repo is
./fix-hotchannel-endorsement.sh
```

**Expected output:**
- ✅ New genesis block generated with 2 orgs
- ✅ Orderer joined to channel
- ✅ Both peers joined to channel
- ✅ Channel list shows "hotchannel" for both peers

**Estimated time:** ~2 minutes

### Step 2: Deploy Chaincode ⏳

Once channel is recreated, deploy chaincode:

```bash
./deploy-chaincode.sh
```

**What this does:**
1. Package chaincode
2. Install on LawEnforcement peer
3. Install on ForensicLab peer
4. **Approve for LawEnforcement** ← Will succeed
5. **Approve for ForensicLab** ← Will succeed
6. **Commit with 2-org endorsement** ← Will succeed (was failing before)
7. Deploy to Cold blockchain (Auditor peer)
8. Initialize both chains with enclave attestation

**Expected result:**
- ✅ Chaincode approved by both organizations
- ✅ Chaincode committed successfully
- ✅ No ENDORSEMENT_POLICY_FAILURE

**Estimated time:** ~3-5 minutes

### Step 3: Start Supporting Services ⏳

Start IPFS and MySQL:

```bash
docker-compose -f docker-compose-storage.yml up -d
```

### Step 4: Verify Complete System ⏳

Check all services are running:

```bash
docker ps | grep -E "orderer|peer|ca-|couchdb|ipfs|mysql" | wc -l
# Should show ~18 containers
```

Verify chaincode:

```bash
./verify-blockchain.sh
```

## Files Modified

| File | Status | Description |
|------|--------|-------------|
| `hot-blockchain/configtx.yaml` | ✅ Modified | Removed Court and Auditor from hot channel profiles |
| `fix-hotchannel-endorsement.sh` | ✅ Created | Automated channel recreation script |
| `deploy-chaincode.sh` | ✅ Already correct | No changes needed - already handles 2-org endorsement |

## Files to be Generated

| File | When | Description |
|------|------|-------------|
| `hot-blockchain/channel-artifacts/hotchannel-fixed.block` | By fix script | New genesis block with 2 orgs |
| `hot-blockchain/channel-artifacts/hotchannel-4orgs.block.bak` | By fix script | Backup of old 4-org genesis block |

## Verification Commands

After running the fix script:

### 1. Verify genesis block has only 2 orgs:

```bash
docker run --rm -v $(pwd):/work -w /work hyperledger/fabric-tools:2.5 \
  configtxlator proto_decode \
  --input hot-blockchain/channel-artifacts/hotchannel.block \
  --type common.Block | \
  jq -r '.data.data[0].payload.data.config.channel_group.groups.Application.groups | keys[]'
```

**Expected output:**
```
ForensicLabMSP
LawEnforcementMSP
```

### 2. Verify peers joined to channel:

```bash
# LawEnforcement
docker exec -e CORE_PEER_LOCALMSPID=LawEnforcementMSP \
    -e CORE_PEER_ADDRESS=peer0.lawenforcement.hot.coc.com:7051 \
    -e CORE_PEER_TLS_ROOTCERT_FILE=/opt/gopath/src/github.com/hyperledger/fabric/peer/organizations/peerOrganizations/lawenforcement.hot.coc.com/peers/peer0.lawenforcement.hot.coc.com/tls/ca.crt \
    -e CORE_PEER_MSPCONFIGPATH=/opt/gopath/src/github.com/hyperledger/fabric/peer/organizations/peerOrganizations/lawenforcement.hot.coc.com/users/Admin@lawenforcement.hot.coc.com/msp \
    cli peer channel list
```

**Expected output:**
```
Channels peers has joined:
hotchannel
```

### 3. Verify orderer status:

```bash
docker exec cli osnadmin channel list -o orderer.hot.coc.com:7053 \
    --ca-file /opt/gopath/src/github.com/hyperledger/fabric/peer/organizations/ordererOrganizations/hot.coc.com/orderers/orderer.hot.coc.com/tls/ca.crt \
    --client-cert /opt/gopath/src/github.com/hyperledger/fabric/peer/organizations/ordererOrganizations/hot.coc.com/orderers/orderer.hot.coc.com/tls/server.crt \
    --client-key /opt/gopath/src/github.com/hyperledger/fabric/peer/organizations/ordererOrganizations/hot.coc.com/orderers/orderer.hot.coc.com/tls/server.key
```

**Expected output:**
```json
{
  "systemChannel": null,
  "channels": [
    {
      "name": "hotchannel",
      "url": "/participation/v1/channels/hotchannel"
    }
  ]
}
```

## Troubleshooting

### If channel recreation fails:

1. **Check logs:**
   ```bash
   docker logs orderer.hot.coc.com 2>&1 | tail -50
   docker logs peer0.lawenforcement.hot.coc.com 2>&1 | tail -50
   ```

2. **Verify network connectivity:**
   ```bash
   ./diagnose-and-fix-network.sh
   ```

3. **Complete reset** (last resort):
   ```bash
   docker-compose -f docker-compose-full.yml down -v
   ./bootstrap-complete-system.sh
   ```

### If chaincode commit still fails:

1. **Check approval status:**
   ```bash
   docker exec cli peer lifecycle chaincode checkcommitreadiness \
       --channelID hotchannel \
       --name dfir \
       --version 1.0 \
       --sequence 1
   ```

2. **Verify only 2 orgs in channel config:**
   ```bash
   # Use verification command from section above
   ```

## Summary

✅ **Configuration Fixed:** Hotchannel now correctly configured with only 2 organizations
✅ **Script Created:** Automated recreation script ready to execute
✅ **Deployment Ready:** deploy-chaincode.sh already handles 2-org endorsement

**Next Action:** Run `./fix-hotchannel-endorsement.sh` to recreate the channel

---

**Last Updated:** November 17, 2025
**Session:** claude/dual-blockchain-copy-01JqBne3N3BgWq2Jh7ymGVe1
