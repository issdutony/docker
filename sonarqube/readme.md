# SonarQube

## 1. Docker Compose

[`docker-compose.yaml`](docker-compose.yaml)

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
    - URL : `http://jenkins:8080/sonarqube-webhook/`

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
    - Server URL : `http://sonarqube:9000`
    - Server authentication token : `sonar-tonken`

- Manage Jenkins > Tools > SonarQube Scanner installations > Add SonarQube Scanner
    - Name : `sonar-scanner`
    - Install automatically
