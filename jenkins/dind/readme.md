# Jenkins DinD (Docker-in-Docker)

## 1. Docker Image

- rebuild
    - from : `docker:dind`
    - to : `rd/docker:dind`
        - [`docker-dind/Dockerfile`](docker-dind/Dockerfile)
    - container name : `docker-daemon`
    - hostname : `docker-daemon`

## 2. Docker Compose

- docker:dind
    - [`docker-dind/docker-compose.yaml`](docker-dind/docker-compose.yaml)

## 3. 建立自簽憑證

- [`../certs/generate-certs.sh`](../certs/generate-certs.sh)
- 將憑證放至 `/opt/jenkins_cert/client`
    - key.pem
    - cert.pem
    - ca.pem

## 4. Build Image

- 在 **docker-daemon** 中 rebuild
    - from : `docker:cli`
    - to : `rd/docker:cli`
        - [`docker-cli/Dockerfile`](docker-cli/Dockerfile)

- 在 **docker-daemon** 中 rebuild
    - from : `maven:3.9.14-eclipse-temurin-21`
    - to : `rd/maven:3.9.14-eclipse-temurin-21`
        - [`../maven/Dockerfile`](../maven/Dockerfile)

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
    mkdir -p /home/jenkins/agent
    mkdir -p /home/jenkins/cache
    mkdir -p /home/jenkins/src
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
    - Docker Image : `rd/docker:cli`
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

- [`pipeline/jenkinsfile.dind.debug`](pipeline/jenkinsfile.dind.debug)
