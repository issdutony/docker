# DooD (Docker-outside-of-Docker) 範例與詳解

**DooD (Docker-outside-of-Docker)** 是一種在容器 (Container) 內部使用 Docker 的技術架構。它的核心精神是：「不」在容器內安裝獨立的 Docker 引擎，而是**透過掛載宿主機的 Docker API Socket (`/var/run/docker.sock`)**，讓容器內的 Docker 執行檔向「宿主機的 Docker 守護進程 (Daemon)」發送指令。

這與 **DinD (Docker-in-Docker)** (在容器內執行一個完整的、獨立的 Docker 引擎) 是兩種截然不同的做法。目前在 CI/CD (如 Jenkins, GitLab CI) 領域中，DooD 是最主流且效能最好的實踐方式。

---

## 一、 DooD 的核心原理與圖解

當你在 DooD 容器內執行 `docker run ...` 或是 `docker build ...` 時，實際上是宿主機在代為建立與執行這些容器。因此新建的容器會與你的 Jenkins 容器處於**平行**的位置，而非在其內部。

```text
宿主機 (Host Machine)
 ├── Docker Daemon (負責真正建立和管理容器)
 │    ├── Jenkins Container (或任何 CI 工具) <----- 這裡透過 docker.sock 下達指令
 │    │
 │    ├── 剛剛被 Jenkins 呼叫產生出來的 Container A (平行級別)
 │    └── 剛剛被 Jenkins 呼叫產生出來的 Container B (平行級別)
```

## 二、 快速上手 DooD 的原生指令範例

這個範例將啟動一個包含 Docker 工具的簡單容器，並證明它所看見的是宿主機的環境。

```bash
# 透過 -v 參數，將宿主機的 docker socket 穿透進入容器內部
docker run -it --rm \
    -v /var/run/docker.sock:/var/run/docker.sock \
    docker:latest sh
```

進入該容器的 shell 之後，執行：

```sh
# 列出目前運行中的容器 (你會發現列出來的包含你自己這個容器本身，以及宿主機上的其他所有容器)
docker ps

# 在裡面啟動一個 nginx 測試容器
docker run -d --name nginx-test -p 80:80 nginx

# 離開容器
exit
```
當你退出回到宿主機後，輸入 `docker ps`，你會發現 `nginx-test` 是跑在宿主機上的！這就是 DooD 的真面目。

---

## 三、 Jenkins Pipeline 中的 DooD 實戰範例

在 Jenkins 的自動化流程中，最常見的 DooD 場景就是「編譯 Docker Image 並推送到映像檔庫 (Registry)」。

以下是一個具有詳細註解的 Jenkinsfile 範例。假設你的 Jenkins Agent 已具備掛載好 `/var/run/docker.sock` 以及具有 `docker` 執行檔的環境。

```groovy
pipeline {
    agent any // 或指定特定的 DooD agent label

    environment {
        // 設定環境變數
        IMAGE_NAME = "my-registry.local/my-app"
        IMAGE_TAG = "${env.BUILD_ID}"
    }

    stages {
        stage('Checkout Code') {
            steps {
                // 1. 取得原始碼
                git branch: 'main', url: 'https://github.com/example/my-app.git'
            }
        }
        
        stage('Build Docker Image via DooD') {
            steps {
                // 2. 透過容器內的 docker 執行檔，呼叫宿主機去執行 docker build
                sh '''
                   echo "開始建立映像檔..."
                   # 這裡的指令等同於交由宿主機的 Docker 來編譯
                   docker build -t $IMAGE_NAME:$IMAGE_TAG .
                '''
            }
        }
        
        stage('Push to Registry') {
            steps {
                // 3. (選用) 將編譯好的映像檔推送到私人倉庫
                //    Jenkins 透過 credentials 工具注入密碼變數
                withCredentials([usernamePassword(credentialsId: 'docker-registry-login', passwordVariable: 'DOCKER_PWD', usernameVariable: 'DOCKER_USER')]) {
                    sh '''
                       # 登入 Registry (同樣是在呼叫宿主機的 Docker daemon 進行身分驗證)
                       echo $DOCKER_PWD | docker login my-registry.local -u $DOCKER_USER --password-stdin
                       
                       # 上傳映像檔
                       docker push $IMAGE_NAME:$IMAGE_TAG
                    '''
                }
            }
        }
    }
    
    post {
        always {
            // 4. 清理環境：把剛剛在宿主機上產生出的 Image 刪除，避免硬碟空間塞滿
            sh '''
               echo "清除佔用的映像檔快取"
               docker rmi $IMAGE_NAME:$IMAGE_TAG || true
            '''
        }
    }
}
```

---

## 四、 優缺點評估

### 優點
1. **效能優異**：因為不用在容器內再墊一層虛擬化層，速度等同於直接在宿主機執行。
2. **共用資源**：能完全利用宿主機既有的 Docker Image 快取機制 (Layer Caching)，大幅縮短 Build 時間。
3. **無須特權模式**：與 DinD 必須開啟 `--privileged` 取用深層系統權限相比，DooD 安全性稍佳 (不需要全開防護，僅需掛載 socket)。

### 缺點與安全風險
1. **容器並非完全隔離**：如同範例所述，在 DooD 容器內可以輕易看見、甚至刪除宿主機上的「其他」容器（例如他不小心執行了 `docker rm -f jenkins-master`，就會造成自毀）。
2. **需要 Socket 權限**：/var/run/docker.sock 必須要有讀寫權限。通常這代表容器內的使用者必須是 `root`，或必須加入宿主機的 `docker` 群組。這為安全防禦開了一個洞。
3. **路徑對應問題 (Volume Mapping)**：如果你在 DooD 的環境中下了 `docker run -v /app/data:/data`，由於真正執行的是宿主機，因此那裡的 `/app/data` 指的地點是**宿主機的目錄**，而不是 DooD 容器內的目錄！這是在設計 Pipeline 腳本時最常遇到的坑。
