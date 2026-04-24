FROM maven:3.9.14-eclipse-temurin-21

ENV OPENSSL_CONF=/dev/null

RUN apt update && \
    apt install --no-install-recommends -y curl bzip2 git protobuf-compiler && \
    curl -fsSL https://bitbucket.org/ariya/phantomjs/downloads/phantomjs-2.1.1-linux-x86_64.tar.bz2 \
    | tar -xj -C /usr/bin --strip-components=2 phantomjs-2.1.1-linux-x86_64/bin/phantomjs && \
    apt autopurge -y && apt clean && rm -rf /var/lib/apt/lists/* /var/cache/apt/* /tmp/*
