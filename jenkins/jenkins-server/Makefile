IMAGE_NAME = test/jenkins:lts-jdk21

# 將 all 放在最上面，並讓它依賴於 rebuild
all: rebuild

.PHONY: all prune rebuild

# 1. 獨立的清理階
prune:
	@echo "正在清理 Docker 構建快取..."
	-docker builder prune -f
	-docker rmi $(IMAGE_NAME)

# 2. 獨立的構建階段`
rebuild: prune
	@echo "開始重新構建 (No Cache)..."
	docker build --no-cache -t $(IMAGE_NAME) .