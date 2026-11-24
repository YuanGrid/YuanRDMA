#!/bin/bash
# YuanNIC 用户态软件包构建：rdma-core(v66) + yuanrdma provider + perftest + 内核 ko
#                          + yuancli 诊断工具 + 手册，最后打包成
#                          YuanNIC_User_Package-<版本>-<YYYYMMDD>.tgz（版本用 --version 给）。
#
# 产物全部收集到 YuanNIC_User_Package/，与系统 doca-host / MLNX_OFED 的 RDMA 栈完全隔离：
#   YuanNIC_User_Package/bin/       perftest 程序 + ibv_* 工具 + yuancli + ynictrl
#   YuanNIC_User_Package/env.sh     运行前 source，把库和程序路径指到本目录
#   YuanNIC_User_Package/lib/       libibverbs / librdmacm / libyuanrdma-rdmav65.so ...
#   YuanNIC_User_Package/include/   头文件（编译依赖本栈的其他程序时用）
#   YuanNIC_User_Package/ko/        内核模块：yuanrdma.ko / yuanmcdma.ko / yuannic.ko
#   YuanNIC_User_Package/doc/       用户手册
#   YuanNIC_User_Package/tools/     运维脚本（flash_and_init.sh / roce_perf_test.sh）
#   YuanNIC_User_Package/firmware/  每块板最新一版烧写镜像（.jic + .rpd + .sof），取自 firmware/
#   YuanNIC_User_Package-<版本>-<YYYYMMDD>.tgz
#                                   整个目录的打包，可直接交给最终用户（包内顶层目录名不带版本）
#
# 关键点：系统里装了 doca-host 3.5.0（OFED 26.07），它的 libibverbs 是 PABI 64，
# 只认 lib*-rdmav64.so；本脚本编出的 rdma-core 是 PABI 65，provider 是 lib*-rdmav65.so。
# 两套库文件名不同、靠 LD_LIBRARY_PATH 选择，不会互相覆盖。
# 本脚本**不安装**任何文件到系统路径，也不会编译/覆盖 rdma-core 的内核模块
# （mlx5_ib / ib_uverbs / rdma_cm 由系统或 DOCA 提供）。
#
# 用法：
#   ./yuannic_user_build.sh --version 26.12.02   # 全量编译 + 打包成 YuanNIC_User_Package-26.12.02-<今天>.tgz
#   ./yuannic_user_build.sh        # 不给版本：版本记为 dev（交付前务必带 --version）
#   ./yuannic_user_build.sh --no-ko   # 只编用户态
#   ./yuannic_user_build.sh --clean   # 清理中间目录后重新编译
#
# 环境变量：
#   YUANNIC_VERSION 同 --version（命令行优先）
#   CMAKE   指定 cmake（默认自动找）
#   JOBS    并行度（默认 nproc）
#   CC_KERN 内核模块编译器（默认自动找 gcc-12/gcc）

set -euo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
# 2026-11-20 从 build/user_tools/ 移到 deploy/：deploy 在仓库根下一层，
# 所以根目录从「上两级」变成「上一级」。
ROOT=$(cd "$HERE/.." && pwd)

# rdma-core 和 perftest 源码已入库到本仓库 code/github/（commit 612d497，2026-11-11）。
# 以下探测顺序支持多种部署场景：
#   1. 环境变量 SRC_RDMACORE/SRC_PERFTEST（优先级最高，用于指向特定版本或本地修改）
#   2. 本仓库 code/github/（正常情况自动找到）
#   3. /opt 下的备份副本（部分服务器环境）
for _d in "${SRC_RDMACORE:-}" "$ROOT/code/github/rdma-core" /opt/code/github/rdma-core; do
    [ -n "$_d" ] && [ -d "$_d" ] && SRC_RDMACORE="$_d" && break
done
for _d in "${SRC_PERFTEST:-}" "$ROOT/code/github/perftest" /opt/code/github/perftest; do
    [ -n "$_d" ] && [ -d "$_d" ] && SRC_PERFTEST="$_d" && break
done
unset _d

SRC_PROVIDER="$ROOT/code/rdmasw/rdma-core-provider/yuanrdma"
SRC_HW_HEADER="$ROOT/code/rdmasw/include/yuanrdma_hw.h"
SRC_ABI_HEADER="$ROOT/code/kernel/yuanrdma/yuanrdma_abi_defs.h"
SRC_KERNEL="$ROOT/code/kernel"
SRC_YNICTRL="$ROOT/code/ynictrl"

# 编译中间目录（rdma-core/perftest 的源码副本与日志）不放仓库里（2026-11-21 用户要求）：
# 仓库保持干净，临时件统一落 /home/roce_build 下。
# 换机器或要回到仓库内编译时用 YUANNIC_BUILD_WORK 覆盖。
WORK="${YUANNIC_BUILD_WORK:-/home/roce_build/yuannic_build/work}"
# 产物默认仍落在 build/user_tools/YuanNIC_User_Package（2026-11-20）：
# 脚本本身挪到了 deploy/，但**消费方没挪**——build/user_tools/flash_and_init.sh
# 与 roce_perf_test.sh 都按「同级目录下有 YuanNIC_User_Package/」来定位包，
# 产物跟着挪会把上板流程直接打断。要改存放位置，用环境变量覆盖这行，
# 并同步改那两个脚本，不要只改一处。
OUT="${YUANNIC_PKG_OUT:-$ROOT/build/user_tools/YuanNIC_User_Package}"

BUILD_KO=1
BUILD_TGZ=1

