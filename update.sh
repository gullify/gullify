#!/bin/bash
set -e

echo "Updating Gullify..."

git pull
docker-compose down
docker-compose up -d --build

echo "Done! Gullify is up to date."
