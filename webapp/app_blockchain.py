#!/usr/bin/env python3
"""
DFIR Blockchain Web Dashboard
Main application for interacting with Hot and Cold blockchains
"""

from flask import Flask, render_template, request, jsonify, send_file
import subprocess
import json
import requests
import mysql.connector
import hashlib
import os
from datetime import datetime
import time

app = Flask(__name__)

# Configuration
HOT_PEER = "peer0.lawenforcement.hot.coc.com:7051"
COLD_PEER = "peer0.archive.cold.coc.com:9051"
CHAINCODE_NAME = "dfir"

# MySQL connection
def get_db():
    """Connect to MySQL database"""
    try:
        return mysql.connector.connect(
            host="localhost",
            port=3306,
            user="cocuser",
            password="cocpassword",
            database="coc_evidence"
        )
    except Exception as e:
        print(f"Database connection error: {e}")
        return None

def exec_chaincode(command_type, channel, chaincode, function, args):
    """Execute chaincode command via CLI container"""
    cli_container = "cli" if channel == "hotchannel" else "cli-cold"

    # Base command
    cmd = [
        "docker", "exec", cli_container,
        "peer", "chaincode", command_type,
        "-C", channel,
        "-n", chaincode,
        "-c", json.dumps({"function": function, "Args": args})
    ]

    # Add TLS and peer parameters for invoke operations
    if command_type == "invoke":
        if channel == "hotchannel":
            cmd.extend([
                "--waitForEvent",
                "--tls",
                "--cafile", "/opt/gopath/src/github.com/hyperledger/fabric/peer/crypto/ordererOrganizations/hot.coc.com/orderers/orderer.hot.coc.com/msp/tlscacerts/tlsca.hot.coc.com-cert.pem",
                "--peerAddresses", "peer0.lawenforcement.hot.coc.com:7051",
                "--tlsRootCertFiles", "/opt/gopath/src/github.com/hyperledger/fabric/peer/crypto/peerOrganizations/lawenforcement.hot.coc.com/peers/peer0.lawenforcement.hot.coc.com/tls/ca.crt",
                "--peerAddresses", "peer0.forensiclab.hot.coc.com:8051",
                "--tlsRootCertFiles", "/opt/gopath/src/github.com/hyperledger/fabric/peer/crypto/peerOrganizations/forensiclab.hot.coc.com/peers/peer0.forensiclab.hot.coc.com/tls/ca.crt"
            ])
        else:  # coldchannel
            cmd.extend([
                "--waitForEvent",
                "--tls",
                "--cafile", "/opt/gopath/src/github.com/hyperledger/fabric/peer/crypto/ordererOrganizations/cold.coc.com/orderers/orderer.cold.coc.com/msp/tlscacerts/tlsca.cold.coc.com-cert.pem",
                "--peerAddresses", "peer0.archive.cold.coc.com:9051",
                "--tlsRootCertFiles", "/opt/gopath/src/github.com/hyperledger/fabric/peer/crypto/peerOrganizations/archive.cold.coc.com/peers/peer0.archive.cold.coc.com/tls/ca.crt"
            ])

    try:
        result = subprocess.run(cmd, capture_output=True, text=True, timeout=45)
        if result.returncode == 0:
            return {"success": True, "data": result.stdout}
        else:
            return {"success": False, "error": result.stderr}
    except subprocess.TimeoutExpired:
        return {"success": False, "error": "Transaction timeout - orderer may not be responding"}
    except Exception as e:
        return {"success": False, "error": str(e)}

@app.route('/')
def index():
    """Main dashboard"""
    return render_template('dashboard.html')

@app.route('/api/blockchain/status')
def blockchain_status():
    """Get blockchain status"""
    try:
        # Check Hot blockchain
        hot_result = subprocess.run([
            "docker", "exec", "cli",
            "peer", "channel", "getinfo", "-c", "hotchannel"
        ], capture_output=True, text=True, timeout=10)

        # Check Cold blockchain
        cold_result = subprocess.run([
            "docker", "exec", "cli-cold",
            "peer", "channel", "getinfo", "-c", "coldchannel"
        ], capture_output=True, text=True, timeout=10)

        return jsonify({
            "hot_blockchain": {
                "status": "running" if hot_result.returncode == 0 else "error",
                "info": hot_result.stdout if hot_result.returncode == 0 else hot_result.stderr
            },
            "cold_blockchain": {
                "status": "running" if cold_result.returncode == 0 else "error",
                "info": cold_result.stdout if cold_result.returncode == 0 else cold_result.stderr
            }
        })
    except Exception as e:
        return jsonify({"error": str(e)}), 500

