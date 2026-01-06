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

mkdir -p /cannon
cd /cannon
mkdir -p clang gcc32 gcc64

wget -O clang.tar.gz \
  android.googlesource.com/platform/prebuilts/clang/host/linux-x86/+archive/a71fa4c09d7109d611ee63964fc9fca58fee38cd.tar.gz
wget -O gcc64.tar.gz \
  https://android.googlesource.com/platform/prebuilts/gcc/linux-x86/aarch64/aarch64-linux-android-4.9/+archive/refs/tags/android-12.1.0_r27.tar.gz
wget -O gcc32.tar.gz \
  https://android.googlesource.com/platform/prebuilts/gcc/linux-x86/arm/arm-linux-androideabi-4.9/+archive/refs/tags/android-12.1.0_r27.tar.gz
wget -O kernel.zip \
  https://github.com/GTian5418/android_kernel_xiaomi_cannon/archive/refs/heads/lineage-20.zip
wget -O AnyKernel3.zip \
  https://github.com/osm0sis/AnyKernel3/archive/refs/heads/master.zip
wget -O Anykernel/dtb.img \
  https://github.com/GTian5418/android_kernel_xiaomi_cannon/releases/download/Kernel/dtb.img
wget -O Anykernel/dtbo.img \
  https://github.com/GTian5418/android_kernel_xiaomi_cannon/releases/download/Kernel/dtbo.img
wget -O config.zip \
  https://github.com/GTian5418/android_kernel_xiaomi_cannon/releases/download/Kernel/config.zip

tar -C clang -zxvf clang.tar.gz
tar -C gcc64 -zxvf gcc64.tar.gz
tar -C gcc32 -zxvf gcc32.tar.gz

unzip kernel.zip
unzip AnyKernel3.zip
unzip config.zip

mv AnyKernel3-master Anykernel
mv android_kernel_xiaomi_cannon-lineage-20 kernel
rm -f AnyKernel3.zip Anykernel/LICENSE Anykernel/README.md

rm -rf *.zip *.gz
```
📜 2. 自动化编译脚本 (build.sh)
该脚本负责从 g 到 g6 阶段的循环编译、语法修正及 AnyKernel3 自动打包。

```bash

cat << 'EOF' > /cannon/build.sh
#!/bin/bash

set -e

# ============================================
# 配置
# ============================================
TOOLCHAIN="/cannon"
CONFIG_DIR="$TOOLCHAIN/config"
KERNEL="$TOOLCHAIN/kernel"
OUT_DIR="$TOOLCHAIN/out"
AK_DIR="$TOOLCHAIN/Anykernel3"
TARGET_IMAGE="$OUT_DIR/arch/arm64/boot/Image.gz"

# 输出文件
ZIPS_OUT="$TOOLCHAIN/God.zip"          # 普通内核
KSU_ZIPS_OUT="$TOOLCHAIN/Su.zip"       # KernelSU (旧版)
KSUN_ZIPS_OUT="$TOOLCHAIN/Next.zip"    # KernelSU-Next

# 工具链
export PATH="$TOOLCHAIN/clang/bin: $TOOLCHAIN/gcc64/bin:$TOOLCHAIN/gcc32/bin:$PATH"
export CCACHE_DIR="$TOOLCHAIN/.ccache"
GCC64="aarch64-linux-android-"
GCC32="arm-linux-androideabi-"
export USE_CCACHE=1
export CC="clang"

# 编译参数
COMMON_ARGS="ARCH=arm64 CLANG_TRIPLE=aarch64-linux-gnu- CROSS_COMPILE=$GCC64"
BUILD_ARGS="CROSS_COMPILE_ARM32=$GCC32 LD=ld.lld KCFLAGS=-Wno-error"

# 初始化
mkdir -p "$OUT_DIR"
mkdir -p "$CCACHE_DIR"
ccache -z
ccache -M 50G

# ============================================
# 函数：编译内核
# ============================================
build_kernel() {
    local BRANCH=$1
    local OUTPUT_ZIP=$2
    local LABEL=$3
    
    echo "=========================================="
    echo "  编译:  $LABEL"
    echo "  分支: $BRANCH"
    echo "  输出: $OUTPUT_ZIP"
    echo "=========================================="
    
    # 切换分支
    cd "$KERNEL"
    git checkout "$BRANCH"
    
    # 清理输出目录
    rm -rf "$OUT_DIR"
    mkdir -p "$OUT_DIR"
    
    # 配置
    make -C "$KERNEL" O="$OUT_DIR" $COMMON_ARGS CC="ccache clang" cannon_defconfig
    make -C "$KERNEL" O="$OUT_DIR" $COMMON_ARGS CC="ccache clang" olddefconfig
    
    # 编译
    make -C "$KERNEL" O="$OUT_DIR" $COMMON_ARGS CC="ccache clang" $BUILD_ARGS -j$(nproc --all) Image.gz
    
    # 检查编译结果
    if [ !  -f "$TARGET_IMAGE" ]; then
        echo "❌ 编译失败:  $LABEL"
        return 1
    fi
    
    # 打包
    cd "$AK_DIR"
    rm -f Image.* *.zip
    cp "$TARGET_IMAGE" "$AK_DIR/"
    zip -r9 "$OUTPUT_ZIP" . -x ".git/*" "README.md" "LICENSE"
    
    echo "✅ 完成: $OUTPUT_ZIP"
    ls -lh "$OUTPUT_ZIP"
    echo ""
}

# ============================================
# 主流程
# ============================================

# 1. 编译普通内核 (main 分支)
build_kernel "main" "$ZIPS_OUT" "普通内核"

# 2. 编译 KernelSU-Next (next 分支)
build_kernel "next" "$KSUN_ZIPS_OUT" "KernelSU-Next"

# 3. 可选：编译旧版 KernelSU (如果有 ksu 分支)
# build_kernel "ksu" "$KSU_ZIPS_OUT" "KernelSU (旧版)"

# ============================================
# 复制到目标目录
# ============================================
echo "=========================================="
echo "  复制到 /mnt/G/"
echo "=========================================="
cp "$ZIPS_OUT" /mnt/G/ 2>/dev/null && echo "✅ God.zip" || echo "⚠️ God.zip 复制失败"
cp "$KSUN_ZIPS_OUT" /mnt/G/ 2>/dev/null && echo "✅ Next.zip" || echo "⚠️ Next.zip 复制失败"
# cp "$KSU_ZIPS_OUT" /mnt/G/ 2>/dev/null && echo "✅ Su. zip" || echo "⚠️ Su.zip 复制失败"

echo ""
echo "=========================================="
echo "✅✅✅  全部完成！✅✅✅"
echo "=========================================="
echo "普通内核:   $ZIPS_OUT"
echo "KernelSU-Next:  $KSUN_ZIPS_OUT"
# echo "KernelSU:   $KSU_ZIPS_OUT"
EOF
chmod +x /cannon/build.sh
./build.sh
```

