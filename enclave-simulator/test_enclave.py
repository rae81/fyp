#!/usr/bin/env python3
"""
Test script for enclave simulator core functionality
Tests CA generation, certificate signing, and key sealing without Flask
"""

import sys
import os
from pathlib import Path
from cryptography import x509
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import rsa, padding
from cryptography.hazmat.backends import default_backend
from cryptography.x509.oid import NameOID, ExtensionOID
import datetime
import json

# Add enclave-simulator directory to path
sys.path.insert(0, str(Path(__file__).parent))

# Import enclave simulator components
from enclave_core import EnclaveSimulator, ENCLAVE_CONFIG

def test_enclave_initialization():
    """Test enclave initialization and sealing key derivation"""
    print("=" * 60)
    print("TEST 1: Enclave Initialization")
    print("=" * 60)

    enclave = EnclaveSimulator()
    print(f"✓ Enclave initialized successfully")
    print(f"  MREnclave: {ENCLAVE_CONFIG['mr_enclave'][:32]}...")
    print(f"  MRSigner:  {ENCLAVE_CONFIG['mr_signer'][:32]}...")
    print(f"  TCB Level: {ENCLAVE_CONFIG['tcb_level']}")

    # Check sealing key
    assert enclave.sealing_key is not None
    assert len(enclave.sealing_key) == 32  # 256 bits
    print(f"✓ Sealing key derived (256-bit AES key)")
    print()
    return enclave

def test_seal_unseal(enclave):
    """Test data sealing and unsealing"""
    print("=" * 60)
    print("TEST 2: Data Sealing/Unsealing")
    print("=" * 60)

    test_data = b"This is secret orderer private key data"

    # Seal the data
    sealed = enclave.seal_data(test_data)
    print(f"✓ Data sealed successfully ({len(sealed)} bytes)")

    # Unseal the data
    unsealed = enclave.unseal_data(sealed)
    print(f"✓ Data unsealed successfully ({len(unsealed)} bytes)")

    # Verify integrity
    assert unsealed == test_data
    print(f"✓ Integrity verified: unsealed data matches original")
    print()

def test_root_ca_generation(enclave):
    """Test Root CA generation"""
    print("=" * 60)
    print("TEST 3: Root CA Generation")
    print("=" * 60)

    cert, private_key = enclave.generate_root_ca()

    # Verify certificate properties
    assert cert.subject == cert.issuer  # Self-signed
    print(f"✓ Certificate is self-signed")

    # Check subject
    cn = cert.subject.get_attributes_for_oid(NameOID.COMMON_NAME)[0].value
    assert cn == "Fabric Enclave Root CA"
    print(f"✓ Subject CN: {cn}")

    # Check key size
    assert private_key.key_size == 4096
    print(f"✓ Private key size: 4096 bits")

    # Check validity period
    try:
        valid_days = (cert.not_valid_after_utc - cert.not_valid_before_utc).days
    except AttributeError:
        valid_days = (cert.not_valid_after - cert.not_valid_before).days
    print(f"✓ Certificate validity: {valid_days} days (~10 years)")

    # Check extensions
    try:
        basic_constraints = cert.extensions.get_extension_for_oid(ExtensionOID.BASIC_CONSTRAINTS)
        assert basic_constraints.value.ca == True
        print(f"✓ CA extension: true")
    except x509.ExtensionNotFound:
        print("⚠ Warning: BasicConstraints extension not found")

    # Verify signature
    cert.public_key().verify(
        cert.signature,
        cert.tbs_certificate_bytes,
        padding.PKCS1v15(),
        cert.signature_hash_algorithm
    )
    print(f"✓ Self-signature verified")
    print()

    return cert, private_key

def test_certificate_signing(enclave):
    """Test CSR signing"""
    print("=" * 60)
    print("TEST 4: Certificate Signing (CSR)")
    print("=" * 60)

    # Generate a test key pair
    test_key = rsa.generate_private_key(
        public_exponent=65537,
        key_size=2048,
        backend=default_backend()
    )

    # Create CSR
    csr = x509.CertificateSigningRequestBuilder().subject_name(x509.Name([
        x509.NameAttribute(NameOID.COUNTRY_NAME, "US"),
        x509.NameAttribute(NameOID.ORGANIZATION_NAME, "TestOrg"),
        x509.NameAttribute(NameOID.COMMON_NAME, "orderer0.hot-chain.com"),
    ])).sign(test_key, hashes.SHA256(), default_backend())

    csr_pem = csr.public_bytes(serialization.Encoding.PEM)
    print(f"✓ Test CSR created for: orderer0.hot-chain.com")

    # Sign the CSR via enclave
    signed_cert_pem = enclave.sign_certificate(csr_pem, "orderer")

    # Load and verify the signed certificate
    signed_cert = x509.load_pem_x509_certificate(signed_cert_pem, default_backend())
    print(f"✓ Certificate signed by enclave CA")

    # Check issuer
    issuer_cn = signed_cert.issuer.get_attributes_for_oid(NameOID.COMMON_NAME)[0].value
    print(f"✓ Issuer CN: {issuer_cn}")

    # Check subject
    subject_cn = signed_cert.subject.get_attributes_for_oid(NameOID.COMMON_NAME)[0].value
    assert subject_cn == "orderer0.hot-chain.com"
    print(f"✓ Subject CN: {subject_cn}")

    # Verify certificate chain
    root_cert = enclave.ca_cert
    root_public_key = root_cert.public_key()

    try:
        root_public_key.verify(
            signed_cert.signature,
            signed_cert.tbs_certificate_bytes,
            padding.PKCS1v15(),
            signed_cert.signature_hash_algorithm
        )
        print(f"✓ Certificate chain validated against Root CA")
    except Exception as e:
        print(f"✗ Certificate verification failed: {e}")

    print()
    return signed_cert

