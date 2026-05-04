#!/bin/bash

docker volume create portainer_data

docker network create portainer_network

docker run -d \
    --name portainer \
    --hostname portainer \
    --restart=always \
    -e TZ=Asia/Taipei \
    -v portainer_data:/data \
    -v /var/run/docker.sock:/var/run/docker.sock \
    # -v /etc/localtime:/etc/localtime:ro \
    # -v /etc/timezone:/etc/timezone:ro \
    --network portainer_network \
    -p 8000:8000 \
    -p 9443:9443 \
    portainer/portainer-ce:sts
