#!/bin/bash
# -----------------------------------------------------------------------------
# 檔案名稱: start-jenkins.sh
# 用途: 動態抓取 Docker Socket 權限並啟動 Jenkins 容器 (非 root 模式)
# -----------------------------------------------------------------------------

# 1. 定義 Jenkins 在主機(Host)上的持久化資料夾目錄
HOST_JENKINS_HOME="/var/jenkins_home"

# 如果主機上的資料夾不存在，就建立它
# 將擁有者設定為 UID 1000:GID 1000 以匹配容器內的 'jenkins' 帳號
if [ ! -d "$HOST_JENKINS_HOME" ]; then
    sudo mkdir -p "$HOST_JENKINS_HOME"
    sudo chown 1000:1000 "$HOST_JENKINS_HOME"
fi

# 2. 動態獲取主機 Docker Socket 的群組 ID (GID)
# 原理說明：每台機器的 docker 群組 ID 不見得會相同(Ubuntu 常見是 998 或 999)
# 使用 stat -c '%g' 可以得出該檔案歸屬的群組 ID 數字
DOCKER_SOCK_GID=$(stat -c '%g' /var/run/docker.sock)
echo "偵測到本機 Docker Socket GID 為: $DOCKER_SOCK_GID"

# 3. 啟動 Jenkins 容器
# 各指令 / 參數說明:
#   run              : 建立並執行一個新的容器
#   -d               : (detach mode) 在後台運行這個容器，不會卡住當前的終端機
#   --name           : 指定容器名稱為 jenkins-dood
#   --restart=always : 當 Docker 服務重啟或發生異常崩潰時，此容器會嘗試自動重啟
#   -p 8080:8080     : 將主機的 8080 埠口對應並接通到容器內的 8080 (這主要是給 Jenkins 網頁介面使用)
#   -p 50000:50000   : 將主機的 50000 埠口對應到容器內 (這用來讓代理節點/Agent 透過 JNLP 連線使用)
#   -v               : (Volume) 將主機的資料夾掛載到容器內部
#      $HOST_JENKINS_HOME:/var/jenkins_home -> 備份與保留 Jenkins 強制設定與 CI 資料
#      /var/run/docker.sock:/var/run/docker.sock -> 核心關鍵，將主機的 socket 檔與容器分享
#   -u jenkins       : 嚴格控制使用者。指定以登入使用者 jenkins 進入系統而非 root
#   --group-add      : (安全與權限關鍵) 在該容器執行時，為我們指定的使用者(jenkins)
#                      額外加上這個指定的群組 ID ($DOCKER_SOCK_GID)
#                      這樣就不會破壞主機套件，又能讓容器剛好能認得 socket！
#   my-jenkins:dood  : 我們剛剛自行 build 出來的 Image Name
docker run -d \
  --name jenkins-dood \
  --hostname jenkins-dood \
  --restart=always \
  -v $HOST_JENKINS_HOME:/var/jenkins_home \
  -v /var/run/docker.sock:/var/run/docker.sock \
  -u jenkins \
  --group-add "${DOCKER_SOCK_GID}" \
  my-jenkins:lts-jdk21

echo "Jenkins (DooD) 已經成功啟動！"

