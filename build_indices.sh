#!/bin/bash
set -e

# 本脚本用于自动化数据分片、索引构建等前期准备工作

num_partitions=$1
dataset=$2 # bigann
dataset_size=$3 # 100M, 1B
metric=$4 # l2, mips
base_file=$5 #
data_path=$6 # generated data stored in this path, without'/' at the end
id=$7 # 
data_type=$8 # uint8, 




# 构建gp-ann
cd ~/workspace/rdma_anns/extern/gp-ann
cmake -S. -Bbuild_l2 -DCMAKE_POLICY_VERSION_MINIMUM=3.5
cmake --build build_l2 -j

# 创建数据文件夹
if [ ! -d "${HOME}/workspace/data" ]; then
    mkdir ${HOME}/workspace/data
fi
cd ${HOME}/workspace/data

# gp-ann 将数据分片

output_path_prefix="${data_path}/partitions_${num_partitions}_${id}/${dataset}_${dataset_size}_partition"

${HOME}/workspace/rdma_anns/scripts/index_creation/partition.sh $metric $base_file $output_path_prefix $num_partitions

if [ ! -d "${data_path}" ]; then
    mkdir ${data_path}
    mkdir ${data_path}/partitions_${num_partitions}_${id}
fi

# 将gp-ann的划分结果转变为可用格式

${HOME}/workspace/rdma_anns/build/src/state_send/convert_partition_txt_to_bin ${output_path_prefix}.k'\'=${num_partitions}.GP ${data_path}/partitions_${num_partitions}_${id}/pipeann_${dataset_size}

# build vamana algorithm in parlayann

cd ${HOME}/workspace/rdma_anns/extern/ParlayANN/algorithms/vamana
make

# 根据分片数构建图文件

# 首先创建文件夹
mkdir -p ${data_path}/indices_${num_partitions}_${id}

for (( i=0; i<=num_partitions-1; i++ ))
do
    ${HOME}/workspace/rdma_anns/scripts/index_creation/create_graph_files.sh \
    ${data_type} \
    ${metric} \
    ${data_path}/partitions_${num_partitions}_${id}/pipeann_${dataset_size}_partition${i}_ids_uint32.bin \
    $base_file \
    64 \ # R, degree
    128 \ # L, search list size
    1.2 \ # alpha, expansion factor
    ${data_path}/indices_${num_partitions}_${id}/ \
    $num_partitions \
    distributed

done

