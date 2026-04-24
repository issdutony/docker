# 在 Jenkins Container 中建立 Cloud Agent (Docker) 詳細步驟與說明

本指南將詳細說明如何在以 Container 形式執行的 Jenkins 中，設定動態建立的 Docker Cloud Agent。這種作法可以讓 Jenkins 在執行 Pipeline 時自動建立臨時的代理節點 (Agent)，並在使用完畢後自動清理，達到資源靈活運用與環境隔離的目標。

## 前置條件 (環境設定)

為了讓 Jenkins Container 能夠控制宿主機 (Host) 的 Docker 引擎來啟動其他的 Agent Container，我們必須將宿主機的 Docker socket (`/var/run/docker.sock`) 掛載進 Jenkins Container 內。

### 1. 修改或建立 Jenkins 的 Docker Compose 設定檔

以下為 `docker-compose.yml` 的範例，確保 Jenkins 具備操作 Docker 的權限。

```yaml
version: '3.8' # 指定 docker-compose 語法版本

services:
  jenkins:
    image: jenkins/jenkins:lts # 使用 Jenkins 官方長期支援版本映像檔
    container_name: jenkins-master # 設定執行中的 Container 名稱
    user: root # 【注意】使用 root 權限執行，以確保有權限讀寫掛載的 docker.sock (生產環境建議建立客製化 image 將 jenkins user 加入 docker 群組)
    ports:
      - "8080:8080" # 將宿主機的 8080 埠映射至 Container 內的 8080 埠，供 Jenkins Web UI 使用
      - "50000:50000" # 將宿主機的 50000 埠映射至 Container 內的 50000 埠，供 Agent TCP 通訊使用 (Inbound agent)
    volumes:
      - jenkins_home:/var/jenkins_home # 掛載 volume，保留 Jenkins 系統設定、Plugin 與任務資料
      - /var/run/docker.sock:/var/run/docker.sock # 【關鍵】將本機的 docker socket 掛載進去，讓 Jenkins 具有操控宿主機的權限
      - /usr/bin/docker:/usr/bin/docker # 【選用】如果你希望也能在 Jenkins 的 shell 步驟直接下 docker 指令，可將此執行檔掛載進入
    restart: always # 當容器異常退出或系統重開機時，自動重啟服務

volumes:
  jenkins_home: # 定義 Jenkins 資料儲存的 docker 內部 volume
```

將上方的檔案存檔為 `docker-compose.yml` 後，執行啟動指令：
```bash
# 啟動並放到背景執行
docker-compose up -d
```

---

## 網頁控制台詳細設定步驟

### 步驟 1：安裝 Docker 外掛程式 (Plugin)

1. 登入 Jenkins Web UI (通常為 `http://<你的機器IP>:8080`)。
2. 進入頁面： **Manage Jenkins (系統管理)** ➔ **Plugins (外掛程式管理)**。
3. 切換至 **Available plugins (可用的外掛)** 標籤頁。
4. 在搜尋框輸入 `Docker`。
5. 勾選下列兩個基本套件：
   * **Docker**：用來建立 Cloud 節點的核心。
   * **Docker Pipeline**：讓你在 Jenkinsfile 中可以使用 docker 相關的宣告語法。
6. 點擊畫面下方的 **Install without restart (安裝但不重新啟動)**。待進度條安裝完成。

### 步驟 2：設定 Docker Cloud (雲端節點)

1. 進入頁面： **Manage Jenkins (系統管理)** ➔ **Clouds (雲端管理)** 或是在舊版裡位於 **Manage nodes and clouds** ➔ **Configure Clouds**。
2. 點擊右上角的 **New cloud (新增 Cloud)**。
3. 命名為 `docker-cloud`，類型選擇 **Docker**，然後點擊底部的 **Create**。
4. 在雲端的詳細設定區塊，點開 **Docker Cloud Details**。
5. **Docker Host URI**：輸入 `unix:///var/run/docker.sock`。
   * *這代表 Jenkins 透過我們先前掛載的本機 socket 來與外部 Docker 服務溝通。*
6. 點擊右側的 **Test Connection (測試連線)**。如果設定正確，此處會顯示當前宿主機的 Docker 版本與 API 版號。
7. 確認 **Enabled (啟用)** 有打勾。

