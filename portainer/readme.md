# Portainer

## Docker Compose

- [`portainer-compose.yaml`](portainer-compose.yaml)

```yaml
name: rd-lab

services:
    portainer:
        image: portainer/portainer-ce:sts

        container_name: portainer
        hostname: portainer

        restart: always

        environment:
            - TZ=Asia/Taipei # 設定時區環境變數

        volumes:
            - portainer_data:/data
            - /var/run/docker.sock:/var/run/docker.sock
            - /etc/localtime:/etc/localtime:ro
            - /etc/timezone:/etc/timezone:ro

        ports:
            - 9443:9443
            - 8000:8000 # Remove if you do not intend to use Edge Agents

volumes:
    portainer_data:
        name: portainer_data

networks:
    default:
        name: rd-lab-network
```

## Setting

- Environment-related > Environments > local
    - Name : `rd-lab`
    - Public IP : `rd-docker`
