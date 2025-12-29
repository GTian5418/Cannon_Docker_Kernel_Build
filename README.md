🛠 1. 环境准备 (Environment Setup)
在 Docker 容器中初始化基础编译环境：

```bash

# 启动并进入容器
docker run -it --name build -v "$(pwd)"/data:/data ubuntu:22.04  

# 安装核心依赖
apt update -y && apt install -y \
    git wget curl tar zip unzip make binutils bison flex libssl-dev \
    bc libelf-dev gcc-aarch64-linux-gnu gcc-arm-linux-gnueabi \
    build-essential python3 libncurses5-dev libncursesw5-dev pkg-config ccache

# 下载并部署 Toolchains (Clang & GCC)
mkdir -p /cannon && cd /cannon
wget https://android.googlesource.com/platform/prebuilts/clang/host/linux-x86/+archive/refs/heads/master-kernel-build-2022/clang-r450784e.tar.gz && mkdir clang && tar -C clang -zxvf clang-r450784e.tar.gz 
wget -O gcc64.tar.gz https://android.googlesource.com/platform/prebuilts/gcc/linux-x86/aarch64/aarch64-linux-android-4.9/+archive/refs/tags/android-12.1.0_r27.tar.gz && mkdir gcc64 && tar -C gcc64 -zxvf gcc64.tar.gz
wget -O gcc32.tar.gz https://android.googlesource.com/platform/prebuilts/gcc/linux-x86/arm/arm-linux-androideabi-4.9/+archive/refs/tags/android-12.1.0_r27.tar.gz && mkdir gcc32 && tar -C gcc32 -zxvf gcc32.tar.gz

# 获取内核源码与配置文件
wget -O kernel.zip https://github.com/GTian5418/android_kernel_xiaomi_cannon/archive/refs/heads/lineage-20.zip && unzip kernel.zip
wget -O AnyKernel3.zip https://github.com/osm0sis/AnyKernel3/archive/refs/heads/master.zip && unzip AnyKernel3.zip && mv AnyKernel3-master Anykernel && rm -f AnyKernel3.zip Anykernel/LICENSE Anykernel/README.md 
wget -O Anykernel/dtb.img https://github.com/GTian5418/android_kernel_xiaomi_cannon/releases/download/Kernel/dtb.img 
wget -O Anykernel/dtbo.img https://github.com/GTian5418/android_kernel_xiaomi_cannon/releases/download/Kernel/dtbo.img
wget https://github.com/GTian5418/android_kernel_xiaomi_cannon/releases/download/Kernel/config.zip && unzip config.zip

# 清理冗余
rm -rf *.zip *.gz
```
📜 2. 自动化编译脚本 (build.sh)
该脚本负责从 g 到 g6 阶段的循环编译、语法修正及 AnyKernel3 自动打包。

```bash

cat << 'EOF' > /cannon/build.sh
#!/bin/bash
TOOLCHAIN="/cannon"
CONFIG_DIR="$TOOLCHAIN/config"
KERNEL="$TOOLCHAIN/android_kernel_xiaomi_cannon-lineage-20"
OUT_DIR="$TOOLCHAIN/out"
AK_DIR="$TOOLCHAIN/Anykernel"
ZIPS_OUT="$TOOLCHAIN/Anykernel3-Cannon-God.zip"

export PATH="$TOOLCHAIN/clang/bin:$TOOLCHAIN/gcc64/bin:$TOOLCHAIN/gcc32/bin:$PATH"
export CCACHE_DIR="$TOOLCHAIN/.ccache"
GCC64="aarch64-linux-android-"
GCC32="arm-linux-androideabi-"
export USE_CCACHE=1
export CC="clang"

COMMON_ARGS="O=$OUT_DIR ARCH=arm64 CLANG_TRIPLE=aarch64-linux-gnu- CROSS_COMPILE=$GCC64"
BUILD_ARGS="CROSS_COMPILE_ARM32=$GCC32 LD=ld.lld KCFLAGS=-Wno-error"

mkdir -p "$OUT_DIR"
mkdir -p "$CCACHE_DIR"
ccache -z
ccache -M 50G

echo ">>> [预处理] 正在修正 sctp/output.c 语法错误..."
TARGET_FILE="$KERNEL/net/sctp/output.c"
if [ -f "$TARGET_FILE" ]; then
    sed -i 's/skb_gro_receive(head, nskb)/skb_gro_receive(\&head, nskb)/g' "$TARGET_FILE"
    sed -i '502s/skb_gro_receive(&head, nskb)/skb_gro_receive(head, nskb)/' "$TARGET_FILE"
fi

build_step() {
    local cfg_file=$1
    echo "================================================"
    echo ">>> 开始处理阶段: $cfg_file"
    local start_time=$(date +%s)
    cp "$CONFIG_DIR/$cfg_file" "$OUT_DIR/.config" 
    sed -i 's/CONFIG_LOCALVERSION="-perf-cus"/CONFIG_LOCALVERSION="-Cannon-God"/' "$OUT_DIR/.config"    
    cd "$KERNEL"
    make $COMMON_ARGS CC="ccache clang" olddefconfig > /dev/null 2>&1
    if make -j$(nproc --all) $COMMON_ARGS $BUILD_ARGS CC="ccache clang" Image.gz; then
        local end_time=$(date +%s)
        local duration=$((end_time - start_time))
        echo ">>> $cfg_file 编译成功！耗时: $((duration / 60))分$((duration % 60))秒"
        ccache -s | grep "hit rate" || true
    else
        echo ">>> [错误] $cfg_file 编译失败！"
        exit 1
    fi
}

TOTAL_START=$(date +%s)
for i in g g1 g2 g3 g4 g5 g6; do
    if [ -f "$CONFIG_DIR/$i.config" ]; then
        build_step "$i.config"
    fi
done
TOTAL_END=$(date +%s)

echo "================================================"
if [ -f "$OUT_DIR/arch/arm64/boot/Image.gz" ]; then
    cd "$AK_DIR"
    rm -f Image.* *.zip
    cp "$OUT_DIR/arch/arm64/boot/Image.gz" .
    sed -i '
    8s/do\.devicecheck=1/do.devicecheck=0/;
    13s/device\.name1=.*/device.name1=cannon/;
    14s/device\.name2=.*/device.name2=cannong/;
    15s/device\.name3=.*/device.name3=/;
    16s/device\.name4=.*/device.name4=/;
    32s|BLOCK=/dev/block/platform/omap/omap_hsmmc\.0/by-name/boot;|BLOCK=auto;|
    ' "$AK_DIR/anykernel.sh"
    zip -r9 "$ZIPS_OUT" . -x ".git/*" > /dev/null
    echo ">>> 完成！总耗时: $(( (TOTAL_END - TOTAL_START) / 60 ))分"
else
    echo ">>> 失败：未生成镜像"
    exit 1
fi
EOF

chmod +x /cannon/build.sh
./build.sh
```
⌨️ 3. 常用手动编译指令 (Manual Debug)
用于日常调试或特定配置修改：

