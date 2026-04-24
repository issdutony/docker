# SonarQube

## 1. Docker Compose

```yaml
name: jenkins

services:
    sonarqube:
        image: sonarqube:community
        hostname: sonarqube
        container_name: sonarqube
        restart: always
        read_only: true
        depends_on:
            db:
                condition: service_healthy
        environment:
            SONAR_JDBC_URL: jdbc:postgresql://db:5432/sonar
            SONAR_JDBC_USERNAME: sonar
            SONAR_JDBC_PASSWORD: sonar
        volumes:
            - sonarqube_data:/opt/sonarqube/data
            - sonarqube_extensions:/opt/sonarqube/extensions
            - sonarqube_logs:/opt/sonarqube/logs
            - sonarqube_temp:/opt/sonarqube/temp
        tmpfs:
            - /tmp:size=256M,mode=1777
        ports:
            - "9000:9000"
        networks:
            - default
    db:
        image: postgres:18.3-alpine
        healthcheck:
            test:
                [
                    "CMD-SHELL",
                    "pg_isready -d $${POSTGRES_DB} -U $${POSTGRES_USER}",
                ]
            interval: 10s
            timeout: 5s
            retries: 5
        hostname: sonarqube-db
        container_name: sonarqube-db
        restart: always
        environment:
            POSTGRES_USER: sonar
            POSTGRES_PASSWORD: sonar
            POSTGRES_DB: sonar
        volumes:
            - sonarqube_db:/var/lib/postgresql
            # - sonarqube_db_data:/var/lib/postgresql/data
        networks:
            - default

volumes:
    sonarqube_data:
        name: sonarqube_data
    sonarqube_temp:
        name: sonarqube_temp
    sonarqube_extensions:
        name: sonarqube_extensions
    sonarqube_logs:
        name: sonarqube_logs
    sonarqube_db:
        name: sonarqube_db
    # sonarqube_db_data:
    #   name: sonarqube_db_data

networks:
    default:
        external: true # 使用既有網路
        name: vm-network
```

## 2. SonarQube Setting

### URL

- Administration > Configuration > General settings > General
    - Server base URL : `http://sonarqube:9000`

### Token

- My Account > Security > Generate Tokens
    - Name : `jenkins-tonken`
    - Type : `Global Analysis Token`
    - Expires in : `No expiration`
    - e.g., `sqa_e43be5912aae01b2252c34cb43e607512341d235`

### Webhook

- Administration > Configuration > Webhooks > Create
    - Name : `jenkins-webhook`
    - URL : `http : //jenkins : 8080/sonarqube-webhook/`

## 3. Jenkins Setting

- Manage Jenkins > Plugins
    - Available plugins : `SonarQube Scanner`

- Manage Jenkins > Credentials > System > Global credentials > Add Credentials
    - Select a type of credential : `Secret text`
        - Scope : `Global (Jenkins, nodes, items, all child items, etc)`
        - Secret : `sqa_e43be5912aae01b2252c34cb43e607512341d235`
        - ID : `sonar-tonken`

- Manage Jenkins > System > SonarQube servers > SonarQube installations
    - Name : `sonar-server`
    - Server URL : `http : //sonarqube : 9000`
    - Server authentication token : `sonar-tonken`

- Manage Jenkins > Tools > SonarQube Scanner installations > Add SonarQube Scanner
    - Name : `sonar-scanner`
    - Install automatically
