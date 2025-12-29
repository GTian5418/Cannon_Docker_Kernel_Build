FROM ubuntu:22.04
ENV DEBIAN_FRONTEND=noninteractive
RUN apt update -y && apt install -y \
    git wget curl tar zip unzip make binutils bison flex libssl-dev bc libelf-dev \
    gcc-aarch64-linux-gnu gcc-arm-linux-gnueabi build-essential python3 \
    libncurses5-dev libncursesw5-dev pkg-config ccache && \
    apt clean && rm -rf /var/lib/apt/lists/*
WORKDIR /cannon
RUN wget https://android.googlesource.com/platform/prebuilts/clang/host/linux-x86/+archive/refs/heads/master-kernel-build-2022/clang-r450784e.tar.gz && \
    mkdir clang && tar -C clang -zxvf clang-r450784e.tar.gz && \
    wget -O gcc64.tar.gz https://android.googlesource.com/platform/prebuilts/gcc/linux-x86/aarch64/aarch64-linux-android-4.9/+archive/refs/tags/android-12.1.0_r27.tar.gz && \
    mkdir gcc64 && tar -C gcc64 -zxvf gcc64.tar.gz && \
    wget -O gcc32.tar.gz https://android.googlesource.com/platform/prebuilts/gcc/linux-x86/arm/arm-linux-androideabi-4.9/+archive/refs/tags/android-12.1.0_r27.tar.gz && \
    mkdir gcc32 && tar -C gcc32 -zxvf gcc32.tar.gz
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
