# source 本文件后，ibv_devinfo / perftest 使用本目录编出的 rdma-core（含 yuanrdma provider）
# 系统自带的 rdma-core 是 39.0，provider 必须与同一版本的 libibverbs 一起用。
_RDMA_BUILD=$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)/build/src/build
export LD_LIBRARY_PATH=$_RDMA_BUILD/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}
export RDMAV_DRIVERS=$_RDMA_BUILD/lib/libyuanrdma:$_RDMA_BUILD/lib/libirdma:$_RDMA_BUILD/lib/libmlx5
export PATH=$_RDMA_BUILD/bin:$PATH
unset _RDMA_BUILD
