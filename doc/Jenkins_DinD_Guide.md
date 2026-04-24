# Jenkins 與 Docker (DinD) CI/CD 完整建置與設定指南

本文件記錄了如何使用 Jenkins 及 Docker-in-Docker (DinD) 來建立強健的 CI/CD 環境。所有設定包含相關指令碼與參數說明皆已詳細註解。

---

## 1. 架構的 Docker Compose 設定檔 (Jenkins & Docker Daemon)
此設定檔將同時建立 `jenkins` 與 `docker-daemon` 兩個容器，並把它們連接到同一個自定義網路以利互相通訊。

新增檔案 `docker-compose.yaml`：

```yaml
version: '3.8'

# 建立專屬服務網路，讓 Jenkins 和 Daemon 可以透過 container_name 溝通
networks:
  vm-network:
    name: vm-network
    driver: bridge

# 設定持繼性存儲卷宗
volumes:
  jenkins-data:            # 給 jenkins 儲存專案或設定
  # jenkins-docker-certs:  # (若改用自己手動生成的 custom-certs 自簽憑證，此共用用 Volume 將不再需要)

services:
  # ----------------------------------------------------
  # 1. Docker DinD 服務設定
  # ----------------------------------------------------
  docker-daemon:
    image: docker:dind
    container_name: docker-daemon
    privileged: true       # DinD 執行必須開啟特權模式以操作核心功能
    networks:
      - vm-network
    environment:
      # [若改用自簽憑證] 將其設為空字串，以關閉官方 dind 在背景自動產生 TLS 憑證的行為
      - DOCKER_TLS_CERTDIR=""
    command:
      # [若改用自簽憑證] 透過命令列參數，明確指定我們手動建立的 TLS 憑證檔案位置
      - --tlsverify
      - --tlscacert=/certs/ca.pem
      - --tlscert=/certs/server-cert.pem
      - --tlskey=/certs/server-key.pem
    volumes:
      # 掛載供 Jenkins 使用的 workspace (當 DinD 啟動 container 時較不容易遇到找不到 volumes 的問題)
      - jenkins-data:/var/jenkins_home
      # [若改用自簽憑證] 直接將主機上我們建立的 custom-certs 資料夾掛載進容器內的 /certs
      - ./custom-certs:/certs:ro
    expose:
      # 分享預設的安全 TLS port，讓在 vm-network 的 Jenkins 可以存取
      - "2376"

  # ----------------------------------------------------
  # 2. Jenkins 服務設定
  # ----------------------------------------------------
  jenkins:
    image: jenkins/jenkins:lts
    container_name: jenkins
    depends_on:
      - docker-daemon      # 確保 Docker Daemon 先啟動
    networks:
      - vm-network
    ports:
      - "8080:8080"        # Jenkins UI 網頁介面
      - "50000:50000"      # Jenkins agent 連線預設使用的 port
    environment:
      # 告訴 Jenkins 系統內部的 Docker CLI 連向我們剛剛架設的 docker-daemon 的 2376 port
      - DOCKER_HOST=tcp://docker-daemon:2376
      # [若改用自簽憑證] 指定 Jenkins 讀取 client 憑證的路徑，因為手動產生的資料夾內直含這些 pem 檔，所以用 /certs
      - DOCKER_CERT_PATH=/certs
      # 啟用 TLS 確認，1 代表 True
      - DOCKER_TLS_VERIFY=1
    volumes:
      # 持續性儲存 Jenkins 組態資料
      - jenkins-data:/var/jenkins_home
      # [若改用自簽憑證] 同樣把你產出的 custom-certs 資料夾給 Jenkins，以提取 Client 及 CA 憑證
      - ./custom-certs:/certs:ro
```
> [!TIP]
> 執行此設定時，請於目錄下輸入指令啟動：`docker-compose up -d` 即可在背景執行您的 CI/CD 基礎設施。

---

## 2. 建立自簽憑證 (TLS)

**提示：** 在上述 `docker-compose.yaml` 中，由於我們使用了官方 `docker:dind` 映像檔並加上環境變數 `DOCKER_TLS_CERTDIR=/certs`，**Dind 啟動時會自動在背景替您生成一套自簽憑證**，因此一般情況下不必手動介入。
若您因企業規定或特殊需求，**必須「手動建置一套自己的自簽憑證」**，請建立並執行下列 Bash 指令碼 `generate-certs.sh`：

```bash
#!/bin/bash
# =========================================================================
# 手動建立 Docker Daemon 與 Client 的 TLS 憑證
# (若使用 docker:dind 的 DOCKER_TLS_CERTDIR=/certs 機制，此步驟可省略)
# =========================================================================

# 1. 建立並進入憑證存放的資料夾
mkdir -p custom-certs && cd custom-certs

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
```

