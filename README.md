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
wget -O AnyKernel3.zip \
  https://github.com/GTian5418/AnyKernel3/archive/refs/heads/cannon.zip
git clone git@github.com:gtcock/android_kernel_xiaomi_cannon.git

tar -C clang -zxvf clang.tar.gz
tar -C gcc64 -zxvf gcc64.tar.gz
tar -C gcc32 -zxvf gcc32.tar.gz

unzip AnyKernel3.zip

mv AnyKernel3-master Anykernel
mv android_kernel_xiaomi_cannon-lineage-20 kernel
rm -f AnyKernel3.zip Anykernel/LICENSE Anykernel/README.md

rm -rf *.zip *.gz
```
📜 2. 自动化编译脚本 (build.sh)

```bash

cat << 'EOF' > /cannon/build.sh
#!/bin/bash

set -e

# ============================================
# 配置
# ============================================
TOOLCHAIN="/cannon"
KERNEL="$TOOLCHAIN/kernel"
OUT_DIR="$TOOLCHAIN/out"
AK_DIR="$TOOLCHAIN/Anykernel3"
TARGET_IMAGE="$OUT_DIR/arch/arm64/boot/Image.gz"

# 输出文件
GOD_ZIP="$TOOLCHAIN/God.zip"      # 普通内核 (main)
SU_ZIP="$TOOLCHAIN/Su.zip"        # KernelSU 原版 (ksu)
NEXT_ZIP="$TOOLCHAIN/Next.zip"    # KernelSU-Next (next)

# 工具链
export PATH="$TOOLCHAIN/clang/bin:$TOOLCHAIN/gcc64/bin:$TOOLCHAIN/gcc32/bin:$PATH"
export CCACHE_DIR="$TOOLCHAIN/.ccache"
GCC64="aarch64-linux-android-"
GCC32="arm-linux-androideabi-"
export USE_CCACHE=1

# 编译参数
COMMON_ARGS="ARCH=arm64 CLANG_TRIPLE=aarch64-linux-gnu- CROSS_COMPILE=$GCC64"
BUILD_ARGS="CROSS_COMPILE_ARM32=$GCC32 LD=ld.lld KCFLAGS=-Wno-error"

# 初始化
mkdir -p "$OUT_DIR"
mkdir -p "$CCACHE_DIR"
ccache -z > /dev/null 2>&1
ccache -M 50G > /dev/null 2>&1

