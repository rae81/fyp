#!/usr/bin/env python3
"""
SGX Enclave REST API Service
==============================
Provides HTTP API for:
- Root CA initialization
- Certificate signing
- Remote attestation
- Orderer key management
"""

from flask import Flask, request, jsonify
from flask_cors import CORS
import logging
from pathlib import Path

from enclave_sgx import SGXEnclave

# Initialize Flask app
app = Flask(__name__)
CORS(app)

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

# Initialize enclave
ENCLAVE_DATA_DIR = Path("/enclave-data")
enclave = SGXEnclave(data_dir=str(ENCLAVE_DATA_DIR))

# Try to load existing Root CA
if enclave.load_sealed_root_ca():
    logger.info("Loaded existing Root CA from sealed storage")
else:
    logger.info("No existing Root CA found - waiting for initialization")


@app.route('/health', methods=['GET'])
def health():
    """Health check endpoint"""
    return jsonify({
        "status": "healthy",
        "service": "SGX Enclave Simulator",
        "version": "2.0.0"
    }), 200


@app.route('/enclave/info', methods=['GET'])
def get_enclave_info():
    """Get enclave information and measurements"""
    try:
        info = enclave.get_info()
        return jsonify(info), 200
    except Exception as e:
        logger.error(f"Error getting enclave info: {e}")
        return jsonify({"error": str(e)}), 500


@app.route('/enclave/attestation', methods=['POST'])
def get_attestation():
    """
    Generate remote attestation quote
    Request body: {"user_data": "base64-encoded-data"} (optional)
    """
    try:
        data = request.get_json() or {}
        user_data = data.get('user_data', '').encode()

        quote = enclave.generate_attestation_quote(user_data)

        return jsonify({
            "status": "success",
            "attestation": quote
        }), 200

    except Exception as e:
        logger.error(f"Error generating attestation: {e}")
        return jsonify({"error": str(e)}), 500


@app.route('/ca/init', methods=['POST'])
def initialize_root_ca():
    """Initialize Root CA inside enclave"""
    try:
        if enclave._secure_memory["root_ca_key"] is not None:
            return jsonify({
                "error": "Root CA already initialized",
                "initialized": True
            }), 400

        cert_pem, sealed_key = enclave.generate_root_ca()

        # Get certificate details
        cert_info = {
            "subject": "CN=DFIR SGX Root CA",
            "issuer": "CN=DFIR SGX Root CA (self-signed)",
            "not_before": "UTC now",
            "not_after": "UTC now + 10 years",
            "serial_number": "random",
        }

        return jsonify({
            "status": "success",
            "message": "Root CA initialized successfully",
            "certificate": cert_pem.decode(),
            "info": cert_info,
            "mrenclave": enclave.mrenclave.hex(),
            "mrsigner": enclave.mrsigner.hex(),
        }), 200

    except Exception as e:
        logger.error(f"Error initializing Root CA: {e}")
        return jsonify({"error": str(e)}), 500


@app.route('/ca/certificate', methods=['GET'])
def get_root_ca_cert():
    """Get Root CA certificate (public)"""
    try:
        if enclave._secure_memory["root_ca_cert"] is None:
            return jsonify({"error": "Root CA not initialized"}), 404

        from cryptography.hazmat.primitives import serialization

        cert_pem = enclave._secure_memory["root_ca_cert"].public_bytes(
            serialization.Encoding.PEM
        )

        return cert_pem.decode(), 200, {'Content-Type': 'application/x-pem-file'}

    except Exception as e:
        logger.error(f"Error getting Root CA cert: {e}")
        return jsonify({"error": str(e)}), 500


@app.route('/ca/sign', methods=['POST'])
def sign_certificate():
    """
    Sign certificate using Root CA
    Request body: {
        "csr": "PEM-encoded CSR",
        "type": "intermediate|peer|client|orderer",
        "validity_days": 365 (optional)
    }
    """
    try:
        if enclave._secure_memory["root_ca_key"] is None:
            return jsonify({"error": "Root CA not initialized"}), 400

        data = request.get_json()
        if not data or 'csr' not in data:
            return jsonify({"error": "Missing CSR in request"}), 400

        csr_pem = data['csr']
        cert_type = data.get('type', 'client')
        validity_days = data.get('validity_days', 365)

        # Sign certificate inside enclave
        cert_pem = enclave.sign_certificate(csr_pem, cert_type, validity_days)

        logger.info(f"Signed {cert_type} certificate")

        return jsonify({
            "status": "success",
            "certificate": cert_pem.decode(),
            "type": cert_type,
            "signed_by": "DFIR SGX Root CA"
        }), 200

    except Exception as e:
        logger.error(f"Error signing certificate: {e}")
        return jsonify({"error": str(e)}), 500


@app.route('/orderer/init', methods=['POST'])
def initialize_orderer_keys():
    """
    Initialize orderer private keys inside enclave
    Request body: {"chain": "hot"|"cold"}
    """
    try:
        data = request.get_json() or {}
        chain = data.get('chain', 'hot')

        if chain not in ['hot', 'cold']:
            return jsonify({"error": "Invalid chain. Must be 'hot' or 'cold'"}), 400

        public_key_pem, sealed_key = enclave.generate_orderer_key(chain)

        logger.info(f"Generated orderer key for {chain} chain")

        return jsonify({
            "status": "success",
            "chain": chain,
            "public_key": public_key_pem.decode(),
            "message": f"Private key sealed in enclave, never exported"
        }), 200

    except Exception as e:
        logger.error(f"Error generating orderer key: {e}")
        return jsonify({"error": str(e)}), 500


@app.route('/seal', methods=['POST'])
def seal_data():
    """
    Seal arbitrary data using enclave
    Request body: {"data": "base64-encoded data"}
    """
    try:
        import base64

        data = request.get_json()
        if not data or 'data' not in data:
            return jsonify({"error": "Missing data in request"}), 400

        plaintext = base64.b64decode(data['data'])
        sealed = enclave.seal_data(plaintext)

        return jsonify({
            "status": "success",
            "sealed_data": base64.b64encode(sealed).decode(),
            "mrenclave": enclave.mrenclave.hex()
        }), 200

    except Exception as e:
        logger.error(f"Error sealing data: {e}")
        return jsonify({"error": str(e)}), 500


@app.route('/unseal', methods=['POST'])
def unseal_data():
    """
    Unseal data using enclave
    Request body: {"sealed_data": "base64-encoded sealed data"}
    """
    try:
        import base64

        data = request.get_json()
        if not data or 'sealed_data' not in data:
            return jsonify({"error": "Missing sealed_data in request"}), 400

        sealed = base64.b64decode(data['sealed_data'])
        plaintext = enclave.unseal_data(sealed)

        return jsonify({
            "status": "success",
            "data": base64.b64encode(plaintext).decode()
        }), 200

    except Exception as e:
        logger.error(f"Error unsealing data: {e}")
        return jsonify({"error": str(e)}), 500


if __name__ == '__main__':
    logger.info("Starting SGX Enclave API service...")
    app.run(host='0.0.0.0', port=5001, debug=False)
