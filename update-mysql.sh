#!/bin/bash

# Helper script to update MySQL database without SSL issues
# This script updates the database schema safely

echo "Updating MySQL Database..."

# Check if update-database.sql exists
if [ ! -f "update-database.sql" ]; then
    echo "❌ Error: update-database.sql not found"
    exit 1
fi

# Execute the SQL script with SSL disabled
mysql -h localhost -P 3306 -u cocuser -pcocpassword --ssl-mode=DISABLED coc_evidence < update-database.sql

if [ $? -eq 0 ]; then
    echo "✅ Database updated successfully"
else
    echo "❌ Database update failed"
    exit 1
fi
