#!/usr/bin/env python3
"""
Generate Fabric Certificates using Enclave Root CA
===================================================

This script generates x.509 certificates for all Hyperledger Fabric components
using the software enclave as the Root CA.

Components:
- Orderers (hot and cold chains)
- Peers (LawEnforcement, ForensicLab, Archive)
- Users and Admins
- TLS certificates for all components

All certificates are signed by the enclave Root CA with mTLS support.
"""

import os
import sys
import json
import requests
import subprocess
from pathlib import Path
from cryptography import x509
from cryptography.x509.oid import NameOID
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import rsa
from cryptography.hazmat.backends import default_backend

ENCLAVE_URL = "http://localhost:5001"
PROJECT_DIR = Path(__file__).parent.parent
CRYPTO_DIR = PROJECT_DIR / "organizations"

class FabricCertGenerator:
    def __init__(self):
        self.enclave_url = ENCLAVE_URL
        self.check_enclave()

    def check_enclave(self):
        """Check if enclave is running"""
        try:
            response = requests.get(f"{self.enclave_url}/health")
            if response.status_code != 200:
                raise Exception("Enclave unhealthy")
            print("✓ Enclave service is running")
        except Exception as e:
            print(f"❌ Enclave service is not running: {e}")
            print("   Start it with: docker-compose -f docker-compose-enclave.yml up -d")
            sys.exit(1)

        # Check if Root CA is initialized
        info = requests.get(f"{self.enclave_url}/enclave/info").json()
        if not info.get("root_ca_initialized"):
            print("❌ Root CA not initialized in enclave")
            print("   Run: ./init_enclave_ca.sh")
            sys.exit(1)
        print("✓ Root CA initialized in enclave")

    def generate_key(self) -> rsa.RSAPrivateKey:
        """Generate RSA private key"""
        return rsa.generate_private_key(
            public_exponent=65537,
            key_size=2048,
            backend=default_backend()
        )

    def create_csr(self, private_key: rsa.RSAPrivateKey, subject_name: x509.Name) -> x509.CertificateSigningRequest:
        """Create a certificate signing request"""
        csr = x509.CertificateSigningRequestBuilder().subject_name(
            subject_name
        ).sign(private_key, hashes.SHA256(), default_backend())
        return csr

    def sign_cert_with_enclave(self, csr: x509.CertificateSigningRequest, cert_type: str = "peer") -> bytes:
        """Sign CSR using enclave CA"""
        csr_pem = csr.public_bytes(serialization.Encoding.PEM).decode()

        response = requests.post(
            f"{self.enclave_url}/ca/sign",
            json={
                "csr": csr_pem,
                "type": cert_type
            }
        )

        if response.status_code != 200:
            raise Exception(f"Failed to sign certificate: {response.text}")

        result = response.json()
        return result["certificate"].encode()

    def save_key_and_cert(self, key: rsa.RSAPrivateKey, cert_pem: bytes, key_path: Path, cert_path: Path):
        """Save private key and certificate to files"""
        # Save private key
        key_path.parent.mkdir(parents=True, exist_ok=True)
        key_pem = key.private_bytes(
            encoding=serialization.Encoding.PEM,
            format=serialization.PrivateFormat.PKCS8,
            encryption_algorithm=serialization.NoEncryption()
        )
        key_path.write_bytes(key_pem)
        os.chmod(key_path, 0o600)

        # Save certificate
        cert_path.parent.mkdir(parents=True, exist_ok=True)
        cert_path.write_bytes(cert_pem)

        print(f"  ✓ Generated: {cert_path.name}")

    def generate_orderer_certs(self, chain_type: str):
        """Generate orderer certificates"""
        print(f"\nGenerating {chain_type.upper()} Chain Orderer Certificates...")

        domain = f"{chain_type}.coc.com"
        orderer_dir = CRYPTO_DIR / f"ordererOrganizations/{domain}"

        # Create MSP structure
        msp_dir = orderer_dir / "orderers" / f"orderer.{domain}" / "msp"
        tls_dir = orderer_dir / "orderers" / f"orderer.{domain}" / "tls"

        # Generate signing certificate
        print(f"  Generating signing certificate for orderer.{domain}...")
        key = self.generate_key()
        subject = x509.Name([
            x509.NameAttribute(NameOID.COUNTRY_NAME, "US"),
            x509.NameAttribute(NameOID.STATE_OR_PROVINCE_NAME, "North Carolina"),
            x509.NameAttribute(NameOID.LOCALITY_NAME, "Durham"),
            x509.NameAttribute(NameOID.ORGANIZATION_NAME, f"orderer.{domain}"),
            x509.NameAttribute(NameOID.COMMON_NAME, f"orderer.{domain}"),
        ])
        csr = self.create_csr(key, subject)
        cert_pem = self.sign_cert_with_enclave(csr, "orderer")

        self.save_key_and_cert(
            key,
            cert_pem,
            msp_dir / "keystore" / "priv_sk",
            msp_dir / "signcerts" / "cert.pem"
        )

        # Store orderer key in enclave
        print(f"  Storing orderer private key in enclave...")
        key_pem = key.private_bytes(
            encoding=serialization.Encoding.PEM,
            format=serialization.PrivateFormat.PKCS8,
            encryption_algorithm=serialization.NoEncryption()
        ).decode()

        response = requests.post(
            f"{self.enclave_url}/orderer/store-key",
            json={"private_key": key_pem}
        )

        if response.status_code == 200:
            print(f"  ✓ Orderer key sealed in enclave")
        else:
            print(f"  ⚠ Warning: Could not store orderer key in enclave: {response.text}")

        # Generate TLS certificate
        print(f"  Generating TLS certificate for orderer.{domain}...")
        tls_key = self.generate_key()
        tls_subject = x509.Name([
            x509.NameAttribute(NameOID.COUNTRY_NAME, "US"),
            x509.NameAttribute(NameOID.STATE_OR_PROVINCE_NAME, "North Carolina"),
            x509.NameAttribute(NameOID.LOCALITY_NAME, "Durham"),
            x509.NameAttribute(NameOID.ORGANIZATION_NAME, f"orderer.{domain}"),
            x509.NameAttribute(NameOID.COMMON_NAME, f"orderer.{domain}"),
        ])
        tls_csr = self.create_csr(tls_key, tls_subject)
        tls_cert_pem = self.sign_cert_with_enclave(tls_csr, "orderer")

        self.save_key_and_cert(
            tls_key,
            tls_cert_pem,
            tls_dir / "server.key",
            tls_dir / "server.crt"
        )

        # Copy root CA cert
        root_ca_cert = Path(PROJECT_DIR) / "enclave-data" / "root-ca.crt"
        if root_ca_cert.exists():
            (msp_dir / "cacerts").mkdir(parents=True, exist_ok=True)
            (msp_dir / "cacerts" / "ca-cert.pem").write_bytes(root_ca_cert.read_bytes())
            (tls_dir / "ca.crt").write_bytes(root_ca_cert.read_bytes())

    def generate_peer_certs(self, org_name: str, domain: str, chain_type: str):
        """Generate peer certificates"""
        print(f"\nGenerating {org_name} Peer Certificates ({chain_type} chain)...")

        peer_dir = CRYPTO_DIR / f"peerOrganizations/{domain}"
        peer_name = f"peer0.{domain}"

        # Create MSP structure
        msp_dir = peer_dir / "peers" / peer_name / "msp"
        tls_dir = peer_dir / "peers" / peer_name / "tls"

        # Generate signing certificate
        print(f"  Generating signing certificate for {peer_name}...")
        key = self.generate_key()
        subject = x509.Name([
            x509.NameAttribute(NameOID.COUNTRY_NAME, "US"),
            x509.NameAttribute(NameOID.STATE_OR_PROVINCE_NAME, "North Carolina"),
            x509.NameAttribute(NameOID.LOCALITY_NAME, "Durham"),
            x509.NameAttribute(NameOID.ORGANIZATION_NAME, domain),
            x509.NameAttribute(NameOID.COMMON_NAME, peer_name),
        ])
        csr = self.create_csr(key, subject)
        cert_pem = self.sign_cert_with_enclave(csr, "peer")

        self.save_key_and_cert(
            key,
            cert_pem,
            msp_dir / "keystore" / "priv_sk",
            msp_dir / "signcerts" / "cert.pem"
        )

        # Generate TLS certificate
        print(f"  Generating TLS certificate for {peer_name}...")
        tls_key = self.generate_key()
        tls_subject = x509.Name([
            x509.NameAttribute(NameOID.COUNTRY_NAME, "US"),
            x509.NameAttribute(NameOID.STATE_OR_PROVINCE_NAME, "North Carolina"),
            x509.NameAttribute(NameOID.LOCALITY_NAME, "Durham"),
            x509.NameAttribute(NameOID.ORGANIZATION_NAME, domain),
            x509.NameAttribute(NameOID.COMMON_NAME, peer_name),
        ])
        tls_csr = self.create_csr(tls_key, tls_subject)
        tls_cert_pem = self.sign_cert_with_enclave(tls_csr, "peer")

        self.save_key_and_cert(
            tls_key,
            tls_cert_pem,
            tls_dir / "server.key",
            tls_dir / "server.crt"
        )

        # Copy root CA cert
        root_ca_cert = Path(PROJECT_DIR) / "enclave-data" / "root-ca.crt"
        if root_ca_cert.exists():
            (msp_dir / "cacerts").mkdir(parents=True, exist_ok=True)
            (msp_dir / "cacerts" / "ca-cert.pem").write_bytes(root_ca_cert.read_bytes())
            (tls_dir / "ca.crt").write_bytes(root_ca_cert.read_bytes())

        # Generate admin user certificate
        print(f"  Generating admin certificate for {org_name}...")
        admin_dir = peer_dir / "users" / f"Admin@{domain}" / "msp"

        admin_key = self.generate_key()
        admin_subject = x509.Name([
            x509.NameAttribute(NameOID.COUNTRY_NAME, "US"),
            x509.NameAttribute(NameOID.STATE_OR_PROVINCE_NAME, "North Carolina"),
            x509.NameAttribute(NameOID.LOCALITY_NAME, "Durham"),
            x509.NameAttribute(NameOID.ORGANIZATION_NAME, domain),
            x509.NameAttribute(NameOID.COMMON_NAME, f"Admin@{domain}"),
        ])
        admin_csr = self.create_csr(admin_key, admin_subject)
        admin_cert_pem = self.sign_cert_with_enclave(admin_csr, "client")

        self.save_key_and_cert(
            admin_key,
            admin_cert_pem,
            admin_dir / "keystore" / "priv_sk",
            admin_dir / "signcerts" / "cert.pem"
        )

        # Copy root CA cert for admin
        (admin_dir / "cacerts").mkdir(parents=True, exist_ok=True)
        (admin_dir / "cacerts" / "ca-cert.pem").write_bytes(root_ca_cert.read_bytes())

    def generate_all_certs(self):
        """Generate all certificates"""
        print("=" * 70)
        print("Generating Fabric Certificates using Enclave Root CA")
        print("=" * 70)

        # Hot chain orderer
        self.generate_orderer_certs("hot")

        # Cold chain orderer
        self.generate_orderer_certs("cold")

        # Hot chain peers
        self.generate_peer_certs("LawEnforcement", "lawenforcement.hot.coc.com", "hot")
        self.generate_peer_certs("ForensicLab", "forensiclab.hot.coc.com", "hot")

        # Cold chain peer
        self.generate_peer_certs("Archive", "archive.cold.coc.com", "cold")

        print("\n" + "=" * 70)
        print("✓ All Fabric Certificates Generated Successfully")
        print("=" * 70)
        print("\nCertificates are located in:")
        print(f"  {CRYPTO_DIR}")
        print("\nAll certificates are signed by the enclave Root CA")
        print("mTLS is enabled for all components")
        print("\nNext steps:")
        print("  1. Verify certificates:")
        print("     ./verify_certs.sh")
        print("  2. Start Fabric network with new certificates")
        print("  3. Register enclave attestation with blockchain")

if __name__ == "__main__":
    generator = FabricCertGenerator()
    generator.generate_all_certs()
