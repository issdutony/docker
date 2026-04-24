# Jenkins 容器化中的 Docker：DinD 與 DooD 完整解析

在 Jenkins 容器內執行 Docker 相關任務（如構建 Docker 映像檔、執行測試容器）時，最常見的做法有兩種：**DooD (Docker outside of Docker)** 與 **DinD (Docker in Docker)**。

## 1. 概念核心差異

| 特性 | DooD (Docker outside of Docker) | DinD (Docker in Docker) |
| --- | --- | --- |
| **運作原理** | 將宿主機 (Host) 的 `/var/run/docker.sock` 掛載到 Jenkins 容器內。 | 在 Jenkins 容器內部啟動一個獨立的 Docker Daemon。 |
| **容器層級** | Jenkins 啟動的新容器，與 Jenkins 容器屬於**平級關係**（都在宿主機上）。 | Jenkins 啟動的新容器，運行在 Jenkins 容器**內部**（巢狀關係）。 |
| **隔離性** | 差。共用宿主機的神經中樞，Jenkins 容器可以看到並控制宿主機上的所有容器。 | 好。擁有獨立的 Docker 環境與映像檔快取。 |
| **快取利用** | 直接使用宿主機的映像檔快取，速度快。 | 內部擁有獨立的快取，初始建置可能較慢。 |
| **安全性** | 較低。一旦 Jenkins 容器被攻破，攻擊者可透過 `docker.sock` 取得宿主機 root 權限。 | 取決於配置。雖然看似隔離，但 DinD 通常需要特權模式 (`--privileged`)，這本身就有安全隱患。 |
| **適用場景** | 單純需要利用 Docker 指令進行簡單建置、發佈，信任該 Jenkins 環境。 | 對隔離性要求較高，或者需要完全乾淨、無狀態的 CI 測試環境。 |

---

## 2. DooD (Docker outside of Docker) 完整做法

### 實作思路
透過掛載宿主機的 Socket 檔案，讓 Jenkins 容器內的 Docker Client 工具可以與宿主機的 Docker Daemon 通訊。

### 步驟與範例設定 (Docker Compose)

建立一個 `docker-compose.yaml` 檔案：

```yaml
version: '3.8'

services:
  jenkins:
    image: jenkins/jenkins:lts
             # 使用官方 Jenkins 長期支援版本
    user: root
             # [重要] 預設 Jenkins 以 jenkins 使用者執行，掛載 docker.sock 可能會產生權限不足 (Permission denied) 的問題。
             # 一種簡單做法是改用 root，另一種更安全的做法是自訂映像檔將 jenkins 使用者加入 docker 群組。
    container_name: jenkins_dood
    ports:
      - "8080:8080"
      - "50000:50000"
    volumes:
      - /your/home/jenkins_home:/var/jenkins_home
             # 將 Jenkins 資料持久化儲存至宿主機
      - /var/run/docker.sock:/var/run/docker.sock
             # [核心配置] 將宿主機的 Docker API Socket 對應到容器內
      # - /usr/bin/docker:/usr/bin/docker
             # ⚠️ [極度不推薦] 早期做法會將宿主機的執行檔掛載進容器，但這常因為 OS 環境或動態連結庫 (Library) 不一致而報錯。現代做法是不掛載它，而是自己利用 Dockerfile 在 Jenkins 內部安裝 docker-cli 工具。
```

### 相關指令說明
若不使用 Docker Compose，使用 docker run 指令的寫法如下：

```bash
docker run -d \
  -p 8080:8080 \
  -p 50000:50000 \
  -v /your/home/jenkins_home:/var/jenkins_home \
          # 掛載資料目錄以保留設定與建置紀錄
  -v /var/run/docker.sock:/var/run/docker.sock \
          # 將宿主機 docker socket 掛載進容器
  --name jenkins_dood \
  --user root \
          # 以 root 權限執行，避免 socket 存取被拒
  jenkins/jenkins:lts
```

### 解決權限問題的進階做法 (取代直接用 root)
寫一個自訂的 `Dockerfile`，安裝 Docker Client：