### 步驟 3：建立 Docker Agent Template (節點範本)

同樣在這個頁面的下半部，此範本定義了 Agent 長什麼樣子、要用哪個 Container 打包。

點擊 **Docker Agent templates** 區塊，再點擊 **Add Docker Template**。
並且填妥下列關鍵欄位：

* **Labels (標籤)**：輸入 `docker-agent`。(這很重要，這是日後 Pipeline 指名要這個 Agent 的關鍵字)
* **Enabled (啟用)**：打勾。
* **Name**：輸入 `docker-builder`。(產生的 Agent 名稱會以這個名稱為字首)
* **Docker Image**：輸入要用作 Agent 的映像檔名稱，例如：`jenkins/inbound-agent:latest`。(官方預設包含基礎 Java)
* **Remote File System Root (遠端檔案系統根目錄)**：輸入 `/home/jenkins/agent`。(這是容器內執行工作與原始碼同步的位置)
* **Usage (使用方式)**：選擇 `Only build jobs with label expressions matching this node (只負責綁定此標籤的任務)`。
* **Connect method (連線方式)**：選擇 `Attach Docker container (透過 Docker 附加)` 或 `Connect with JNLP (透過 Inbound TCP)`。預設選 `Attach Docker container` 最簡單且不需額外設定密鑰。
* **Pull strategy (下載策略)**：可選擇 `Pull once and update latest (下載一次並更新)` 或 `Pull whenever there is a newer version`。

最後檢查無誤，點擊最下方的 **Save (存檔)**。

---

## 步驟 4：建立 Pipeline 測試

現在我們要驗證 Cloud Agent 是否能依據需求自動產生，然後自動銷毀。

1. 回到首頁並點選 **New Item (新增作業)**。
2. 命名為 `TestCloudAgent`，點選 **Pipeline**，按 **OK**。
3. 捲動到最下方的 **Pipeline script** 區塊，輸入下面的程式碼：

```groovy
// 宣告式 Pipeline 的進入點，必須包在 pipeline {} 中
pipeline {
    
    // 定義此 Pipeline 在哪個環境執行
    agent { 
        // 透過 label 指定我們要用剛才建立的 "docker-agent" 環境。
        // 當 Jenkins 找不到既有可用的機器時，會呼叫 Docker Cloud 動態創建一個新的 Container！
        label 'docker-agent' 
    }

    // 定義各個執行階段
    stages {
        stage('Test Agent Environment') {
            steps {
                // 第一步：簡單的列印訊息
                echo 'Hello from Dynamic Docker Cloud Agent!'
                
                // 第二步：執行 sh 指令，列出我們這台剛產生的 Agent 的基礎資訊，藉此驗證的確在容器內
                sh '''
                   # 印出系統版本資訊以確認是我們拉取的 Image
                   cat /etc/os-release
                   
                   # 確認 Java 版本，這是 agent 運作的基礎
                   java -version
                   
                   # 確認目前所在路徑，這應該會對應到我們設置的 /home/jenkins/agent 之下
                   pwd
                   
                   # 列出資料夾權限與所有者
                   ls -al
                '''
            }
        }
    }
    
    // 結尾動作
    post {
        always {
             echo '任務關閉，這台 Agent Container 將在一段時間後自動被 Jenkins 回收註銷。'
        }
    }
}
```

4. 點擊左下角 **Save (存檔)**。
5. 點選左側面板的 **Build Now (馬上建置)**。

### 預期結果
點開左側的 **Build History (建置歷程)** 中的 `#1`，點擊 **Console Output (終端機輸出)**。
你將會看到：
1. Jenkins 發現需要一個叫做 `docker-agent` 的環境。
2. Jenkins 透過 `/var/run/docker.sock` 對 Docker 發號施令，生成了一個名為 `jenkins-docker-builder-xxxxx` 的新 Container。
3. Container 下載程式碼、成功執行你的 Shell 指令。
4. 建置完成。若在 Jenkins 首頁左側的節點列表觀察，這個節點在閒置一段時間（預設約1~5分鐘）後，便會被 Jenkins 主動銷毀離線 (Offline)，不佔用多餘資源。
