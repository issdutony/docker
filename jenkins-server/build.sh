#!/bin/bash

IMAGE_NAME="rd/jenkins:lts-jdk21"

docker builder prune -a -f

docker image rm ${IMAGE_NAME}

docker build --no-cache -t ${IMAGE_NAME} .
# docker build --no-cache --network=host -t ${IMAGE_NAME} .
