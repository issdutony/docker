#!/bin/bash

docker builder prune -a -f
docker build --no-cache -t rd/maven:3.9.14-eclipse-temurin-21 .
# docker build --no-cache --network=host -t rd/maven:3.9.14-eclipse-temurin-21 .
