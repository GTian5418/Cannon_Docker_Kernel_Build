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
