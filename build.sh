sudo docker rmi $(sudo docker images -q) -f
sudo kolla-build -n $DOCKER_NAMESPACE --base ubuntu --base-image ubuntu --base-tag 16.04 --profile default