```dockerfile
FROM jenkins/jenkins:lts
USER root
# 安裝 Docker Client 先決條件
RUN apt-get update && apt-get install -y \
    ca-certificates curl gnupg \
# 下載 Docker 官方金鑰庫並設定來源
 && install -m 0755 -d /etc/apt/keyrings \
 && curl -fsSL https://download.docker.com/linux/debian/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg \
 && chmod a+r /etc/apt/keyrings/docker.gpg \
 && echo "deb [arch="$(dpkg --print-architecture)" signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/debian "$(. /etc/os-release && echo "$VERSION_CODENAME")" stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null \
# 安裝 Docker CLI 工具 (不包含 daemon)
 && apt-get update && apt-get install -y docker-ce-cli \
# 將 Jenkins 使用者加入 ping / docker 相關群組 (gid 在宿主機可能有所不同，需注意匹配)
 && groupadd -g 999 docker && usermod -aG docker jenkins

USER jenkins
```

---

## 3. DinD (Docker in Docker) 完整做法

### 實作思路
DinD 的做法是使用特殊的 `docker:dind` 映像檔，直接在一個特權容器內發行一個獨立的 Daemon。為了與 Jenkins 整合，我們通常會用到**兩個容器**一起協作模式：一個是 Jenkins 主節點容器，另一個是負責處理 Docker 任務的 DinD 容器。它們可以透過 TCP 網路互相通訊。

### 步驟與範例設定 (Docker Compose)

建立一個 `docker-compose.yaml` 檔案：

```yaml
version: '3.8'

services:
  # 負責執行 Docker Daemon 的 DinD 容器
  docker-dind:
    image: docker:dind
             # 使用官方提供的 DinD 映像檔
    container_name: jenkins_dind_docker
    privileged: true
             # [核心配置] 必須開啟特權模式才能在容器內再執行 Docker 層的控制功能 (如 cgroups)
    environment:
      - DOCKER_TLS_CERTDIR=/certs
             # 啟用 TLS 加密，保障通訊安全。憑證將會產生於此目錄
    volumes:
      - jenkins-docker-certs:/certs/client
             # 將產生的客戶端憑證獨立存放在 volume 提供 Jenkins 存取
      - jenkins-data:/var/jenkins_home
             # [重要] 必須與 Jenkins 端掛載相同的資料空間，因為當在 Jenkins 指出以目錄掛載容器時，Dind 會掛載到 "它自己" 視角的絕對路徑
    ports:
      - "2376:2376"

  # Jenkins 主應用戶端
  jenkins:
    image: jenkins/jenkins:lts
#   或自訂具有 docker-cli 的客製映像檔 (見 DooD 範例中 Dockerfile 安裝方式)
    container_name: jenkins_dind_master
    ports:
      - "8080:8080"
      - "50000:50000"
    environment:
      - DOCKER_HOST=tcp://docker-dind:2376
             # [核心配置] 指定 Docker 服務地址為 dind 容器
      - DOCKER_CERT_PATH=/certs/client
             # 指向正確的憑證路徑
      - DOCKER_TLS_VERIFY=1
             # 要求 TLS 驗證確保連線安全
    volumes:
      - jenkins-data:/var/jenkins_home
             # 這部分使得配置檔資料保持一致
      - jenkins-docker-certs:/certs/client:ro
             # 唯讀模式掛載並讀取 Docker 憑證

volumes:
  jenkins-data:
  jenkins-docker-certs:
```

### 相關指令說明
若不使用 Docker Compose，使用 CLI 指令分別啟動並建立網路的步驟如下：

**1. 建立共用網路與 Volumes**
```bash
docker network create jenkins-net
          # 建立提供內部通訊的橋接網路
docker volume create jenkins-docker-certs
          # 儲存連線所用的 TLS 憑證
docker volume create jenkins-data
          # 存儲 Jenkins 的專案與日誌歷史設定
```

