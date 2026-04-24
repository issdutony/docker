# 解決 Cloud Agent 中 `docker: not found` 錯誤

這個錯誤 `docker: not found` 發生在您的 Cloud Agent 容器內。
**發生原因：**這是因為您設定在 Jenkins 雲端範本 (Docker Template) 中使用的基礎映像檔 (Image)，例如官方預設的 `jenkins/inbound-agent` 或 `jenkins/agent`，**裡面預設只有安裝 Java，本身並沒有內建 `docker` 用戶端的指令執行檔。**

因為在 DooD (解法一) 中，雖然您已經將宿主機的通訊端點 `/var/run/docker.sock` 接了進去，但容器內依舊需要有 `docker` 這支基礎程式才能去跟 Socket 溝通。

要解決這個問題，我們有兩種常見的做法：

---

## 🛠️ 方案 A：建立一個內建 Docker 的自訂 Agent Image (最穩定推薦)

這是業界最標準且最不會踩雷的做法。我們不在 Pipeline 裡面處理，而是自己打包一個「裝有 Docker 用戶端」的 Jenkins Agent 映像檔，讓 Cloud Node 預設使用它。

### 步驟 1：建立 Dockerfile
在您的任何一台機器上，建立一個名為 `Dockerfile` 的檔案：

```dockerfile
# 使用 Jenkins 官方所提供的 Inbound Agent 做為最基礎的底層 (保障 Jenkins 連線所需之 Java 環境)
FROM jenkins/inbound-agent:latest

# 切換成最高權限的 root 帳號，以利進行軟體安裝
USER root

# 更新 APT 套件庫清單，並安裝 docker.io (這會安裝 docker client)
RUN apt-get update && \
    apt-get install -y docker.io && \
    rm -rf /var/lib/apt/lists/*

# (選用) 將原本的 jenkins 帳號加入 docker 群組
# 如果您宿主機的 docker.sock 沒有開放全域讀寫(chmod 666)，則需要這一步
# RUN usermod -aG docker jenkins

# 切換回預設的 jenkins 帳號，以符合 Jenkins 官方安全性最佳實踐
USER jenkins
```

### 步驟 2：打包並推送 (若有私有映像檔庫)
執行指令將此 Dockerfile 打包成新的映像檔：
```bash
# -t 標記您自己專屬的映像檔名稱
docker build -t my-jenkins-docker-agent:latest .
```

### 步驟 3：修改 Jenkins 設定
回到 Jenkins 網頁介面：
1. **Manage Jenkins** ➔ **Clouds** ➔ 找到您的 **Docker Agent templates**。
2. 將原先的 **Docker Image** (原本可能是 `jenkins/inbound-agent`) 改成您剛剛打包的名稱 `my-jenkins-docker-agent:latest`。
3. 儲存設定。
下次再跑 Pipeline 時，產生的 Agent 就具備 `docker` 指令可供操作了。

---

## 🪛 方案 B：硬掛載宿主機的 Docker 執行檔 (偷吃步、最快速)

如果您不想自己維護一份 Dockerfile，也可以試著在不改 Image 的前提下，直接把**宿主機的 `docker` 執行檔**當作檔案掛載進 Agent 裡面。

**做法：**
1. 進入 Jenkins 網頁控制台：**Manage Jenkins** ➔ **Clouds**。
2. 點開 **Docker Agent templates**。
3. 找到您的範本，展開進階設定尋找 **Volumes (磁碟空間)** 欄位。
4. 原本您應該只有寫一行 `/var/run/docker.sock:/var/run/docker.sock`。
5. 請空一行，加上掛載執行檔的路徑（共兩行）：
   ```text
   /var/run/docker.sock:/var/run/docker.sock
   /usr/bin/docker:/usr/bin/docker
   ```
   *(請確認您宿主機的 docker 安裝路徑的確是 `/usr/bin/docker`，可用 `which docker` 指令查詢)*
6. 儲存設定並重跑 Pipeline。

> ⚠️ **方案 B 注意事項：** 
> 將宿主機二進位檔直接掛入容器內部並不一定 100% 成功，這取決於您宿主機的 Linux 系統 (如 CentOS) 與 Agent 容器的 Linux 系統 (Debian/Ubuntu) 兩者之間共享函式庫 (glibc) 的相容性。如果相容性不符，執行時可能會發生 `libxxx.so not found` 或是 `cannot execute binary file` 的錯誤。若遇到該錯誤，請直接乖乖採用 **方案 A**。
