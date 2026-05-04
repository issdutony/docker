IMAGE_NAME = rd/jenkins:lts-jdk21


# 預設執行方法1
.DEFAULT_GOAL := rebuild

.PHONY: all prune rebuild

# 預設執行方法2
# all: rebuild

# 1. 清理快取
prune:
	@echo "正在清理 Docker 構建快取..."
	-docker builder prune -a -f
	-docker rmi $(IMAGE_NAME)

# 2. 建構 image
rebuild: prune
	@echo "開始重新建構 (No Cache)..."
	docker build --no-cache -t $(IMAGE_NAME) .