**2. 啟動 DinD 守護執行容器**
```bash
docker run \
  --name jenkins-docker \
  --rm \
  --detach \
  --privileged \
          # [核心參數] 賦予該容器最高系統層級權限，讓它能建立網路、掛載檔案系統等子層的虛擬環境
  --network jenkins-net \
  --network-alias docker \
          # 提供 DNS 名稱 (alias)，讓之後加入同一網路的容器可以直接呼叫 "docker" 解析至本容器
  --env DOCKER_TLS_CERTDIR=/certs \
          # 指定憑證放置的預設檔案路徑
  --volume jenkins-docker-certs:/certs/client \
          # 掛載憑證至共用 Volume 中
  --volume jenkins-data:/var/jenkins_home \
          # [必須] 跟下面 Jenkins 使用同個 Workspace，以便 Jenkins 下構建指令找得到檔案
  docker:dind
          # 官方提供的 docker daemon image
```

**3. 啟動 Jenkins 主應用程式**
```bash
docker run \
  --name jenkins-server \
  --rm \
  --detach \
  --network jenkins-net \
          # 必須讓兩者在同一個虛擬網段中互連
  --env DOCKER_HOST=tcp://docker:2376 \
          # [核心參數] 指令 Jenkins 內部的 client 此處為 Docker API Daemon 的主機位址
  --env DOCKER_CERT_PATH=/certs/client \
          # 聲明客戶端要使用的憑證位置
  --env DOCKER_TLS_VERIFY=1 \
          # 開啟安全憑證加密連線
  --publish 8080:8080 \
  --publish 50000:50000 \
  --volume jenkins-data:/var/jenkins_home \
  --volume jenkins-docker-certs:/certs/client:ro \
  # 需要使用包含 docker-cli 的 Jenkins Image，您可以透過上述 DooD 中的 Dockerfile 自行編譯一個
  my-jenkins-with-docker-cli
```

---

## 4. 總結與最佳實踐建議

如果你想在 Jenkins 內僅進行「構建並推送 (Build & Push)」動作，或者在專案間**沒有互相干擾的高風險**：
🌟 **推薦選項：優先選用 DooD** (配置最為輕量、且重複使用宿主機的 Docker 快取以提升速度)。只需透過 `groupadd/usermod` 適當處理好 Jenkins 容器內讀取 `docker.sock` 的權限，避免直接使用 `root` 以強化安全。

如果你希望擁有一個極度隔離、每次發佈都能重置不受干擾的環境，或是需要在 CI 流程中建置像 `k8s` in `docker` (KinD) 這樣複雜的架構：
🌟 **推薦選項：使用 DinD**。請明確認知啟動 `--privileged` 帶來的風險，並確保運作 Jenkins 跟 Dind Container 的伺服器在內網受保護的情境下工作。

---

## 5. 為什麼說 DinD 的隔離性較高？

說「DinD 隔離性較高」，主要是因為 **Jenkins 中發生的 Docker 行為，不會直接影響或干擾到底層宿主機 (Host) 上正在運作的其他服務。** 

以下詳述為什麼 DinD 可以達到這種隔離效果：

### 1. 獨立的守護進程 (Dedicated Daemon)
*   **DooD 情境：** Jenkins 共用宿主機的 Docker Daemon。如果 Jenkins 在建置過程中執行了 `docker kill $(docker ps -q)` 或 `docker system prune -a`（這在 CI/CD 清理腳本中很常見），它會**把宿主機上所有的資料庫、Nginx 等其他專案的容器全部刪除**，引發嚴重的災難。
*   **DinD 情境：** Jenkins 操作的是位於 DinD 容器**內部**的獨立 Docker Daemon。剛才那些破壞性指令，只會在 DinD 容器內部生效，最糟的情況只是搞砸了那一次的建置環境，宿主機上其他的網路服務完全不受影響。

### 2. 命名與網路防衝突 (No Naming/Network Collisions)
*   **DooD 情境：** 假設有兩個 CI 任務同時執行，而且都需要啟動一個叫做 `mysql-test` 的資料庫容器給測試環境使用，或者同時嘗試將容器的埠號暴露並綁定 `3306`，它們會在宿主機的層級發生名稱衝突或通訊埠佔用錯誤。
*   **DinD 情境：** 若替專案配置隔離的 DinD 節點，測試用的容器是在 DinD 這個「沙箱」內部發配虛擬網路與容器名稱，不會溢出到宿主機，因此不會與宿主機層發生衝突。

