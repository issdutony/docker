# 在 Jenkins Cloud Agent 中再次使用 Docker Image 的做法與分析

如果您已經透過 Docker Cloud 動態產生了一個 Cloud Agent (這是一台 Container)，而您又希望在這個 Pipeline 中再呼叫其他的 Docker Image (例如 `maven:3` 或 `node:18` 來編譯程式)，這會遇到一個經典的架構挑戰。

## 💔 核心挑戰：Workspace 路徑不一致的陷阱 (The DooD Volume Trap)

在 Jenkins 宣告式寫法中，我們通常希望這樣寫：
```groovy
pipeline {
    agent { label 'docker-agent' } // 指派環境為我們的 Cloud Agent (第一層 Container)
    stages {
        stage('Build') {
            agent { 
                docker { image 'maven:3-alpine' } // 試圖用宣告語法啟動第二層 Container
            }
            steps { sh 'mvn clean package' }
        }
    }
}
```
**這麼做通常會失敗！**
因為在上一篇介紹的 **DooD (掛載 docker.sock)** 架構下，Jenkins 會向「宿主機」下達 `docker run -v /home/jenkins/agent/workspace/my-job:/home/jenkins/agent/workspace/my-job maven:3-alpine` 以建立第二層容器。  
由於宿主機收到指令後去找的是「**宿主機系統上的**」 `/home/jenkins/agent/workspace`，但這個裝有原始碼的目錄其實只存在於「第一層 Cloud Agent Container 內部」，結果導致第二個 (Maven) 容器拿到一個完全空的資料夾，因為找不到任何專案檔案而編譯報錯。

為了解決這個問題，業界常見有以下三種解決方案：

---

## 🟢 解法一：手動指令搭配 `--volumes-from` (維持 DooD 高效能)

**設計思維**：不依賴 Jenkins 原生幫你封裝好的 `agent { docker }` 語法，改用 Shell 指令自己呼叫宿主機的 Docker 時，利用 `--volumes-from` 參數掛載當前 Cloud Agent 的磁碟。

**前提條件**：
1. Cloud Agent 的 Docker Template 中須將 `/var/run/docker.sock` 掛載進 Container。
2. Cloud Agent 內建有 `docker` client 指令。

**範例腳本**：
```groovy
pipeline {
    // 指派給我們動態生成的 Cloud Agent
    agent { label 'docker-agent' } 

    stages {
        stage('取得程式碼') {
            steps {
                // 程式碼只會下載在目前的 Cloud Agent 空間裡
                git 'https://github.com/my-project.git'
            }
        }
        stage('使用別的 Image 進行建置') {
            steps {
                // 利用 --volumes-from $HOSTNAME 參數，讓新的 maven 容器可以「繼承穿透」看見當前 Cloud Agent 的所有檔案系統
                // 註：$HOSTNAME 代表當前執行中的 Cloud Agent 容器 ID
                // 註：-w $(pwd) 可以把工作目錄直接指到我們當下所在的 workspace
                sh '''
                   echo "使用另外的 Image 進行編譯..."
                   docker run --rm \
                       --volumes-from $HOSTNAME \
                       -w $(pwd) \
                       maven:3-alpine sh -c "mvn clean package"
                '''
            }
        }
    }
}
```

---

## 🟡 解法二：打包專屬的「萬能」Agent Image (最穩定推薦)

**設計思維**：如果您專案需要用到的環境是可預測的 (例如 Node + Maven + Docker)，與其在 Pipeline 裡不斷反覆啟動不同的 Image，不如直接寫一個 Dockerfile，把需要的工具全部一次裝進一個自訂的 Agent Image 裡面。

**Dockerfile 範例**：
```dockerfile
# 基於官方 Jenkins Inbound Agent
FROM jenkins/inbound-agent:latest

# 切換成 root 安裝必要工具
USER root

# 一併安裝 docker 用戶端、nodejs、maven 等 CI 所需的所有依賴包
RUN apt-get update && apt-get install -y docker.io nodejs maven

# 切換回標準執行權限
USER jenkins
```

** Pipeline 應用**：
把這個自訂好的 Image (例如 `my-custom-agent:v1`) 放進 Jenkins 雲端節點範本的 Image 欄位。那您的 Pipeline 就不用呼叫子容器，直接使用原本的環境即可：
```groovy
pipeline {
    agent { label 'docker-agent' } // 這個 agent 已經內建所有我們擴充的工具
    stages {
        stage('Build') {
            steps {
                // 全部工具都在同一個環境裡，不存在任何磁碟掛載問題
                sh 'npm ci'
                sh 'mvn clean package' 
            }
        }
    }
}
```

---

## 🔴 解法三：使用 DinD (Docker-in-Docker) 模式

**設計思維**：如果您非常希望 Pipeline 維持使用 Jenkins 原本原生的 `agent { docker { ... } }` 宣告式寫法，而且要磁碟自動掛載能完美生效，就必須把 Cloud Agent 從 DooD 改為完整的 **DinD (Docker-in-Docker)** 環境 (也就是在 Cloud Agent 裡面自己泡一個隔離的 Docker Daemon)。

**Jenkins 網頁的設定調整**：
1. 在 Jenkins 網頁的 Cloud Agent Template 中，Image 改填 `docker:dind` 或是包含 dind 技術的自製 agent。
2. **必須勾選 Privileged 特權模式** (這對安全性是一大讓步，不勾選 DinD 根本無法運作)。
3. **移除**宿主機的 `/var/run/docker.sock` Mount。這時 Agent 就有自己完整的沙盒宇宙了。

**範例腳本**：
DinD 環境建立後，原生的宣告式代碼又能夠正常發揮作用了：
```groovy
pipeline {
    agent { label 'dind-agent' } 
    
    stages {
        stage('Build') {
            // 這個寫法現在能完美生效，因為第二層 container 會被創建在 Dind Agent 內，路徑完全吻合，沒有 DooD 取代宿主目錄的問題
            agent {
                docker {
                    image 'maven:3-alpine'
                    reuseNode true // 【重要】要求此 Container 重複使用上一層(dind-agent) 的 workspace 節點
                }
            }
            steps {
                sh 'mvn clean package'
            }
        }
    }
}
```
**此法缺點：**
犧牲了權限安全性 (Privileged)，而且每次啟動 DinD 時這台代理人內部的 Docker 快取是空白的，您無法受惠於宿主機原本已下載過的 Image，導致下載速度變慢拉長整體 CI 時間。

---
## 總結：該挑哪一個？

1. **專案工具單一固定** ➔ 推薦 **「解法二」**，製作專用的 Build Image，直接解決痛點，也是大公司標準做法。
2. **需要時常變換各種工具 Image** ➔ 推薦 **「解法一」(`--volumes-from`)**，手寫指令稍微麻煩一點，但兼具高效能並解決路徑對應問題。
3. **非用 Jenkins 原生態宣告寫法不可** ➔ 才考慮使用 **「解法三」(DinD)** 方案。