@app.route('/api/evidence/create', methods=['POST'])
def create_evidence():
    """Create new evidence on blockchain"""
    try:
        data = request.json

        # Validate required fields
        required = ['id', 'case_id', 'type', 'description', 'hash', 'location']
        if not all(k in data for k in required):
            return jsonify({"error": "Missing required fields"}), 400

        # Choose blockchain based on target
        channel = "coldchannel" if data.get('blockchain') == 'cold' else "hotchannel"

        # Parse metadata to get timestamp
        metadata = json.loads(data.get('metadata', '{}'))
        timestamp_str = metadata.get('timestamp', datetime.now().isoformat())

        # Convert ISO timestamp to Unix timestamp (int64)
        try:
            # Parse ISO format: 2025-11-08T22:48:52.778Z
            if timestamp_str.endswith('Z'):
                timestamp_str = timestamp_str[:-1]
                timestamp_dt = datetime.fromisoformat(timestamp_str)
            else:
                timestamp_dt = datetime.fromisoformat(timestamp_str)
            timestamp_unix = int(timestamp_dt.timestamp())
        except:
            # Fallback to current time if parsing fails
            timestamp_unix = int(datetime.now().timestamp())

        # Create evidence on blockchain
        result = exec_chaincode(
            "invoke",
            channel,
            CHAINCODE_NAME,
            "CreateEvidenceSimple",
            [
                data['id'],
                data['case_id'],
                data['type'],
                data['description'],
                data['hash'],
                data['location'],
                data.get('metadata', '{}'),
                str(timestamp_unix)  # Pass timestamp as 8th parameter
            ]
        )

        # If successful, also save to MySQL for quick listing
        if result.get('success'):
            try:
                db = get_db()
                if db:
                    cursor = db.cursor()

                    # Parse metadata
                    metadata = json.loads(data.get('metadata', '{}'))

                    # Convert channel name to blockchain_type enum value
                    blockchain_type = 'cold' if channel == 'coldchannel' else 'hot'

                    # Remove 'sha256:' prefix from hash if present
                    clean_hash = data['hash'].replace('sha256:', '')

                    # Convert timestamp to MySQL datetime format
                    timestamp_str = metadata.get('timestamp', datetime.now().isoformat())
                    try:
                        if timestamp_str.endswith('Z'):
                            timestamp_str = timestamp_str[:-1]
                        timestamp_dt = datetime.fromisoformat(timestamp_str)
                        mysql_timestamp = timestamp_dt.strftime('%Y-%m-%d %H:%M:%S')
                    except:
                        mysql_timestamp = datetime.now().strftime('%Y-%m-%d %H:%M:%S')

                    # Insert into MySQL
                    cursor.execute("""
                        INSERT INTO evidence_metadata
                        (evidence_id, case_id, evidence_type, description, sha256_hash,
                         ipfs_hash, collected_by, blockchain_type, collected_timestamp, location)
                        VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s, %s)
                    """, (
                        data['id'],
                        data['case_id'],
                        data['type'],
                        data['description'],
                        clean_hash,
                        data['location'].replace('ipfs://', ''),
                        metadata.get('collected_by', 'Unknown'),
                        blockchain_type,
                        mysql_timestamp,
                        metadata.get('location', 'Unknown')
                    ))

                    db.commit()
                    cursor.close()
                    db.close()
                    print(f"✓ Evidence {data['id']} saved to MySQL successfully")
            except Exception as db_error:
                import traceback
                error_details = traceback.format_exc()
                print(f"❌ MySQL storage ERROR for evidence {data['id']}:")
                print(f"   Error: {db_error}")
                print(f"   Details: {error_details}")
                # Don't fail the request if MySQL fails - blockchain is source of truth

        return jsonify(result)
    except Exception as e:
        return jsonify({"error": str(e)}), 500