### 3. 專屬的檔案系統與映像檔快取 (Isolated Storage)
*   DinD 擁有自己獨立的 `/var/lib/docker` 儲存空間。這意味著 CI 環境有著完全乾淨的初始狀態，不會受到宿主機上「剛巧存在」的舊版映像檔快取而造成意外成功或失敗。這對於保證「每次建置結果都是一致且可重現的 (Reproducible Builds)」至關重要。

### 4. 訪問權限的受限 (Scope of Visibility)
*   在 DooD 中，Jenkins 只要輸入 `docker ps`，就能窺探甚至控制宿主機上所有其他無關容器的資訊，這存在越權資料存取的隱患。
*   在 DinD 中，Jenkins 只能看到自己在 DinD Sandbox 裡面產生出來的容器，無法得知宿主機在運算什麼。

> [!WARNING]
> **「隔離」不等於「絕對安全」**
> 雖然 DinD 在 **應用程式層與開發流程** 上提供了極佳的防干擾隔離，但因為它的底層通常仰賴 `--privileged` (特權模式) 啟動來取得建立巢狀 Cgroups 的能力，其實它握有極大權力。如果駭客透過漏洞在 DinD 容器裡獲得 Root 執行權，仍有較高機率可透過特權模式越獄 (Privilege escalation) 退回宿主機。因此說它隔離度高是指「開發隔離」，在防範惡意攻擊的資安層面上仍要多加注意。

---

## 6. 如何解決 DinD 需要 `--privileged` 特權模式的安全隱憂？

如果安全團隊不允許在正式環境中開啟 `--privileged`，但您又需要類似的隔離建置與運行能力，可以考慮以下幾種替代方案與最佳實踐：

### 1. 使用切換至無根 Docker (Rootless DinD)
官方提供了 `docker:dind-rootless` 映像檔。這允許您以非 root 使用者身分啟動 Docker Daemon。
雖然它能夠大幅度降低越獄風險，但**仍可能需要部分進階權限**，例如開放特定的 Capabilities 且必須搭配宿主機 User Namespaces 配置。
*   **優點：** 就算服務被控制，攻擊者突破沙箱後在宿主機上也只是一個無特權的普通帳號。
*   **缺點：** 儲存驅動 (Storage Driver) 的支援有限，且宿主機層的設定較為繁雜 (如 `/etc/subuid`)。

