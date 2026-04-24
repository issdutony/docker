# Jenkins

## 1. Docker Image

- rebuild
    - from : `jenkins/jenkins:lts-jdk21`
    - to : `rd/jenkins:lts-jdk21`
        - [`jenkins-server/Dockerfile`](jenkins-server/Dockerfile)

## 2. Environment

- JENKINS_HOME (default : `/var/jenkins_home`) : `/opt/jenkins_home`
- DOCKER_TLS_CERTDIR (default : `/certs`) : `/opt/jenkins_cert`
- AGENT_WORKDIR (default : `/home/jenkins/agent`) : `/home/jenkins/agent`
- CACHE_DIR : `/home/jenkins/cache`
- SRC_DIR : `/home/jenkins/src`

## 3. Docker Compose

- [`jenkins-server/docker-compose.yaml`](jenkins-server/docker-compose.yaml)

## 4. Plugins

- Docker
- Docker Pipeline
- Lockable Resources
- Pipeline Graph Analysis
- Pipeline Stage View
- Locale

# Jenkins DooD Steps

## 1. Image

- rebuild
    - from : `jenkins/inbound-agent:latest-jdk21`
    - to : `rd/inbound-agent:latest-jdk21`
        - [`dood/jenkins-agent/Dockerfile`](dood/jenkins-agent/Dockerfile)

## 2. Jenkins Setting

- Create Path on Docker Engine Host:

    ```bash
    sudo mkdir -p /home/jenkins/cache
    sudo mkdir -p /home/jenkins/src
    ```

- Clouds
    - Cloud name : `dood-cloud`
    - Type : `Docker`

- Docker Cloud details
    - Name : `dood-cloud`
    - Docker Host URI : `unix:///var/run/docker.sock`
    - Enabled

- Docker Agent templates
    - Labels : `dood-agent`
    - Enabled
    - Docker Image : [`rd/inbound-agent:latest-jdk21`](dood/jenkins-agent/Dockerfile)
    - Container Settings
        - Mounts : `type=bind,source=/var/run/docker.sock,target=/var/run/docker.sock`
    - Remote File System Root : `/home/jenkins/agent`
    - Usage : `Only build jobs with label expressions matching this node`
    - Connect method : `Attach Docker container`
        - EntryPoint Cmd : [`/entrypoint.sh`](dood/jenkins-agent/entrypoint.sh)
    - Remove volumes
    - Pull strategy : `Never pull`

## 3. Pipeline Test

- rebuild
    - from : `maven:3.9.14-eclipse-temurin-21`
    - to : `rd/maven:3.9.14-eclipse-temurin-21`
        - [`maven/Dockerfile`](maven/Dockerfile)
- pipeline
    - [`dood/pipeline/jenkinsfile.dood.debug`](dood/pipeline/jenkinsfile.dood.debug)

# Jenkins DinD Steps

## 1. Docker Image

- rebuild
    - from : `docker:dind`
    - to : `rd/docker:dind`
        - [`dind/docker-dind/Dockerfile`](dind/docker-dind/Dockerfile)
    - container name : **`docker-daemon`**

## 2. Docker Compose

- docker:dind
    - [`dind/docker-dind/docker-compose.yaml`](dind/docker-dind/docker-compose.yaml)

## 3. 建立自簽憑證

- [`certs/generate-certs.sh`](certs/generate-certs.sh)
- 將憑證放至 `/opt/jenkins_cert/client`
    - key.pem
    - cert.pem
    - ca.pem

## 4. Build Image

- 在 **docker-daemon** 中 rebuild
    - from : `docker:cli`
    - to : `rd/docker:cli`
        - [`dind/docker-cli/Dockerfile`](dind/docker-cli/Dockerfile)

- 在 **docker-daemon** 中 rebuild
    - from : `maven:3.9.14-eclipse-temurin-21`
    - to : `rd/maven:3.9.14-eclipse-temurin-21`
        - [`maven/Dockerfile`](maven/Dockerfile)

## 5. Jenkins Setting

### 匯入 TLS 到 Jenkins Credentials

1. `Manage Jenkins` > `Credentials` > `Global` > `Add Credentials`

- Select a type of credential : `X.509 Client Certificate`
- Add X.509 Client Certificate :
    - Scope : `Global (Jenkins, nodes, items, all child items, etc)`
    - Client Key : `key.pem`
    - Client Certificate : `cert.pem`
    - Server CA Certificate : `ca.pem`
    - ID : `dind-client-certs`

### 設定 Docker Cloud

- Create Path on **docker-daemon** :

    ```bash
    sudo mkdir -p /home/jenkins/agent
    sudo mkdir -p /home/jenkins/cache
    sudo mkdir -p /home/jenkins/src
    ```

- Clouds
    - Cloud name : `dind-cloud`
    - Type : `Docker`
- Docker Cloud details
    - Name : `dind-cloud`
    - Docker Host URI : `tcp://docker-daemon:2376`
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
