# CH592 编译镜像 (linux/amd64 + linux/arm64)
# MounRiver 只提供 x86_64 的 Linux 工具链: amd64 上直接运行, arm64 上用 qemu-user 运行,
# 两个架构用的都是同一份 WCH GCC, 和 macOS 上编出来的固件一致, 源码不需要任何修改.
#
# 准备: 把 MounRiver Linux x64 工具链里的 GCC 目录(含 bin/ libexec/ 的那一层)解压到 docker/toolchain/
# 构建单架构: docker build --platform linux/arm64 -t ch592-build docker
# 构建多架构: docker buildx build --platform linux/amd64,linux/arm64 -t <仓库>/ch592-build --push docker
# 国内网络可加镜像源:
#   --build-arg APT_MIRROR=http://mirrors.ustc.edu.cn   (必须是 http: 此时还没装 ca-certificates, apt 包本身有 GPG 签名校验)
#   --build-arg NODE_MIRROR=https://npmmirror.com/mirrors/node
#   --build-arg NPM_REGISTRY=https://registry.npmmirror.com
# 使用: docker run --rm -v "$PWD":/src -w /src -u "$(id -u):$(id -g)" ch592-build make -j8
#
# 层按变化频率从低到高排列, 改动后面的层不会让前面的 apt / node 重新下载;
# apt / npm 下载的包放在 BuildKit 缓存里, 即使层失效也不用重新下载.

FROM debian:bookworm-slim

# source 让 ghcr.io 把镜像包关联到仓库, 仓库的 Actions 可直接用 GITHUB_TOKEN 拉取
LABEL org.opencontainers.image.source=https://github.com/xiaohuangtx/riscv32-wch-toolchain \
      org.opencontainers.image.description="WCH RISC-V GCC 15.2 (MounRiver) 编译环境, 用于 CH592 固件"

# 由 BuildKit 根据 --platform 自动填入
ARG TARGETARCH
# 其余 ARG 放在用到它的那一步前面: ARG 的值变化会让它之后所有 RUN 层的缓存失效
ARG APT_MIRROR=

# python3: Makefile 里的 tools/*.py
# git: conventional-changelog-cli 根据 git 提交记录生成 CHANGELOG
# curl: 下载 node
# *:amd64: 工具链运行依赖的 x86_64 动态库(amd64 上就是本机库)
# 仅 arm64: qemu-user-static 运行 x86_64 程序; file 识别工具链里哪些是 x86_64 可执行文件
# 去掉 docker-clean 才能让下载的 .deb 留在缓存里; 缓存按架构区分, 避免两个架构的 apt 状态互相覆盖
RUN --mount=type=cache,id=apt-cache-$TARGETARCH,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,id=apt-lists-$TARGETARCH,target=/var/lib/apt/lists,sharing=locked \
    rm -f /etc/apt/apt.conf.d/docker-clean \
 && if [ -n "$APT_MIRROR" ]; then \
        sed -i "s|http://deb.debian.org|$APT_MIRROR|g" /etc/apt/sources.list.d/debian.sources; \
    fi \
 && case "$TARGETARCH" in \
        amd64) extra="" ;; \
        arm64) dpkg --add-architecture amd64; extra="qemu-user-static file" ;; \
        *) echo "unsupported TARGETARCH: $TARGETARCH" >&2; exit 1 ;; \
    esac \
 && apt-get update \
 && apt-get install -y --no-install-recommends \
        make python3 git curl ca-certificates \
        libc6:amd64 libstdc++6:amd64 zlib1g:amd64 libzstd1:amd64 \
        $extra

ARG NODE_VERSION=24.14.1
ARG NODE_MIRROR=https://nodejs.org/dist
# 用官方 node 包而不是 Debian 的 npm: 后者会额外拉进两百多个 node-* 包
RUN case "$TARGETARCH" in \
        amd64) arch=x64 ;; \
        arm64) arch=arm64 ;; \
    esac \
 && curl -fsSL "$NODE_MIRROR/v$NODE_VERSION/node-v$NODE_VERSION-linux-$arch.tar.gz" \
    | tar xz -C /usr/local --strip-components=1 --no-same-owner \
        --exclude='*.md' --exclude=LICENSE --exclude=share \
 && node --version

ARG NPM_REGISTRY=https://registry.npmjs.org
# 用 --system 而不是 --global: docker run -u 指定其他用户时 root 的 ~/.gitconfig 不生效,
# 挂载进来的 /src 属主不一致时 git 会报 dubious ownership
RUN --mount=type=cache,id=npm-$TARGETARCH,target=/root/.npm \
    git config --system --add safe.directory '*' \
 && npm install -g --registry="$NPM_REGISTRY" conventional-changelog-cli \
 && conventional-changelog --help > /dev/null

# PREFIX 需和 docker/toolchain/bin 下的文件名前缀一致, 仅用于构建时自检;
# 不是默认的 riscv32-wch-elf- 时, 编译也要传 make PREFIX=...
ARG PREFIX=riscv32-wch-elf-
COPY toolchain/ /opt/wch-gcc/
COPY wrap-x86_64.sh /usr/local/bin/
RUN test -x /opt/wch-gcc/bin/${PREFIX}gcc \
 && if [ "$TARGETARCH" = arm64 ]; then wrap-x86_64.sh /opt/wch-gcc; fi

ENV PATH=/opt/wch-gcc/bin:$PATH

# 构建时就验证 cc1 / as / ld / lto 都能跑通, 缺动态库会在这里报错
RUN ${PREFIX}gcc --version \
 && printf 'int main(void){return 0;}\n' > /tmp/t.c \
 && ${PREFIX}gcc -march=rv32imac_zicsr -mabi=ilp32 -Os -flto -fuse-linker-plugin \
        --specs=nano.specs --specs=nosys.specs /tmp/t.c -o /tmp/t.elf \
 && ${PREFIX}size /tmp/t.elf \
 && rm -f /tmp/t.c /tmp/t.elf
