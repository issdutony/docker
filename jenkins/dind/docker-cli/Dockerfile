FROM docker:cli

RUN apk add --no-cache openjdk21-jdk && \
    rm -rf /var/cache/apk/* && \
    <<EOF cat > /etc/profile.d/aliases.sh
alias ll="ls -lAvF --color=auto"
alias la="ls -lavF --color=auto"
alias lh="ls -lAvFh --color=auto"
EOF

ENV ENV="/etc/profile.d/aliases.sh"
