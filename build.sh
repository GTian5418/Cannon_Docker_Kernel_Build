#!/bin/bash
TOOLCHAIN="/cannon"
CONFIG_DIR="$TOOLCHAIN/config"
KERNEL="$TOOLCHAIN/android_kernel_xiaomi_cannon-lineage-20"
OUT_DIR="$TOOLCHAIN/out"
AK_DIR="$TOOLCHAIN/Anykernel"
ZIPS_OUT="$TOOLCHAIN/Anykernel3-Cannon-God.zip"
KSU_ZIPS_OUT="$TOOLCHAIN/Anykernel3-Cannon-God-KernelSu.zip"
KSUN_ZIPS_OUT="$TOOLCHAIN/Anykernel3-Cannon-God-KernelSu-Next.zip"
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
TARGET_FILE="$KERNEL/net/sctp/output.c"
if [ -f "$TARGET_FILE" ]; then
    sed -i 's/skb_gro_receive(head, nskb)/skb_gro_receive(\&head, nskb)/g' "$TARGET_FILE"
    sed -i '502s/skb_gro_receive(&head, nskb)/skb_gro_receive(head, nskb)/' "$TARGET_FILE"
fi
build_step() {
    local cfg_file=$1
    local current_out=$2
    local current_kernel=$3
    local start_time=$(date +%s)    
    mkdir -p "$current_out"
    cp "$CONFIG_DIR/$cfg_file" "$current_out/.config" 
    sed -i 's/CONFIG_LOCALVERSION="-perf-cus"/CONFIG_LOCALVERSION="-Cannon-God"/' "$current_out/.config"        
    cd "$current_kernel"
    make O="$current_out" $COMMON_ARGS CC="ccache clang" olddefconfig > /dev/null 2>&1
    if make -j$(nproc --all) O="$current_out" $COMMON_ARGS $BUILD_ARGS CC="ccache clang" Image.gz; then
        local end_time=$(date +%s)
        local duration=$((end_time - start_time))
        echo ">>> $cfg_file 编译成功！耗时: $((duration / 60))分$((duration % 60))秒"
    else
        echo ">>> [错误] $cfg_file 编译失败！"
        exit 1
    fi
}
TOTAL_START=$(date +%s)
for i in g g1 g2 g3 g4 g5 g6; do
    if [ -f "$CONFIG_DIR/$i.config" ]; then
        build_step "$i.config" "$OUT_DIR" "$KERNEL"
    fi
done
if [ -f "$OUT_DIR/arch/arm64/boot/Image.gz" ]; then
    cd "$AK_DIR"
    rm -f Image.* *.zip
    cp "$OUT_DIR/arch/arm64/boot/Image.gz" .
    sed -i '8s/do\.devicecheck=1/do.devicecheck=0/;13s/device\.name1=.*/device.name1=cannon/;14s/device\.name2=.*/device.name2=cannong/;32s|BLOCK=.*|BLOCK=auto;|' anykernel.sh
    zip -r9 "$ZIPS_OUT" . -x ".git/*" > /dev/null
fi



cp -r "$KERNEL" "$TOOLCHAIN/kernelsu_next"
cp -rp "$OUT_DIR" "$TOOLCHAIN/outsu_next"
cd "$KERNEL"
curl -LSs https://raw.githubusercontent.com/tiann/KernelSU/main/kernel/setup.sh | bash -s v0.9.5
build_step "g7.config" "$OUT_DIR" "$KERNEL"
cd "$AK_DIR"
rm -f Image.*
cp "$OUT_DIR/arch/arm64/boot/Image.gz" .
zip -r9 "$KSU_ZIPS_OUT" . -x ".git/*" > /dev/null
cd "$TOOLCHAIN/kernelsu_next"
curl -LSs "https://raw.githubusercontent.com/KernelSU-Next/KernelSU-Next/next/kernel/setup.sh" | bash -s v1.1.1
sed -i '/static int ksu_umount_mnt/,/^}/c\
static int ksu_umount_mnt(struct path *path, int flags)\
{\
\textern int do_umount(struct vfsmount *mnt, int flags);\
\treturn do_umount(path->mnt, flags);\
}' drivers/kernelsu/core_hook.c
sed -i 's/^static int do_umount/int do_umount/' fs/namespace.c
if ! grep -q "EXPORT_SYMBOL(do_umount);" fs/namespace.c; then
    sed -i '/return retval;[[:space:]]*}/a EXPORT_SYMBOL(do_umount);' fs/namespace.c
fi
build_step "g7.config" "$TOOLCHAIN/outsu_next" "$TOOLCHAIN/kernelsu_next"
cd "$AK_DIR"
rm -f Image.*
cp "$TOOLCHAIN/outsu_next/arch/arm64/boot/Image.gz" .
zip -r9 "$KSUN_ZIPS_OUT" . -x ".git/*" > /dev/null
TOTAL_END=$(date +%s)
echo "================================================"
echo ">>> 全部完成！总耗时: $(( (TOTAL_END - TOTAL_START) / 60 ))分"
