#!/bin/bash
set -e

# 定義目錄
CLIENT_CERT_DIR="/opt/jenkins_cert/client"
SERVER_CERT_DIR="/opt/jenkins_cert/server"

# DinD 容器在 Docker 網路中的 Hostname (必須與 DinD compose 的服務名稱/容器名稱一致)
DIND_HOSTNAME="docker-daemon"

echo "建立憑證目錄..."
sudo mkdir -p "$CLIENT_CERT_DIR"
sudo mkdir -p "$SERVER_CERT_DIR"

# 建立暫存目錄操作憑證
TMP_DIR=$(mktemp -d)
cd "$TMP_DIR"

echo "1. 產生 CA (Certificate Authority)..."
openssl genrsa -out ca-key.pem 4096
openssl req -new -x509 -days 3650 -key ca-key.pem -sha256 -out ca.pem -subj "/CN=MyDockerCA"

echo "2. 產生 Server 憑證 (供 docker:dind 驗證外部連線)..."
openssl genrsa -out server-key.pem 4096
openssl req -subj "/CN=$DIND_HOSTNAME" -sha256 -new -key server-key.pem -out server.csr
# 設定 SAN (Subject Alternative Name) 允許 Jenkins 透過 docker-dind 或 localhost 進行連線
echo "subjectAltName = DNS:$DIND_HOSTNAME,IP:127.0.0.1" > extfile.cnf
echo "extendedKeyUsage = serverAuth" >> extfile.cnf
openssl x509 -req -days 3650 -sha256 -in server.csr -CA ca.pem -CAkey ca-key.pem -CAcreateserial -out server-cert.pem -extfile extfile.cnf

echo "3. 產生 Client 憑證 (供 Jenkins 代表客戶端發起連線)..."
openssl genrsa -out key.pem 4096
openssl req -subj '/CN=jenkins-client' -new -key key.pem -out client.csr
echo "extendedKeyUsage = clientAuth" > extfile-client.cnf
openssl x509 -req -days 3650 -sha256 -in client.csr -CA ca.pem -CAkey ca-key.pem -CAcreateserial -out cert.pem -extfile extfile-client.cnf

# 調整權限與搬移到指定目標層
chmod -v 0400 ca-key.pem key.pem server-key.pem
chmod -v 0444 ca.pem server-cert.pem cert.pem

echo "將 Client 憑證移至 $CLIENT_CERT_DIR"
sudo cp -f ca.pem cert.pem key.pem "$CLIENT_CERT_DIR/"

echo "將 Server 憑證移至 $SERVER_CERT_DIR"
sudo cp -f ca.pem server-cert.pem server-key.pem "$SERVER_CERT_DIR/"

cd /
rm -rf "$TMP_DIR"
echo "憑證核發結束。"
