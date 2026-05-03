# Jenkins

## 1. Environment

- JENKINS_HOME (default : `/var/jenkins_home`) : `/opt/jenkins_home`
- DOCKER_TLS_CERTDIR (default : `/certs`) : `/opt/jenkins_cert`
- AGENT_WORKDIR (default : `/home/jenkins/agent`) : `/home/jenkins/agent`
- CACHE_DIR : `/home/jenkins/cache`
- SRC_DIR : `/home/jenkins/src`


[jenkins/jenkins-server/docker-compose.yaml](https://raw.githubusercontent.com/issdutony/docker/refs/heads/main/jenkins/jenkins-server/docker-compose.yaml)

```yaml
name: jenkins

services:
  jenkins:
    image: rd/jenkins:lts-jdk21

    container_name: jenkins
    hostname: jenkins

    restart: always

    environment:
      - TZ=Asia/Taipei # 設定時區環境變數
      # 告訴 Jenkins 系統內部的 Docker CLI 連向我們剛剛架設的 docker-daemon 的 2376 port
      - DOCKER_HOST=tcp://docker-daemon:2376
      # [若改用自簽憑證] 指定 Jenkins 讀取 client 憑證的路徑，因為手動產生的資料夾內直含這些 pem 檔，所以用 /certs
      - DOCKER_CERT_PATH=/certs
      # 啟用 TLS 確認，1 代表 True
      - DOCKER_TLS_VERIFY=1
      # 告訴 Jenkins 內部路徑改了
      # - JENKINS_HOME=/opt/jenkins_home

    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
      - /opt/jenkins_home:/var/jenkins_home
      - /opt/jenkins_cert/client:/certs/client:ro

    ports:
      - "8080:8080"
      - "50000:50000"

    user: "jenkins"

    group_add:
      - "${DOCKER_GID:-999}"

networks:
  default:
    name: vm-network
    external: true
```

## 2. Plugins

- Docker
- Docker Pipeline
- Lockable Resources
- Pipeline Graph Analysis
- Locale

# Jenkins DooD Steps

## 1. Image

- jenkins/jenkins : lts-jdk21
- jenkins/inbound-agent : latest-jdk21

## 2. Steps

- Create Path : 
    - /home/jenkins/cache
    - /home/jenkins/src

- Clouds
    - Cloud name : `dood-cloud`
    - Type : `Docker`

- Docker Cloud details
    - Name : `dood-cloud`
    - Docker Host URI : `unix : ///var/run/docker.sock`
    - Enabled

- Docker Agent templates
    - Labels : `dood-agent`
    - Enabled
    - Docker Image : `rd/inbound-agent : latest-jdk21`
    - Container Settings
        - Mounts : `type=bind,source=/var/run/docker.sock,target=/var/run/docker.sock`
    - Remote File System Root : `/home/jenkins/agent`
    - Usage : `Only build jobs with label expressions matching this node`
    - Connect method : `Attach Docker container`
        - EntryPoint Cmd : `/entrypoint.sh`
    - Pull strategy : `Never pull`

## 3. Pipeline Test

```groovy
pipeline {
    agent {
        label 'dood-agent'
    }

    options {
        lock(resource: "lock-${JOB_NAME}")
        disableConcurrentBuilds()
        skipDefaultCheckout()
        buildDiscarder(logRotator(numToKeepStr: '5', artifactNumToKeepStr: '5'))
        // timestamps()
    }

    environment {
        // git
        TEZ_BRANCH = 'branch-0.10.5'
        TEZ_REPO = 'https://github.com/apache/tez.git'

        // Build
        CACHE_DIR = "/home/jenkins/cache/${JOB_NAME}/.m2"
        SRC_DIR = '/home/jenkins/src/tez'

        /// SonarQube
        SONAR_SERVER = 'sonar-server'
        PROJECT_KEY = 'dood-debug'
        PROJECT_NAME = 'Dood Debug'
    }

    stages {
        stage('1. Checkout') {
            steps {
                script {
                    def String dockerImage = 'alpine:latest'
                    def String dockerArgs = [
                        "-u root",
                        "-v ${SRC_DIR}:${SRC_DIR}",
                        "-v ${CACHE_DIR}:${CACHE_DIR}",
                        "--network vm-network"
                    ].join(' ')

                    docker.image(dockerImage).inside(dockerArgs) {
                        sh '''
                        cp -a ${SRC_DIR}/. ${WORKSPACE}/
                        chown -R 1000:1000 ${WORKSPACE} ${CACHE_DIR}
                        chmod -R 755 ${CACHE_DIR}
                        ls -la ${WORKSPACE}
                        ls -la ${CACHE_DIR}
                        '''
                    }
                }
                // input message: '繼續執行？', ok: 'Continue'
            }
        }

        stage('2. Build with Maven (skip tez-ui)') {
            steps {
                script {
                    def String dockerImage = 'rd/maven:3.9.14-eclipse-temurin-21'
                    def String dockerArgs = [
                        "-v ${CACHE_DIR}:${CACHE_DIR}",
                        "--network vm-network"
                    ].join(' ')

                    docker.image(dockerImage).inside(dockerArgs) {
                        sh '''
                        mvn clean package \
                            -DskipTests=true \
                            -Dmaven.javadoc.skip=true \
                            -pl !tez-ui \
                            -Dmaven.repo.local=${CACHE_DIR}
                        '''
                    }
                }
                // input message: '繼續執行？', ok: 'Continue'
            }
        }

        stage('3. SonarQube Code Quality Analysis') {
            steps {
                script {
                    def String dockerImage = 'rd/maven:3.9.14-eclipse-temurin-21'
                    def String dockerArgs = [
                        "-v ${CACHE_DIR}:${CACHE_DIR}",
                        "--network vm-network"
                    ].join(' ')

                    docker.image(dockerImage).inside(dockerArgs) {
                        withSonarQubeEnv("${SONAR_SERVER}") {
                            sh '''
                            mvn sonar:sonar \
                                -Dsonar.projectKey="$PROJECT_KEY" \
                                -Dsonar.projectName="$PROJECT_NAME" \
                                -Dsonar.java.binaries=. \
                                -pl !tez-ui \
                                -Dmaven.repo.local=${CACHE_DIR}
                            '''
                        }
                    }
                }
                // input message: '繼續執行？', ok: 'Continue'
            }
        }

        stage('4. Quality Gate') {
            steps {
                timeout(time: 10, unit: 'MINUTES') {
                    waitForQualityGate abortPipeline: true
                }
                // input message: '繼續執行？', ok: 'Continue'
            }
        }

        stage('5. Archive Artifacts') {
            steps {
                script {
                    sh '''
                    for f in tez-dist/target/tez-*.tar.gz \
                             tez-dist/target/tez-*-minimal.tar.gz \
                             tez-ui/target/tez-*.war; do
                        if [ -f "$f" ]; then
                            sha256sum "$f" > "$f.sha256"
                            echo "Generated SHA256 for $f"
                        fi
                    done
                    '''

                    // allowEmptyArchive:true 可防止找不到檔案時 Pipeline fail
                    archiveArtifacts artifacts:'''
                        tez-dist/target/tez-*.tar.gz,
                        tez-dist/target/tez-*-minimal.tar.gz,
                        tez-ui/target/tez*.war,
                        **/target/*.sha256
                    ''',
                    fingerprint: true,
                    allowEmptyArchive: true
                }
            }
        }
    }

    post {
        always {
            script {
                cleanWs(
                    deleteDirs: true,
                    disableDeferredWipeout: true
                )
                // cleanWs()
            }
        }
    }
}
```

# Jenkins DinD Steps

## Image

- docker : dind
- docker : cli

## Step

## 建立自簽憑證

- generate-certs.sh

## Build Image

- 在 docker-daemon 容器中 build docker : cli & maven image
- 在 docker-daemon 容器中 mkdir -p /home/jenkins/agent

## 匯入 TLS 到 Jenkins Credentials

1. `Manage Jenkins`
2. `Credentials`
3. `Global`
4. `Add Credentials`
5. Select a type of credential : `X.509 Client Certificate`
6. Add X.509 Client Certificate : 
    - Scope : `Global (Jenkins, nodes, items, all child items, etc)`
    - Client Key : `key.pem`
    - Client Certificate : `cert.pem`
    - Server CA Certificate : `ca.pem`
    - ID : `dind-client-certs`

## 設定 Docker Cloud

- Create Path in docker-daemon : 
    - /home/jenkins/cache
    - /home/jenkins/src
- Clouds
    - Cloud name : `dind-cloud`
    - Type : `Docker`
- Docker Cloud details
    - Name : `dind-cloud`
    - Docker Host URI : `tcp : //docker-daemon : 2376`
    - Server credentials : `dind-client-certs`
    - Enabled
- Docker Agent templates
    - Labels : `dind-agent`
    - Enabled
    - Docker Image : `rd/docker : cli`
    - Container Settings
        - Mounts : 
        ```
        type=bind,source=/var/run/docker.sock,target=/var/run/docker.sock
        type=bind,source=/home/jenkins/agent,target=/home/jenkins/agent
        ```
    - Remote File System Root : `/home/jenkins/agent`
    - Usage : `Only build jobs with label expressions matching this node`
    - Connect method : `Attach Docker container`
    - Remove volumes
    - Pull strategy : `Pull once and update latest`

## Pipeline Test

```groovy
pipeline {
    agent {
        label 'dind-agent'
    }

    options {
        lock(resource: "lock-${JOB_NAME}")
        disableConcurrentBuilds()
        skipDefaultCheckout()
        buildDiscarder(logRotator(numToKeepStr: '5', artifactNumToKeepStr: '5'))
        // timestamps()
    }

    environment {
        // git
        TEZ_BRANCH = 'branch-0.10.5'
        TEZ_REPO = 'https://github.com/apache/tez.git'

        // Build
        CACHE_DIR = "/home/jenkins/cache/${JOB_NAME}/.m2"
        SRC_DIR = '/home/jenkins/src/tez'

        /// SonarQube
        SONAR_SERVER = 'sonar-server'
        PROJECT_KEY = 'dind-debug'
        PROJECT_NAME = 'Dind Debug'
    }

    stages {
        stage('1. Checkout') {
            steps {
                script {
                    def String dockerImage = 'rd/maven:3.9.14-eclipse-temurin-21'
                    def String dockerArgs = [
                        "-v ${SRC_DIR}:${SRC_DIR}",
                        "-v ${CACHE_DIR}:${CACHE_DIR}",
                        "--network host"
                    ].join(' ')

                    docker.image(dockerImage).inside(dockerArgs) {
                        sh '''
                        cp -a ${SRC_DIR}/. ${WORKSPACE}/
                        '''

                        input message: '繼續執行？', ok: 'Continue'

                        sh '''
                        mvn clean package \
                            -DskipTests=true \
                            -Dmaven.javadoc.skip=true \
                            -pl !tez-ui \
                            -Dmaven.repo.local=${CACHE_DIR}
                        '''

                        input message: '繼續執行？', ok: 'Continue'

                        withSonarQubeEnv("${SONAR_SERVER}") {
                            sh '''
                            mvn sonar:sonar \
                                -Dsonar.projectKey="$PROJECT_KEY" \
                                -Dsonar.projectName="$PROJECT_NAME" \
                                -Dsonar.java.binaries=. \
                                -pl !tez-ui \
                                -Dmaven.repo.local=${CACHE_DIR}
                            '''
                        }

                        timeout(time: 10, unit: 'MINUTES') {
                            waitForQualityGate abortPipeline: true
                        }
                    }
                }
            }
        }

        stage('5. Archive Artifacts') {
            steps {
                script {
                    sh '''
                    for f in tez-dist/target/tez-*.tar.gz \
                             tez-dist/target/tez-*-minimal.tar.gz \
                             tez-ui/target/tez-*.war; do
                        if [ -f "$f" ]; then
                            sha256sum "$f" > "$f.sha256"
                            echo "Generated SHA256 for $f"
                        fi
                    done
                    '''

                    // allowEmptyArchive:true 可防止找不到檔案時 Pipeline fail
                    archiveArtifacts artifacts:'''
                        tez-dist/target/tez-*.tar.gz,
                        tez-dist/target/tez-*-minimal.tar.gz,
                        tez-ui/target/tez*.war,
                        **/target/*.sha256
                    ''',
                    fingerprint: true,
                    allowEmptyArchive: true
                }
            }
        }
    }

    post {
        always {
            script {
                cleanWs(
                    deleteDirs: true,
                    disableDeferredWipeout: true
                )
                // cleanWs()
            }
        }
    }
}
```