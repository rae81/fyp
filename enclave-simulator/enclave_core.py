#!/usr/bin/env python3
"""
Enclave Core Module - Flask-independent
Contains the core EnclaveSimulator class for testing
"""

import os
import json
import hashlib
import secrets
import base64
from datetime import datetime, timedelta
from typing import Dict, Optional, Tuple
from pathlib import Path

from cryptography import x509
from cryptography.x509.oid import NameOID, ExtensionOID
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import rsa, padding
from cryptography.hazmat.backends import default_backend
from cryptography.hazmat.primitives.ciphers import Cipher, algorithms, modes
from cryptography.hazmat.primitives.kdf.pbkdf2 import PBKDF2HMAC

# Enclave configuration
ENCLAVE_CONFIG = {
    "name": "DFIR-Enclave-Simulator",
    "version": "1.0.0",
    "mr_enclave": None,  # Will be generated
    "mr_signer": None,   # Will be generated
    "tcb_level": "1",
    "sealing_key": None  # Encryption key for stored keys
}

# Persistent storage paths
ENCLAVE_DATA_DIR = os.environ.get("ENCLAVE_DATA_DIR", "/tmp/enclave-data")
Path(ENCLAVE_DATA_DIR).mkdir(parents=True, exist_ok=True)

ROOT_CA_KEY_FILE = Path(ENCLAVE_DATA_DIR) / "root_ca_key.sealed"
ROOT_CA_CERT_FILE = Path(ENCLAVE_DATA_DIR) / "root_ca_cert.pem"
ORDERER_KEY_FILE = Path(ENCLAVE_DATA_DIR) / "orderer_key.sealed"

# Enclave memory (simulated secure memory)
ENCLAVE_MEMORY = {
    "root_ca_key": None,
    "root_ca_cert": None,
    "orderer_key": None,
}

