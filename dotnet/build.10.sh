#!/bin/bash

docker builder prune -a -f
docker build --no-cache -f Dockerfile.10 -t rd/mcr.microsoft.com/dotnet/sdk:10.0 .
