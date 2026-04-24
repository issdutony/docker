# Docker Swarm 與 GlusterFS 高可用性儲存架構建置指南
# Docker Swarm 與 GlusterFS 高可用性儲存架構建置指南

這份指南詳細說明了如何將 Docker Swarm 與 GlusterFS 結合，為微型及中小型叢集（例如 1 Manager + 2 Worker）提供最完美的持久化儲存解決方案，徹底消除單點故障（SPOF）。

## 架構設計與優勢

業界最穩定、且最不容易遇到外掛（Plugin）不相容問題的做法是：**「在底層 Host OS 建立並掛載 GlusterFS，然後上層的 Docker Swarm 直接以 Bind Mount (或 Local Volume) 的方式使用該目錄」**。

* **防爆力強**：擁有三份資料副本，叢集中任何一台機器的電源被拔除，剩餘節點上依然保有完整資料。
* **Docker 原生容錯**：Swarm 發現機器斷線，會立刻將 Container 重啟到健康節點。因為底層目錄早已透過 GlusterFS 同步，瞬間就能接手運作。
* **維護簡單**：完全不依賴第三方 Docker Volume Plugin，交給穩健的 Linux 核心處理檔案系統掛載。

---

## 假設環境與前置作業

假設您的 3 台主機 IP 分別為：
* **Node 1 (Manager)**: `192.168.1.10`
* **Node 2 (Worker 1)**: `192.168.1.11`
* **Node 3 (Worker 2)**: `192.168.1.12`

> **注意**：請確保這 3 台機器的防火牆有互相開放網路連線，測試期間可先暫時關閉內部防火牆限制。

---

## 第一階段：在底層系統建置 GlusterFS

### 步驟 1：安裝 GlusterFS (3 台主機均需執行)

以 Ubuntu / Debian 作業系統為例：

```bash
sudo apt update
# 安裝 GlusterFS 伺服器端與用戶端套件
sudo apt install glusterfs-server glusterfs-client -y

# 啟動服務並設定開機自動啟動
sudo systemctl enable --now glusterfs-server
```

### 步驟 2：組成信任池 (只需在 Node 1 執行)

挑選 Manager 節點 (Node 1)，主動去邀請另外兩台 Worker 節點加入儲存叢集。

```bash
# 從 Node 1 探測並加入另外兩個節點
sudo gluster peer probe 192.168.1.11
sudo gluster peer probe 192.168.1.12

# 檢查信任池連線狀態（應顯示已連接）
sudo gluster peer status
```

### 步驟 3：建立三副本的儲存卷 (只需在 Node 1 執行)

將三台機器的實體硬碟空間整合，建立一個具有容錯能力（Replica 3，即存 3 份副本）的雲端硬碟卷。此處假設將資料儲存在 `/gluster/brick` 目錄，卷名稱為 `gv0`。

```bash
# 建議先在 3 台機器上手動建立好存放層的空目錄
# sudo mkdir -p /gluster/brick

# 建立名為 gv0 的卷，指定 replica 3
sudo gluster volume create gv0 replica 3 \
  192.168.1.10:/gluster/brick \
  192.168.1.11:/gluster/brick \
  192.168.1.12:/gluster/brick \
  force

# 啟動這顆分散式儲存卷
sudo gluster volume start gv0
```

---

## 第二階段：在主機掛載這個雲端硬碟

### 步驟 4：將 Gluster 卷掛載到 Linux 本地路徑 (3 台主機均需執行)

我們統一在每台機器上建立一個共同的入口目錄（例如 `/mnt/swarm_data`）。當檔案寫進這裡時，GlusterFS 即會在其背後自動處理同步。

```bash
# 建立共用的掛載入口目錄
sudo mkdir -p /mnt/swarm_data

# 執行掛載，來源使用 localhost:/gv0 以確保優先經由本機網路連線，提升效能與可靠度
sudo mount -t glusterfs localhost:/gv0 /mnt/swarm_data
```

**【重要建議：設定開機自動掛載】**
為了避免伺服器重開機後遺失掛載，請將以下設定寫入 `/etc/fstab` 檔案中：

```text
# 在 /etc/fstab 加入此行：
localhost:/gv0  /mnt/swarm_data  glusterfs  defaults,_netdev  0  0
```

---

## 第三階段：部署 Docker Swarm 服務

至此，3 台伺服器的 `/mnt/swarm_data` 目錄已完全打通。對 Docker 而言，只需要當作本機的目錄直接掛載即可。

### 步驟 5：編寫與部署 docker-compose.yml

在您的工作目錄下建立 `docker-compose.yml`：

```yaml
version: "3.8"

services:
  web:
    image: nginx:latest
    ports:
      - "8080:80"
    deploy:
      replicas: 3 # 在叢集中啟動 3 個 Nginx 實例
    volumes:
      # 將容器內的網頁根目錄對應到底層掛載好的 GlusterFS 資料夾
      - type: bind
        source: /mnt/swarm_data/nginx_html
        target: /usr/share/nginx/html
```

在 Swarm Manager (Node 1) 上執行部署指令：

```bash
docker stack deploy -c docker-compose.yml my_stack
```

現在，無論哪個 Nginx 實例處理請求，讀取的都會是經過儲存叢集同步維護的高可用靜態檔案了！
