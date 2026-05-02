#!/bin/bash

docker builder prune -a -f
docker build --no-cache --network=host -t rd/inbound-agent:latest-jdk21 .
