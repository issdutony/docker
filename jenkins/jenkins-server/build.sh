#!/bin/bash

docker builder prune -a -f
docker build --no-cache --network=host -t rd/jenkins:lts-jdk21 .
