#!/bin/bash

# SGX Orderer Key Protection Setup Guide
# This configures Hyperledger Fabric orderer to use Intel SGX enclave for key protection

echo "=================================="
echo "SGX Orderer Configuration Guide"
echo "=================================="
echo ""

cat << 'EOF'

OVERVIEW:
---------
Instead of storing priv_sk as a plain file, the orderer private key
will be protected inside an SGX enclave. The key never exists in
plain text in system memory.

ARCHITECTURE:
-------------
┌─────────────────────────────────────┐
│  Host OS                            │
│  ┌───────────────────────────────┐  │
│  │  SGX Enclave                  │  │
│  │  ┌─────────────────────────┐  │  │
│  │  │ Orderer Private Key     │  │  │
│  │  │ (Encrypted in memory)   │  │  │
│  │  │                         │  │  │
│  │  │ Signing Engine          │  │  │
│  │  └─────────────────────────┘  │  │
│  │           ▲                   │  │
│  │           │ Sealed Key        │  │
│  └───────────┼───────────────────┘  │
│              │                      │
│  ┌───────────┴───────────────────┐  │
│  │  Orderer Process              │  │
│  │  - Calls enclave for signing  │  │
│  │  - Never sees raw key         │  │
│  └───────────────────────────────┘  │
└─────────────────────────────────────┘

PREREQUISITES:
--------------
1. SGX-enabled CPU (Intel with SGX support)
2. SGX driver installed
3. AESM service running
4. SGX SDK installed

IMPLEMENTATION OPTIONS:
-----------------------

Option A: Use Hyperledger Fabric BCCSP with SGX provider
Option B: Implement custom SGX signing service
Option C: Use Intel SGX SSL library with Fabric

RECOMMENDED: Option B (Custom SGX Signing Service)

STEPS:
------

1. Create SGX Enclave for Key Storage
   - Enclave holds priv_sk in encrypted memory
   - Provides signing API: Sign(data) -> signature
   - Seals key to disk (encrypted, bound to enclave)

2. Modify Orderer to Use Enclave
   - Replace BCCSP SW with BCCSP SGX
   - Orderer calls enclave instead of reading priv_sk
   - All signing operations go through enclave

3. Remote Attestation
   - Orderer proves it's using genuine SGX enclave
   - Peers can verify orderer's enclave measurement
   - Provides cryptographic proof of key protection

CONFIGURATION:
--------------

# orderer.yaml changes:
General:
    BCCSP:
        Default: SGX
        SGX:
            EnclaveLibrary: /usr/local/lib/orderer_signing_enclave.so
            Hash: SHA2
            Security: 256
            SealedKeyPath: /var/hyperledger/orderer/sgx/sealed_key.bin

# Environment variables:
FABRIC_ORDERER_GENERAL_BCCSP_DEFAULT=SGX
FABRIC_ORDERER_GENERAL_BCCSP_SGX_ENCLAVELIBRARY=/usr/local/lib/orderer_signing_enclave.so

SECURITY BENEFITS:
------------------
✅ Private key never in plain text memory (even encrypted pages)
✅ OS kernel cannot read key (isolated from privileged software)
✅ Root user cannot extract key
✅ Side-channel protection (with proper enclave code)
✅ Remote attestation proves correct execution
✅ Sealed storage (key encrypted, bound to this enclave)

DEVELOPMENT STEPS:
------------------

1. Enclave Development (C/C++)
   ├── Define ECALL: ecall_sign_block(data, data_len, signature, sig_len)
   ├── Implement ECDSA signing inside enclave
   ├── Load sealed key on initialization
   └── Build enclave shared library (.so)

2. Orderer Integration
   ├── Create BCCSP SGX provider
   ├── Implement KeyStore that calls enclave
   ├── Replace file-based key loading
   └── Test block signing through enclave

3. Deployment
   ├── Generate key inside enclave (or import securely)
   ├── Seal key to disk
   ├── Configure orderer to use SGX BCCSP
   └── Start orderer with SGX enabled

SAMPLE CODE STRUCTURE:
----------------------

// Enclave (orderer_signing_enclave.edl)
enclave {
    trusted {
        public sgx_status_t ecall_initialize_key([in, size=key_len] const uint8_t* sealed_key,
                                                   size_t key_len);

        public sgx_status_t ecall_sign_block([in, size=data_len] const uint8_t* data,
                                             size_t data_len,
                                             [out, size=sig_max_len] uint8_t* signature,
                                             size_t sig_max_len,
                                             [out] size_t* sig_actual_len);

        public sgx_status_t ecall_get_public_key([out, size=64] uint8_t* pubkey);

        public sgx_status_t ecall_attest([out] sgx_report_t* report);
    };
};

// Host App (BCCSP SGX Provider)
func (sgx *SGXKeyStore) Sign(k bccsp.Key, digest []byte, opts bccsp.SignerOpts) ([]byte, error) {
    var signature [64]byte
    var sigLen uint64

    // Call into enclave
    ret := ecall_sign_block(
        sgx.enclaveID,
        digest,
        uint64(len(digest)),
        signature[:],
        64,
        &sigLen,
    )

    if ret != sgx.SGX_SUCCESS {
        return nil, fmt.Errorf("SGX signing failed: %v", ret)
    }

    return signature[:sigLen], nil
}

TESTING:
--------
1. Unit tests: Sign known data, verify signature
2. Integration tests: Full orderer block signing
3. Attestation tests: Verify enclave measurements
4. Performance tests: Measure signing latency
5. Security tests: Attempt to extract key (should fail)

PRODUCTION CHECKLIST:
---------------------
☐ SGX driver installed and tested
☐ AESM service running
☐ Enclave code audited for security
☐ Attestation working with Intel Attestation Service (IAS)
☐ Sealed keys backed up securely
☐ Monitoring for SGX errors
☐ Fallback plan if SGX fails
☐ Documentation for operations team

IMPORTANT NOTES:
----------------
⚠️  Enclave code must be carefully written to avoid:
    - Memory leaks that expose key
    - Side-channel attacks (timing, cache)
    - Bugs that allow key extraction

⚠️  Use Intel's SGX SDK properly:
    - Seal keys with MRSIGNER policy (survives enclave updates)
    - Implement proper error handling
    - Follow Intel's best practices

⚠️  Test thoroughly:
    - Key never appears in plain text (check with debugger)
    - Signatures are valid and verifiable
    - Performance is acceptable (< 10ms per signature)

REFERENCES:
-----------
- Intel SGX Developer Guide: https://software.intel.com/sgx
- Hyperledger Fabric BCCSP: https://hyperledger-fabric.readthedocs.io/
- Example SGX Signing: https://github.com/intel/linux-sgx
- Your existing SGX chaincode implementation

EOF

echo ""
echo "For your specific setup:"
echo "------------------------"
echo "Since your chaincode already uses SGX, you have the infrastructure."
echo "The orderer SGX integration follows the same pattern:"
echo ""
echo "  Chaincode:  Evidence data → SGX Enclave → Encrypted storage"
echo "  Orderer:    Block data → SGX Enclave → Signature"
echo ""
echo "Both use SGX to protect sensitive operations!"
echo ""