usage()
{
    cat <<'USAGE'
用法：
  ./yuannic_user_build.sh [选项]

选项：
  -h, --help     显示本帮助并退出
                     默认行为（不加 --clean/--no-ko 时即"全量编译"）
  -v, --version <版本>
                 交付包版本，形如 26.12.02（可带后缀，如 26.12.02-rc1）。写进 VERSION、
                 README，并进入包名：YuanNIC_User_Package-<版本>-<YYYYMMDD>.tgz，
                 日期取构建当天。不给时版本记为 dev，并打印警告。
      --clean    先删除 work/ 中间目录再编译（rdma-core 和 perftest 都重编）
      --no-ko    只编用户态，跳过内核模块（yuanrdma.ko / yuanmcdma.ko / yuannic.ko）
      --no-tgz   不生成 .tgz（只留目录）

环境变量：
  YUANNIC_VERSION 同 --version，命令行给了以命令行为准。
  CMAKE          指定 cmake 可执行文件。默认自动挑一个 >= 3.18.1 的；
                 注意 PATH 里若有 Xilinx Vitis 的 cmake 3.3.2 会被跳过。
  JOBS           并行度，默认 nproc。
  CC_KERN        编内核模块用的编译器，默认自动找 gcc-12，找不到则用 gcc。
                 必须与编译当前内核的编译器一致（Ubuntu 22.04 HWE 6.8 是 gcc-12）。
  YUANNIC_FW_DIR    固件镜像目录，默认仓库根 firmware/。
  YUANNIC_FW_BOARDS 只带指定板卡的镜像，如 "C"；默认每块板各带最新一版。

做什么：
  1. 复制 code/github/rdma-core（v66）到 work/，注入 code/rdmasw/rdma-core-provider/yuanrdma，
     注册 provider 与 ABI 头（yuanrdma_abi_defs.h → rdma-core 内改名 yuanrdma-abi.h），用 cmake + ninja 编出完整 userspace 栈。
  2. 复制 code/github/perftest 到 work/，对着上面这套 rdma-core 编出 perftest 6.31。
  3. （未加 --no-ko 时）编 code/kernel 下的 yuanrdma.ko、yuanmcdma.ko、yuannic.ko。
  4. 编 code/ynictrl 下的 ynictrl（FPGA 网卡固件更新工具）。
  5. 把程序、库、头文件、ko、yuancli、手册全部收集到 YuanNIC_User_Package/。
  6. 生成 VERSION / README.md / doc/ 两份手册。
  7. 打包成 YuanNIC_User_Package-<版本>-<YYYYMMDD>.tgz（--no-tgz 可跳过），
     放在本脚本所在目录；包内顶层目录名固定为 YuanNIC_User_Package/。

产物：
  YuanNIC_User_Package/env.sh      运行前 source 本文件
  YuanNIC_User_Package/bin/        perftest 6.31 + ibv_* 工具 + yuancli + ynictrl
  YuanNIC_User_Package/lib/        libibverbs(PABI 65) / librdmacm / libyuanrdma-rdmav65.so ...
  YuanNIC_User_Package/include/    头文件
  YuanNIC_User_Package/ko/         yuanrdma.ko / yuanmcdma.ko / yuannic.ko
  YuanNIC_User_Package/etc/libibverbs.d/  空目录，libibverbs 启动时 opendir 用（消除 Warning）
  YuanNIC_User_Package/doc/        用户手册
  YuanNIC_User_Package/firmware/   每块板最新一版烧写镜像（.jic / .rpd / .sof + SHA256SUMS）
  YuanNIC_User_Package-<版本>-<YYYYMMDD>.tgz   可直接交付的压缩包

与系统 DOCA/OFED 的隔离：
  系统 doca-host 3.5.0（OFED 26.07）的 libibverbs 是 PABI 64，只认 lib*-rdmav64.so；
  本脚本编出的是 PABI 65，provider 为 lib*-rdmav65.so。文件名不同，靠
  LD_LIBRARY_PATH + RDMAV_DRIVERS 选择，互不覆盖。脚本不往系统路径安装任何文件，
  也不编 rdma-core 的内核模块（mlx5_ib / ib_uverbs / rdma_cm 由系统或 DOCA 提供）。

示例：
  ./yuannic_user_build.sh --version 26.12.02   # 全量编译 + 打包（YuanNIC_User_Package-26.12.02-<今天>.tgz）
  ./yuannic_user_build.sh                # 全量编译 + 打包，版本记为 dev
  ./yuannic_user_build.sh --clean        # 清理后全量重编
  ./yuannic_user_build.sh --no-ko        # 只编用户态
  ./yuannic_user_build.sh --no-tgz       # 不生成 .tgz
  JOBS=16 ./yuannic_user_build.sh --clean --version 26.12.02

编译完成后使用：
  tar xzf YuanNIC_User_Package-<版本>-<YYYYMMDD>.tgz
  source YuanNIC_User_Package/env.sh
  ibv_devinfo -d yuanrdma0
  ib_write_bw -d yuanrdma0 -x 3 -F <对端IP>
USAGE
}

PKG_VERSION="${YUANNIC_VERSION:-}"
DO_CLEAN=0
while [ $# -gt 0 ]; do
    case "$1" in
        -h|--help) usage; exit 0 ;;
        -v|--version)
            [ $# -ge 2 ] && [ -n "$2" ] || { echo "$1 后面要跟版本号，如 $1 26.12.02" >&2; exit 1; }
            PKG_VERSION="$2"; shift ;;
        --version=*) PKG_VERSION="${1#--version=}" ;;
        --no-ko)   BUILD_KO=0 ;;
        --no-tgz)  BUILD_TGZ=0 ;;
        --clean)   DO_CLEAN=1 ;;
        *) echo "未知参数：$1" >&2; echo "" >&2; usage >&2; exit 1 ;;
    esac
    shift
done

# 版本号会进文件名，只收「数字.数字.数字」加可选后缀，挡掉 R26.12.02、空格、斜杠之类。
if [ -z "$PKG_VERSION" ]; then
    PKG_VERSION=dev
    echo "警告：没给 --version，版本记为 dev；交付给用户的包请带 --version <版本>（如 26.12.02）" >&2
elif ! printf '%s\n' "$PKG_VERSION" | grep -qE '^[0-9]+\.[0-9]+\.[0-9]+([.-][0-9A-Za-z]+)*$'; then
    echo "版本号「$PKG_VERSION」格式不对：应为 26.12.02 这样的「数字.数字.数字」，可带 -rc1 之类后缀" >&2
    exit 1
fi
# 构建时间只取一次：VERSION 里的时间与包名里的日期必须一致，跨零点构建也不会错开。
BUILD_EPOCH=$(date +%s)
BUILD_TIME=$(date -d "@$BUILD_EPOCH" '+%Y-%m-%d %H:%M:%S')
BUILD_DATE=$(date -d "@$BUILD_EPOCH" '+%Y%m%d')
PKG_NAME="YuanNIC_User_Package-$PKG_VERSION-$BUILD_DATE"

# 参数全部校验通过后才删中间目录，避免参数写错却先把 work/ 清掉
if [ "$DO_CLEAN" = 1 ]; then
    rm -rf "$WORK"; echo "已清理 $WORK"
fi

JOBS=${JOBS:-$(nproc)}
CC_KERN=${CC_KERN:-}

log()  { echo ""; echo "=== $* ==="; }
die()  { echo ""; echo "错误：$*" >&2; exit 1; }

# ---------------------------------------------------------------------------
# 0. 前置检查
# ---------------------------------------------------------------------------
log "0. 前置检查"

[ -d "$SRC_RDMACORE" ] || die "找不到 rdma-core 源码：$SRC_RDMACORE
    请 clone 到 $ROOT/code/github/rdma-core，或设置 SRC_RDMACORE 环境变量。
    获取方式：
      git clone https://github.com/linux-rdma/rdma-core.git $ROOT/code/github/rdma-core
      git -C $ROOT/code/github/rdma-core checkout b63b7bfe5d5b0adb97b973c71723adf2323afa2c"
[ -d "$SRC_PERFTEST" ] || die "找不到 perftest 源码：$SRC_PERFTEST
    请 clone 到 $ROOT/code/github/perftest，或设置 SRC_PERFTEST 环境变量。
    获取方式：
      git clone https://github.com/linux-rdma/perftest.git $ROOT/code/github/perftest
      git -C $ROOT/code/github/perftest checkout 68fdb9f2359ce39865daca0c1bc66e381a43afa4"
[ -d "$SRC_PROVIDER" ] || die "找不到 yuanrdma provider：$SRC_PROVIDER"
[ -f "$SRC_HW_HEADER" ] || die "找不到 $SRC_HW_HEADER"
[ -f "$SRC_ABI_HEADER" ] || die "找不到 $SRC_ABI_HEADER"

