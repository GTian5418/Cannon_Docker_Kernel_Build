FROM ubuntu:22.04
ENV DEBIAN_FRONTEND=noninteractive
RUN apt update -y && apt install -y \
    git wget curl tar zip unzip make binutils bison flex libssl-dev bc libelf-dev \
    gcc-aarch64-linux-gnu gcc-arm-linux-gnueabi build-essential python3 \
    libncurses5-dev libncursesw5-dev pkg-config ccache && \
    apt clean && rm -rf /var/lib/apt/lists/*
WORKDIR /cannon

# Clang r487747c —— 和 LineageOS 21 源码树里的 prebuilts/clang 完全一致
RUN wget -O /tmp/clang.tgz \
      'https://android.googlesource.com/platform/prebuilts/clang/host/linux-x86/+archive/7154d3eddcb62ff7909a6ae2bf0c03e445e65bc4/clang-r487747c.tar.gz' && \
    mkdir -p clang && tar -C clang -zxf /tmp/clang.tgz && rm -f /tmp/clang.tgz

# GCC 4.9（只作 CROSS_COMPILE 前缀，实际 CC=clang）
RUN wget -O /tmp/gcc64.tgz https://android.googlesource.com/platform/prebuilts/gcc/linux-x86/aarch64/aarch64-linux-android-4.9/+archive/refs/tags/android-12.1.0_r27.tar.gz && \
    mkdir -p gcc64 && tar -C gcc64 -zxf /tmp/gcc64.tgz && \
    wget -O /tmp/gcc32.tgz https://android.googlesource.com/platform/prebuilts/gcc/linux-x86/arm/arm-linux-androideabi-4.9/+archive/refs/tags/android-12.1.0_r27.tar.gz && \
    mkdir -p gcc32 && tar -C gcc32 -zxf /tmp/gcc32.tgz && \
    rm -f /tmp/gcc64.tgz /tmp/gcc32.tgz

# 内核源码（四个分支：lineage-21-cannon / next / ksu / next-susfs）
RUN git clone https://github.com/top-android/android_kernel_xiaomi_cannon.git kernel

# AnyKernel3（打包成可刷 zip）
RUN wget -O /tmp/ak.zip https://github.com/GTian5418/AnyKernel3/archive/refs/heads/cannon.zip && \
    unzip -q /tmp/ak.zip -d /tmp && mv /tmp/AnyKernel3-cannon /cannon/Anykernel && \
    rm -f /tmp/ak.zip /cannon/Anykernel/LICENSE /cannon/Anykernel/README.md

COPY build.sh /cannon/build.sh
RUN chmod +x /cannon/build.sh

# 产物会被拷到 /output（运行时 -v 挂载）
CMD ["/bin/bash", "-c", "/cannon/build.sh && mkdir -p /output && cp /cannon/dist/*.zip /output/"]