### 2. 使用 Sysbox Runtime (專屬隔離執行環境)
[Sysbox](https://github.com/nestybox/sysbox) 是一種專為「在容器內無特權跑容器」設計的 OCI Container Runtime。
它透過強大的 Kernel 層級 User Namespace 隔離，讓您可以**完全不增加 `--privileged`** 的狀況下，在容器內順利運行 Docker Daemon、Systemd 甚至 Kubernetes (KinD)。
*   **優點：** 完美取代特權模式的 DinD，讓容器具備近乎虛擬機 (VM) 的強大隔離性與安全性。
*   **缺點：** 需要在底層虛擬機修改預設的 Runtime (替換掉原生的 runc)，對既有的維運環境改動較大。

### 3. 切換至無 Daemon 的建置工具 (Daemonless Builders - 推薦 ⭐)
如果 Jenkins 內部發起 Docker 的需求「**只是為了打包 Docker Image 並推送到倉庫**」，而不是要在 CI 中臨時把容器跑起來做測試網頁，那麼強烈建議**完全拋棄 Docker Daemon (DinD/DooD)，改用無守護進程的建置專業工具**：
*   **Kaniko (Google 開源)：** 最熱門的做法。它連 Docker Daemon 都不需要，完全在 Application user-space 中解析 Dockerfile，層層建置出映像檔，執行時**完全不需要任何特權參數**。
*   **Buildah (Red Hat 開源)：** 類似 Kaniko，專為相容 OCI 標準的無根建置所設計。
*   **優點：** 是目前實務上最安全的 CI/CD 容器建置方案，特別適合管制的嚴格環境與 Kubernetes 架構。

### 4. 遷移至 Kubernetes 原生架構分配資源
如果您的 Jenkins 已經具備條件遷移至 Kubernetes 叢集 (使用 Jenkins Kubernetes Plugin)，可以善用 K8s 的隔離機制。
*   讓每一次的建置，都是一個動態產生的 Pod。該 Pod 可以只包含需要的工具鏈，即使為了完整測試開啟了一定的權限 (如 DinD Pod)，生命週期也只存在於那數分鐘建置期間，完成即銷毀。
*   在這種原生架構中，絕大部分都會拋棄 DinD，直接切換到以 **Kaniko Container** 執行的 Pod 來專職做打包動作，免除了維護長壽命 DinD Node 的任何風險。

> [!TIP]
> **總結：**
> 1. 如果您的重點是「自動化 Build Image」，以安全掛帥請絕對首選轉換成 **Kaniko** 工具。
> 2. 如果您的重點是想「在容器中動態 Run 各種服務器測試」，則可以請維運團隊研究底層導入 **Sysbox Runtime** 來根本解決問題。

---

## 7. Docker Swarm 環境下的建議與抉擇

如果您是在 **Docker Swarm** 叢集中部署 Jenkins 與 CI Agent，狀況會變得非常特殊。在這類叢集環境中：

⭐ **結論：強烈建議使用 DooD (或更佳的 Kaniko)，極度不建議使用 DinD。**

### 為什麼在 Swarm 中不推薦 DinD？
**Swarm 對 `--privileged` 的嚴格限制：** 
基於安全架構設計，Docker 官方在 Swarm 叢集模式 (`docker stack deploy` 或是 `docker service create`) 中，**預設不支援 `--privileged` 參數**。這意味著您無法利用原生的 Swarm Service 語法去優雅地擴展或調度一個標準的 DinD 節點。如果硬要跑 DinD，維運人員通常只能被迫退回單機使用 `docker run` 來起容器，這會打亂整體 Swarm 服務的一致性與自動恢復能力。

### 在 Swarm 中使用 DooD 的最佳實踐與架構
如果您的 CI 流程不僅要「打包映像檔」，還要自動透過 `docker stack deploy` 發佈新版本到 Swarm 中，**DooD 是最實際的妥協選擇**。但請遵循以下架構設計：

1. **掛載 Socket (`/var/run/docker.sock`)：** Swarm 完美支援 `type: bind` 掛載 Socket，Jenkins Agent 依然能輕鬆與本機的 Daemon 溝通來打包 Image。
2. **管理節點部署限制 (Placement Constraints)：** 如果 Jenkins Agent 需要執行 `docker service update` 或 `docker stack deploy` 等控制命令，它**必須**被分配到 Swarm 的 Manager Node 上（因為 Worker Node 無法呼叫管理 API）。您必須在設定檔中註明：
   ```yaml
   deploy:
     placement:
       constraints: [node.role == manager]
   ```
3. **優化解法：Worker 建置 + 遠端發佈：** 
   若把繁重的編譯任務丟給 Manager Node 會影響叢集穩定性。更好的做法是將 Jenkins Agent (DooD) 佈署在普通的 **Worker Node** 上專做打包，並在需要「發佈」的最終階段，透過 Jenkins 腳本以 `SSH` 登入 Manager Node 執行指令，或是設定 `DOCKER_HOST=tcp://<manager-ip>:2376` (加上 TLS 憑證) 進行安全的遠端呼叫機制。

> [!TIP]
> 總之，如果在 Swarm 環境下設計 CI/CD 架構：
> - **單純打包 Image：** 改用完全與 Daemon 脫鉤的 **Kaniko**。
> - **需要使用 Docker CLI 進行自動化部署：** 請使用 **DooD**，但請極度重視權限邊界，並妥善規劃 Manager Node 與 Worker Node 的任務配置。

---

## 8. 實戰陷阱：以 Jenkins 容器動態啟動 Docker Agent (Stage Container) 可行嗎？

**答：完全可行，這也是業界最常見的現代化 CI/CD 架構！** 但如果你是在前述的 **DooD 環境**下操作，非常容易踩到一個著名的「**Workspace 目錄空白陷阱 (Volume Mount Trap)**」。

### 情境描述
假設你的 Jenkins 本身是跑在一個 Docker 容器中，且你在 Pipeline 中寫了以特定 Image 來編譯前端或後端專案，像這樣：
```groovy
pipeline {
    agent none
    stages {
        stage('Build node app') {
            // 這個 Stage 會因為 Cloud 或者 Pipeline 外掛，動態啟動包含 Node 18 的新容器來執行
            agent {
                docker { image 'node:18' }
            }
            steps {
                sh 'npm install && npm run build'
            }
        }
    }
}
```

### 💣 DooD 發生的嚴重災難 (找不到原始碼)
若 Jenkins 是使用 DooD (掛載 `/var/run/docker.sock`)，它會將需求傳遞給底層的「宿主機 Docker Daemon」來建立 `node:18` 這個新編譯容器。
為了讓 `node:18` 能讀到專案代碼，Jenkins Pipeline 會自動嘗試把當前的 Workspace 資料夾掛載給 `node:18`，**但這會發生路徑認知錯亂**：

1. Jenkins 告訴宿主機 Daemon：「幫我把我的 `/var/jenkins_home/workspace/my-job` 資料夾，掛載到 `node:18` 這個容器內」。
2. 宿主機收到指令後，呆呆地去尋找宿主機上的 `/var/jenkins_home/workspace/my-job`... 但這個路徑只存在於 Jenkins 容器內，宿主機上根本不存在！
3. 結果：宿主機在 `node:18` 內掛載了一個空無一物的假目錄，導致 Pipeline 報錯：`npm ERR! enoent ENOENT: no such file or directory, open 'package.json'`。

### ✨ 破解此陷阱的三種解法

#### 解法 1：維持 DooD，但讓宿主機與容器的「實體目錄」100% 完全對稱 (推薦)
啟動您的 Jenkins 主服務時，如果改用實體路徑掛載 (Bind Mount)，必須讓掛載前後的**字串長得一模一樣**。
```yaml
services:
  jenkins:
    ...
    volumes:
      # 左邊(宿主機)與右邊(容器內)的絕對路徑必須 100% 相同！
      - /var/jenkins_home:/var/jenkins_home
      - /var/run/docker.sock:/var/run/docker.sock
```
這樣一來，不管 Jenkins 要求宿主機掛載哪一個位於 `/var/jenkins_home/` 內的 Workspace，宿主機都能在對應的相同位置完美找到該資料夾並交給 Node 編譯容器。

#### 解法 2：改用 DinD 架構 (⚠️ 注意：Swarm 環境不適用)
如果是在一般單機 Docker 或 K8s 中，採用本篇第 3 章節介紹的 DinD 模式可以完美避開此問題。所有的 `agent { docker {...} }` 新生編譯容器，都會誕生在 DinD 這個隔離的沙箱裡面。由於大家都在同一套邏輯檔案系統之下工作，自然就不會有任何掛載路徑認知錯亂的問題了。**但正如第 7 節所述，如果您的基礎架構是落在 Docker Swarm 上，由於無法使用 `--privileged` 特權模式，此解法無法輕易實作，請堅決採用「解法 1」。**

#### 解法 3：使用 Docker Cloud Plugin 將 Agent 和 Master 物理分離
不要在 Jenkins Master (Controller) 就地運行編譯專用的 Pipeline，而是在 Jenkins 的 `Manage Jenkins -> System -> Cloud` 中設定。讓每一次 Job 被觸發時，由 Cloud 插件動態在別台 Node 上產生包含基礎環境與 Docker 引擎的 Agent (JNLP 節點)。只要讓那台 Agent 是乾淨的單機實體虛擬機，就能避開容器中跑容器的路徑錯亂。
