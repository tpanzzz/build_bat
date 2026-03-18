#!/bin/bash

# 遇到错误立即停止
set -e

echo "===== 1. 配置 Kitware 官方 CMake APT 源 ====="
sudo apt update
sudo apt install -y gpg wget lsb-release
# 下载并安装 Kitware 签名密钥
wget -O - https://apt.kitware.com/keys/kitware-archive-latest.asc 2>/dev/null | \
    gpg --dearmor - | sudo tee /usr/share/keyrings/kitware-archive-keyring.gpg >/dev/null
# 添加软件源
echo "deb [signed-by=/usr/share/keyrings/kitware-archive-keyring.gpg] https://apt.kitware.com/ubuntu/ $(lsb_release -cs) main" | \
    sudo tee /etc/apt/sources.list.d/kitware.list >/dev/null

echo "===== 2. 安装基础依赖与最新版 CMake ====="
sudo apt update
sudo apt install -y cmake autoconf automake libtool pkg-config make g++ \
    libaio-dev libgoogle-perftools-dev clang-format libboost-all-dev \
    libmkl-full-dev libjemalloc-dev libssl-dev nlohmann-json3-dev libsparsehash-dev

mkdir -p ~/workspace && cd ~/workspace

echo "===== 3. 编译安装 libzmq ====="
if [ ! -d "libzmq" ]; then git clone https://github.com/zeromq/libzmq/; fi
cd libzmq && ./autogen.sh && ./configure --prefix=/usr/local --enable-drafts
make -j$(nproc) && sudo make install && sudo ldconfig
cd ~/workspace

echo "===== 4. 编译安装 parlaylib ====="
if [ ! -d "parlaylib" ]; then git clone https://github.com/cmuparlay/parlaylib; fi
cd parlaylib && mkdir -p build && cd build
cmake .. && sudo cmake --build . --target install
cd ~/workspace

echo "===== 5. 编译安装 Catch2 ====="
if [ ! -d "Catch2" ]; then git clone https://github.com/catchorg/Catch2.git; fi
cd Catch2 && cmake -B build -S . -DBUILD_TESTING=OFF
sudo cmake --build build/ -j$(nproc) --target install
cd ~/workspace

echo "===== 6. 构建 BatANN (rdma_anns) ====="
# 使用 HTTPS 避免 SSH Key 验证问题
if [ ! -d "rdma_anns" ]; then git clone https://github.com/namanhboi/rdma_anns.git; fi
cd rdma_anns
git submodule update --init --recursive --remote

# 编译 liburing 子模块
cd extern/liburing && ./configure && make -j$(nproc)
cd ~/workspace/rdma_anns

# 编译并安装 spdlog
if [ ! -d "spdlog" ]; then git clone https://github.com/gabime/spdlog.git; fi
cd spdlog && mkdir -p build && cd build
cmake .. && sudo cmake --build . --target install

# 主项目编译
cd ~/workspace/rdma_anns
cmake -S. -B build \
    -DCMAKE_POSITION_INDEPENDENT_CODE=ON \
    -DCMAKE_EXPORT_COMPILE_COMMANDS=1 \
    -DTEST_UDL2=OFF -DTEST_UDL1=OFF \
    -DDISK_FS_DISKANN_WRAPPER=OFF \
    -DDISK_FS_DISTRIBUTED=ON \
    -DDISK_KV=OFF -DIN_MEM=OFF \
    -DPQ_KV=OFF -DPQ_FS=ON \
    -DDATA_TYPE=uint8 \
    -DTEST_COMPUTE_PIPELINE=OFF \
    -DBALANCE_ALL=OFF \
    -DCMAKE_BUILD_TYPE=RELEASE

cmake --build build/ -j$(nproc)

echo "===== 7. 设置测试数据集与 Python 环境 ====="
cd ~/
if [ ! -d "big-ann-benchmarks" ]; then git clone https://github.com/harsha-simhadri/big-ann-benchmarks; fi
cd big-ann-benchmarks
# 针对你环境中的 Python 3.10.12 安装依赖
pip3 install -r requirements_py3.10.txt
python3 create_dataset.py --dataset bigann-10M

echo "🎉 恭喜！所有环境配置与编译已圆满完成。"