@app.route('/api/evidence/<evidence_id>')
def get_evidence(evidence_id):
    """Query evidence from blockchain"""
    try:
        # Try Hot blockchain first
        result = exec_chaincode(
            "query",
            "hotchannel",
            CHAINCODE_NAME,
            "ReadEvidenceSimple",
            [evidence_id]
        )

        if result['success']:
            return jsonify(json.loads(result['data']))

        # Try Cold blockchain if not found in Hot
        result = exec_chaincode(
            "query",
            "coldchannel",
            CHAINCODE_NAME,
            "ReadEvidenceSimple",
            [evidence_id]
        )

        if result['success']:
            return jsonify(json.loads(result['data']))

        return jsonify({"error": "Evidence not found"}), 404
    except Exception as e:
        return jsonify({"error": str(e)}), 500

@app.route('/api/evidence/list')
def list_evidence():
    """List all evidence from MySQL metadata database"""
    try:
        db = get_db()
        if not db:
            return jsonify([])  # Return empty array instead of error

        cursor = db.cursor(dictionary=True)

        # Check if table exists, create if it doesn't
        try:
            cursor.execute("SELECT * FROM evidence_metadata ORDER BY collected_timestamp DESC LIMIT 100")
            evidence = cursor.fetchall()
        except mysql.connector.errors.ProgrammingError:
            # Table doesn't exist, return empty array
            cursor.close()
            db.close()
            return jsonify([])

        # Convert datetime objects to strings
        for e in evidence:
            if e.get('collected_timestamp'):
                e['collected_timestamp'] = str(e['collected_timestamp'])
            if e.get('created_at'):
                e['created_at'] = str(e['created_at'])
            if e.get('updated_at'):
                e['updated_at'] = str(e['updated_at'])

        cursor.close()
        db.close()
        return jsonify(evidence)
    except Exception as e:
        print(f"Evidence list error: {e}")
        return jsonify([])  # Return empty array on any error

@app.route('/api/containers/status')
def containers_status():
    """Get Docker containers status"""
    try:
        result = subprocess.run(
            ["docker", "ps", "--format", "{{.Names}}\t{{.Status}}"],
            capture_output=True,
            text=True,
            timeout=5
        )

        if result.returncode == 0:
            containers = []
            for line in result.stdout.strip().split('\n'):
                if '\t' in line:
                    name, status = line.split('\t', 1)
                    containers.append({"name": name, "status": status})
            return jsonify(containers)
        else:
            return jsonify({"error": result.stderr}), 500
    except Exception as e:
        return jsonify({"error": str(e)}), 500

@app.route('/api/ipfs/status')
def ipfs_status():
    """Get IPFS node status"""
    try:
        # Try docker exec since IPFS is in container
        result = subprocess.run(
            ["docker", "exec", "ipfs-node", "ipfs", "version"],
            capture_output=True,
            text=True,
            timeout=5
        )
        if result.returncode == 0:
            version = result.stdout.strip().split()[-1] if result.stdout else "unknown"
            return jsonify({"status": "running", "Version": version})
        else:
            return jsonify({"status": "error", "error": result.stderr}), 500
    except Exception as e:
        return jsonify({"status": "offline", "error": str(e)}), 500