---

## 3. Jenkins Docker Cloud 與 Container Template 設定

當 Jenkins 與 docker-daemon 皆已運行後，需要在 Jenkins UI 當中設定 Docker Cloud 使其可動態配置 Agent。

### 步驟 A: 匯入 TLS 到 Jenkins Credentials
1. 進入 Jenkins 首頁，點選左側 `Manage Jenkins` (管理 Jenkins) -> 選取底下的 `Credentials` (憑證管理)。
2. 在 `(global)` 區域選擇 `Add Credentials`。
3. `Kind` (類型) 選擇 `X.509 Client Certificate`。若沒看到代表還沒裝 **Docker plugin**，請至 Plugin Manager 安裝。
4. 設定 `ID` 欄位為：`docker-client-certs`。
5. 我們需要提供掛載到 Jenkins 的自簽憑證內容。您可以直接從主機的 `custom-certs` 資料夾中取得，或是透過下列指令從容器內倒出：
   - **Client Key:**
     ```bash
     docker exec jenkins cat /certs/key.pem
     ```
   - **Client Certificate:**
     ```bash
     docker exec jenkins cat /certs/cert.pem
     ```
   - **Server CA Certificate:**
     ```bash
     docker exec jenkins cat /certs/ca.pem
     ```
6. 按下 `Create` 完成儲存。

### 步驟 B: 設定 Docker Cloud 
1. 至 `Manage Jenkins` -> `Clouds`。
2. 按右上的 `New cloud` -> 名稱填 `docker`，型態選擇 `Docker` 並接著按 Create。
3. 把 `Docker Cloud details` 點開。
4. **Docker Host URI** 輸入：`tcp://docker-daemon:2376` (直接呼叫同一個網路當中的 daemon container 名字及 port)。
5. **Server credentials** 下拉選單選擇剛剛建立的憑證：`docker-client-certs`。
6. 按下左下方 `Test Connection`，若顯示類似 `Version: 24.0.x, API Version: 1.43` 的字樣，就代表 Jenkins 成功連線了！

### 步驟 C: 設定 Container Template (非必填，但若想設定固定範本可參考)
若您不希望在每個 Jenkinsfile 裡寫大量的 image 宣告，可在此繼續擴充一個 Template。
1. 在同一頁最底部可找到 `Docker Agent templates`，按 `Add Docker Template`。
2. **Labels:** `docker-agent` (這會讓 pipeline 透過指定 label 使用此環境)。
3. **Name:** 隨意命名，例如 `my-docker-agent`。
4. **Docker Image:** 此處**必須**填寫有安裝 Java 執行環境的映像檔，強烈建議使用客製化的 `jenkins/inbound-agent`。
   > [!WARNING] 
   > **致命地雷區：UI Template 本質上必須要有 Java！**
   > * 只要是在這個 Jenkins 網頁管理介面中設定的 Template，系統就會把它當作一個「完整的 Node 節點」。**Jenkins 的任何 Node 都必須使用 Java 來執行 `remoting.jar` 代理程式**。
   > * 所以您**絕對不能**在此處直接填寫 `docker:cli` 這種沒有 Java 的輕量映像檔！否則即便解決了 404 目錄掛載錯誤，最終也會在啟動時爆出 `exec: "java": executable file not found in $PATH` 導致啟動全毀。
   > * **標準解法一 (以 Jenkins 官方為底)**：自己寫一份 Dockerfile，以 `jenkins/inbound-agent` 為基底 (`FROM`)，以 `root` 身分透過 `apt-get` 裝入 `docker-ce-cli`。這能保持最正統穩定的 Jenkins Agent 環境。
   > * **標準解法二 (以 Docker 官方為底)**：自己寫一份 Dockerfile，以 `docker:cli` 為基底 (`FROM`)，透過 `apk add --no-cache openjdk17-jre` 裝入 Java 執行環境。這能保持極小的映像檔體積，但缺點是預設以 `root` 執行，且無法走原生 JNLP 回連。
   >
   > *(註：如果您不會用到 UI Template，而是使用 Pipeline 中的 `agent { docker { ... } }` 動態掛載，Jenkins 就不會把裡面當成子 Node，此時反而就可以放心使用無 Java 的原生 `docker:cli` 了！)*

5. **Remote File System Root:** 
   * 使用解法一 (`inbound-agent` 為底)：請填寫 `/home/jenkins/agent` (官方標準工作目錄)。
   * 使用解法二 (`docker:cli` 為底)：請改填 `/tmp` 或是 `/home` (輕型系統預設必定存在的目錄，否則會報錯 404)。
