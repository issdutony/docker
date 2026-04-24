#!/bin/bash
# =========================================================================
# 手動建立 Docker Daemon 與 Client 的 TLS 憑證
# (若使用 docker:dind 的 DOCKER_TLS_CERTDIR=/certs 機制，此步驟可省略)
# =========================================================================

# 1. 建立並進入憑證存放的資料夾
mkdir -p /opt/jenkins_certs && cd /opt/jenkins_certs

# ----------------------------------------------------
# A. 建立 CA (Certificate Authority) 根憑證
# ----------------------------------------------------
# 建立 CA 私鑰 (使用 RSA 4096 位元加密，為了方便 CI/CD 自動化已移除 -aes256 密碼保護)
openssl genrsa -out ca-key.pem 4096

# 建立 CA 根憑證，有效期限設定為 3650 天 (約十年)
# -x509: 產生自簽憑證，-sha256: 使用 SHA256 進行安全保護
openssl req -new -x509 -days 3650 -key ca-key.pem -sha256 -out ca.pem \
    -subj "/C=TW/ST=Taiwan/L=Taipei/O=MyOrg/OU=IT/CN=MyLocalCA"

# ----------------------------------------------------
# B. 建立 Server 端 (即 docker-daemon) 的憑證
# ----------------------------------------------------
# 建立 Docker Daemon 使用的私鑰
openssl genrsa -out server-key.pem 4096

# 產生憑證簽署請求 (CSR)，指定 Common Name(CN) 為服務名稱 docker-daemon
openssl req -subj "/CN=docker-daemon" -sha256 -new -key server-key.pem -out server.csr

# 建立限制檔案以支援 IP 解析，並允許該憑證可用於伺服器身份驗證
echo subjectAltName = DNS:docker-daemon,IP:127.0.0.1 >> extfile.cnf
echo extendedKeyUsage = serverAuth >> extfile.cnf

# 使用前面建出來的 CA 核發 server 的最終憑證
openssl x509 -req -days 3650 -sha256 -in server.csr -CA ca.pem -CAkey ca-key.pem \
    -CAcreateserial -out server-cert.pem -extfile extfile.cnf

# ----------------------------------------------------
# C. 建立 Client 端 (即 Jenkins) 的憑證
# ----------------------------------------------------
# 建立 Client 私鑰
openssl genrsa -out key.pem 4096

# 產生 Client 憑證申請，CN 可任意命名，此處使用 "client"
openssl req -subj "/CN=client" -new -key key.pem -out client.csr

# 限制屬性宣告為 Client 授權
echo extendedKeyUsage = clientAuth > extfile-client.cnf

# 使用 CA 核發給 Client 的最終憑證
openssl x509 -req -days 3650 -sha256 -in client.csr -CA ca.pem -CAkey ca-key.pem \
    -CAcreateserial -out cert.pem -extfile extfile-client.cnf

# ----------------------------------------------------
# D. 清理與掛載權限設定
# ----------------------------------------------------
# 清除產生時借用的暫存檔
rm -v client.csr server.csr extfile.cnf extfile-client.cnf

# 為了安全考量，將私鑰權限設定為唯讀
chmod -v 0400 ca-key.pem key.pem server-key.pem
chmod -v 0444 ca.pem server-cert.pem cert.pem

# 【掛載權限重點】
# 因為官方 Jenkins Container 執行程序的使用者身分 (UID) 預設為 1000：
# 如果您在主機上是用 root (UID 0) 產出這些檔案並設為 0400，Jenkins 掛載後會發生 Permission Denied 無法讀取。
# 相對的，docker-daemon 容器是以 root (UID 0) 運行，它可以無視 Owner 強制讀取所有檔案。
# 所以我們只要把整個憑證資料夾的擁有者變更為 UID 1000，即可一次完美滿足 Jenkins 和 Docker 兩者的讀取需求。
chown -R 1000:1000 $(pwd)

echo "所有憑證建立完成，存放於 $(pwd) 目錄。"