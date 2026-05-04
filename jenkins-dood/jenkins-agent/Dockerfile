# -----------------------------------------------------------------------------
# 檔案名稱: Dockerfile-Agent
# -----------------------------------------------------------------------------

# 使用官方的代理機為基底
FROM jenkins/inbound-agent:latest-jdk21

# 切換到 root 以安裝所需工具
USER root

# 安裝 Docker CLI，並且多裝一個最重要的權限神兵： gosu
RUN apt update && \
    apt install --no-install-recommends -y ca-certificates curl gosu && \
    install -m 0755 -d /etc/apt/keyrings && \
    curl -fsSL https://download.docker.com/linux/debian/gpg -o /etc/apt/keyrings/docker.asc && \
    chmod a+r /etc/apt/keyrings/docker.asc && \
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] \
    https://download.docker.com/linux/debian $(. /etc/os-release && echo \"$VERSION_CODENAME\") stable" \
    | tee /etc/apt/sources.list.d/docker.list > /dev/null && \
    apt update && \
    apt install --no-install-recommends -y docker-ce-cli docker-compose-plugin && \
    apt full-upgrade -y && \
    apt autopurge -y && apt clean && rm -rf /var/lib/apt/lists/* /var/cache/apt/* /tmp/* && \
    <<EOF cat >> /etc/bash.bashrc
alias ll="ls -lAvF --time-style='+%Y-%m-%d %H:%M:%S' --group-directories-first --color=always"
alias la="ls -lavF --time-style='+%Y-%m-%d %H:%M:%S' --group-directories-first --color=always"
alias lh="ls -lAvFh --time-style='+%Y-%m-%d %H:%M:%S' --group-directories-first --color=always"
EOF

# 把我們第一步寫的神奇大腦腳本丟進去
COPY entrypoint.sh /entrypoint.sh

# 賞賜給腳本可執行的權力
RUN chmod +x /entrypoint.sh

# 【極度關鍵！！】：請保持這份 Dockerfile 結尾是 root 身分！
# 千萬不要寫出 USER jenkins！我們必須讓這台容器開機時是最高皇權 (root)，
# 才能讓 entrypoint 有資格執行 groupadd。
# 降階的工作我們已經寫在 entrypoint 裡交給 gosu 負責了。

# 宣告：請容器預設開機時，去跑我們寫的腳本
ENTRYPOINT ["/entrypoint.sh"]
