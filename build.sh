#!/bin/bash
TOOLCHAIN="/cannon"
KERNEL="$TOOLCHAIN/kernel"
OUT_DIR="$TOOLCHAIN/out"
AK_DIR="$TOOLCHAIN/Anykernel3"
TARGET_IMAGE="$OUT_DIR/arch/arm64/boot/Image.gz"
ZIPS_OUT="$TOOLCHAIN/Docker.zip"          
KSU_ZIPS_OUT="$TOOLCHAIN/Su.zip"       
KSUN_ZIPS_OUT="$TOOLCHAIN/Next.zip"    
export PATH="$TOOLCHAIN/clang/bin:$TOOLCHAIN/gcc64/bin:$TOOLCHAIN/gcc32/bin:$PATH"
export CCACHE_DIR="$TOOLCHAIN/.ccache"
GCC64="aarch64-linux-android-"
GCC32="arm-linux-androideabi-"
export USE_CCACHE=1
export CC="clang"
COMMON_ARGS="ARCH=arm64 CLANG_TRIPLE=aarch64-linux-gnu- CROSS_COMPILE=$GCC64"
BUILD_ARGS="CROSS_COMPILE_ARM32=$GCC32 LD=ld.lld KCFLAGS=-Wno-error"
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
    echo "  编译: $LABEL"
    echo "  分支: $BRANCH"
    echo "  输出: $OUTPUT_ZIP"
    echo "=========================================="
    cd "$KERNEL"
    git checkout "$BRANCH"
    rm -rf "$OUT_DIR"
    mkdir -p "$OUT_DIR"
    make -C "$KERNEL" O="$OUT_DIR" $COMMON_ARGS CC="ccache clang" cannon_defconfig
    make -C "$KERNEL" O="$OUT_DIR" $COMMON_ARGS CC="ccache clang" olddefconfig
    make -C "$KERNEL" O="$OUT_DIR" $COMMON_ARGS CC="ccache clang" $BUILD_ARGS -j$(nproc --all) Image.gz
    if [ !  -f "$TARGET_IMAGE" ]; then
        echo "❌ 编译失败:  $LABEL"
        return 1
    fi
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
build_kernel "main" "$ZIPS_OUT" "Docker内核"
build_kernel "next" "$KSUN_ZIPS_OUT" "KernelSU-Next"
build_kernel "ksu" "$KSU_ZIPS_OUT" "KernelSU"
echo "=========================================="
echo "✅✅✅  全部完成！✅✅✅"
echo "=========================================="
echo "普通内核:   $ZIPS_OUT"
echo "KernelSU-Next:  $KSUN_ZIPS_OUT"
echo "KernelSU:   $KSU_ZIPS_OUT"