6. **Connect method:** 
   * 使用解法一 (`inbound-agent` 為底)：選取 `Connect with JNLP` 或 `Inbound Jenkins Agent` (業界推薦的穩定長連線)。
   * 使用解法二 (`docker:cli` 為底)：只能選取 **`Attach Docker container`**。
7. **Pull strategy:** 若您填寫的是官方公有庫 Image (如 docker:cli 等) 請選 `Pull once and update latest`；如果是您**手動自己編譯的客製化 Image (未推送到 Docker Hub)**，這裡請務必改選為 **`Never pull`**，否則會報錯 404 Access Denied。
8. **Network:** 請保持**空白**。*(因為 Agent 是被創建在 DinD 容器內部，填寫外層的 vm-network 會引發找不到網路而啟動失敗的崩潰錯誤)*。
9. 按下底下的 `Save` 儲存整體 Cloud 設定。

---

## 4. 測試用的 Pipeline

建立一個 `Jenkinsfile` (或是直接在 Jenkins 內建構新的 Pipeline Job 貼入此代碼)。這個範例將展現如何動態啟動包含 Docker CLI 的 Agent，並指示它使用剛設定好的安全 TLS 連向我們的 `docker-daemon` 進行 Image 建立。

```groovy
pipeline {
    agent {
        // 動態使用 Docker 啟動一個基於 docker:cli 的 Container 作為此 Pipeline 的執行階段
        docker {
            image 'docker:cli'
            // [終極解法] 為了避開 DinD 內部網路與 DNS 的複雜隔離地雷
            // 這裡我們直接掛載 DinD 自己內部的 /var/run/docker.sock 即可讓子容器完美接管！
            args '-u root -v /var/run/docker.sock:/var/run/docker.sock'
        }
    }
    
    stages {
        stage('連線測試 (Test Docker Connection)') {
            steps {
                script {
                    // 印出 Docker Daemon 連結狀態確認
                    echo "Testing connection to Docker Daemon via TLS DinD..."
                    sh 'docker info'
                }
            }
        }
        
        stage('模擬建置 (Build Image Demo)') {
            steps {
                script {
                    echo "Creating a dummy Dockerfile..."
                    // 在工作目錄中產出測試用的 Dockerfile
                    sh '''
                    cat <<EOF > Dockerfile
                    FROM alpine:latest
                    RUN echo "Hello from Jenkins and Docker in Docker!" > /hello.txt
                    CMD ["cat", "/hello.txt"]
                    EOF
                    '''
                    
                    echo "Building the Docker Image..."
                    // 執行打包 Image 的動作
                    sh 'docker build -t my-dind-test-image:latest .'
                }
            }
        }

        stage('驗證建置結果 (Verify Build)') {
            steps {
                script {
                    // 查詢剛剛打包出來的映像檔是否存在
                    echo "Check if the newly built image exists:"
                    sh 'docker images | grep my-dind-test-image'
                }
            }
        }
    }
}
```

---

## 5. 進階技巧：如何隱藏與省略 Pipeline 中的環境變數參數？

如果團隊內有多個專案，每次在 `Jenkinsfile` 的 `args` 裡都要傳遞落落長的環境變數與掛載不僅難以管理，也容易寫錯。您可以採用以下兩種方式來徹底簡化：

### 作法一：在 Jenkins UI Template 中使用 Socket 掛載法 (終極大絕招)
由於我們的系統跑在 DinD 架構中，Jenkins 叫出來的 Container Agent 實際上是誕生在 docker-daemon 容器「內部」的。這導致它無法輕易透過外層的 `vm-network` 網路，也無法解析對外的 TCP TLS `docker-daemon` 主機位置。

為了解決這個網路嵌套造成的崩潰地雷，我們可以使用**最直白強大且免設定憑證**的作法：直接把 DinD 自己內建的 Docker Socket 掛進去！

在 **Docker Agent templates** 頁面，展開 `Advanced` (進階選項) 區域：

1. **Network:** 請確認保持**空白**。
2. **Environments:** 請將之前寫的 DOCKER_HOST 等連線變數**刪除清空** (我們不再依靠 TCP 和 TLS 連線)。
3. **Mounts (或 Volumes):** 填寫 `type=bind,source=/var/run/docker.sock,target=/var/run/docker.sock`。

