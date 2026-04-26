FROM mcr.microsoft.com/dotnet/sdk:10.0

RUN apt update && \
    apt full-upgrade -y && \
    apt install --no-install-recommends -y openjdk-21-jdk && \
    dotnet tool install --global dotnet-sonarscanner && \
    apt autopurge -y && apt clean && rm -rf /var/lib/apt/lists/* /var/cache/apt/* /tmp/* /var/tmp/* && \
    <<EOF cat >> /etc/bash.bashrc
export PATH="$PATH:/root/.dotnet/tools"
EOF

# ENV ENV="/root/.bashrc"

