#!/bin/bash

for name in nova_compute nova_ssh nova_libvirt
do
    for id in $(sudo docker ps -q -a -f name=$name)
    do
        sudo docker stop $id
        sudo docker rm $id
    done
done

