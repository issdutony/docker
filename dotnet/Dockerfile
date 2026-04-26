FROM mcr.microsoft.com/dotnet/sdk:10.0

RUN apt update && \
    apt full-upgrade -y && \
    apt install --no-install-recommends -y openjdk-21-jdk && \
    apt autopurge -y && apt clean && rm -rf /var/lib/apt/lists/* /var/cache/apt/* /tmp/* /var/tmp/*
