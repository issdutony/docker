#!/bin/bash

docker builder prune -a -f
docker build --no-cache -t rd/inbound-agent:latest-jdk21 .