# cmake：系统自带 3.22 即可（rdma-core 要求 >= 3.18.1）。
# 注意 PATH 里若有 Xilinx Vitis 的 cmake 3.3.2，它不满足要求，这里优先用 /usr/bin/cmake。
if [ -z "${CMAKE:-}" ]; then
    for c in /usr/bin/cmake /usr/local/bin/cmake "$(command -v cmake 2>/dev/null || true)"; do
        [ -x "$c" ] || continue
        ver=$("$c" --version 2>/dev/null | head -1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)
        [ -n "$ver" ] || continue
        maj=$(echo "$ver" | cut -d. -f1); min=$(echo "$ver" | cut -d. -f2)
        if [ "$maj" -gt 3 ] || { [ "$maj" -eq 3 ] && [ "$min" -ge 18 ]; }; then
            CMAKE=$c; break
        fi
    done
fi
[ -n "${CMAKE:-}" ] && [ -x "$CMAKE" ] || die "找不到 cmake >= 3.18.1（可用 CMAKE=/path/to/cmake 指定）"
echo "cmake      : $CMAKE ($("$CMAKE" --version | head -1))"

command -v ninja >/dev/null || die "缺少 ninja（apt install ninja-build）"
command -v make  >/dev/null || die "缺少 make"
command -v autoconf >/dev/null || command -v autoreconf >/dev/null || die "缺少 autoconf/automake/libtool"
for t in autoconf automake libtoolize; do
    command -v $t >/dev/null || die "缺少 $t（apt install autoconf automake libtool）"
done

# perftest 需要 pciutils 头文件与库（多架构下头文件在 /usr/include/<triplet>/pci/）
pci_header_found=0
for h in /usr/include/pci/pci.h /usr/include/*-linux-gnu*/pci/pci.h; do
    [ -f "$h" ] && { pci_header_found=1; break; }
done
[ "$pci_header_found" = "1" ] || die "缺少 pci/pci.h（apt install libpci-dev）"

if [ "$BUILD_KO" = "1" ]; then
    [ -d "/lib/modules/$(uname -r)/build" ] || die "缺少内核头文件（apt install linux-headers-$(uname -r)）"
    if [ -z "$CC_KERN" ]; then
        if command -v gcc-12 >/dev/null; then CC_KERN=gcc-12; else CC_KERN=gcc; fi
    fi
    echo "kernel cc  : $CC_KERN"
fi

