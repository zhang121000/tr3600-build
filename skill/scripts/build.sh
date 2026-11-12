#!/bin/bash
# Cudy TR3600 v1 本地 Docker 编译脚本
# 前置：Docker 容器（ubuntu:24.04），挂载 work 目录到 /work
# 容器创建：docker run -dit --name owrt-build --cap-add MKNOD -v /path/to/work:/work ubuntu:24.04 bash

set -e
export DEBIAN_FRONTEND=noninteractive
export FORCE_UNSAFE_CONFIGURE=1
export GOPROXY=https://goproxy.cn,direct

GHM="https://ghproxy.net/"  # GitHub 加速镜像，按可用性更换

echo "===== [1/7] 安装编译依赖 ====="
apt-get update
apt-get install -y build-essential clang flex bison g++ gawk gettext git \
  libncurses-dev libssl-dev python3 python3-setuptools rsync unzip zlib1g-dev \
  file wget qemu-utils libelf-dev dwarves zstd swig curl ca-certificates

echo "===== [2/7] 克隆 OpenWrt 25.12 ====="
cd /build  # 容器原生文件系统（不要挂载 macOS 目录，大小写问题）
if [ ! -d openwrt ]; then
  git clone --depth 1 -b openwrt-25.12 ${GHM}https://github.com/openwrt/openwrt.git openwrt || \
  git clone --depth 1 -b openwrt-25.12 https://github.com/openwrt/openwrt.git openwrt
fi
cd openwrt

echo "===== [3/7] 应用补丁（设备支持 + EEE 修复） ====="
git apply /work/patches/*.patch

echo "===== [4/7] 添加 PassWall 插件源 ====="
echo "src-git passwall_packages ${GHM}https://github.com/Openwrt-Passwall/openwrt-passwall-packages.git;main" >> feeds.conf.default
echo "src-git passwall ${GHM}https://github.com/Openwrt-Passwall/openwrt-passwall.git;main" >> feeds.conf.default
./scripts/feeds update -a
./scripts/feeds install -a

echo "===== [5/7] 生成配置 ====="
cp /work/config.seed .config
make defconfig

echo "===== [6/7] 下载源码包 ====="
make download -j$(nproc) || make download -j4

echo "===== [7/7] 编译 ====="
make -j$(nproc) || make -j1 V=s

echo "===== 拷贝产物 ====="
mkdir -p /work/output
cp -a bin/targets/mediatek/filogic/ /work/output/
echo "BUILD_ALL_DONE"