配置与环境导出
```bash

export i=/toolchain/out/arch/arm64/boot
export o=/toolchain/android_kernel_xiaomi_cannon-lineage-20/arch/arm64/configs

# 进入配置菜单
make O=$OUT_DIR menuconfig

# 快速同步配置
cp android_kernel_xiaomi_cannon-lineage-20/arch/arm64/configs/god_defconfig /toolchain/out/.config
单阶段快速编译
Bash

# 示例：以 g.config 进行编译
cp "$CONFIG_DIR/g.config" "$OUT_DIR/.config"
make $COMMON_ARGS olddefconfig
make -j$(nproc --all) $COMMON_ARGS $BUILD_ARGS Image.gz
```
📦 4. AnyKernel3 打包适配
如果您需要手动初始化 AnyKernel3 环境：

```bash

wget -O Anykernel.zip https://github.com/osm0sis/AnyKernel3/archive/refs/heads/master.zip
unzip -d ./Anykernel3 
rm -rf /Anykernel3/LICENSE /Anykernel3/README.md

# 自动适配 Cannon 设备参数
sed -i '
8s/do\.devicecheck=1/do.devicecheck=0/;
13s/device\.name1=.*/device.name1=cannon/;
14s/device\.name2=.*/device.name2=cannong/;
15s/device\.name3=.*/device.name3=/;
16s/device\.name4=.*/device.name4=/;
32s|BLOCK=/dev/block/platform/omap/omap_hsmmc\.0/by-name/boot;|BLOCK=auto;|
' Anykernel/anykernel.sh
🐳 5. Dockerfile (一键部署镜像)
使用该 Dockerfile 可以构建一个完整的编译镜像：

Dockerfile

FROM ubuntu:22.04
ENV DEBIAN_FRONTEND=noninteractive

RUN apt update -y && apt install -y \
    git wget curl tar zip unzip make binutils bison flex libssl-dev bc libelf-dev \
    gcc-aarch64-linux-gnu gcc-arm-linux-gnueabi build-essential python3 \
    libncurses5-dev libncursesw5-dev pkg-config ccache && \
    apt clean && rm -rf /var/lib/apt/lists/*

WORKDIR /cannon

# 预下载编译工具链
RUN wget https://android.googlesource.com/platform/prebuilts/clang/host/linux-x86/+archive/refs/heads/master-kernel-build-2022/clang-r450784e.tar.gz && \
    mkdir clang && tar -C clang -zxvf clang-r450784e.tar.gz && \
    wget -O gcc64.tar.gz https://android.googlesource.com/platform/prebuilts/gcc/linux-x86/aarch64/aarch64-linux-android-4.9/+archive/refs/tags/android-12.1.0_r27.tar.gz && \
    mkdir gcc64 && tar -C gcc64 -zxvf gcc64.tar.gz && \
    wget -O gcc32.tar.gz https://android.googlesource.com/platform/prebuilts/gcc/linux-x86/arm/arm-linux-androideabi-4.9/+archive/refs/tags/android-12.1.0_r27.tar.gz && \
    mkdir gcc32 && tar -C gcc32 -zxvf gcc32.tar.gz

# 预下载内核源码与组件
RUN wget -O kernel.zip https://github.com/GTian5418/android_kernel_xiaomi_cannon/archive/refs/heads/lineage-20.zip && \
    unzip kernel.zip && \
    wget -O AnyKernel3.zip https://github.com/osm0sis/AnyKernel3/archive/refs/heads/master.zip && \
    unzip AnyKernel3.zip && mv AnyKernel3-master Anykernel && \
    wget -O Anykernel/dtb.img https://github.com/GTian5418/android_kernel_xiaomi_cannon/releases/download/Kernel/dtb.img && \
    wget -O Anykernel/dtbo.img https://github.com/GTian5418/android_kernel_xiaomi_cannon/releases/download/Kernel/dtbo.img && \
    wget https://github.com/GTian5418/android_kernel_xiaomi_cannon/releases/download/Kernel/config.zip && \
    unzip config.zip && \
    rm -rf *.zip *.gz Anykernel/LICENSE Anykernel/README.md

COPY build.sh /cannon/build.sh
RUN chmod +x /cannon/build.sh

CMD ["/bin/bash", "-c", "/cannon/build.sh && cp /cannon/*.zip /output/"]
```
