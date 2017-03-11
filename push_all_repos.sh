#!/bin/bash
set -e
for repo in $(sudo docker images --format '{{.Repository}}' | grep $DOCKER_NAMESPACE); do sudo docker push $repo; done