@app.route('/api/ipfs/upload', methods=['POST'])
def ipfs_upload():
    """Upload file to IPFS"""
    try:
        if 'file' not in request.files:
            return jsonify({"error": "No file provided"}), 400

        file = request.files['file']
        if file.filename == '':
            return jsonify({"error": "Empty filename"}), 400

        # Create temporary directory for uploads
        upload_dir = '/tmp/ipfs-uploads'
        os.makedirs(upload_dir, exist_ok=True)

        # Save file temporarily
        temp_path = os.path.join(upload_dir, file.filename)
        file.save(temp_path)

        try:
            # Calculate SHA-256 hash of the file
            sha256_hash = hashlib.sha256()
            with open(temp_path, 'rb') as f:
                for chunk in iter(lambda: f.read(4096), b''):
                    sha256_hash.update(chunk)
            file_hash = sha256_hash.hexdigest()

            # Copy file to IPFS container
            copy_result = subprocess.run(
                ["docker", "cp", temp_path, f"ipfs-node:/tmp/{file.filename}"],
                capture_output=True,
                text=True,
                timeout=30
            )

            if copy_result.returncode != 0:
                return jsonify({
                    "error": f"Failed to copy file to IPFS container: {copy_result.stderr}"
                }), 500

            # Add file to IPFS
            ipfs_result = subprocess.run(
                ["docker", "exec", "ipfs-node", "ipfs", "add", "-Q", f"/tmp/{file.filename}"],
                capture_output=True,
                text=True,
                timeout=60
            )

            if ipfs_result.returncode == 0:
                ipfs_hash = ipfs_result.stdout.strip()

                # Clean up temp files
                try:
                    os.remove(temp_path)
                    subprocess.run(
                        ["docker", "exec", "ipfs-node", "rm", f"/tmp/{file.filename}"],
                        capture_output=True,
                        timeout=10
                    )
                except:
                    pass

                return jsonify({
                    "success": True,
                    "ipfs_hash": ipfs_hash,
                    "file_hash": file_hash,
                    "filename": file.filename,
                    "gateway_url": f"http://localhost:8080/ipfs/{ipfs_hash}"
                })
            else:
                return jsonify({
                    "error": f"IPFS add failed: {ipfs_result.stderr}"
                }), 500

        finally:
            # Clean up temp file if still exists
            if os.path.exists(temp_path):
                try:
                    os.remove(temp_path)
                except:
                    pass

    except Exception as e:
        return jsonify({"error": str(e)}), 500

@app.route('/api/ipfs/files')
def ipfs_files():
    """List all pinned files in IPFS"""
    try:
        # List all pinned files
        result = subprocess.run(
            ["docker", "exec", "ipfs-node", "ipfs", "pin", "ls", "--type=recursive"],
            capture_output=True,
            text=True,
            timeout=10
        )

        if result.returncode == 0:
            files = []
            for line in result.stdout.strip().split('\n'):
                if line:
                    # Format: Qm... recursive
                    parts = line.split()
                    if parts:
                        ipfs_hash = parts[0]
                        files.append({
                            "hash": ipfs_hash,
                            "gateway_url": f"http://localhost:8080/ipfs/{ipfs_hash}"
                        })
            return jsonify({"success": True, "files": files})
        else:
            return jsonify({"error": result.stderr}), 500
    except Exception as e:
        return jsonify({"error": str(e)}), 500

@app.route('/api/cases/list')
def list_cases():
    """List all cases"""
    try:
        db = get_db()
        if not db:
            return jsonify([])

        cursor = db.cursor(dictionary=True)
        cursor.execute("""
            SELECT
                c.*,
                COUNT(DISTINCT e.evidence_id) as evidence_count
            FROM cases c
            LEFT JOIN evidence_metadata e ON c.case_id = e.case_id
            GROUP BY c.case_id
            ORDER BY c.created_at DESC
        """)
        cases = cursor.fetchall()

        # Convert date objects to strings
        for case in cases:
            if case.get('opened_date'):
                case['opened_date'] = str(case['opened_date'])
            if case.get('closed_date'):
                case['closed_date'] = str(case['closed_date'])
            if case.get('created_at'):
                case['created_at'] = str(case['created_at'])
            if case.get('updated_at'):
                case['updated_at'] = str(case['updated_at'])

        cursor.close()
        db.close()
        return jsonify(cases)
    except Exception as e:
        print(f"List cases error: {e}")
        return jsonify([])

