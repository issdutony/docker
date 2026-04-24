#!/bin/bash

docker builder prune -a -f
docker build --no-cache -t rd/jenkins:lts-jdk21 .