class EnclaveSimulator:
    """Simulates a Trusted Execution Environment"""

    def __init__(self):
        """Initialize the enclave simulator"""
        self.data_dir = ENCLAVE_DATA_DIR

        # Generate enclave measurements (simulating SGX MRENCLAVE/MRSIGNER)
        if ENCLAVE_CONFIG["mr_enclave"] is None:
            ENCLAVE_CONFIG["mr_enclave"] = hashlib.sha256(b"DFIR-Enclave-Code-v1.0.0").hexdigest()
            ENCLAVE_CONFIG["mr_signer"] = hashlib.sha256(b"DFIR-Enclave-Signer-Key").hexdigest()

        # Derive sealing key from enclave measurements
        self.sealing_key = self._derive_sealing_key()

        print(f"✓ Enclave simulator initialized")
        print(f"  MREnclave: {ENCLAVE_CONFIG['mr_enclave'][:32]}...")
        print(f"  MRSigner:  {ENCLAVE_CONFIG['mr_signer'][:32]}...")

    def _derive_sealing_key(self) -> bytes:
        """
        Derive sealing key from enclave measurements
        In real SGX, this would use CPU-protected keys
        """
        kdf = PBKDF2HMAC(
            algorithm=hashes.SHA256(),
            length=32,  # 256-bit key
            salt=ENCLAVE_CONFIG["mr_enclave"].encode()[:16],
            iterations=100000,
            backend=default_backend()
        )
        return kdf.derive(b"enclave-sealing-key-simulation")

    def seal_data(self, data: bytes) -> bytes:
        """
        Seal (encrypt) data using enclave sealing key
        In real SGX, this uses EGETKEY instruction
        """
        iv = os.urandom(16)
        cipher = Cipher(
            algorithms.AES(self.sealing_key),
            modes.CBC(iv),
            backend=default_backend()
        )
        encryptor = cipher.encryptor()

        # Pad data to block size
        block_size = 16
        padding_length = block_size - (len(data) % block_size)
        padded_data = data + bytes([padding_length] * padding_length)

        encrypted = encryptor.update(padded_data) + encryptor.finalize()
        return iv + encrypted

    def unseal_data(self, sealed_data: bytes) -> bytes:
        """
        Unseal (decrypt) data using enclave sealing key
        """
        iv = sealed_data[:16]
        encrypted = sealed_data[16:]

        cipher = Cipher(
            algorithms.AES(self.sealing_key),
            modes.CBC(iv),
            backend=default_backend()
        )
        decryptor = cipher.decryptor()
        padded_data = decryptor.update(encrypted) + decryptor.finalize()

        # Remove padding
        padding_length = padded_data[-1]
        return padded_data[:-padding_length]

    def generate_root_ca(self) -> Tuple[x509.Certificate, rsa.RSAPrivateKey]:
        """
        Generate Root CA certificate and private key inside enclave
        Private key NEVER leaves enclave unencrypted
        """
        print("  Generating 4096-bit RSA key pair (this may take a moment)...")

        # Generate private key
        private_key = rsa.generate_private_key(
            public_exponent=65537,
            key_size=4096,
            backend=default_backend()
        )

        # Build certificate
        subject = issuer = x509.Name([
            x509.NameAttribute(NameOID.COUNTRY_NAME, "US"),
            x509.NameAttribute(NameOID.STATE_OR_PROVINCE_NAME, "Virginia"),
            x509.NameAttribute(NameOID.LOCALITY_NAME, "Reston"),
            x509.NameAttribute(NameOID.ORGANIZATION_NAME, "DFIR-Fabric-Enclave"),
            x509.NameAttribute(NameOID.COMMON_NAME, "Fabric Enclave Root CA"),
        ])

        cert = (
            x509.CertificateBuilder()
            .subject_name(subject)
            .issuer_name(issuer)
            .public_key(private_key.public_key())
            .serial_number(x509.random_serial_number())
            .not_valid_before(datetime.utcnow())
            .not_valid_after(datetime.utcnow() + timedelta(days=3650))  # 10 years
            .add_extension(
                x509.BasicConstraints(ca=True, path_length=None),
                critical=True,
            )
            .add_extension(
                x509.KeyUsage(
                    digital_signature=True,
                    key_cert_sign=True,
                    crl_sign=True,
                    key_encipherment=False,
                    content_commitment=False,
                    data_encipherment=False,
                    key_agreement=False,
                    encipher_only=False,
                    decipher_only=False,
                ),
                critical=True,
            )
            .add_extension(
                x509.SubjectKeyIdentifier.from_public_key(private_key.public_key()),
                critical=False,
            )
            .sign(private_key, hashes.SHA256(), default_backend())
        )

        # Seal private key to disk
        key_pem = private_key.private_bytes(
            encoding=serialization.Encoding.PEM,
            format=serialization.PrivateFormat.PKCS8,
            encryption_algorithm=serialization.NoEncryption()
        )
        sealed_key = self.seal_data(key_pem)
        ROOT_CA_KEY_FILE.write_bytes(sealed_key)

        # Store certificate (public, no need to seal)
        cert_pem = cert.public_bytes(serialization.Encoding.PEM)
        ROOT_CA_CERT_FILE.write_bytes(cert_pem)

        # Load into enclave memory
        ENCLAVE_MEMORY["root_ca_key"] = private_key
        ENCLAVE_MEMORY["root_ca_cert"] = cert

        self.ca_key = private_key
        self.ca_cert = cert

        print(f"  ✓ Root CA generated and sealed")
        print(f"    Serial: {hex(cert.serial_number)}")
        # Handle both old and new cryptography API
        try:
            print(f"    Valid: {cert.not_valid_before_utc.date()} to {cert.not_valid_after_utc.date()}")
        except AttributeError:
            print(f"    Valid: {cert.not_valid_before.date()} to {cert.not_valid_after.date()}")

        return cert, private_key

    def load_root_ca(self):
        """Load Root CA from sealed storage"""
        # Load private key
        sealed_key = ROOT_CA_KEY_FILE.read_bytes()
        key_pem = self.unseal_data(sealed_key)
        private_key = serialization.load_pem_private_key(
            key_pem,
            password=None,
            backend=default_backend()
        )

        # Load certificate
        cert_pem = ROOT_CA_CERT_FILE.read_bytes()
        cert = x509.load_pem_x509_certificate(cert_pem, default_backend())

        # Store in enclave memory
        ENCLAVE_MEMORY["root_ca_key"] = private_key
        ENCLAVE_MEMORY["root_ca_cert"] = cert

        self.ca_key = private_key
        self.ca_cert = cert

    def sign_certificate(self, csr_pem: bytes, cert_type: str) -> bytes:
        """
        Sign a CSR with Root CA
        cert_type: peer, orderer, client, intermediate-ca
        """
        # Ensure Root CA is loaded
        if not ENCLAVE_MEMORY["root_ca_cert"]:
            self.load_root_ca()

        ca_key = ENCLAVE_MEMORY["root_ca_key"]
        ca_cert = ENCLAVE_MEMORY["root_ca_cert"]

        # Load CSR
        csr = x509.load_pem_x509_csr(csr_pem, default_backend())

        # Determine validity period based on type
        if cert_type == "intermediate-ca":
            validity_days = 1825  # 5 years
        elif cert_type == "orderer":
            validity_days = 825   # ~2 years
        else:
            validity_days = 365   # 1 year

        # Build certificate
        builder = (
            x509.CertificateBuilder()
            .subject_name(csr.subject)
            .issuer_name(ca_cert.subject)
            .public_key(csr.public_key())
            .serial_number(x509.random_serial_number())
            .not_valid_before(datetime.utcnow())
            .not_valid_after(datetime.utcnow() + timedelta(days=validity_days))
        )

        # Add extensions based on certificate type
        if cert_type == "intermediate-ca":
            builder = builder.add_extension(
                x509.BasicConstraints(ca=True, path_length=0),
                critical=True,
            )
            builder = builder.add_extension(
                x509.KeyUsage(
                    digital_signature=True,
                    key_cert_sign=True,
                    crl_sign=True,
                    key_encipherment=False,
                    content_commitment=False,
                    data_encipherment=False,
                    key_agreement=False,
                    encipher_only=False,
                    decipher_only=False,
                ),
                critical=True,
            )
        elif cert_type in ["peer", "orderer"]:
            builder = builder.add_extension(
                x509.BasicConstraints(ca=False, path_length=None),
                critical=True,
            )
            builder = builder.add_extension(
                x509.KeyUsage(
                    digital_signature=True,
                    key_encipherment=True,
                    key_cert_sign=False,
                    crl_sign=False,
                    content_commitment=False,
                    data_encipherment=False,
                    key_agreement=False,
                    encipher_only=False,
                    decipher_only=False,
                ),
                critical=True,
            )
        else:  # client
            builder = builder.add_extension(
                x509.BasicConstraints(ca=False, path_length=None),
                critical=True,
            )
            builder = builder.add_extension(
                x509.KeyUsage(
                    digital_signature=True,
                    key_encipherment=False,
                    key_cert_sign=False,
                    crl_sign=False,
                    content_commitment=False,
                    data_encipherment=False,
                    key_agreement=False,
                    encipher_only=False,
                    decipher_only=False,
                ),
                critical=True,
            )

        # Add SubjectKeyIdentifier (required by Fabric)
        builder = builder.add_extension(
            x509.SubjectKeyIdentifier.from_public_key(csr.public_key()),
            critical=False,
        )

        # Add AuthorityKeyIdentifier (required by Fabric)
        builder = builder.add_extension(
            x509.AuthorityKeyIdentifier.from_issuer_public_key(ca_key.public_key()),
            critical=False,
        )

        # Sign certificate
        cert = builder.sign(ca_key, hashes.SHA256(), default_backend())

        return cert.public_bytes(serialization.Encoding.PEM)

    def store_orderer_key(self, key_pem: bytes):
        """
        Store orderer private key in enclave (sealed)
        """
        # Seal the key
        sealed_key = self.seal_data(key_pem)
        ORDERER_KEY_FILE.write_bytes(sealed_key)

        # Load into enclave memory
        private_key = serialization.load_pem_private_key(
            key_pem,
            password=None,
            backend=default_backend()
        )
        ENCLAVE_MEMORY["orderer_key"] = private_key

        print("  ✓ Orderer private key stored in enclave")

    def sign_block(self, block_data: bytes) -> bytes:
        """
        Sign a block using orderer private key
        This is called by the orderer for each block
        """
        if not ENCLAVE_MEMORY["orderer_key"]:
            # Try to load from sealed storage
            if ORDERER_KEY_FILE.exists():
                sealed_key = ORDERER_KEY_FILE.read_bytes()
                key_pem = self.unseal_data(sealed_key)
                private_key = serialization.load_pem_private_key(
                    key_pem,
                    password=None,
                    backend=default_backend()
                )
                ENCLAVE_MEMORY["orderer_key"] = private_key
            else:
                raise Exception("Orderer key not found in enclave")

        orderer_key = ENCLAVE_MEMORY["orderer_key"]

        # Sign with PSS padding
        signature = orderer_key.sign(
            block_data,
            padding.PSS(
                mgf=padding.MGF1(hashes.SHA256()),
                salt_length=padding.PSS.MAX_LENGTH
            ),
            hashes.SHA256()
        )

        return signature

    def generate_attestation_quote(self, report_data: bytes = b"") -> Dict:
        """
        Generate mock SGX attestation quote
        In real SGX, this would be generated by CPU
        """
        quote = {
            "version": 3,
            "mr_enclave": ENCLAVE_CONFIG["mr_enclave"],
            "mr_signer": ENCLAVE_CONFIG["mr_signer"],
            "tcb_level": ENCLAVE_CONFIG["tcb_level"],
            "timestamp": int(datetime.utcnow().timestamp()),
            "nonce": secrets.token_hex(16),
            "report_data": base64.b64encode(report_data).decode() if report_data else "",
        }

        # Sign the quote (in real SGX, this is done by Intel QE)
        report_json = json.dumps(quote, sort_keys=True)
        quote["signature"] = hashlib.sha256(report_json.encode()).hexdigest()

        return quote

    def verify_attestation_quote(self, quote: Dict) -> Tuple[bool, str]:
        """
        Verify an attestation quote
        """
        # Check MREnclave
        if quote.get("mr_enclave") != ENCLAVE_CONFIG["mr_enclave"]:
            return False, "MREnclave mismatch"

        # Check MRSigner
        if quote.get("mr_signer") != ENCLAVE_CONFIG["mr_signer"]:
            return False, "MRSigner mismatch"

        # Check TCB level
        if quote.get("tcb_level") != ENCLAVE_CONFIG["tcb_level"]:
            return False, "TCB level mismatch"

        # Check timestamp (not too old)
        quote_time = datetime.fromtimestamp(quote.get("timestamp", 0))
        age = datetime.utcnow() - quote_time
        if age.total_seconds() > 300:  # 5 minutes
            return False, f"Quote too old ({age.total_seconds()}s)"

        return True, "Quote verified successfully"
