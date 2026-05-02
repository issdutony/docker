#!/bin/bash

docker builder prune -a -f
docker build --no-cache -f Dockerfile.8 -t rd/mcr.microsoft.com/dotnet/sdk:8.0 .
