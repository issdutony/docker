# Jenkins

## 1. Docker Image

- rebuild
    - from : `jenkins/jenkins:lts-jdk21`
    - to : `rd/jenkins:lts-jdk21`
        - [`Dockerfile`](Dockerfile)

## 2. Environment

- JENKINS_HOME (default : `/var/jenkins_home`) : `/opt/jenkins_home`
- DOCKER_TLS_CERTDIR (default : `/certs/client`) : `/opt/jenkins_cert/client`
- AGENT_WORKDIR (default : `/home/jenkins/agent`) : `/home/jenkins/agent`
- CACHE_DIR : `/home/jenkins/cache`
- SRC_DIR : `/home/jenkins/src`

## 3. Docker Compose

- [`docker-compose.yaml`](docker-compose.yaml)

## 4. Plugins

- `Manage Jenkins` > `Plugins` > `Available plugins`
    - Docker
    - Docker Pipeline
    - Lockable Resources
    - Pipeline Graph Analysis
    - Pipeline Stage View
    - Locale

## 5. Setting

- `Manage Jenkins` > `Nodes` > `Built-In Node` > `Configure`
    - Number of executors : `0`
    - Usage : `Only build jobs with label expressions matching this node`


- `Manage Jenkins` > `System`
    - `Jenkins URL` : e.g.,`http://docker-vm:8080/`

    - `Timestamper`
        - System clock time format : `'<b>'yyyy-MM-dd HH:mm:ss'</b>'`
        - Elapsed time format : `'<b>'HH:mm:ss.S'</b>'`
        - Enabled for all Pipeline builds`

- `Manage Jenkins` > `Appearance` > `Pipeline Stages`
    - Show pipeline stages on job page
    - Show stage names by default
    - Show stage durations by default

- `Manage Jenkins` > `Appearance` > `Pipeline Graph`
    - Show pipeline graph on build page