# 打印系统 RDMA 栈的 PABI，提醒两套库并存
SYS_IBV=$(ls /usr/lib/*/libibverbs.so.1.* 2>/dev/null | head -1 || true)
if [ -n "$SYS_IBV" ]; then
    SYS_PABI=$(basename "$SYS_IBV" | grep -oE '\.[0-9]+\.0$' | tr -d '.0' || true)
    echo "系统 ibverbs: $SYS_IBV  (PABI ${SYS_PABI:-未知})"
fi
echo "本栈 PABI  : 65（provider 文件名 lib*-rdmav65.so）"

# ---------------------------------------------------------------------------
# 1. 准备 rdma-core 源码副本并注入 yuanrdma provider
# ---------------------------------------------------------------------------
log "1. 准备 rdma-core 源码并注入 provider"

RC="$WORK/rdma-core"
rm -rf "$RC"
mkdir -p "$WORK"
cp -a "$SRC_RDMACORE/." "$RC/"
rm -rf "$RC/.git" "$RC/.git_upstream"

cp -a "$SRC_PROVIDER" "$RC/providers/yuanrdma"
cp "$SRC_ABI_HEADER" "$RC/kernel-headers/rdma/yuanrdma-abi.h"
cp "$SRC_HW_HEADER"  "$RC/providers/yuanrdma/yuanrdma_hw.h"

# 注册 provider 子目录与 ABI 头（两个列表都要加，缺一个就编不出来）
sed -i 's#^add_subdirectory(providers/erdma)$#add_subdirectory(providers/erdma)\nadd_subdirectory(providers/yuanrdma)#' "$RC/CMakeLists.txt"
sed -i 's#^  rdma/erdma-abi.h$#  rdma/erdma-abi.h\n  rdma/yuanrdma-abi.h#' "$RC/kernel-headers/CMakeLists.txt"

grep -q 'add_subdirectory(providers/yuanrdma)' "$RC/CMakeLists.txt" \
    || die "provider 注册失败：CMakeLists.txt 里没有 yuanrdma"
grep -q 'rdma/yuanrdma-abi.h' "$RC/kernel-headers/CMakeLists.txt" \
    || die "ABI 头注册失败"

# ---------------------------------------------------------------------------
# 2. 编译 rdma-core（含 yuanrdma provider）
# ---------------------------------------------------------------------------
log "2. 编译 rdma-core + yuanrdma provider"

mkdir -p "$RC/build"
(
    cd "$RC/build"
    # CMAKE_INSTALL_SYSCONFDIR 指到 YuanNIC_User_Package/etc：libibverbs 编译期会把
    # IBV_CONFIG_DIR 固化成 <这个目录>/libibverbs.d。这样运行期即使没有
    # RDMAV_DRIVERS，也只会从本目录读 provider 配置，不会去碰系统的
    # /etc/libibverbs.d（那是 DOCA/OFED 的地盘），也不会报 "couldn't open" 警告。
    "$CMAKE" -GNinja \
        -DCMAKE_BUILD_TYPE=RelWithDebInfo \
        -DNO_MAN_PAGES=1 \
        -DNO_PYVERBS=1 \
        -DENABLE_RESOLVE_NEIGH=0 \
        -DENABLE_STATIC=0 \
        -DCMAKE_INSTALL_SYSCONFDIR="$OUT/etc" \
        .. > "$WORK/cmake.log" 2>&1
    ninja -j "$JOBS" > "$WORK/ninja.log" 2>&1
) || {
    echo "--- cmake 日志末尾 ---"; tail -n 30 "$WORK/cmake.log" 2>/dev/null || true
    echo "--- ninja 日志末尾 ---"; tail -n 40 "$WORK/ninja.log" 2>/dev/null || true
    die "rdma-core 编译失败"
}
echo "rdma-core 编译完成"

# ---------------------------------------------------------------------------
# 3. 编译 perftest（对着上面这套 rdma-core 编）
# ---------------------------------------------------------------------------
log "3. 编译 perftest"

PT="$WORK/perftest"
rm -rf "$PT"
cp -a "$SRC_PERFTEST/." "$PT/"
rm -rf "$PT/.git"

# 关键：头文件和库都指向本次编译的 rdma-core，绝不能用系统 DOCA 的那套
RC_BUILD="$RC/build"
(
    cd "$PT"
    ./autogen.sh > "$WORK/perftest_autogen.log" 2>&1
    # CPPFLAGS/LDFLAGS 里用 $$ORIGIN：configure 会把它写进 Makefile，
    # make 展开 $$ -> $，最终 gcc 拿到 $ORIGIN，运行期按可执行文件位置找 lib/。
    # 注意是 ../lib：perftest 程序最终放在 bin/ 里，库在 lib/ 里，是兄弟目录。
    # 写成 $ORIGIN/lib 会让程序在 bin/ 下找不到库（来源：move 到 bin/ 时的真实回归）。
    CPPFLAGS="-I$RC_BUILD/include ${CPPFLAGS:-}" \
    LDFLAGS="-L$RC_BUILD/lib -Wl,-rpath,'\$\$ORIGIN/../lib' ${LDFLAGS:-}" \
    LD_LIBRARY_PATH="$RC_BUILD/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}" \
    ./configure \
        --prefix="$PT/install" \
        --enable-option-checking=fatal \
        > "$WORK/perftest_configure.log" 2>&1
    make -j "$JOBS" > "$WORK/perftest_make.log" 2>&1
) || {
    echo "--- configure 日志末尾 ---"; tail -n 30 "$WORK/perftest_configure.log" 2>/dev/null || true
    echo "--- make 日志末尾 ---"; tail -n 40 "$WORK/perftest_make.log" 2>/dev/null || true
    die "perftest 编译失败"
}
echo "perftest 编译完成"

# ---------------------------------------------------------------------------
# 4. 编译内核模块（只编 yuanrdma / yuanmcdma / yuannic，不碰 rdma-core 的内核模块）
# ---------------------------------------------------------------------------
KO_DIR="$WORK/ko"
if [ "$BUILD_KO" = "1" ]; then
    log "4. 编译内核模块"
    rm -rf "$KO_DIR"; mkdir -p "$KO_DIR"

    echo "  - yuanrdma.ko"
    make -C "$SRC_KERNEL/yuanrdma" CC="$CC_KERN" > "$WORK/yuanrdma_make.log" 2>&1 || {
        tail -n 40 "$WORK/yuanrdma_make.log"; die "yuanrdma.ko 编译失败"; }

    echo "  - yuanmcdma.ko / yuannic.ko"
    make -C "$SRC_KERNEL" CC="$CC_KERN" > "$WORK/kernel_make.log" 2>&1 || {
        tail -n 40 "$WORK/kernel_make.log"; die "yuanmcdma/yuannic 编译失败"; }

    for k in yuanrdma/yuanrdma.ko mcdma/mcdma_kmod/yuanmcdma.ko yuannic_netdev/yuannic.ko; do
        [ -f "$SRC_KERNEL/$k" ] || die "没有生成 $k"
        cp "$SRC_KERNEL/$k" "$KO_DIR/"
    done
    echo "内核模块编译完成"
else
    echo ""; echo "=== 4. 跳过内核模块（--no-ko）==="
fi

# ---------------------------------------------------------------------------
# 4b. 编译 ynictrl（FPGA 网卡固件更新工具，源码在 code/ynictrl）
# ---------------------------------------------------------------------------
YNICTRL_DIR="$WORK/ynictrl"
log "4b. 编译 ynictrl（固件更新工具）"

if [ ! -d "$SRC_YNICTRL" ]; then
    echo "  [跳过] 找不到 $SRC_YNICTRL"
else
    rm -rf "$YNICTRL_DIR"
    mkdir -p "$YNICTRL_DIR"
    # 只拷源码，不带旧的 .o / 旧二进制，避免拿到过期产物。
    # ynic_net_base.h 已在 code/ynictrl/include/，编译自包含。
    rsync -a --exclude '*.o' --exclude 'ynictrl' "$SRC_YNICTRL"/ "$YNICTRL_DIR"/

    make -C "$YNICTRL_DIR" > "$WORK/ynictrl_make.log" 2>&1 || {
        tail -n 40 "$WORK/ynictrl_make.log"; die "ynictrl 编译失败"; }

    [ -x "$YNICTRL_DIR/ynictrl" ] || die "没有生成 ynictrl"
    echo "  ynictrl 编译完成：$("$YNICTRL_DIR/ynictrl" --version 2>&1 | head -1)"
fi

# ---------------------------------------------------------------------------
# 5. 收集产物到 YuanNIC_User_Package/
# ---------------------------------------------------------------------------
log "5. 收集产物到 YuanNIC_User_Package/"

rm -rf "$OUT"
mkdir -p "$OUT/bin" "$OUT/lib" "$OUT/include" "$OUT/ko"
# libibverbs 启动时会 opendir(IBV_CONFIG_DIR)，目录不存在就打一条 Warning。
# 这里建一个空目录（路径已在上面的 cmake 参数里固化成 $OUT/etc），把警告消掉；
# provider 实际由 env.sh 的 RDMAV_DRIVERS 加载，不依赖这个目录里的配置。
mkdir -p "$OUT/etc/libibverbs.d"

# 库：保留符号链接（libibverbs.so.1 -> libibverbs.so.1.17.65.0 之类必须成对拷）
cp -a "$RC_BUILD/lib/." "$OUT/lib/"

# provider 插件（-rdmav65.so）确认在
ls "$OUT/lib"/libyuanrdma-rdmav*.so >/dev/null 2>&1 || {
    ls -la "$OUT/lib" | head -30
    die "没有找到 libyuanrdma-rdmav65.so，检查 provider 是否编入"
}
echo "provider  : $(ls "$OUT/lib"/libyuanrdma-rdmav*.so | xargs -n1 basename)"

# 头文件（编译依赖本栈的其他程序时用）
cp -a "$RC_BUILD/include/." "$OUT/include/" 2>/dev/null || true

# perftest 程序：放到 bin/
# 注意：autotools 把可执行文件生成在源码树根目录（work/perftest/），不是 src/
PT_BIN="$PT"
perftest_bins="ib_atomic_bw ib_atomic_lat ib_read_bw ib_read_lat ib_send_bw ib_send_lat
ib_write_bw ib_write_lat ib_write_bw_postlist ib_send_bw_postlist raw_ethernet_bw
raw_ethernet_lat raw_ethernet_burst_lat raw_ethernet_fs_rate
raw_ethernet_send_bw raw_ethernet_send_lat raw_ethernet_send_burst_lat"
copied=0
for b in $perftest_bins; do
    if [ -x "$PT_BIN/$b" ]; then
        cp "$PT_BIN/$b" "$OUT/bin/"
        copied=$((copied + 1))
    fi
done
[ "$copied" -gt 0 ] || die "没有拷到任何 perftest 程序"
echo "perftest  : 已拷贝 $copied 个程序"

# rdma-core 自带的工具：ibv_devinfo / ibv_devices 排障必用，pingpong 系列做最小联通验证。
# 它们编在 work/rdma-core/build/bin/，不拷的话 env.sh 里 PATH 指向 bin/ 也找不到。
RDT_BIN="$RC_BUILD/bin"
# rping / ucmatose / udaddy / rdma_server / rdma_client / cmtime 是 librdmacm 的验收工具：
# 软件 GSI（QP1）落地后用它们验 rdma_cm 建连（RC 走 rping/ucmatose，UD 走 udaddy）。
rdma_tools="ibv_devinfo ibv_devices ibv_asyncwatch ibv_rc_pingpong ibv_uc_pingpong
ibv_ud_pingpong ibv_srq_pingpong ibv_xsrq_pingpong
rping ucmatose udaddy rdma_server rdma_client cmtime"
tools_copied=0
for t in $rdma_tools; do
    if [ -x "$RDT_BIN/$t" ]; then
        cp "$RDT_BIN/$t" "$OUT/bin/"
        tools_copied=$((tools_copied + 1))
    fi
done
[ "$tools_copied" -gt 0 ] || die "没有拷到任何 rdma-core 工具（检查 $RDT_BIN）"
echo "rdma 工具 : 已拷贝 $tools_copied 个（ibv_devinfo / ibv_devices / *pingpong）"

# 内核模块
if [ -d "$KO_DIR" ] && [ -n "$(ls -A "$KO_DIR" 2>/dev/null)" ]; then
    cp "$KO_DIR"/*.ko "$OUT/ko/"
    echo "内核模块  : $(ls "$OUT/ko"/*.ko | xargs -n1 basename | tr '\n' ' ')"
fi

# ynictrl（固件更新工具）
if [ -x "$YNICTRL_DIR/ynictrl" ]; then
    cp "$YNICTRL_DIR/ynictrl" "$OUT/bin/"
    echo "ynictrl    : 已拷贝"
fi

# ---------------------------------------------------------------------------
# 6. 生成 env.sh
# ---------------------------------------------------------------------------
log "6. 生成 env.sh"

cat > "$OUT/env.sh" <<'ENVEOF'
# 本文件由 yuannic_user_build.sh 生成，请勿手工修改。
#
# source 之后，当前 shell 里的 RDMA 程序（ib_write_bw / ibv_devinfo / yuancli）
# 只用本包里的这一套库和 provider，不会碰到系统的 doca-host / MLNX_OFED。
#
#   source /path/to/YuanNIC_User_Package/env.sh
#   ib_write_bw -d yuanrdma0 -x 3 -F <对端IP>
#
# 原理：
#   1) LD_LIBRARY_PATH 指向 lib/，本包的 libibverbs(PABI 65) 先于系统(PABI 64)被加载；
#   2) RDMAV_DRIVERS 用绝对路径只加载我们的 libyuanrdma，屏蔽系统 /etc/libibverbs.d；
#   3) PATH 前置 bin/，避免误用 /usr/bin 下 DOCA 自带的 perftest。

YUANNIC_DIR=$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)

# 1. 库
export LD_LIBRARY_PATH="$YUANNIC_DIR/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"

# 2. 只加载本栈的 provider（绝对路径，dlopen 时会自动追加 -rdmav65.so）
export RDMAV_DRIVERS="$YUANNIC_DIR/lib/libyuanrdma"

# 若确实需要在同一进程里同时看到 ConnectX，再打开下面这行：
#   export RDMAV_DRIVERS="$YUANNIC_DIR/lib/libyuanrdma:$YUANNIC_DIR/lib/libmlx5"
# 注意：那是用 v66 的 mlx5 userspace 去配 DOCA 的 mlnx-ofed 内核，需自行验证。

# 3. 程序
export PATH="$YUANNIC_DIR/bin${PATH:+:$PATH}"

# 4. 供脚本引用
export YUANNIC_DIR
# 兼容旧名字，已有脚本里写的 $ROCE_NIC_DIR 仍然可用
export ROCE_NIC_DIR="$YUANNIC_DIR"

if [ -n "${BASH_VERSION:-}" ] && [ "${BASH_VERSINFO[0]:-0}" -ge 4 ]; then
    hash -r 2>/dev/null || true
fi
ENVEOF
chmod +x "$OUT/env.sh"

# ---------------------------------------------------------------------------
# 6b. 版本信息、README、用户手册
# ---------------------------------------------------------------------------
log "6b. 生成 VERSION / README.md / doc/"

mkdir -p "$OUT/doc"

# 镜像/构建信息：每份交付包都要能追溯到具体版本
cat > "$OUT/VERSION" <<VEREOF
YuanNIC_User_Package
version      : $PKG_VERSION
package      : $PKG_NAME.tgz
build_time   : $BUILD_TIME
build_host   : $(hostname)
kernel       : $(uname -r)
git_head     : $(git -C "$ROOT" rev-parse --short=8 HEAD 2>/dev/null || echo unknown)
git_dirty    : $(git -C "$ROOT" status --porcelain 2>/dev/null | wc -l) files modified
rdma-core    : 66.0 (PABI 65)
perftest     : $(grep -m1 'PACKAGE_VERSION' "$PT/configure.ac" 2>/dev/null | grep -oE '[0-9]+\.[0-9]+' | head -1 || echo 6.31)
provider     : libyuanrdma-rdmav65.so
VEREOF

cat > "$OUT/README.md" <<'READMEEOF'
# YuanNIC 用户包

版本 @PKG_VERSION@，构建日期 @BUILD_DATE@（详见 `VERSION`）。

YuanNIC 400G RoCEv2 网卡的**用户态 RDMA 软件包**。内含 perftest 测试工具、
rdma-core 运行库、内核模块和诊断工具，与系统自带的 RDMA 栈（doca-host /
MLNX_OFED）完全隔离，不需要卸载系统里任何东西。

## 目录

```
YuanNIC_User_Package/
├── README.md          本文件
├── VERSION            构建信息（版本、时间、内核、git commit）
├── env.sh             使用前必须 source
├── bin/               perftest 工具 + ibv_* + yuancli + ynictrl
├── lib/               rdma-core 运行库 + libyuanrdma provider
├── include/           头文件（自己编写基于本栈的程序时需要）
├── ko/                yuanrdma.ko / yuanmcdma.ko / yuannic.ko
├── etc/libibverbs.d/  provider 配置目录（libibverbs 启动时要读）
├── tools/             flash_and_init.sh（烧写 + 环境初始化）/ roce_perf_test.sh
├── firmware/          每块板最新一版固件（.jic / .rpd / .sof，见 firmware/README.md）
└── doc/
    ├── user-guide.md      完整使用手册
    └── perftest-guide.md  perftest 测试指南
```

## 三步跑起来

```bash
tar xzf @PKG_NAME@.tgz && cd YuanNIC_User_Package

# 1) 加载驱动（顺序不能反，yuanmcdma 必须第一个）
sudo insmod ko/yuanmcdma.ko     # 它做 pci_enable_device，打开 MemSpace+BusMaster
sudo insmod ko/yuannic.ko     # 可选，ynictrl 需要
sudo insmod ko/yuanrdma.ko
dmesg | tail -3              # 期望 "yuanrdma: engine version ..."

# 2) 配网口
sudo ip link set <netdev> up
sudo ip addr add 192.168.50.1/24 dev <netdev>

# 3) 加载环境并验证
source ./env.sh
ibv_devinfo -d yuanrdma0             # 期望 state: PORT_ACTIVE
ib_write_bw -d yuanrdma0 -x <gid> -F 192.168.50.2
```

详细说明见 `doc/user-guide.md`。

## 重要说明

- **`yuanmcdma.ko` 必须最先加载**，它负责打开 PCI Memory Space + Bus Master。
  没加载它时 RDMA 数据面一条事务都发不出去，但设备看起来是正常的。
- **卸载顺序**：`rmmod yuanrdma; rmmod yuannic; rmmod yuanmcdma`。
- 同一台机器上如果还有 ConnectX 网卡，测 ConnectX 时不要 source `env.sh`，
  用系统默认的那套；测 YuanNIC 时再 source。两者可同时运行，互不影响。
- `env.sh` 只影响当前 shell，不会修改系统任何文件。
READMEEOF

cat > "$OUT/doc/user-guide.md" <<'GUIDEEOF'
# YuanNIC 用户手册

## 1. 安装

解压即用，无需安装：

```bash
tar xzf @PKG_NAME@.tgz
cd YuanNIC_User_Package
```

包名里的 `@PKG_VERSION@` 是版本、`@BUILD_DATE@` 是构建日期；解压出来的目录名固定是
`YuanNIC_User_Package/`，版本以目录里的 `VERSION` 文件为准。

本包不向系统路径安装任何文件，所有库和程序都留在包内目录里，
通过 `env.sh` 临时改变当前 shell 的查找路径，因此**不会与系统 RDMA 栈冲突**。

## 2. 加载驱动

顺序不能变，`yuanmcdma.ko` 必须是第一个：

```bash
sudo insmod ko/yuanmcdma.ko    # 必须第一个
sudo insmod ko/yuannic.ko    # 可选
sudo insmod ko/yuanrdma.ko
```

`yuanmcdma.ko` 负责 `pci_enable_device()`，打开 PCI 配置空间的 Memory Space
和 Bus Master。BAS（引擎主动读写主机内存）依赖这两位，缺了它 RDMA 数据面
一条事务都发不出去。

加载成功的标志：

```bash
dmesg | grep yuanrdma
# yuanrdma: engine version 00010000 caps 0d060404, netdev eth0
```

若出现 `RoCE engine not present (ID deadbeef)`，说明 BAR2 地址映射不对，
先确认镜像是否匹配本板卡。

卸载（顺序相反）：

```bash
sudo rmmod yuanrdma; sudo rmmod yuannic; sudo rmmod yuanmcdma
```

## 3. 网口配置

```bash
ip -br link                          # 找到 YuanNIC 对应的网口，假设是 eth0
sudo ip link set eth0 up
sudo ip addr add 192.168.50.1/24 dev eth0
```

查看链路与设备：

```bash
ethtool eth0 | grep -E 'Speed|Link detected'   # 期望 400000Mb/s, yes
source ./env.sh
ibv_devinfo -d yuanrdma0                       # 期望 state: PORT_ACTIVE
```

## 4. 找到 GID 索引

RoCEv2 用 IPv4 GID。索引会随地址增减变化，每次改完 IP 都要重新确认：

```bash
show_gids        # 或：for i in $(seq 0 31); do
                 #         echo "$i $(cat /sys/class/infiniband/yuanrdma0/ports/1/gids/$i) \
                 #               $(cat /sys/class/infiniband/yuanrdma0/ports/1/gid_attrs/types/$i)"
                 #       done
```

找形如 `0000:0000:0000:0000:0000:ffff:c0a8:3201` 且类型为 `RoCE v2` 的那一行，
序号就是 `-x` 要用的值。

## 5. 诊断工具 yuancli

`yuancli` 直接 mmap PCI BAR2，**不需要驱动已加载**，驱动态异常时也能用。

```bash
./bin/yuancli                    # 列出所有命令
./bin/yuancli '?'                # 同上（加引号，避免被 shell 扩展）
./bin/yuancli register '?'       # 列出 register 下的命令

./bin/yuancli register probe_engine          # 引擎是否在线
./bin/yuancli register dump_registers        # 全部寄存器+计数器
./bin/yuancli register dump_debug_registers --diff 3   # 3 秒内哪些计数在涨
./bin/yuancli capabilities                   # 哪些功能有真硬件
```

命令名一律用完整单词，旧的短名（`reg` / `probe` / `dbg` 等）仍可用。

## 6. 固件更新（ynictrl）

```bash
sudo ./bin/ynictrl -c YN400GA7B027A -a 0 -q      # 查询当前版本
sudo ./bin/ynictrl -c YN400GA7B027A -a 0 -p firmware/<镜像>-R<版本>.rpd                     # 升级，序列号保持不变
sudo ./bin/ynictrl -c YN400GA7B027A -a 0 -p firmware/<镜像>-R<版本>.rpd -n MD400G260713002  # 升级并同时写序列号
sudo ./bin/ynictrl -c YN400GA7B027A -a 0 -n MD400G260713002                                # 只改序列号
```

固件更新需要 `yuannic.ko` 已加载。

- `-q` 的 `BANK` 是当前运行的镜像：`Active`（升级区）或 `Boot`（出厂回退镜像）；`TYPE` 是产品型号。
- `-p` 依次显示 `erase` / `program` / `verify` 三行，每行都到 `100%` 才算完成；随后打印写入的
  `firmware info` 与 `serial number`，最后提示 `update success`，重启后生效。任何一步失败都会报错并以非 0 退出，
  不会切换镜像。
- 序列号以 `MD` 开头、只含字母数字、最多 15 位；不带 `-n` 时保留 flash 里原有的序列号。

## 6.1 环境初始化脚本 flash_and_init.sh

`tools/flash_and_init.sh` 把「清理残留 → 重枚举 PCIe → 装驱动 → 配网 → 探 GID」串成一条命令。

**默认不烧写固件**：

```bash
./tools/flash_and_init.sh                 # 默认：不烧写，只重新拉一遍环境
./tools/flash_and_init.sh --flash <镜像>  # 要烧写必须显式加 --flash
```

烧写会覆盖易失镜像、也可能让卡需要冷断电才能恢复，所以不做默认动作。给了镜像名却没加
`--flash` 时脚本直接报错退出，不会静默跳过——避免「以为烧了、其实跑的还是老镜像」。

## 7. 常见问题

**Q: `ibv_devices` 是空的**
没有 source `env.sh`。本包用 `RDMAV_DRIVERS` 指定 provider，未设置时看不到设备。

**Q: `insmod yuanrdma.ko` 报 Unknown symbol**
缺 `ib_core` / `ib_uverbs`。本包不含它们（由内核提供）：
```bash
sudo modprobe ib_core && sudo modprobe ib_uverbs
```

**Q: 端口状态不是 ACTIVE**
先确认 `ethtool` 显示 `Link detected: yes`，再检查对端是否同速率。

**Q: 与系统 DOCA 的库冲突？**
不会。本包是 PABI 65（`lib*-rdmav65.so`），系统 DOCA 是 PABI 64，文件名不同，
靠 `LD_LIBRARY_PATH` 选择。
GUIDEEOF

cat > "$OUT/doc/perftest-guide.md" <<'PTEOF'
# perftest 测试指南

## 1. 两个角色

perftest 是一对程序：**服务端**先起，**客户端**再连。两端都要 source `env.sh`。

```bash
# 服务端（先起，通常在另一台机器）
source ./env.sh
ib_write_bw -d yuanrdma0 -x <gid> -F

# 客户端
source ./env.sh
ib_write_bw -d yuanrdma0 -x <gid> -F <服务端IP>
```

`-d` 设备名，`-x` 本端 GID 索引（两端可以不同），`-F` 使用当前速率。

**两个方向都要测**。同一张卡当发起方（客户端）和当响应方（服务端），瓶颈不是一回事：
发送侧受组包/每包固定开销限制，接收侧受数据搬移流水限制，只测一个方向拿到的是半张图。
建议的顺序是先「本卡作客户端」（看 TX 能力），再「本卡作服务端」（看 RX 能力）。

## 2. 六个标准用例

```bash
ib_write_bw     # 写带宽（RDMA WRITE）
ib_read_bw      # 读带宽（RDMA READ）
ib_send_bw      # 发送带宽（SEND，带接收端 CPU 参与）
ib_write_lat    # 写延迟
ib_read_lat     # 读延迟
ib_send_lat     # 发送延迟
```

带宽测试建议 `-s <尺寸> -D <秒数>`（单尺寸跑固定时长），例如 `-s 1048576 -D 30`；
延迟测试建议 `-s 2 -n 5000`。

> 三点经验（都是踩过的）：
> - **延迟用 2 字节**。延迟随消息长度线性增长（1M 时约 400 µs），那个数字只反映带宽，
>   跟"首包延迟"无关，也没法和历史数据比。
> - **别用 `-a` 做基线**。全尺寸扫描里小包档位很慢，一轮要十几分钟，而且只关心其中一两行。
> - **`-D` 是"Symmetric"参数**，两端必须给同样的值；服务端没跑起来时客户端会给
>   `Couldn't connect`，而 `#iterations 0` 往往是链路已断、一个包都没发出去，
>   两者都先去看 `tx_packets` 涨不涨，再读报错文字。

## 3. 结果解读

带宽输出每行是 `size iters peak(Mb/s) avg(Mb/s) msg_rate`，看**均值**。
小尺寸行反映每包开销，大尺寸行反映稳态带宽。

延迟输出是 `size iters t_min t_max t_typical t_avg t_stdev t_99 t_99.9`，看 `t_typ` 或 `t_avg`。

## 4. 常见问题

| 现象 | 原因 |
|---|---|
| `Couldn't connect to <ip>:<port>` | 服务端没起、IP 不通、端口被占 |
| `Unable to init the socket connection` | 服务端进程被 ssh 断开连带杀掉了 |
| 打完表头就退出、不报错 | GID 索引错（`-x`） |
| 带宽远低于线速 | 检查 PCIe 链路速率、MTU、是否单 QP |

## 5. 一键测试脚本（可选）

若两端都是本项目环境，可用 `roce_perf_test.sh` 自动跑六个用例并汇总。

**默认就跑两个方向**：先本卡作客户端、再本卡作服务端，顺序固定，方便不同固件版本之间横向比。

```bash
./tools/roce_perf_test.sh --label <固件版本>       # 两个方向 × 六个用例
./tools/roce_perf_test.sh --sides client           # 只测本卡作客户端（TX 方向）
./tools/roce_perf_test.sh --sides server           # 只测本卡作服务端（RX 方向）
./tools/roce_perf_test.sh --only write_bw,read_bw  # 只跑指定用例（仍是两个方向）
```

结果表按方向分两段打印，同一用例在两个方向的数字**不能直接对比**——它们量的是不同的通路。
PTEOF

# 上面的文档用带引号的 heredoc（正文里有反引号和 $，不能让 shell 展开），
# 版本与包名先写成 @占位符@，这里统一替换；漏换的占位符直接报错，不让它进交付包。
sed -i -e "s/@PKG_VERSION@/$PKG_VERSION/g" -e "s/@BUILD_DATE@/$BUILD_DATE/g" -e "s/@PKG_NAME@/$PKG_NAME/g" \
    "$OUT/README.md" "$OUT/doc/user-guide.md" "$OUT/doc/perftest-guide.md"
if grep -n '@[A-Z_]*@' "$OUT/README.md" "$OUT/doc/user-guide.md" "$OUT/doc/perftest-guide.md"; then
    die "文档里还有没替换的占位符（见上）"
fi


# ---------------------------------------------------------------------------
# 7. 自检
# ---------------------------------------------------------------------------
log "7. 自检"

echo "--- lib/ 中的关键库 ---"
ls -la "$OUT/lib"/libibverbs.so.1 "$OUT/lib"/librdmacm.so.1 "$OUT/lib"/libyuanrdma-rdmav*.so 2>/dev/null \
    | awk '{print "  " $NF, $NF ~ /->/ ? "" : ""}' || true

echo "--- env.sh 解析出的 RDMAV_DRIVERS ---"
( set +u; . "$OUT/env.sh" >/dev/null 2>&1; echo "  LD_LIBRARY_PATH=$LD_LIBRARY_PATH"; echo "  RDMAV_DRIVERS=$RDMAV_DRIVERS" )

echo "--- 库文件自洽性（ldd ibv_devinfo 不可用则跳过）---"
if [ -x "$OUT/bin/ib_write_bw" ]; then
    if LD_LIBRARY_PATH="$OUT/lib" ldd "$OUT/bin/ib_write_bw" 2>/dev/null | grep -q "not found"; then
        echo "  [警告] 有未解析的动态库："
        LD_LIBRARY_PATH="$OUT/lib" ldd "$OUT/bin/ib_write_bw" 2>/dev/null | grep "not found" | sed 's/^/    /'
    else
        echo "  ib_write_bw 动态库全部解析成功"
        echo "  链接的 libibverbs: $(LD_LIBRARY_PATH="$OUT/lib" ldd "$OUT/bin/ib_write_bw" 2>/dev/null | grep libibverbs | awk '{print $3}')"
    fi
fi

# ---------------------------------------------------------------------------
# 8. yuancli（配置与诊断工具）
# ---------------------------------------------------------------------------
log "8. 收集 yuancli"

# yuancli 是纯 Python（只用标准库），直接拷脚本即可，用户机器不需要装依赖。
# 它直接 mmap PCI BAR2，不依赖驱动，驱动态异常时也能用来诊断。
if [ -f "$ROOT/deploy/yuancli" ]; then
    cp "$ROOT/deploy/yuancli" "$OUT/bin/yuancli"
    chmod +x "$OUT/bin/yuancli"
    echo "  yuancli 已放入 bin/（纯 Python，无第三方依赖）"
else
    echo "  [警告] 找不到 $ROOT/deploy/yuancli，跳过"
fi

# 运维脚本放 tools/：这两个脚本会自己判断「在包内」还是「在开发目录」，
# 所以放进包里直接跑也行（见脚本头部的路径探测）。
mkdir -p "$OUT/tools"
for t in flash_and_init.sh roce_perf_test.sh; do
    if [ -f "$ROOT/build/user_tools/$t" ]; then
        cp "$ROOT/build/user_tools/$t" "$OUT/tools/$t"
        chmod +x "$OUT/tools/$t"
        echo "  $t 已放入 tools/"
    else
        echo "  [警告] 找不到 build/user_tools/$t，跳过"
    fi
done

# ---------------------------------------------------------------------------
# 9. 固件镜像：每块板各取最新一版，把 .jic / .rpd / .sof 带进交付包
# ---------------------------------------------------------------------------
# 交付包里带上烧写镜像，客户拿到包就能自己把卡烧到与本文档栈配套的 RTL 版本，
# 不用再回开发机取固件。镜像名形如
#   <型号>-<类型><版本>-B<build>-<YYYYMMDD>-<速率>-<githash>.<后缀>
#   类型 A = All（.jic，boot + active 双镜像，烧整片 flash）
#        R = Release / active（.rpd 供 ynictrl 在线升级，.sof 供 JTAG 临时加载）
#        B = Boot / Factory（.rpd）
# 「最新」按「日期，再按 Build 号」比：Build 号换版本序列时会重新起数，单看它会把
# 旧序列排在前面；也不用 mtime——拷贝/重新归档会刷新 mtime。
# 每块板（型号段 A / C …）各选各的，互不比较。
#   YUANNIC_FW_DIR     镜像目录，默认仓库根 firmware/
#   YUANNIC_FW_BOARDS  只带指定板卡，空格分隔的型号或末位字母（如 "C" 或 "YN400GA7B027C"）；默认全部
log "9. 收集固件镜像"

FW_SRC="${YUANNIC_FW_DIR:-$ROOT/firmware}"
FW_OUT="$OUT/firmware"
rm -rf "$FW_OUT"
mkdir -p "$FW_OUT"
fw_count=0
if [ -d "$FW_SRC" ]; then
    # 找出目录里出现过的型号（只认带版本号的正规镜像，固定名的 *_Release.sof 之类不算）
    models=$(ls "$FW_SRC" 2>/dev/null \
        | sed -n 's/^\(YN400GA7B027[A-Z]\)-[ABR][0-9][0-9.]*-B[0-9][0-9]*-[0-9]\{8\}-.*\.\(jic\|rpd\|sof\)$/\1/p' | sort -u)
    if [ -n "${YUANNIC_FW_BOARDS:-}" ]; then
        wanted=""
        for w in $YUANNIC_FW_BOARDS; do
            case "$w" in YN400GA7B027?) wanted="$wanted $w" ;; ?) wanted="$wanted YN400GA7B027$w" ;; *) die "YUANNIC_FW_BOARDS 里的 $w 不是型号也不是板卡字母" ;; esac
        done
        models=$(for m in $models; do case " $wanted " in *" $m "*) echo "$m" ;; esac; done)
    fi
    for model in $models; do
        # 版本键 = 类型字母之后的全部（<版本>-B<build>-<日期>-<速率>-<githash>），A/B/R 三类共用
        best_key=""; best_rank=""
        for f in "$FW_SRC/$model"-[ABR]*-B*-*-*-*.*; do
            [ -f "$f" ] || continue
            key=$(basename "$f" | sed -n "s/^$model-[ABR]\(.*\)\.\(jic\|rpd\|sof\)\$/\1/p")
            [ -n "$key" ] || continue
            date=$(printf '%s\n' "$key" | sed -n 's/^[0-9.]*-B[0-9]*-\([0-9]\{8\}\)-.*/\1/p')
            build=$(printf '%s\n' "$key" | sed -n 's/^[0-9.]*-B\([0-9]*\)-.*/\1/p')
            [ -n "$date" ] && [ -n "$build" ] || continue
            rank=$(printf '%s%08d' "$date" "$((10#$build))")
            if [ -z "$best_rank" ] || [ "$rank" \> "$best_rank" ]; then
                best_rank=$rank; best_key=$key
            fi
        done
        [ -n "$best_key" ] || continue
        echo "  $model  最新一版：$best_key"
        got=0
        for want in "A:jic" "R:rpd" "B:rpd" "R:sof"; do
            f="$FW_SRC/$model-${want%%:*}$best_key.${want##*:}"
            if [ -f "$f" ]; then
                cp "$f" "$FW_OUT/" || die "拷贝 $f 失败"
                echo "    $(basename "$f")  ($(du -h "$f" | cut -f1))"
                got=$((got + 1)); fw_count=$((fw_count + 1))
            fi
        done
        # .jic 只有 boot + active 一起编（或有预置 boot 镜像）时才会出；缺了只能在线升级 active，提示一下
        [ -f "$FW_SRC/$model-A$best_key.jic" ] || echo "    [警告] 这一版没有 .jic（没法离线烧整片 flash，只能用 .rpd 在线升级 active）"
        [ -f "$FW_SRC/$model-R$best_key.rpd" ] || echo "    [警告] 这一版没有 Release .rpd（ynictrl 在线升级用不了）"
    done
    if [ "$fw_count" -gt 0 ]; then
        ( cd "$FW_OUT" && sha256sum -- *.* > SHA256SUMS )
        cat > "$FW_OUT/README.md" <<'FWEOF'
# 固件镜像

每块板一组，文件名里的型号段区分板卡（`YN400GA7B027A` = NH400-A，`YN400GA7B027C` = NH400-C），
`B<build>-<日期>` 是版本，与 `ynictrl -q` 读回的 VERSION 对应。烧之前先核对 `SHA256SUMS`。

| 文件 | 用途 | 怎么烧 |
|---|---|---|
| `<型号>-A….jic` | 整片 flash 镜像（Factory boot + active） | JTAG：`tools/flash_and_init.sh --flash <文件名>`（掉电保持，配置器件按型号自动选） |
| `<型号>-R….rpd` | active 镜像 | 在线升级：`bin/ynictrl -c <型号> -a 0 -p <文件>`（`-a` 是网卡序号；只写 active 区，Factory 区不动） |
| `<型号>-B….rpd` | Factory boot 镜像 | 一般不需要单独烧（`ynictrl -b` 写备份区）；整片恢复用 `.jic` |
| `<型号>-R….sof` | active 镜像（易失） | JTAG 临时加载：`tools/flash_and_init.sh --sram <文件名>`，掉电恢复 flash 里的版本 |

型号必须与板卡一致，`flash_and_init.sh` 会按文件名里的型号段认板、拒绝烧错卡。
FWEOF
        echo "  共 $fw_count 个镜像，校验和写入 firmware/SHA256SUMS"
    else
        echo "  [警告] $FW_SRC 下没有符合条件的带版本号镜像，跳过（先跑板卡的 yuannic_build.sh）"
    fi
else
    echo "  [警告] 没有 $FW_SRC 目录（客户环境正常现象；可用 YUANNIC_FW_DIR 指定），跳过"
fi

# ---------------------------------------------------------------------------
# 10. 打包
# ---------------------------------------------------------------------------
# 包名带版本和日期：YuanNIC_User_Package-<版本>-<YYYYMMDD>.tgz。只覆盖同名包，
# 其他版本/日期的旧包不删（可能已经交付出去，要留底），需要时手工清理。
TGZ="$HERE/$PKG_NAME.tgz"
if [ "$BUILD_TGZ" = "1" ]; then
    log "10. 打包 $TGZ"
    rm -f "$TGZ"
    # 在产物目录的父目录里打，包内顶层目录名就是 YuanNIC_User_Package/。
    # 注意这里必须是 $(dirname "$OUT") 而不是 $HERE：2026-11-20 脚本移到 deploy/ 后，
    # 产物仍出在 build/user_tools/（消费方按同级目录找包），两者已不是同一个目录。
    # 写成 -C "$HERE" 会报 "tar: YuanNIC_User_Package: Cannot stat"。
    # 保留符号链接（lib/ 下的 .so.1 -> .so.1.19.66.0 必须成对），所以不用 -h。
    tar czf "$TGZ" -C "$(dirname "$OUT")" "$(basename "$OUT")" || die "打包失败"
    chmod 644 "$TGZ"
    echo "  大小：$(du -h "$TGZ" | cut -f1)"
    echo "  md5 ：$(md5sum "$TGZ" | cut -d' ' -f1)"
    others=$(cd "$HERE" && ls -1 YuanNIC_User_Package*.tgz 2>/dev/null | grep -vxF "$PKG_NAME.tgz" || true)
    [ -z "$others" ] || echo "  同目录还有其他包（未删除）：$(echo $others)"
else
    log "10. 跳过打包（--no-tgz）"
fi

log "完成"
echo "版本    ：$PKG_VERSION（构建日期 $BUILD_DATE）"
echo "产物目录：$OUT"
[ "$BUILD_TGZ" = "1" ] && echo "交付包  ：$TGZ"
echo ""
echo "使用："
echo "  tar xzf $(basename "$TGZ") && cd $(basename "$OUT")"
echo "  sudo insmod ko/yuanmcdma.ko && sudo insmod ko/yuannic.ko && sudo insmod ko/yuanrdma.ko"
echo "  source ./env.sh && ibv_devinfo -d yuanrdma0"
echo ""
echo "--- $OUT ---"
ls -la "$OUT"
echo "--- bin/ ---"
ls -la "$OUT/bin"
echo "--- doc/ ---"
ls -la "$OUT/doc"
echo "--- ko/ ---"
ls -la "$OUT/ko"
echo "--- firmware/ ---"
ls -la "$OUT/firmware"