@app.route('/api/cases/create', methods=['POST'])
def create_case():
    """Create a new case"""
    try:
        data = request.json

        # Validate required fields
        required = ['case_id', 'case_name', 'case_number', 'investigating_agency', 'lead_investigator', 'opened_date']
        if not all(k in data for k in required):
            return jsonify({"error": "Missing required fields"}), 400

        db = get_db()
        if not db:
            return jsonify({"error": "Database connection failed"}), 500

        cursor = db.cursor()
        cursor.execute("""
            INSERT INTO cases
            (case_id, case_name, case_number, case_type, investigating_agency,
             lead_investigator, status, opened_date, description)
            VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s)
        """, (
            data['case_id'],
            data['case_name'],
            data['case_number'],
            data.get('case_type', 'Digital Forensics'),
            data['investigating_agency'],
            data['lead_investigator'],
            data.get('status', 'open'),
            data['opened_date'],
            data.get('description', '')
        ))

        db.commit()
        cursor.close()
        db.close()

        return jsonify({"success": True, "case_id": data['case_id']})
    except mysql.connector.errors.IntegrityError as e:
        return jsonify({"error": "Case ID or case number already exists"}), 400
    except Exception as e:
        print(f"Create case error: {e}")
        return jsonify({"error": str(e)}), 500

@app.route('/api/cases/<case_id>')
def get_case(case_id):
    """Get case details with evidence list"""
    try:
        db = get_db()
        if not db:
            return jsonify({"error": "Database connection failed"}), 404

        cursor = db.cursor(dictionary=True)

        # Get case details
        cursor.execute("SELECT * FROM cases WHERE case_id = %s", (case_id,))
        case = cursor.fetchone()

        if not case:
            cursor.close()
            db.close()
            return jsonify({"error": "Case not found"}), 404

        # Get evidence for this case
        cursor.execute("""
            SELECT * FROM evidence_metadata
            WHERE case_id = %s
            ORDER BY collected_timestamp DESC
        """, (case_id,))
        evidence = cursor.fetchall()

        # Convert date/timestamp objects to strings
        if case.get('opened_date'):
            case['opened_date'] = str(case['opened_date'])
        if case.get('closed_date'):
            case['closed_date'] = str(case['closed_date'])
        if case.get('created_at'):
            case['created_at'] = str(case['created_at'])
        if case.get('updated_at'):
            case['updated_at'] = str(case['updated_at'])

        for e in evidence:
            if e.get('collected_timestamp'):
                e['collected_timestamp'] = str(e['collected_timestamp'])
            if e.get('created_at'):
                e['created_at'] = str(e['created_at'])
            if e.get('updated_at'):
                e['updated_at'] = str(e['updated_at'])

        case['evidence'] = evidence
        case['evidence_count'] = len(evidence)

        cursor.close()
        db.close()
        return jsonify(case)
    except Exception as e:
        print(f"Get case error: {e}")
        return jsonify({"error": str(e)}), 500

@app.route('/health')
def health():
    """Health check endpoint"""
    return jsonify({
        "status": "healthy",
        "timestamp": datetime.now().isoformat(),
        "service": "DFIR Blockchain Dashboard"
    })

if __name__ == '__main__':
    print()
    print("=" * 75)
    print("       DFIR BLOCKCHAIN EVIDENCE MANAGEMENT SYSTEM")
    print("=" * 75)
    print()
    print("📍 SERVICE URLS:")
    print()
    print("  🌐 Main Dashboard:          http://localhost:5000")
    print("  📁 IPFS Web UI:             https://webui.ipfs.io")
    print("  🔗 IPFS Gateway:            http://localhost:8080")
    print("  🗄️  MySQL phpMyAdmin:        http://localhost:8081")
    print("  🔥 Hot Chain Explorer:      http://localhost:8090")
    print("  ❄️  Cold Chain Explorer:     http://localhost:8091")
    print()
    print("  Credentials:")
    print("    phpMyAdmin:  cocuser / cocpassword")
    print("    Explorers:   exploreradmin / exploreradminpw")
    print()
    print("=" * 75)
    print()
    print("🔧 API ENDPOINTS:")
    print()
    print("  GET  /api/blockchain/status    - Blockchain health status")
    print("  POST /api/evidence/create      - Create new evidence")
    print("  GET  /api/evidence/<id>        - Query evidence by ID")
    print("  GET  /api/evidence/list        - List all evidence")
    print("  POST /api/ipfs/upload          - Upload file to IPFS")
    print("  GET  /api/ipfs/status          - IPFS node status")
    print("  GET  /api/containers/status    - Docker containers status")
    print()
    print("=" * 75)
    print()
    print("✅ System Ready - Press Ctrl+C to stop")
    print()

    app.run(host='0.0.0.0', port=5000, debug=True)
