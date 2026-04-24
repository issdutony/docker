#!/bin/bash

docker stop $(docker ps -a -q)
docker rm $(docker ps -a -q)
docker rmi $(docker images -q)
docker network prune -f
docker volume prune -f
docker system prune -a -f
sudo systemctl restart docker

