#!/usr/bin/env python3
"""
Software Enclave Simulator for Hyperledger Fabric
=================================================

This service simulates a Trusted Execution Environment (TEE) that:
1. Acts as the Root Certificate Authority (CA) for Fabric
2. Stores and manages the orderer private key
3. Provides block signing services for the orderer
4. Generates mock attestation quotes (simulating SGX)
5. Issues x.509 certificates for all Fabric components

Security Features (Simulated):
- Encrypted key storage
- Isolated key operations
- Attestation generation
- Certificate signing

Author: Claude AI
Date: 2025-11-11
"""

import os
import json
import hashlib
import secrets
import base64
from datetime import datetime, timedelta
from typing import Dict, Optional, Tuple
from pathlib import Path

try:
    from flask import Flask, request, jsonify
    FLASK_AVAILABLE = True
except ImportError:
    FLASK_AVAILABLE = False
    Flask = None
    request = None
    jsonify = None

from cryptography import x509
from cryptography.x509.oid import NameOID, ExtensionOID
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import rsa, padding
from cryptography.hazmat.backends import default_backend
from cryptography.hazmat.primitives.ciphers import Cipher, algorithms, modes
from cryptography.hazmat.primitives.kdf.pbkdf2 import PBKDF2HMAC

app = Flask(__name__) if FLASK_AVAILABLE else None

# Enclave configuration
ENCLAVE_CONFIG = {
    "name": "DFIR-Enclave-Simulator",
    "version": "1.0.0",
    "mr_enclave": None,  # Will be generated
    "mr_signer": None,   # Will be generated
    "tcb_level": "1",
    "sealing_key": None  # Encryption key for stored keys
}

# Storage paths
ENCLAVE_DATA_DIR = Path("/home/user/Dual-hyperledger-Blockchain/enclave-data")
ROOT_CA_KEY_FILE = ENCLAVE_DATA_DIR / "root-ca.key.enc"
ROOT_CA_CERT_FILE = ENCLAVE_DATA_DIR / "root-ca.crt"
ORDERER_KEY_FILE = ENCLAVE_DATA_DIR / "orderer.key.enc"
ATTESTATION_LOG_FILE = ENCLAVE_DATA_DIR / "attestation.log"
SEALED_KEYS_FILE = ENCLAVE_DATA_DIR / "sealed_keys.json.enc"

# In-memory key cache (simulates enclave memory)
ENCLAVE_MEMORY = {
    "root_ca_key": None,
    "root_ca_cert": None,
    "orderer_key": None,
    "sealed": False,
    "attestation_nonce": None
}

