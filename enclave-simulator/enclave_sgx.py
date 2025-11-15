#!/usr/bin/env python3
"""
Software SGX Enclave Simulator
================================
Simulates Intel SGX Trusted Execution Environment with:
- Secure enclave memory isolation
- Sealed storage (encrypted with CPU-derived keys)
- MRENCLAVE/MRSIGNER measurements
- Remote attestation with quote generation
- Orderer private key management
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
from cryptography.hazmat.primitives.ciphers.aead import AESGCM
from cryptography.hazmat.primitives.kdf.hkdf import HKDF

# SGX Enclave Configuration
SGX_CONFIG = {
    "enclave_name": "DFIR-SGX-Enclave",
    "enclave_version": "2.0.0",
    "product_id": 1,
    "security_version": 1,
    "debug_mode": False,  # Production mode
}

# Simulated CPU-protected keys (in real SGX, these come from CPU fuses)
CPU_ROOT_KEY = hashlib.sha256(b"SGX-CPU-ROOT-SEAL-KEY-SIMULATION").digest()

# Enclave measurements (computed from enclave binary hash)
ENCLAVE_CODE = b"DFIR-SGX-Enclave-Code-v2.0.0-Production"
ENCLAVE_SIGNER_PUBKEY = b"DFIR-SGX-Signer-Public-Key"

class SGXEnclave:
    """Simulates Intel SGX Enclave with sealing and attestation"""

    def __init__(self, data_dir: str = "/enclave-data"):
        """Initialize SGX enclave simulator"""
        self.data_dir = Path(data_dir)
        self.data_dir.mkdir(parents=True, exist_ok=True)

        # Compute enclave measurements (MRENCLAVE = SHA256 of enclave code)
        self.mrenclave = hashlib.sha256(ENCLAVE_CODE).digest()
        self.mrsigner = hashlib.sha256(ENCLAVE_SIGNER_PUBKEY).digest()

        # Derive sealing key from CPU root key + enclave identity
        self.sealing_key = self._derive_seal_key()

        # Enclave secure memory (simulated protected memory)
        self._secure_memory = {
            "root_ca_key": None,
            "root_ca_cert": None,
            "orderer_hot_key": None,
            "orderer_cold_key": None,
            "attestation_key": None,
        }

        # Generate attestation key pair (for signing quotes)
        self._attestation_key = rsa.generate_private_key(
            public_exponent=65537,
            key_size=3072,
            backend=default_backend()
        )

        print(f"✓ SGX Enclave initialized")
        print(f"  MRENCLAVE: {self.mrenclave.hex()[:32]}...")
        print(f"  MRSIGNER:  {self.mrsigner.hex()[:32]}...")
        print(f"  Security Version: {SGX_CONFIG['security_version']}")

    def _derive_seal_key(self) -> bytes:
        """
        Derive sealing key using HKDF
        In real SGX: EGETKEY instruction derives key from CPU fuses + MRENCLAVE
        """
        hkdf = HKDF(
            algorithm=hashes.SHA256(),
            length=32,
            salt=self.mrenclave[:16],
            info=b"SGX-SEAL-KEY",
            backend=default_backend()
        )
        return hkdf.derive(CPU_ROOT_KEY)

    def seal_data(self, data: bytes) -> bytes:
        """
        Seal (encrypt) data using enclave sealing key
        Uses AES-256-GCM for authenticated encryption
        In real SGX: Data can only be unsealed by same enclave
        """
        aesgcm = AESGCM(self.sealing_key)
        nonce = os.urandom(12)  # 96-bit nonce for GCM

        # Additional authenticated data includes enclave measurements
        aad = self.mrenclave + self.mrsigner

        ciphertext = aesgcm.encrypt(nonce, data, aad)

        # Return nonce + ciphertext
        return nonce + ciphertext

    def unseal_data(self, sealed_data: bytes) -> bytes:
        """
        Unseal (decrypt) data using enclave sealing key
        Only this enclave (with matching MRENCLAVE) can unseal
        """
        nonce = sealed_data[:12]
        ciphertext = sealed_data[12:]

        aesgcm = AESGCM(self.sealing_key)
        aad = self.mrenclave + self.mrsigner

        try:
            plaintext = aesgcm.decrypt(nonce, ciphertext, aad)
            return plaintext
        except Exception as e:
            raise ValueError(f"Unseal failed - wrong enclave or corrupted data: {e}")

    def generate_root_ca(self) -> Tuple[bytes, bytes]:
        """
        Generate Root CA inside enclave
        Private key NEVER leaves enclave (stays in secure memory)
        """
        # Generate key pair inside enclave
        private_key = rsa.generate_private_key(
            public_exponent=65537,
            key_size=4096,
            backend=default_backend()
        )

        # Create self-signed Root CA certificate
        subject = issuer = x509.Name([
            x509.NameAttribute(NameOID.COUNTRY_NAME, "US"),
            x509.NameAttribute(NameOID.STATE_OR_PROVINCE_NAME, "California"),
            x509.NameAttribute(NameOID.LOCALITY_NAME, "San Francisco"),
            x509.NameAttribute(NameOID.ORGANIZATION_NAME, "DFIR Blockchain Root CA"),
            x509.NameAttribute(NameOID.ORGANIZATIONAL_UNIT_NAME, "SGX Enclave"),
            x509.NameAttribute(NameOID.COMMON_NAME, "DFIR SGX Root CA"),
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
                x509.BasicConstraints(ca=True, path_length=2),
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
            .sign(private_key, hashes.SHA256(), backend=default_backend())
        )

        # Store private key in secure enclave memory (NEVER export)
        self._secure_memory["root_ca_key"] = private_key
        self._secure_memory["root_ca_cert"] = cert

        # Seal private key to persistent storage
        key_pem = private_key.private_bytes(
            encoding=serialization.Encoding.PEM,
            format=serialization.PrivateFormat.PKCS8,
            encryption_algorithm=serialization.NoEncryption()
        )
        sealed_key = self.seal_data(key_pem)

        # Save sealed key and public cert
        sealed_key_file = self.data_dir / "root_ca_key.sealed"
        cert_file = self.data_dir / "root_ca_cert.pem"

        sealed_key_file.write_bytes(sealed_key)
        cert_file.write_bytes(cert.public_bytes(serialization.Encoding.PEM))

        print(f"✓ Root CA generated inside enclave")
        print(f"  Private key sealed to: {sealed_key_file}")
        print(f"  Certificate: {cert_file}")

        return (
            cert.public_bytes(serialization.Encoding.PEM),
            sealed_key
        )

    def load_sealed_root_ca(self) -> bool:
        """Load sealed Root CA key from storage"""
        sealed_key_file = self.data_dir / "root_ca_key.sealed"
        cert_file = self.data_dir / "root_ca_cert.pem"

        if not sealed_key_file.exists() or not cert_file.exists():
            return False

        # Unseal private key
        sealed_data = sealed_key_file.read_bytes()
        key_pem = self.unseal_data(sealed_data)

        private_key = serialization.load_pem_private_key(
            key_pem,
            password=None,
            backend=default_backend()
        )

        # Load certificate
        cert_pem = cert_file.read_bytes()
        cert = x509.load_pem_x509_certificate(cert_pem, backend=default_backend())

        # Store in secure memory
        self._secure_memory["root_ca_key"] = private_key
        self._secure_memory["root_ca_cert"] = cert

        print(f"✓ Root CA loaded into enclave secure memory")
        return True

    def sign_certificate(self, csr_pem: str, cert_type: str = "intermediate",
                        validity_days: int = 365) -> bytes:
        """
        Sign certificate using Root CA private key inside enclave
        Private key NEVER leaves enclave
        """
        if self._secure_memory["root_ca_key"] is None:
            raise ValueError("Root CA not initialized in enclave")

        # Parse CSR
        csr = x509.load_pem_x509_csr(csr_pem.encode(), backend=default_backend())

        # Verify CSR signature
        if not csr.is_signature_valid:
            raise ValueError("Invalid CSR signature")

        # Determine certificate extensions based on type
        if cert_type == "intermediate":
            path_length = 1
            key_usage = x509.KeyUsage(
                digital_signature=True,
                key_cert_sign=True,
                crl_sign=True,
                key_encipherment=False,
                content_commitment=False,
                data_encipherment=False,
                key_agreement=False,
                encipher_only=False,
                decipher_only=False,
            )
        elif cert_type == "peer":
            path_length = None
            key_usage = x509.KeyUsage(
                digital_signature=True,
                key_encipherment=True,
                key_cert_sign=False,
                crl_sign=False,
                content_commitment=False,
                data_encipherment=False,
                key_agreement=False,
                encipher_only=False,
                decipher_only=False,
            )
        else:  # client, orderer, etc.
            path_length = None
            key_usage = x509.KeyUsage(
                digital_signature=True,
                key_encipherment=True,
                key_cert_sign=False,
                crl_sign=False,
                content_commitment=False,
                data_encipherment=False,
                key_agreement=False,
                encipher_only=False,
                decipher_only=False,
            )

        # Build certificate
        cert_builder = (
            x509.CertificateBuilder()
            .subject_name(csr.subject)
            .issuer_name(self._secure_memory["root_ca_cert"].subject)
            .public_key(csr.public_key())
            .serial_number(x509.random_serial_number())
            .not_valid_before(datetime.utcnow())
            .not_valid_after(datetime.utcnow() + timedelta(days=validity_days))
        )

        # Add extensions
        if path_length is not None:
            cert_builder = cert_builder.add_extension(
                x509.BasicConstraints(ca=True, path_length=path_length),
                critical=True,
            )
        else:
            cert_builder = cert_builder.add_extension(
                x509.BasicConstraints(ca=False, path_length=None),
                critical=True,
            )

        cert_builder = cert_builder.add_extension(key_usage, critical=True)

        # Add Subject Alternative Names from CSR if present
        try:
            san_ext = csr.extensions.get_extension_for_oid(ExtensionOID.SUBJECT_ALTERNATIVE_NAME)
            cert_builder = cert_builder.add_extension(san_ext.value, critical=False)
        except x509.ExtensionNotFound:
            pass

        # Sign with Root CA key (inside enclave)
        cert = cert_builder.sign(
            self._secure_memory["root_ca_key"],
            hashes.SHA256(),
            backend=default_backend()
        )

        return cert.public_bytes(serialization.Encoding.PEM)

    def generate_orderer_key(self, chain: str = "hot") -> Tuple[bytes, bytes]:
        """
        Generate orderer private key inside enclave
        Key is sealed and NEVER exposed in plaintext outside enclave
        """
        # Generate key pair inside enclave
        private_key = rsa.generate_private_key(
            public_exponent=65537,
            key_size=2048,
            backend=default_backend()
        )

        # Store in secure memory
        key_name = f"orderer_{chain}_key"
        self._secure_memory[key_name] = private_key

        # Seal private key
        key_pem = private_key.private_bytes(
            encoding=serialization.Encoding.PEM,
            format=serialization.PrivateFormat.PKCS8,
            encryption_algorithm=serialization.NoEncryption()
        )
        sealed_key = self.seal_data(key_pem)

        # Save sealed key
        sealed_key_file = self.data_dir / f"orderer_{chain}_key.sealed"
        sealed_key_file.write_bytes(sealed_key)

        # Export public key only
        public_key_pem = private_key.public_key().public_bytes(
            encoding=serialization.Encoding.PEM,
            format=serialization.PublicFormat.SubjectPublicKeyInfo
        )

        print(f"✓ Orderer {chain} key generated and sealed in enclave")

        return (public_key_pem, sealed_key)

    def generate_attestation_quote(self, user_data: bytes = b"") -> Dict:
        """
        Generate SGX attestation quote
        In production: Would contact Intel Attestation Service (IAS)
        This simulates the quote generation process
        """
        # Quote body contains enclave measurements
        quote_body = {
            "version": 3,
            "sign_type": 1,  # EPID linkable signature
            "mrenclave": self.mrenclave.hex(),
            "mrsigner": self.mrsigner.hex(),
            "product_id": SGX_CONFIG["product_id"],
            "security_version": SGX_CONFIG["security_version"],
            "attributes": {
                "debug": SGX_CONFIG["debug_mode"],
                "mode64bit": True,
            },
            "report_data": hashlib.sha256(user_data).hexdigest(),
            "timestamp": datetime.utcnow().isoformat(),
        }

        # Sign quote with attestation key
        quote_json = json.dumps(quote_body, sort_keys=True).encode()
        quote_hash = hashlib.sha256(quote_json).digest()

        signature = self._attestation_key.sign(
            quote_hash,
            padding.PSS(
                mgf=padding.MGF1(hashes.SHA256()),
                salt_length=padding.PSS.MAX_LENGTH
            ),
            hashes.SHA256()
        )

        # Attestation public key for verification
        attestation_pubkey = self._attestation_key.public_key().public_bytes(
            encoding=serialization.Encoding.PEM,
            format=serialization.PublicFormat.SubjectPublicKeyInfo
        )

        return {
            "quote": quote_body,
            "signature": base64.b64encode(signature).decode(),
            "attestation_public_key": attestation_pubkey.decode(),
        }

    def get_info(self) -> Dict:
        """Get enclave information and status"""
        return {
            "enclave_name": SGX_CONFIG["enclave_name"],
            "version": SGX_CONFIG["enclave_version"],
            "mrenclave": self.mrenclave.hex(),
            "mrsigner": self.mrsigner.hex(),
            "security_version": SGX_CONFIG["security_version"],
            "debug_mode": SGX_CONFIG["debug_mode"],
            "root_ca_initialized": self._secure_memory["root_ca_key"] is not None,
            "sealed_keys": [
                f.name for f in self.data_dir.glob("*.sealed")
            ],
        }
