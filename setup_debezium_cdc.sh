#!/bin/bash

echo "=== SETTING UP DEBEZIUM CDC CONNECTOR ==="

# Wait for Debezium to be ready
echo "Waiting for Debezium Connect to be ready..."
until curl -f -s http://localhost:8083/connectors; do
    echo "Waiting for Debezium..."
    sleep 5
done

echo "✅ Debezium Connect is ready!"

# Create PostgreSQL CDC connector
echo "Creating PostgreSQL CDC connector..."
curl -X POST http://localhost:8083/connectors \
  -H "Content-Type: application/json" \
  -d '{
    "name": "demographics-connector",
    "config": {
      "connector.class": "io.debezium.connector.postgresql.PostgresConnector",
      "database.hostname": "postgres",
      "database.port": "5432",
      "database.user": "admin",
      "database.password": "admin123",
      "database.dbname": "demographics",
      "database.server.name": "demographics_server",
      "topic.prefix": "demographics_server",
      "table.include.list": "public.demographics",
      "plugin.name": "pgoutput",
      "slot.name": "debezium_slot",
      "publication.name": "demographics_publication"
    }
  }'

echo
echo "✅ Debezium CDC connector created!"

# Check connector status
echo "Checking connector status..."
sleep 5
curl -s http://localhost:8083/connectors/demographics-connector/status | jq .

echo
echo "=== CDC SETUP COMPLETE ===" 