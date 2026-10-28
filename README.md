# Cannon Docker Kernel Build

Redmi Note 9T 5G（cannon / cannong，MT6853T）的**内核单独编译**环境。
不依赖 LineageOS 源码树，一把出五个分支的内核，打成 AnyKernel3 可刷 zip。

> 只想换内核、不想动 system 的话用这个；要出整包 ROM 请用
> [top-android/cannon-build](https://github.com/top-android/cannon-build)。

## 和源码树内编译的关系

工具链**已经对齐**（2026-10-28 更新）：

| 项 | 源码树 | 本仓库 |
|---|---|---|
| Clang | `clang-r487747c`（Android clang 17.0.2） | 同 |
| GCC | 4.9（`aarch64` / `arm`） | 同 |
| 内核版本串 | `4.14.336 #1 ...` | 同（`KBUILD_BUILD_VERSION=1`） |
| 产物 | `boot.img`（内核+ramdisk） | AnyKernel3 zip（只换内核） |

之前用的是 2021 年的 clang 归档（r383902 时代），已弃用 —— 编译器不一致会导致
「独立编的能用、ROM 里编的不能用」这类很难查的问题。

## 环境准备

```bash
docker run -it --name build -v "$(pwd)"/data:/data ubuntu:22.04

apt update -y && apt install -y \
    git wget curl tar zip unzip make binutils bison flex libssl-dev \
    bc libelf-dev gcc-aarch64-linux-gnu gcc-arm-linux-gnueabi \
    build-essential python3 libncurses5-dev libncursesw5-dev pkg-config ccache

mkdir -p /cannon && cd /cannon
```

### 1. Clang（必须和源码树一致）

```bash
# 方式 A（推荐）：从已经同步好的 LOS 源码树直接拷
cp -r /cannon/rom/prebuilts/clang/host/linux-x86/clang-r487747c /cannon/clang

# 方式 B：钉死提交号直接下（解压后 324 MB，和树里那份完全一样）
wget -O /tmp/clang.tgz \
  'https://android.googlesource.com/platform/prebuilts/clang/host/linux-x86/+archive/7154d3eddcb62ff7909a6ae2bf0c03e445e65bc4/clang-r487747c.tar.gz'
mkdir -p /cannon/clang && tar -C /cannon/clang -zxf /tmp/clang.tgz
```

> `+archive/<commit>/<dir>.tar.gz` 这种形式才能只取一个目录；写成 `+archive/<branch>/<dir>.tar.gz` 会 400。
> `7154d3ed…` 是 LOS 21 树里 `prebuilts/clang/host/linux-x86` 的提交，不要随便换。

验证：

```bash
/cannon/clang/bin/clang --version | head -1
# 期望：Android (10087095, ...) clang version 17.0.2 ... based on r487747c
```

### 2. GCC 4.9（只用作 CROSS_COMPILE 前缀）

```bash
mkdir -p /cannon/gcc64 /cannon/gcc32
wget -O gcc64.tar.gz https://android.googlesource.com/platform/prebuilts/gcc/linux-x86/aarch64/aarch64-linux-android-4.9/+archive/refs/tags/android-12.1.0_r27.tar.gz
wget -O gcc32.tar.gz https://android.googlesource.com/platform/prebuilts/gcc/linux-x86/arm/arm-linux-androideabi-4.9/+archive/refs/tags/android-12.1.0_r27.tar.gz
tar -C /cannon/gcc64 -zxf gcc64.tar.gz
tar -C /cannon/gcc32 -zxf gcc32.tar.gz
rm -f gcc64.tar.gz gcc32.tar.gz
```

### 3. AnyKernel3（打包用）+ dtb / dtbo / config

> `anykernel.sh` 依赖 `dtb.img` / `dtbo.img` / `config.zip`，不能漏。

```bash
wget -O /tmp/ak.zip https://github.com/GTian5418/AnyKernel3/archive/refs/heads/cannon.zip
unzip -q /tmp/ak.zip -d /tmp
mv /tmp/AnyKernel3-cannon /cannon/Anykernel
rm -f /tmp/ak.zip /cannon/Anykernel/LICENSE /cannon/Anykernel/README.md

# anykernel.sh 依赖这三个，不能漏
wget -O /cannon/Anykernel/dtb.img  https://github.com/GTian5418/android_kernel_xiaomi_cannon/releases/download/Kernel/dtb.img
wget -O /cannon/Anykernel/dtbo.img https://github.com/GTian5418/android_kernel_xiaomi_cannon/releases/download/Kernel/dtbo.img
wget -O /tmp/config.zip https://github.com/GTian5418/android_kernel_xiaomi_cannon/releases/download/Kernel/config.zip
unzip -q /tmp/config.zip -d /cannon && rm -f /tmp/config.zip
```

### 4. 内核源码

```bash
cd /cannon
git clone git@github.com:top-android/android_kernel_xiaomi_cannon.git kernel
cd kernel && git branch -a
# 应该看到：lineage-21-cannon / next / ksu / next-susfs / next-susfs-new
```

## 目录结构

```text
/cannon/
├── build.sh          编译脚本
├── kernel/           内核源码（五分支）
├── clang/            clang-r487747c
├── gcc64/ gcc32/     GCC 4.9
├── Anykernel/        AnyKernel3
├── out/              编译中间产物（每次重建）
├── dist/             输出 zip
└── .ccache/
```

## 编译

```bash
cd /cannon
./build.sh                  # 五个分支全编
./build.sh next ksu         # 只编指定的
```

输出：

| 分支 | 文件 | 内容 |
|---|---|---|
| `lineage-21-cannon` | `dist/God.zip` | 无 KernelSU（ROM 用的就是这个） |
| `next` | `dist/Next.zip` | KernelSU-Next v1.1.1 |
| `ksu` | `dist/Su.zip` | KernelSU v0.9.5 |
| `next-susfs` | `dist/Susfs.zip` | KernelSU-Next + SUSFS（旧版 1.x 协议） |
| `next-susfs-new` | `dist/SusfsNew.zip` | KernelSU-Next v3.4.2 + SUSFS v2.3.0（新 reboot 超调用协议） |

### `next-susfs-new` 有什么不同

它是 2026-10-28 重新做的一条线：SUSFS 用上游 v2.3.0 的**新 reboot 超调用协议**
（`syscall(SYS_reboot, 0xDEADBEEF, 0xFAFAFAFA, cmd, &payload)`），不再是旧版的 prctl。
一共 7 个功能，都能从用户态驱动：

| 功能 | 命令（`ksu_susfs`） |
|---|---|
| sus_path | `add_sus_path` / `add_sus_path_loop` |
| sus_kstat | `add_sus_kstat` / `add_sus_kstat_static` |
| sus_mount | 挂载时自动 |
| spoof_uname | `set_uname <release> <version>` |
| spoof_cmdline | `set_cmdline <words...>` |
| open_redirect | `add_open_redirect <target> <redirected>`（只对 uid<2000 生效） |
| enable_log | `enable_log 0\|1` |

工具源码和详细说明放在**另一个私有仓库**里（未公开，不提供链接），
对应其 `tools/ksu_susfs/` 与 `docs/2026-10-28-SUSFS*` 系列。

## 几个关键点

### 版本号固定为 `#1`

内核版本串里的 `#N` 由 `scripts/mkcompile_h` 生成，不设变量时读 `.version` 自增。
脚本里设了：

```bash
export KBUILD_BUILD_VERSION=1
```

并且每次编译前 `rm -rf out`，所以永远是 `4.14.336 #1 ...`。

### 版本串不能有 `-God` / `-g<hash>` 后缀

那两个后缀来自 **defconfig**：

- `CONFIG_LOCALVERSION="-God"` → 出现 `-God`
- 缺 `# CONFIG_LOCALVERSION_AUTO is not set` → 该选项默认 `y`，`git describe` 把 commit 哈希带出来

`lineage-21-cannon` / `next` / `ksu` / `next-susfs` 四个分支的 defconfig 完全一致
（md5 都是 `e7a04a2113d79ea77ad0dd82b186ad8a`），版本串是干净的 `4.14.336`。

`next-susfs-new` 的 md5 是 `d09afffbfcc3f7cc43ffc3ac33051b1a` —— 差异**只**在文件末尾多了
7 行 `CONFIG_KSU_SUSFS_*`，版本串同样是 `4.14.336`，没有 `-God` / `-g<hash>`。

如果以后又从别的分支拉代码，记得检查 defconfig 第 2 行。

### 为什么脚本用 `git checkout -f`

强制丢弃工作区改动，避免上一次编译留下的脏文件（比如手工 patch 过的 defconfig）污染结果。

### 编完自动切回主分支

脚本最后会 `git checkout -f lineage-21-cannon`。否则内核仓库停在 KernelSU 分支上，
之后在源码树里 `m bootimage` 会把 KernelSU 内核打进 `boot.img`。

## 刷入

```bash
# 需要先有可用的 recovery 或 KernelSU/Magisk 环境
adb reboot recovery
# recovery → Apply update → Apply from ADB
adb sideload God.zip
```

或者用 KernelSU 管理器 / 内核刷写工具直接刷 zip。

## 已知限制

- 只出 `Image.gz`，不带 `dtbo` / `vbmeta`。换内核不需要动这些。
- AnyKernel3 的 `anykernel.sh` 来自 [GTian5418/AnyKernel3](https://github.com/GTian5418/AnyKernel3) 的 `cannon` 分支，设备名、分区布局都在里面。
- 内核源码变更后记得 `git pull`，五个分支要一起拉。
