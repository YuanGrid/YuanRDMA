#!/bin/sh
# 用 code/github/rdma-core（v66，只读）+ 本目录的 yuanrdma provider 编出一套 rdma-core。
# 产物在 code/rdmasw/rdma-core-provider/build/（不入库）：build/lib/libyuanrdma-rdmav*.so 等。
# 用法：./build.sh；运行 perftest 时：
#   export LD_LIBRARY_PATH=$PWD/build/lib RDMAV_DRIVERS=yuanrdma  （或用 build/etc 中的 driver 配置）
set -e
HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$HERE/../../.." && pwd)

# rdma-core 源码已入库到本仓库 code/github/（commit 612d497，2026-11-11）。
# 以下探测顺序支持多种部署场景：
#   1. 环境变量 SRC_RDMACORE（优先级最高，用于指向特定版本或本地修改）
#   2. 本仓库 code/github/rdma-core（正常情况自动找到）
#   3. /opt 下的备份副本（部分服务器环境）
for _d in "${SRC_RDMACORE:-}" "$ROOT/code/github/rdma-core" /opt/code/github/rdma-core; do
    [ -n "$_d" ] && [ -d "$_d" ] && SRC_RDMACORE="$_d" && break
done
unset _d
if [ -z "${SRC_RDMACORE:-}" ]; then
    echo "错误：找不到 rdma-core 源码，已尝试：$ROOT/code/github/rdma-core、/opt/..." >&2
    echo "  请设置 SRC_RDMACORE 环境变量，或 clone 到 $ROOT/code/github/rdma-core" >&2
    exit 1
fi

WORK=$HERE/build/src
CMAKE=${CMAKE:-cmake}
rm -rf "$WORK" && mkdir -p "$WORK"
cp -a "$SRC_RDMACORE/." "$WORK/"
rm -rf "$WORK/.git_upstream"
cp -a "$HERE/yuanrdma" "$WORK/providers/yuanrdma"
cp "$ROOT/code/kernel/yuanrdma/yuanrdma_abi_defs.h" "$WORK/kernel-headers/rdma/yuanrdma-abi.h"
cp "$ROOT/code/rdmasw/include/yuanrdma_hw.h" "$WORK/providers/yuanrdma/yuanrdma_hw.h"
# 注册 provider 与 ABI 头（两个列表都要加）
sed -i 's#^  rdma/erdma-abi.h$#  rdma/erdma-abi.h\n  rdma/yuanrdma-abi.h#' "$WORK/kernel-headers/CMakeLists.txt"
sed -i 's#^add_subdirectory(providers/erdma)$#add_subdirectory(providers/erdma)\nadd_subdirectory(providers/yuanrdma)#' "$WORK/CMakeLists.txt"
mkdir -p "$WORK/build"
cd "$WORK/build"
$CMAKE -GNinja -DNO_MAN_PAGES=1 -DNO_PYVERBS=1 -DENABLE_RESOLVE_NEIGH=0 -DCMAKE_BUILD_TYPE=RelWithDebInfo .. > "$HERE/build/cmake.log"
ninja > "$HERE/build/ninja.log"
rm -rf "$HERE/build/lib" "$HERE/build/bin" "$HERE/build/etc"
cp -a lib bin etc "$HERE/build/"
echo "ok: $HERE/build/lib"
