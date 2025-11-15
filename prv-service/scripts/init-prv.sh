#!/bin/bash
set -e

echo "Initializing PRV with default users..."

grpcurl -plaintext -d '{
  "roles": [
    {"user_id": "admin001", "role": "admin", "clearance": 1},
    {"user_id": "inv001", "role": "investigator", "clearance": 2},
    {"user_id": "inv002", "role": "investigator", "clearance": 2},
    {"user_id": "aud001", "role": "auditor", "clearance": 3},
    {"user_id": "court001", "role": "court", "clearance": 4}
  ]
}' localhost:50051 dfir.prv.PRV/InitPRV

echo ""
echo "✓ Initialization complete!"
