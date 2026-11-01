#!/bin/sh
# 构建 linux/amd64 + linux/arm64 镜像, 同时推送到 Docker Hub 和 GitHub Container Registry
#
# 用法: docker/build-push.sh [标签]        标签默认 v15.2
#       CN_MIRROR=1 docker/build-push.sh   构建时使用国内 apt / node / npm 镜像源
#
# 推送前先登录两个仓库:
#   docker login                                  Docker Hub
#   docker login ghcr.io -u <GitHub 用户名>        密码填 classic PAT, 需要 write:packages 权限
set -eu

TAG=${1:-v15.2}
DOCKERHUB_IMAGE=${DOCKERHUB_IMAGE:-xiaohuangtx/riscv32-wch-toolchain}
GHCR_IMAGE=${GHCR_IMAGE:-ghcr.io/xiaohuangtx/riscv32-wch-toolchain}
SOURCE=https://github.com/xiaohuangtx/riscv32-wch-toolchain

cd "$(dirname "$0")"

set --
if [ "${CN_MIRROR:-0}" = 1 ]; then
    set -- \
        --build-arg APT_MIRROR=http://mirrors.ustc.edu.cn \
        --build-arg NODE_MIRROR=https://npmmirror.com/mirrors/node \
        --build-arg NPM_REGISTRY=https://registry.npmmirror.com
fi

# 多架构镜像的 index 上没有 Dockerfile 里的 LABEL, ghcr.io 读的是 index 的 annotation
docker buildx build \
    --platform linux/amd64,linux/arm64 \
    "$@" \
    --annotation "index:org.opencontainers.image.source=$SOURCE" \
    --annotation "index:org.opencontainers.image.description=WCH RISC-V GCC 15.2 (MounRiver) 编译环境, 用于 CH592 固件" \
    -t "$DOCKERHUB_IMAGE:$TAG" \
    -t "$GHCR_IMAGE:$TAG" \
    --push \
    .
