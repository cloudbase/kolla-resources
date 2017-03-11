#!/bin/bash
set -e
REPO=$1
echo Creating: $REPO
curl -s -H "X-Docker-Token: true" -H "Content-Type: application/json"  -X PUT --user $DOCKER_USERNAME:$DOCKER_PASSWORD https://index.docker.io/v1/repositories/$REPO/ -d '[{"id": "1234"}]' > /dev/null