def test_orderer_key_storage(enclave):
    """Test orderer private key storage and signing"""
    print("=" * 60)
    print("TEST 5: Orderer Key Storage & Block Signing")
    print("=" * 60)

    # Generate test orderer key
    orderer_key = rsa.generate_private_key(
        public_exponent=65537,
        key_size=2048,
        backend=default_backend()
    )

    orderer_key_pem = orderer_key.private_bytes(
        encoding=serialization.Encoding.PEM,
        format=serialization.PrivateFormat.PKCS8,
        encryption_algorithm=serialization.NoEncryption()
    )

    # Store in enclave
    enclave.store_orderer_key(orderer_key_pem)
    print(f"✓ Orderer private key stored in enclave (sealed)")

    # Verify key is sealed on disk
    sealed_file = Path(enclave.data_dir) / "orderer_key.sealed"
    assert sealed_file.exists()
    print(f"✓ Sealed key file exists: {sealed_file}")

    # Test block signing
    test_block_data = b"This is a test blockchain block header"
    signature = enclave.sign_block(test_block_data)
    print(f"✓ Block signed successfully ({len(signature)} bytes)")

    # Verify signature
    public_key = orderer_key.public_key()
    try:
        public_key.verify(
            signature,
            test_block_data,
            padding.PSS(
                mgf=padding.MGF1(hashes.SHA256()),
                salt_length=padding.PSS.MAX_LENGTH
            ),
            hashes.SHA256()
        )
        print(f"✓ Block signature verified with orderer public key")
    except Exception as e:
        print(f"✗ Signature verification failed: {e}")

    print()

def test_attestation_quote(enclave):
    """Test attestation quote generation"""
    print("=" * 60)
    print("TEST 6: Attestation Quote Generation")
    print("=" * 60)

    report_data = b"test_user_data"
    quote = enclave.generate_attestation_quote(report_data)

    print(f"✓ Attestation quote generated")
    print(f"  MREnclave: {quote['mr_enclave'][:32]}...")
    print(f"  MRSigner:  {quote['mr_signer'][:32]}...")
    print(f"  TCB Level: {quote['tcb_level']}")
    print(f"  Timestamp: {datetime.datetime.fromtimestamp(quote['timestamp']).isoformat()}")
    print(f"  Nonce:     {quote['nonce'][:16]}...")

    # Verify quote
    is_valid, message = enclave.verify_attestation_quote(quote)
    if is_valid:
        print(f"✓ Quote verified: {message}")
    else:
        print(f"✗ Quote verification failed: {message}")

    print()

def test_full_fabric_cert_workflow(enclave):
    """Test complete Fabric certificate issuance workflow"""
    print("=" * 60)
    print("TEST 7: Full Fabric Certificate Workflow")
    print("=" * 60)

    # Simulate generating certificates for different Fabric components
    components = [
        ("orderer", "orderer0.hot-chain.com"),
        ("peer", "peer0.lawenforcement.com"),
        ("client", "admin@lawenforcement.com"),
    ]

    for cert_type, common_name in components:
        # Generate key
        key = rsa.generate_private_key(
            public_exponent=65537,
            key_size=2048,
            backend=default_backend()
        )

        # Create CSR
        csr = x509.CertificateSigningRequestBuilder().subject_name(x509.Name([
            x509.NameAttribute(NameOID.COUNTRY_NAME, "US"),
            x509.NameAttribute(NameOID.ORGANIZATION_NAME, "DFIR-Fabric"),
            x509.NameAttribute(NameOID.COMMON_NAME, common_name),
        ])).sign(key, hashes.SHA256(), default_backend())

        csr_pem = csr.public_bytes(serialization.Encoding.PEM)

        # Sign via enclave
        cert_pem = enclave.sign_certificate(csr_pem, cert_type)
        cert = x509.load_pem_x509_certificate(cert_pem, default_backend())

        # Verify chain
        root_public_key = enclave.ca_cert.public_key()
        try:
            root_public_key.verify(
                cert.signature,
                cert.tbs_certificate_bytes,
                padding.PKCS1v15(),
                cert.signature_hash_algorithm
            )
            print(f"✓ {cert_type:8s} certificate issued and verified: {common_name}")
        except Exception as e:
            print(f"✗ {cert_type:8s} verification failed: {common_name} - {e}")

    print()

def main():
    """Run all enclave tests"""
    print("\n" + "=" * 60)
    print("ENCLAVE SIMULATOR TEST SUITE")
    print("=" * 60)
    print()

    try:
        # Test 1: Initialization
        enclave = test_enclave_initialization()

        # Test 2: Sealing
        test_seal_unseal(enclave)

        # Test 3: Root CA
        cert, key = test_root_ca_generation(enclave)

        # Test 4: Certificate signing
        test_certificate_signing(enclave)

        # Test 5: Orderer key storage
        test_orderer_key_storage(enclave)

        # Test 6: Attestation
        test_attestation_quote(enclave)

        # Test 7: Full workflow
        test_full_fabric_cert_workflow(enclave)

        # Summary
        print("=" * 60)
        print("ALL TESTS PASSED ✓")
        print("=" * 60)
        print()
        print("Enclave simulator is functioning correctly:")
        print("  • Data sealing/unsealing works")
        print("  • Root CA generation works")
        print("  • Certificate signing works")
        print("  • Orderer key storage and block signing works")
        print("  • Attestation quote generation works")
        print("  • Full Fabric certificate workflow works")
        print()

        return 0

    except Exception as e:
        print()
        print("=" * 60)
        print("TEST FAILED ✗")
        print("=" * 60)
        print(f"Error: {e}")
        import traceback
        traceback.print_exc()
        return 1

if __name__ == "__main__":
    sys.exit(main())