> [!TIP]
> **資安迷思：這不就變成傳說中不安全的 DooD 了嗎？**
> 乍看之下又掛載了 `docker.sock`，寫法跟 DooD (Docker-out-of-Docker) 一模一樣，但**這兩者在安全級別上是截然不同的**！
> * **傳統危險的 DooD**：掛載的是「物理宿主機 (Ubuntu)」的本機 Socket！一旦駭客取得權限下達 `docker stop` 或 `docker rm`，他可以隨意刪除您主機上包含資料庫、Jenkins 在內的所有容器，甚至駭進實體機。
> * **我們現在的作法 (Nested DooD)**：我們掛載的是「**DinD 隔離容器內部**」的 Socket！這個引擎裡除了準備被摧毀的 Agent 子容器以外，什麼都沒有。即使駭客獲得全部權限，他的破壞範圍 (Blast Radius) 也被死死鎖在 DinD 這個沙盒容器裡面，根本碰不到外面的核心。

一旦在這裡綁定並儲存，您寫 Pipeline 時只需要單純指定標籤 `agent { label 'my-docker-agent' }` 即可操作，**不再需要傳遞任何一丁點環境變數或是 TLS 憑證檔案！**

```groovy
pipeline {
    // 您只需要這一行！後台直接為您用內建 socket 接好 docker CLI 引擎 !
    agent { label 'my-docker-agent' } 
    
    stages {
        stage('Test') {
            steps {
                // 自動帶有 DOCKER_HOST 等環境變數，直接可用
                sh 'docker info' 
            }
        }
    }
}
```

### 作法二：自行封裝成客製化映像檔 (Custom Image)
如果您非常喜愛 Declarative Pipeline `agent { docker { ... } }` 的自帶拉取便利性，但不想要每次指定 `-e DOCKER_HOST`，您可以先寫一份 Dockerfile 打包出自己的執行環境：

```dockerfile
FROM docker:cli
# 將環境變數寫死封裝在裡面
ENV DOCKER_HOST=tcp://docker-daemon:2376
ENV DOCKER_TLS_VERIFY=1
ENV DOCKER_CERT_PATH=/certs
```
未來撰寫 Pipeline 時，除了將 image 指定為您私有的客製映像檔外，`args` 參數列就**只須留下掛載憑證的 `-v` 段落**便大功告成！

---

## 6. 進階解答：如何掛載並編譯位於「外部實體宿主機」的本地專案目錄？

在 DinD 架構中，Jenkins 開出的代理節點 (Agent Container) 是躲在 `docker-daemon` 容器肚子裡的。如果您的專案程式碼不是放在 Git 等 SCM 上，而是實實在在地躺在 Ubuntu 實體宿主機的某個資料夾 (例如 `/home/yuan/myproject`)，位在深層的子 Agent 絕對無法直接掛載它！

為了解決這個跨層級的訪問問題，我們必須使用「俄羅斯娃娃 (雙重掛載)」的通關技巧：

### 第一步：把主機目錄先「輸入」到 DinD 容器中
找到您最外層負責啟動環境的 `docker-compose.yaml`，在 `docker-daemon` 服務的 `volumes` 區段增加一行設定，把實體主機上的程式碼送進 Docker 引擎裡做準備：

```yaml
  docker-daemon:
    image: docker:dind
    # ...省略其他設定
    volumes:
      - jenkins-data:/var/jenkins_home
      # [新增這行] 將外層 Ubuntu 實體機上的專案資料夾映射進 DinD 內部備用
      - /home/yuan/myproject:/host-projects/myproject:ro
```
*(設定完後記得在實體機執行 `docker-compose up -d` 重啟 DinD 讓掛載生效)*

### 第二步：讓 Agent 從 DinD 手中取用該目錄
這時候對於 DinD 來說，它的目錄中已經有完整的程式碼了。當您在撰寫 Pipeline，或是設定 Jenkins UI Template 的掛載時，來源 (`source`) 就可以直接填寫前一步備用好的目錄：

**在 Pipeline 的掛載範例：**
```groovy
pipeline {
    agent {
        docker {
            image 'docker:cli'
            // 利用兩組 -v 參數達成操作：
            // 第一組掛載 Socket (取得操作引擎權限)
            // 第二組把 DinD 第一步拿到的目錄，再次往下掛給這個子 Agent 當作 /workspace
            args '-u root -v /var/run/docker.sock:/var/run/docker.sock -v /host-projects/myproject:/workspace:ro'
        }
    }
    stages {
        stage('Local Build') {
            steps {
                // 此時 Agent 內部看到的 /workspace，就是您 Ubuntu 實體主機上的 /home/yuan/myproject！
                sh 'docker build -t my-local-code-image /workspace'
            }
        }
    }
}
```
如果您是偏好使用 UI Template 的作法，則同樣可以在 Jenkins Cloud 的 **Mounts (或 Volumes)** 中再加一組：
`type=bind,source=/host-projects/myproject,target=/workspace,readonly`

