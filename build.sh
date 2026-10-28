#!/bin/bash
# cannon (MT6853T) 内核单独编译 —— 四个分支，产物为 AnyKernel3 可刷 zip
#
# 用法：  ./build.sh              编全部四个分支
#         ./build.sh next ksu     只编指定的
#
set +u   # 不要开 set -u，下面有大量可选变量

TOOLCHAIN=${TOOLCHAIN:-/cannon}
KERNEL=$TOOLCHAIN/kernel
OUT_DIR=$TOOLCHAIN/out
AK_DIR=$TOOLCHAIN/Anykernel
DIST=$TOOLCHAIN/dist
CLANG=$TOOLCHAIN/clang
GCC64=$TOOLCHAIN/gcc64
GCC32=$TOOLCHAIN/gcc32

export PATH="$CLANG/bin:$GCC64/bin:$GCC32/bin:$PATH"
export CCACHE_DIR=$TOOLCHAIN/.ccache
export USE_CCACHE=1
export BUILD_NUMBER=${BUILD_NUMBER:-$(date +%Y%m%d)}
# ★ 固定 #1：不设的话 scripts/mkcompile_h 会读 .version 自增，越编越大
export KBUILD_BUILD_VERSION=1

CCACHE_BIN=$(command -v ccache || true)
if [ -n "$CCACHE_BIN" ]; then
    KERNEL_CC="CC=$CCACHE_BIN clang"
else
    KERNEL_CC="CC=clang"
fi
COMMON_ARGS="ARCH=arm64 CLANG_TRIPLE=aarch64-linux-gnu- CROSS_COMPILE=aarch64-linux-android-"
BUILD_ARGS="CROSS_COMPILE_ARM32=arm-linux-androideabi- LD=ld.lld"

mkdir -p "$OUT_DIR" "$DIST" "$CCACHE_DIR"
[ -n "$CCACHE_BIN" ] && ccache -M 50G >/dev/null 2>&1

build_one() {
    local br=$1 zipname=$2 label=$3
    echo ""
    echo "========================================"
    echo "  编译: $label"
    echo "  分支: $br"
    echo "  输出: $DIST/$zipname"
    echo "========================================"

    cd "$KERNEL" || return 1
    git checkout -f "$br" || return 1
    echo "  source: $(git log --oneline -1)"

    rm -rf "$OUT_DIR" && mkdir -p "$OUT_DIR"

    make -C "$KERNEL" O="$OUT_DIR" $COMMON_ARGS $KERNEL_CC cannon_defconfig >/dev/null || return 1
    make -C "$KERNEL" O="$OUT_DIR" $COMMON_ARGS $KERNEL_CC olddefconfig      >/dev/null || return 1
    rm -f "$OUT_DIR/.version"

    local start=$(date +%s)
    if ! make -C "$KERNEL" O="$OUT_DIR" $COMMON_ARGS $KERNEL_CC $BUILD_ARGS -j"$(nproc)" Image.gz; then
        echo "  !! 编译失败: $label"
        return 1
    fi
    local took=$(( $(date +%s) - start ))

    local img="$OUT_DIR/arch/arm64/boot/Image.gz"
    [ -f "$img" ] || { echo "  !! 没有 Image.gz"; return 1; }

    echo ""
    echo "  编译完成，用时 ${took}s"
    strings -n 20 "$OUT_DIR/arch/arm64/boot/Image" 2>/dev/null | grep -m1 'Linux version' | sed 's/^/  /'

    cd "$AK_DIR" || return 1
    rm -f Image.gz Image Image.gz-dtb
    cp "$img" "$AK_DIR/Image.gz"
    rm -f "$DIST/$zipname"
    zip -r9 "$DIST/$zipname" . -x '.git/*' '*.zip' >/dev/null
    rm -f "$AK_DIR/Image.gz"

    echo "  产物: $DIST/$zipname ($(du -h "$DIST/$zipname" | cut -f1))"
}

declare -A MAP=(
    [lineage-21-cannon]=God.zip
    [next]=Next.zip
    [ksu]=Su.zip
    [next-susfs]=Susfs.zip
    [next-susfs-new]=SusfsNew.zip
)
declare -A LABEL=(
    [lineage-21-cannon]="无 KernelSU"
    [next]="KernelSU-Next v1.1.1"
    [ksu]="KernelSU v0.9.5"
    [next-susfs]="KernelSU-Next + SUSFS"
    [next-susfs-new]="KernelSU-Next v3.4.2 + SUSFS v2.3.0"
)

BRANCHES=("$@")
[ ${#BRANCHES[@]} -eq 0 ] && BRANCHES=(lineage-21-cannon next ksu next-susfs next-susfs-new)

FAILED=()
for br in "${BRANCHES[@]}"; do
    build_one "$br" "${MAP[$br]:-$br.zip}" "${LABEL[$br]:-$br}" || FAILED+=("$br")
done

# 编完切回主分支，避免之后在源码树里 m bootimage 时把 KernelSU 内核打进去
cd "$KERNEL" && git checkout -f lineage-21-cannon >/dev/null 2>&1

echo ""
echo "========================================"
echo "  完成"
echo "========================================"
ls -lh "$DIST"/*.zip 2>/dev/null
md5sum "$DIST"/*.zip 2>/dev/null
if [ ${#FAILED[@]} -gt 0 ]; then echo "失败分支: ${FAILED[*]}"; exit 1; fi
exit 0
