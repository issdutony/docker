# Jenkins DooD (Docker-outside-of-Docker)

## 1. Docker Image

- rebuild
    - from : `jenkins/inbound-agent:latest-jdk21`
    - to : `rd/inbound-agent:latest-jdk21`
        - [`jenkins-agent/Dockerfile`](jenkins-agent/Dockerfile)

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
    - Docker Image : [`rd/inbound-agent:latest-jdk21`](jenkins-agent/Dockerfile)
    - Container Settings
        - Mounts : `type=bind,source=/var/run/docker.sock,target=/var/run/docker.sock`
    - Remote File System Root : `/home/jenkins/agent`
    - Usage : `Only build jobs with label expressions matching this node`
    - Connect method : `Attach Docker container`
        - EntryPoint Cmd : [`/entrypoint.sh`](jenkins-agent/entrypoint.sh)
    - Remove volumes
    - Pull strategy : `Never pull`

## 3. Pipeline Test

- rebuild
    - from : `maven:3.9.14-eclipse-temurin-21`
    - to : `rd/maven:3.9.14-eclipse-temurin-21`
        - [`../maven/Dockerfile`](../maven/Dockerfile)
- pipeline
    - [`pipeline/jenkinsfile.dood.debug`](pipeline/jenkinsfile.dood.debug)