透過這種「宿主機 ⮕ DinD ⮕ Agent」的雙層轉交機制，實體機的本地原始碼就能暢通無阻地直達最深層的建置環境了！

---

## 7. 疑難排解：在 Agent 內啟動 Container 時報錯 `could not be found among [/var/run/docker.sock]` 怎麼辦？

### 錯誤情境
在 Pipeline 中，您可能使用了宣告 `agent { docker { image 'maven' } }` 或是 `withDockerContainer('maven')` 試圖拉起一個環境容器來跑指令，但 Jenkins 面板吐出類似以下的警告並導致建置失敗：
```
docker-xxx seems to be running inside container yyy
but /tmp/workspace/pipeline-debug could not be found among [/var/run/docker.sock]
```

### 為什麼會這樣？
因為 Jenkins 非常的聰明，它發現您現在所在的節點 (`docker-xxx`) 本身**就已經是一個利用 Docker 生出來的子容器了**！
而您現在又想要從子容器裡面，再透過 `docker.sock` 叫出一個「孫輩容器」(Maven)。為了讓兩者能夠共享同一個 Workspace 原始碼，Jenkins 試圖去分析子容器身上的來源目錄，卻無奈地發現子容器身上只有掛載 `/var/run/docker.sock`，Workspace (`/tmp/...`) 只是暫時的系統檔案而非**獨立的 Docker Volume**，導致它無法把這個路徑傳接給孫輩容器。

### 解決方法
我們必須告訴 Jenkins UI Template：**請把這個 Agent 容器的 Workspace 目錄獨立變成一個 Volume**，這樣 Jenkins Pipeline 外掛才能拿這個 Volume 識別碼，接力傳給下一層容器！

1. 轉到 Jenkins 介面的 **Manage Jenkins -> Clouds -> 您的 Docker Cloud -> Agent templates**。
2. 展開 `Advanced` (進階選項)。
3. 在 **Mounts (或 Volumes)** 欄位中，除了您原本設定好的 `docker.sock` 掛載之外，再新增一行設定 (按下 Add)：
   ```text
   type=volume,target=/tmp/workspace
   ```
   *(註：如果這段 Pipeline 會大量運用 `@tmp` 目錄，您還可以多加一行 `type=volume,target=/tmp/workspace@tmp`)*

按下 Save 儲存！再次觸發您的 Pipeline，Jenkins 就會開心地發現：「太好了！Workspace 是一個實體 Volume，我可以直接把這個 Volume 同步分配給 Maven 容器了！」，建置任務就能夠順利通行了！

---

## 8. 效能優化：如何快取 Maven (.m2) 等套件依賴，避免每次 Pipeline 都重新下載？

在 Jenkins Docker 動態環境中，我們每次拉起的 Agent 都是「免洗 (Ephemeral)」的。這代表一旦 Pipeline 結束，整個容器連同它剛剛辛辛苦苦下載好幾百 MB 的 Maven 或 npm 依賴套件，全部都會灰飛煙滅。下一次建置時，它又得從零開始向全世界下載一次，嚴重拖慢 CI/CD 速度！

為了讓依賴套件可以「跨任務 (Cross-build) 持久化保存」，我們只需要使用 Docker 最強大的功能：**Named Volume (具名卷宗)**。

### 解決作法：
只要幫 Maven 在 DinD 引擎內要一塊「永遠不刪除的專屬硬碟」即可！

**如果您是在 Pipeline 中的 `args` 宣告：**
將這塊具名卷宗持久化掛載給 Maven 預設的緩存目錄 `/root/.m2`。
```groovy
pipeline {
    agent {
        docker {
            image 'tony/maven:3.9.14...'
            // 使用 `-v maven-repo-cache:/root/.m2`
            // Docker 會自動在底層建置一塊名為 maven-repo-cache 的硬碟供未來的每次建置共用！
            args '-u root -v /var/run/docker.sock:/var/run/docker.sock -v maven-repo-cache:/root/.m2'
        }
    }
    stages {
        stage('Build') {
            steps {
                sh 'mvn clean install'
            }
        }
    }
}
```

這個具名卷宗 (`maven-repo-cache`) 是儲存在真正執行 `docker run` 的守護行程（也就是您的 DinD 容器）身上。因此，**無論您未來生成了幾百萬個免洗的 Agent 代理節點，只要它們都是向 DinD 提出建置要求，且掛上了這個具名的 Volume，它們就能完美共享這份下載好的依賴快取！**
