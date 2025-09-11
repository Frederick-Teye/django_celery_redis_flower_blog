#!/bin/sh

# The host and port for the database are read from environment variables.
DB_HOST=${DB_HOST:-db}
DB_PORT=${DB_PORT:-5432}
REDIS_HOST=${REDIS_HOST:-redis}
REDIS_PORT=${REDIS_PORT:-6379}

echo "Waiting for database at $DB_HOST:$DB_PORT..."

# Use Python to check port availability
while ! python -c "import socket; s = socket.socket(socket.AF_INET, socket.SOCK_STREAM); s.settimeout(1); result = s.connect_ex(('$DB_HOST', $DB_PORT)); s.close(); exit(result)"; do
  sleep 0.1
done

echo "Database started"

# Wait for Redis
echo "Waiting for Redis at $REDIS_HOST:$REDIS_PORT..."
while ! python -c "import socket; s = socket.socket(socket.AF_INET, socket.SOCK_STREAM); s.settimeout(1); result = s.connect_ex(('$REDIS_HOST', $REDIS_PORT)); s.close(); exit(result)"; do
  sleep 0.1
done
echo "Redis started"

# hand over control to whatever command was passed (from docker-compose.yml)
exec "$@"