# ============================================
# 函数：编译内核
# ============================================
setup_kernelsu() {
    local BRANCH=$1
    
    cd "$KERNEL"
    
    if [ "$BRANCH" = "ksu" ]; then
        echo "设置 KernelSU 原版..."
        
        curl -LSs https://raw.githubusercontent.com/tiann/KernelSU/main/kernel/setup.sh | bash -s v0.9.5
        
        echo "✅ KernelSU 设置完成"
        
    elif [ "$BRANCH" = "next" ]; then
        echo "设置 KernelSU-Next v1.1.1..."
        
        curl -LSs "https://raw.githubusercontent.com/KernelSU-Next/KernelSU-Next/next/kernel/setup.sh" | bash -s v1.1.1
        
        echo "✅ KernelSU-Next v1.1.1 设置完成"
        
        if [ -d KernelSU-Next ]; then
            cd KernelSU-Next
            COMMIT_COUNT=$(git rev-list --count HEAD 2>/dev/null || echo "0")
            if [ "$COMMIT_COUNT" != "0" ]; then
                KSU_VERSION=$((10000 + COMMIT_COUNT + 200))
                echo "提交数: $COMMIT_COUNT"
                echo "版本号: $KSU_VERSION"
            fi
            cd ..
        fi
    fi
}
cleanup_kernelsu() {
    local BRANCH=$1
    
    cd "$KERNEL"
    
    echo "清理 KernelSU 文件..."
    
    if [ "$BRANCH" = "ksu" ]; then
        # 手动清理 KernelSU
        rm -rf KernelSU
        [ -L drivers/kernelsu ] && rm drivers/kernelsu
        
        # 恢复 drivers/Makefile
        if grep -q "kernelsu" drivers/Makefile; then
            sed -i '/kernelsu/d' drivers/Makefile
        fi
        
        # 恢复 drivers/Kconfig
        if grep -q "drivers/kernelsu/Kconfig" drivers/Kconfig; then
            sed -i '/drivers\/kernelsu\/Kconfig/d' drivers/Kconfig
        fi
        
    elif [ "$BRANCH" = "next" ]; then
        # 手动清理 KernelSU-Next
        rm -rf KernelSU-Next
        [ -L drivers/kernelsu ] && rm drivers/kernelsu
        
        # 恢复 drivers/Makefile
        if grep -q "kernelsu" drivers/Makefile; then
            sed -i '/kernelsu/d' drivers/Makefile
        fi
        
        # 恢复 drivers/Kconfig
        if grep -q "drivers/kernelsu/Kconfig" drivers/Kconfig; then
            sed -i '/drivers\/kernelsu\/Kconfig/d' drivers/Kconfig
        fi
    fi
    
    echo "✅ 清理完成"
}
build_kernel() {
    local BRANCH=$1
    local OUTPUT_ZIP=$2
    local LABEL=$3
    
    echo ""
    echo "=========================================="
    echo "  编译:  $LABEL"
    echo "  分支: $BRANCH"
    echo "  输出: $OUTPUT_ZIP"
    echo "=========================================="
    
    # 切换分支
    cd "$KERNEL"
    echo "切换到 $BRANCH 分支..."
    git checkout "$BRANCH"
    
    # 设置 KernelSU（如果不是 main）
    if [ "$BRANCH" != "main" ]; then
        setup_kernelsu "$BRANCH"
    fi
    
    # 清理输出目录
    echo "清理输出目录..."
    rm -rf "$OUT_DIR"
    mkdir -p "$OUT_DIR"
    
    # 配置
    echo "配置内核..."
    make -C "$KERNEL" O="$OUT_DIR" $COMMON_ARGS CC="ccache clang" cannon_defconfig > /dev/null
    
    # 编译
    echo "开始编译..."
    START_TIME=$(date +%s)
    
    if make -C "$KERNEL" O="$OUT_DIR" $COMMON_ARGS CC="ccache clang" $BUILD_ARGS -j$(nproc) Image.gz 2>&1 | tee /tmp/build_${BRANCH}.log; then
        END_TIME=$(date +%s)
        DURATION=$((END_TIME - START_TIME))
        echo "✅ 编译成功 (耗时: ${DURATION}s)"
    else
        echo "❌ 编译失败:  $LABEL"
        cleanup_kernelsu "$BRANCH"
        exit 1
    fi
    
    # 检查编译结果
    if [ !  -f "$TARGET_IMAGE" ]; then
        echo "❌ 内核镜像不存在: $TARGET_IMAGE"
        cleanup_kernelsu "$BRANCH"
        exit 1
    fi
    
    # 显示内核信息
    echo ""
    echo "内核信息:"
    ls -lh "$TARGET_IMAGE"
    
    # 显示版本号（对于 KernelSU 版本）
    if [ "$BRANCH" != "main" ]; then
        echo ""
        echo "KernelSU 版本信息:"
        grep -i "KernelSU.*version" /tmp/build_${BRANCH}. log | head -3 || echo "(未找到版本信息)"
    fi
    
    # 打包
    echo ""
    echo "打包中..."
    cd "$AK_DIR"
    
    # 删除旧的内核镜像
    rm -f Image.gz Image Image.gz-dtb
    
    # 删除旧的输出 zip
    rm -f "$OUTPUT_ZIP"
    
    # 复制新内核
    cp "$TARGET_IMAGE" "$AK_DIR/Image.gz"
    
    # 打包
    zip -r9 "$OUTPUT_ZIP" .  -x ". git/*" "*.git*" "README. md" "LICENSE" "*.zip" > /dev/null
    
    echo "✅ 完成: $OUTPUT_ZIP"
    ls -lh "$OUTPUT_ZIP"
    
    # 清理 AnyKernel3 目录中的内核镜像
    rm -f "$AK_DIR/Image.gz"
    
    # 清理 KernelSU
    if [ "$BRANCH" != "main" ]; then
        cleanup_kernelsu "$BRANCH"
    fi
}

# ============================================
# 主流程
# ============================================

echo "=========================================="
echo "  Xiaomi Cannon 内核编译脚本"
echo "=========================================="
echo "时间: $(date)"
echo "CPU 核心: $(nproc)"
echo ""

# 1. 编译普通内核 (main 分支)
build_kernel "main" "$GOD_ZIP" "普通内核"

# 2. 编译 KernelSU 原版 (ksu 分支)
build_kernel "ksu" "$SU_ZIP" "KernelSU 原版"

# 3. 编译 KernelSU-Next (next 分支)
build_kernel "next" "$NEXT_ZIP" "KernelSU-Next"

# ============================================
# 汇总
# ============================================
echo ""
echo "=========================================="
echo "  编译完成汇总"
echo "=========================================="

echo ""
echo "输出文件:"
ls -lh /cannon/*. zip 2>/dev/null | awk '{print $9 " - " $5}'

# 计算 MD5
echo ""
echo "MD5 校验:"
md5sum /cannon/*.zip 2>/dev/null | awk '{print $2 ": " $1}'

# ============================================
# 复制到目标目录
# ============================================
echo ""
echo "=========================================="
echo "  复制到 /mnt/G/"
echo "=========================================="

for zip in "$GOD_ZIP" "$SU_ZIP" "$NEXT_ZIP"; do
    if [ -f "$zip" ]; then
        BASENAME=$(basename "$zip")
        if cp "$zip" /mnt/G/ 2>/dev/null; then
            echo "✅ $BASENAME"
        else
            echo "⚠️ $BASENAME 复制失败"
        fi
    else
        echo "❌ $(basename $zip) 不存在"
    fi
done

echo ""
echo "=========================================="
echo "✅✅✅ 全部完成！✅✅✅"
echo "=========================================="
echo "时间: $(date)"
echo ""
echo "生成的内核:"
echo "  1. God.zip  - 普通内核（无 KernelSU）"
echo "  2. Su.zip   - KernelSU 原版"
echo "  3. Next. zip - KernelSU-Next v1.1.1"
echo ""
EOF
chmod +x /cannon/build.sh
./build.sh
```

