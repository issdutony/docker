FROM jenkins/jenkins:lts-jdk21

USER root

RUN apt update && \
    apt install --no-install-recommends -y ca-certificates curl && \
    install -m 0755 -d /etc/apt/keyrings && \
    curl -fsSL https://download.docker.com/linux/debian/gpg -o /etc/apt/keyrings/docker.asc && \
    chmod a+r /etc/apt/keyrings/docker.asc && \
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] \
    https://download.docker.com/linux/debian $(. /etc/os-release && echo \"$VERSION_CODENAME\") stable" \
    | tee /etc/apt/sources.list.d/docker.list > /dev/null && \
    apt update && \
    apt install --no-install-recommends -y docker-ce-cli docker-compose-plugin && \
    apt autopurge -y && apt clean && rm -rf /var/lib/apt/lists/* /var/cache/apt/* /tmp/* /var/tmp/* && \
    <<EOF cat >> /etc/bash.bashrc
alias ll="ls -lAvF --time-style='+%Y-%m-%d %H:%M:%S' --group-directories-first --color=always"
alias la="ls -lavF --time-style='+%Y-%m-%d %H:%M:%S' --group-directories-first --color=always"
alias lh="ls -lAvFh --time-style='+%Y-%m-%d %H:%M:%S' --group-directories-first --color=always"
EOF

USER jenkins
