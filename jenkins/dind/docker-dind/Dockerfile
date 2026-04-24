FROM docker:dind

# 使用 Heredoc 寫入，完全不用理會引號轉義問題
RUN apk upgrade --no-cache  && \
    rm -rf /var/cache/apk/* && \
    <<EOF cat > /etc/profile.d/aliases.sh
alias ll="ls -lAvF --color=auto"
alias la="ls -lavF --color=auto"
alias lh="ls -lAvFh --color=auto"
EOF

ENV ENV="/etc/profile.d/aliases.sh"
