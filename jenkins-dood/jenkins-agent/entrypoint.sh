#!/bin/bash
# -----------------------------------------------------------------------------
# 腳本名稱: entrypoint.sh
# 用途: 動態偵測 Docker Socket 權限並自動將 Jenkins 納入群組
# -----------------------------------------------------------------------------

set -e # 遇到錯誤時立即報錯停止

echo "========== 啟動動態權限偵測程序 ==========" >&2

# 1. 偵測 /var/run/docker.sock 是否安全掛載進來了
if [ -S /var/run/docker.sock ]; then
    # 2. 自動偵測母機掛載進來的 socket GID 數字
    DOCKER_GID=$(stat -c '%g' /var/run/docker.sock)
    
    # 3. 檢查系統內是否已經有這個數字的群組。沒有就建一個叫 docker_agent 的群組
    if ! getent group "$DOCKER_GID" > /dev/null 2>&1; then
        groupadd -g "$DOCKER_GID" docker_agent
    fi
    
    # 4. 把預設的 jenkins 使用者塞進剛才拿到號碼的群組中
    usermod -aG "$DOCKER_GID" jenkins
    echo "[完成] 已成功辨識 Socket 並將 jenkins 納入群組 (動態 GID: $DOCKER_GID)" >&2
else
    echo "[警告] 未偵測到 /var/run/docker.sock! 請確認 Cloud 設定的 Volumes!" >&2
fi

echo "========== 授權完畢，準備啟動 Jenkins Agent ==========" >&2

# 5. 【終極降權指令】：
# 現在任務完成，我們不能再佔住特權。利用 gosu 工具，強制把衣服從 root 換成 jenkins。
# 並啟動正規 Jenkins 原本要跑的指令 (/usr/local/bin/jenkins-agent "$@")
exec gosu jenkins /usr/local/bin/jenkins-agent "$@"