class EnclaveSimulator:
    """Simulates a Trusted Execution Environment"""

    def __init__(self):
        """Initialize the enclave simulator"""
        self.initialized = False
        self.sealing_key = None
        self._setup_enclave()

    def _setup_enclave(self):
        """Set up the enclave environment"""
        # Create data directory
        ENCLAVE_DATA_DIR.mkdir(parents=True, exist_ok=True)

        # Generate enclave measurements (simulating SGX)
        enclave_code = "DFIR-Enclave-Simulator-v1.0.0"
        ENCLAVE_CONFIG["mr_enclave"] = hashlib.sha256(enclave_code.encode()).hexdigest()
        ENCLAVE_CONFIG["mr_signer"] = hashlib.sha256(b"Claude-Signer").hexdigest()

        # Generate sealing key (for encrypting stored keys)
        self.sealing_key = self._derive_sealing_key()
        ENCLAVE_CONFIG["sealing_key"] = base64.b64encode(self.sealing_key).decode()

        print("✓ Enclave simulator initialized")
        print(f"  MREnclave: {ENCLAVE_CONFIG['mr_enclave'][:16]}...")
        print(f"  MRSigner:  {ENCLAVE_CONFIG['mr_signer'][:16]}...")

    def _derive_sealing_key(self) -> bytes:
        """Derive a sealing key (simulates SGX sealing key derivation)"""
        # In real SGX, this would be derived from CPU key + enclave measurement
        # For simulation, we use a deterministic key based on enclave identity
        kdf = PBKDF2HMAC(
            algorithm=hashes.SHA256(),
            length=32,
            salt=ENCLAVE_CONFIG["mr_enclave"].encode()[:16],
            iterations=100000,
            backend=default_backend()
        )
        return kdf.derive(b"enclave-sealing-key-simulation")

    def seal_data(self, data: bytes) -> bytes:
        """Seal (encrypt) data using enclave sealing key"""
        # Generate random IV
        iv = os.urandom(16)

        # Encrypt data
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

        # Return IV + encrypted data
        return iv + encrypted

    def unseal_data(self, sealed_data: bytes) -> bytes:
        """Unseal (decrypt) data using enclave sealing key"""
        # Extract IV and encrypted data
        iv = sealed_data[:16]
        encrypted = sealed_data[16:]

        # Decrypt data
        cipher = Cipher(
            algorithms.AES(self.sealing_key),
            modes.CBC(iv),
            backend=default_backend()
        )
        decryptor = cipher.decryptor()

        padded_data = decryptor.update(encrypted) + decryptor.finalize()

        # Remove padding
        padding_length = padded_data[-1]
        data = padded_data[:-padding_length]

        return data

    def generate_root_ca(self) -> Tuple[x509.Certificate, rsa.RSAPrivateKey]:
        """Generate Root CA certificate and key inside enclave"""
        print("Generating Root CA inside enclave...")

        # Generate private key
        private_key = rsa.generate_private_key(
            public_exponent=65537,
            key_size=4096,
            backend=default_backend()
        )

        # Create self-signed certificate
        subject = issuer = x509.Name([
            x509.NameAttribute(NameOID.COUNTRY_NAME, "US"),
            x509.NameAttribute(NameOID.STATE_OR_PROVINCE_NAME, "Secure Enclave"),
            x509.NameAttribute(NameOID.LOCALITY_NAME, "TEE"),
            x509.NameAttribute(NameOID.ORGANIZATION_NAME, "DFIR Blockchain System"),
            x509.NameAttribute(NameOID.ORGANIZATIONAL_UNIT_NAME, "Enclave Root CA"),
            x509.NameAttribute(NameOID.COMMON_NAME, "DFIR Enclave Root CA"),
        ])

        cert = x509.CertificateBuilder().subject_name(
            subject
        ).issuer_name(
            issuer
        ).public_key(
            private_key.public_key()
        ).serial_number(
            x509.random_serial_number()
        ).not_valid_before(
            datetime.utcnow()
        ).not_valid_after(
            datetime.utcnow() + timedelta(days=3650)  # 10 years
        ).add_extension(
            x509.BasicConstraints(ca=True, path_length=None),
            critical=True,
        ).add_extension(
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
        ).add_extension(
            x509.SubjectKeyIdentifier.from_public_key(private_key.public_key()),
            critical=False,
        ).sign(private_key, hashes.SHA256(), default_backend())

        # Store in enclave memory
        ENCLAVE_MEMORY["root_ca_key"] = private_key
        ENCLAVE_MEMORY["root_ca_cert"] = cert

        # Seal and persist to disk
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

        print("✓ Root CA generated and sealed in enclave")
        return cert, private_key

    def load_root_ca(self) -> Tuple[x509.Certificate, rsa.RSAPrivateKey]:
        """Load Root CA from sealed storage"""
        if not ROOT_CA_KEY_FILE.exists():
            raise FileNotFoundError("Root CA not initialized")

        # Unseal private key
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

        return cert, private_key

    def sign_certificate(self, csr_pem: bytes, cert_type: str = "peer") -> bytes:
        """Sign a certificate signing request"""
        # Load CSR
        csr = x509.load_pem_x509_csr(csr_pem, default_backend())

        # Get Root CA
        ca_cert = ENCLAVE_MEMORY["root_ca_cert"]
        ca_key = ENCLAVE_MEMORY["root_ca_key"]

        if not ca_cert or not ca_key:
            raise RuntimeError("Root CA not loaded")

        # Determine validity period and extensions based on cert type
        if cert_type == "intermediate-ca":
            validity_days = 1825  # 5 years
            path_length = 0
            basic_constraints = x509.BasicConstraints(ca=True, path_length=path_length)
        else:
            validity_days = 825  # ~2 years
            basic_constraints = x509.BasicConstraints(ca=False, path_length=None)

        # Build certificate
        cert = x509.CertificateBuilder().subject_name(
            csr.subject
        ).issuer_name(
            ca_cert.subject
        ).public_key(
            csr.public_key()
        ).serial_number(
            x509.random_serial_number()
        ).not_valid_before(
            datetime.utcnow()
        ).not_valid_after(
            datetime.utcnow() + timedelta(days=validity_days)
        ).add_extension(
            basic_constraints,
            critical=True,
        )

        # Copy SAN extension from CSR if present
        try:
            san_ext = csr.extensions.get_extension_for_oid(x509.oid.ExtensionOID.SUBJECT_ALTERNATIVE_NAME)
            cert = cert.add_extension(san_ext.value, critical=False)
        except x509.ExtensionNotFound:
            pass  # No SAN in CSR, that's okay

        # Add key usage based on type
        if cert_type == "orderer":
            cert = cert.add_extension(
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
        elif cert_type == "peer":
            cert = cert.add_extension(
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
        elif cert_type == "client":
            cert = cert.add_extension(
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

        # Sign certificate
        signed_cert = cert.sign(ca_key, hashes.SHA256(), default_backend())

        return signed_cert.public_bytes(serialization.Encoding.PEM)

    def store_orderer_key(self, key_pem: bytes):
        """Store orderer private key in enclave (sealed)"""
        sealed_key = self.seal_data(key_pem)
        ORDERER_KEY_FILE.write_bytes(sealed_key)

        # Load into memory
        private_key = serialization.load_pem_private_key(
            key_pem,
            password=None,
            backend=default_backend()
        )
        ENCLAVE_MEMORY["orderer_key"] = private_key

        print("✓ Orderer private key stored in enclave")

    def sign_block(self, block_data: bytes) -> bytes:
        """Sign a block for the orderer"""
        orderer_key = ENCLAVE_MEMORY.get("orderer_key")
        if not orderer_key:
            raise RuntimeError("Orderer key not loaded")

        # Sign the block
        signature = orderer_key.sign(
            block_data,
            padding.PSS(
                mgf=padding.MGF1(hashes.SHA256()),
                salt_length=padding.PSS.MAX_LENGTH
            ),
            hashes.SHA256()
        )

        return signature

    def generate_attestation_quote(self) -> Dict:
        """Generate a mock attestation quote (simulates SGX EREPORT)"""
        # Generate nonce
        nonce = secrets.token_hex(16)
        ENCLAVE_MEMORY["attestation_nonce"] = nonce

        # Create attestation report
        report_data = {
            "mr_enclave": ENCLAVE_CONFIG["mr_enclave"],
            "mr_signer": ENCLAVE_CONFIG["mr_signer"],
            "tcb_level": ENCLAVE_CONFIG["tcb_level"],
            "timestamp": int(datetime.utcnow().timestamp()),
            "nonce": nonce,
            "attributes": {
                "root_ca": "active",
                "orderer_key": "sealed",
                "version": ENCLAVE_CONFIG["version"]
            }
        }

        # Sign the report (simulating Intel's signing)
        report_json = json.dumps(report_data, sort_keys=True)
        signature = hashlib.sha256(report_json.encode()).hexdigest()

        quote = {
            "version": 2,
            "sign_type": 1,  # Unlinkable signature
            "report_body": report_data,
            "signature": signature,
            "quote_type": "simulation"
        }

        # Log attestation
        log_entry = {
            "timestamp": datetime.utcnow().isoformat(),
            "nonce": nonce,
            "mr_enclave": ENCLAVE_CONFIG["mr_enclave"][:16] + "...",
            "signature": signature[:16] + "..."
        }

        with open(ATTESTATION_LOG_FILE, "a") as f:
            f.write(json.dumps(log_entry) + "\n")

        return quote

# Initialize enclave
enclave = EnclaveSimulator()

# ============================================================================
# REST API Endpoints (only if Flask is available)
# ============================================================================

def _define_routes():
    """Define Flask routes - only called if Flask is available"""
    @app.route('/health', methods=['GET'])
    def health():
        """Health check endpoint"""
        return jsonify({
            "status": "healthy",
            "enclave": "running",
            "version": ENCLAVE_CONFIG["version"]
        })

    @app.route('/enclave/info', methods=['GET'])
def enclave_info():
    """Get enclave information"""
    return jsonify({
        "name": ENCLAVE_CONFIG["name"],
        "version": ENCLAVE_CONFIG["version"],
        "mr_enclave": ENCLAVE_CONFIG["mr_enclave"],
        "mr_signer": ENCLAVE_CONFIG["mr_signer"],
        "tcb_level": ENCLAVE_CONFIG["tcb_level"],
        "root_ca_initialized": ENCLAVE_MEMORY["root_ca_cert"] is not None,
        "orderer_key_loaded": ENCLAVE_MEMORY["orderer_key"] is not None
    })

@app.route('/ca/init', methods=['POST'])
def init_root_ca():
    """Initialize Root CA in enclave"""
    try:
        if ROOT_CA_CERT_FILE.exists():
            return jsonify({
                "error": "Root CA already initialized"
            }), 400

        cert, key = enclave.generate_root_ca()

        return jsonify({
            "success": True,
            "message": "Root CA initialized",
            "certificate": cert.public_bytes(serialization.Encoding.PEM).decode(),
            "subject": cert.subject.rfc4514_string(),
            "serial_number": hex(cert.serial_number),
            "valid_from": cert.not_valid_before.isoformat(),
            "valid_until": cert.not_valid_after.isoformat()
        })
    except Exception as e:
        return jsonify({"error": str(e)}), 500

@app.route('/ca/certificate', methods=['GET'])
def get_root_ca_certificate():
    """Get Root CA certificate"""
    try:
        if not ROOT_CA_CERT_FILE.exists():
            return jsonify({"error": "Root CA not initialized"}), 404

        cert_pem = ROOT_CA_CERT_FILE.read_bytes()
        return cert_pem, 200, {'Content-Type': 'application/x-pem-file'}
    except Exception as e:
        return jsonify({"error": str(e)}), 500

@app.route('/ca/sign', methods=['POST'])
def sign_certificate():
    """Sign a certificate request"""
    try:
        data = request.json
        csr_pem = data.get('csr')
        cert_type = data.get('type', 'peer')  # peer, orderer, client, intermediate-ca

        if not csr_pem:
            return jsonify({"error": "CSR required"}), 400

        # Ensure Root CA is loaded
        if not ENCLAVE_MEMORY["root_ca_cert"]:
            enclave.load_root_ca()

        # Sign the CSR
        cert_pem = enclave.sign_certificate(csr_pem.encode(), cert_type)

        return jsonify({
            "success": True,
            "certificate": cert_pem.decode()
        })
    except Exception as e:
        return jsonify({"error": str(e)}), 500

@app.route('/orderer/store-key', methods=['POST'])
def store_orderer_key():
    """Store orderer private key in enclave"""
    try:
        data = request.json
        key_pem = data.get('private_key')

        if not key_pem:
            return jsonify({"error": "Private key required"}), 400

        enclave.store_orderer_key(key_pem.encode())

        return jsonify({
            "success": True,
            "message": "Orderer private key stored and sealed in enclave"
        })
    except Exception as e:
        return jsonify({"error": str(e)}), 500

@app.route('/orderer/sign-block', methods=['POST'])
def sign_block():
    """Sign a block for the orderer"""
    try:
        data = request.json
        block_data_hex = data.get('block_data')

        if not block_data_hex:
            return jsonify({"error": "Block data required"}), 400

        block_data = bytes.fromhex(block_data_hex)
        signature = enclave.sign_block(block_data)

        return jsonify({
            "success": True,
            "signature": signature.hex()
        })
    except Exception as e:
        return jsonify({"error": str(e)}), 500

@app.route('/attestation/generate-quote', methods=['POST'])
def generate_quote():
    """Generate attestation quote"""
    try:
        quote = enclave.generate_attestation_quote()

        return jsonify({
            "success": True,
            "quote": quote
        })
    except Exception as e:
        return jsonify({"error": str(e)}), 500

@app.route('/attestation/verify', methods=['POST'])
def verify_attestation():
    """Verify an attestation quote"""
    try:
        data = request.json
        quote = data.get('quote')

        if not quote:
            return jsonify({"error": "Quote required"}), 400

        # Verify signature
        report_data = quote.get('report_body')
        signature = quote.get('signature')

        report_json = json.dumps(report_data, sort_keys=True)
        expected_signature = hashlib.sha256(report_json.encode()).hexdigest()

        valid = (signature == expected_signature)

        # Check MREnclave matches
        mr_enclave_match = (report_data.get('mr_enclave') == ENCLAVE_CONFIG['mr_enclave'])

        return jsonify({
            "success": True,
            "valid": valid and mr_enclave_match,
            "signature_valid": valid,
            "mr_enclave_match": mr_enclave_match,
            "mr_enclave": report_data.get('mr_enclave'),
            "timestamp": report_data.get('timestamp')
        })
    except Exception as e:
        return jsonify({"error": str(e)}), 500

if __name__ == '__main__':
    print("=" * 60)
    print("DFIR Software Enclave Simulator Starting...")
    print("=" * 60)
    print(f"Version: {ENCLAVE_CONFIG['version']}")
    print(f"MREnclave: {ENCLAVE_CONFIG['mr_enclave'][:32]}...")
    print(f"MRSigner:  {ENCLAVE_CONFIG['mr_signer'][:32]}...")
    print(f"Data Directory: {ENCLAVE_DATA_DIR}")
    print("=" * 60)

    # Try to load existing Root CA
    try:
        if ROOT_CA_CERT_FILE.exists():
            enclave.load_root_ca()
            print("✓ Root CA loaded from sealed storage")
        else:
            print("⚠ Root CA not initialized - call /ca/init to create")
    except Exception as e:
        print(f"⚠ Could not load Root CA: {e}")

    # Try to load orderer key
    try:
        if ORDERER_KEY_FILE.exists():
            sealed_key = ORDERER_KEY_FILE.read_bytes()
            key_pem = enclave.unseal_data(sealed_key)
            private_key = serialization.load_pem_private_key(
                key_pem,
                password=None,
                backend=default_backend()
            )
            ENCLAVE_MEMORY["orderer_key"] = private_key
            print("✓ Orderer private key loaded from sealed storage")
    except Exception as e:
        print(f"⚠ Could not load orderer key: {e}")

    print("=" * 60)
    print("Enclave API listening on http://0.0.0.0:5001")
    print("=" * 60)

    app.run(host='0.0.0.0', port=5001, debug=False)
