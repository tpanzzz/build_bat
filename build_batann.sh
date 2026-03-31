#!/bin/bash

# 遇到错误立即停止
set -e

echo "===== 1. 配置 Git 协议替换 (SSH -> HTTPS) ====="
# 解决子模块中 git@github.com 导致的权限拒绝问题
git config --global url."https://github.com/".insteadOf git@github.com:

echo "===== 2. 配置 Kitware 官方 CMake APT 源 ====="
sudo apt update
sudo apt install -y gpg wget lsb-release
wget -O - https://apt.kitware.com/keys/kitware-archive-latest.asc 2>/dev/null | \
    gpg --dearmor - | sudo tee /usr/share/keyrings/kitware-archive-keyring.gpg >/dev/null
echo "deb [signed-by=/usr/share/keyrings/kitware-archive-keyring.gpg] https://apt.kitware.com/ubuntu/ $(lsb_release -cs) main" | \
    sudo tee /etc/apt/sources.list.d/kitware.list >/dev/null

echo "===== 3. 安装基础依赖 (含 TBB 和 NUMA) ====="
sudo apt update
# 额外添加了 libtbb-dev 和 libnuma-dev 以支持 KaMinPar 编译
sudo apt install -y cmake autoconf automake libtool pkg-config make g++ \
    libaio-dev libgoogle-perftools-dev clang-format libboost-all-dev \
    libmkl-full-dev libjemalloc-dev libssl-dev nlohmann-json3-dev \
    libsparsehash-dev libtbb-dev libnuma-dev

mkdir -p ~/workspace && cd ~/workspace

echo "===== 4. 编译安装 libzmq ====="
if [ ! -d "libzmq" ]; then git clone https://github.com/zeromq/libzmq/; fi
cd libzmq && ./autogen.sh && ./configure --prefix=/usr/local --enable-drafts
make -j$(nproc) && sudo make install && sudo ldconfig
cd ~/workspace

echo "===== 5. 编译安装 parlaylib ====="
if [ ! -d "parlaylib" ]; then git clone https://github.com/cmuparlay/parlaylib; fi
cd parlaylib && mkdir -p build && cd build
cmake .. && sudo cmake --build . --target install
cd ~/workspace

echo "===== 6. 编译安装 Catch2 ====="
if [ ! -d "Catch2" ]; then git clone https://github.com/catchorg/Catch2.git; fi
cd Catch2 && cmake -B build -S . -DBUILD_TESTING=OFF
sudo cmake --build build/ -j$(nproc) --target install
cd ~/workspace

echo "===== 7. 构建 BatANN (rdma_anns) ====="
if [ ! -d "rdma_anns" ]; then git clone https://github.com/tpanzzz/rdma_anns.git; fi
cd rdma_anns

# 核心修改：不带 --remote，确保回滚到主仓库记录的稳定版本
echo "正在初始化子模块到记录版本..."
git submodule update --init --recursive

# 编译 liburing
cd extern/liburing && ./configure && make -j$(nproc)
cd ~/workspace/rdma_anns

# 安装 spdlog
if [ ! -d "spdlog" ]; then git clone https://github.com/gabime/spdlog.git; fi
cd spdlog && mkdir -p build && cd build
cmake .. && sudo cmake --build . --target install

# 主项目编译：添加 CMAKE_POLICY_VERSION_MINIMUM 解决低版本限制问题
echo "开始执行主项目 CMake 配置..."
cd ~/workspace/rdma_anns
rm -rf build # 清理旧缓存
cmake -S. -B build \
    -DCMAKE_POLICY_VERSION_MINIMUM=3.5 \
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

echo "===== 8. 设置测试数据集 ====="
cd ~/
if [ ! -d "big-ann-benchmarks" ]; then git clone https://github.com/harsha-simhadri/big-ann-benchmarks; fi
cd big-ann-benchmarks
sudo apt install python3-pip -y
pip3 install -r requirements_py3.10.txt
# 如果需要自动生成数据，请取消下行注释
python3 create_dataset.py --dataset bigann-10M

echo "🎉 所有流程已自动化完成！"