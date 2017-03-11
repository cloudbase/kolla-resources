#!/bin/bash
set -e
for repo in $(sudo docker images --format '{{.Repository}}' | grep $DOCKER_NAMESPACE); do ./create_repo.sh $repo; done
