#!/bin/bash
# build.sh — 编译并安装 Verilator 5.032 到 /opt/verilator，并配好环境变量
#
# 本目录是 Verilator 上游源码树（只有 configure.ac + Makefile.in，没有 configure）。
# 本脚本按 autoconf → configure → make → make install → 环境变量的顺序跑完。
#
# 用法：
#   ./build.sh                  # 全流程（编译 + 安装 + 配环境 + 冒烟）
#   ./build.sh -j4              # 指定并行度（默认 nproc）
#   ./build.sh --prefix=/usr/local/verilator
#   ./build.sh build            # 只编译，不安装
#   ./build.sh install          # 只安装（要求已编译）
#   ./build.sh env              # 只配环境变量
#   ./build.sh check            # 只做版本与 --timing 冒烟
#   ./build.sh uninstall        # 删安装目录与 env 文件
#   ./build.sh clean | distclean
#   ./build.sh -h|--help
#
# 依赖（apt，本仓库 tool/apt_pkts.sh 已含）：
#   build-essential autoconf flex bison help2man perl libfl-dev
#   zlib1g-dev libgoogle-perftools-dev ccache
#
# 资源提示：单进程 g++ 峰值约 1 GB。16 核 -j16 约需 16 GB；若同时有 Quartus fit
#   （峰值 25~32 GB）在跑，用 -j4 更稳。
#
# 注意：install 会覆盖安装目录里已有的 Verilator。若有 cocotb 仿真（Vtop）正在跑，
#   脚本会停下来；确实要换用 --force。

set -uo pipefail

SRCDIR=$(cd "$(dirname "$(readlink -f "$0")")" && pwd)
PREFIX=${PREFIX:-/opt/verilator}
JOBS=$(nproc)
PROFILE_D=/etc/profile.d/verilator.sh
FORCE=0
STEP=all

usage() { sed -n '2,30p' "$0" | sed 's/^# \{0,1\}//'; }

while [ $# -gt 0 ]; do
    case "$1" in
        -j*)              JOBS=${1#-j} ;;
        -j)               shift; JOBS=${1:-$JOBS} ;;
        --prefix=*)       PREFIX=${1#--prefix=} ;;
        --force)          FORCE=1 ;;
        all|build|install|env|check|uninstall|clean|distclean) STEP=$1 ;;
        -h|--help)        usage; exit 0 ;;
        *) echo "未知参数: $1（用 -h 看用法）" >&2; exit 1 ;;
    esac
    shift
done

say()  { printf '\n\033[1m== %s\033[0m\n' "$*"; }
die()  { printf '\033[31m错误\033[0m %s\n' "$*" >&2; exit 1; }

require_root() {
    [ "$(id -u)" = "0" ] || die "此步骤需要 root：sudo $0 $STEP"
}

check_deps() {
    local missing=()
    for c in autoconf flex bison perl g++ make; do
        command -v "$c" >/dev/null 2>&1 || missing+=("$c")
    done
    if [ ${#missing[@]} -gt 0 ]; then
        die "缺少构建工具：${missing[*]}
   Ubuntu 上执行：sudo $(dirname "$SRCDIR")/../../../tool/apt_pkts.sh
   或：sudo apt-get install -y build-essential autoconf flex bison help2man perl libfl-dev zlib1g-dev libgoogle-perftools-dev ccache"
    fi
}

do_configure() {
    say "configure 检查"
    cd "$SRCDIR" || die "进不去 $SRCDIR"
    check_deps
    if [ ! -x ./configure ] || [ configure.ac -nt configure ]; then
        say "autoconf"
        autoconf || die "autoconf 失败"
    fi
    if [ ! -f ./Makefile ] || [ ! -f ./config.status ]; then
        say "configure --prefix=$PREFIX"
        ./configure --prefix="$PREFIX" --disable-doxygen-doc --enable-longtests \
            || die "configure 失败（日志见 $SRCDIR/config.log）"
    else
        echo "   已有 configure/Makefile，跳过（要重配先 ./build.sh distclean）"
    fi
}

do_build() {
    do_configure
    say "编译（-j$JOBS）"
    cd "$SRCDIR" || die "进不去 $SRCDIR"
    make -j"$JOBS" || die "编译失败"
}

guard_bin_in_use() {
    if pgrep -x Vtop >/dev/null 2>&1 || pgrep -f 'sim_build/Vtop' >/dev/null 2>&1; then
        if [ "$FORCE" = 1 ]; then
            echo "   警告：仍有仿真在跑，--force 继续"
        else
            die "有 cocotb 仿真（Vtop）正在运行，安装会换掉它正在用的 Verilator。
   等仿真结束，或加 --force 强制执行。"
        fi
    fi
}

do_install() {
    require_root
    [ -x "$SRCDIR/bin/verilator_bin" ] || die "还没编译（找不到 bin/verilator_bin），先跑 ./build.sh build"
    guard_bin_in_use
    say "安装到 $PREFIX"
    cd "$SRCDIR" || die "进不去 $SRCDIR"
    make install || die "make install 失败"
}

do_env() {
    require_root
    say "写 $PROFILE_D"
    mkdir -p "$(dirname "$PROFILE_D")"
    cat > "$PROFILE_D" <<EOF
# Verilator（由 code/github/verilator-5.032/build.sh 生成，勿手改）
export VERILATOR_ROOT=$PREFIX
case ":\$PATH:" in
  *":$PREFIX/bin:"*) ;;
  *) export PATH="$PREFIX/bin:\$PATH" ;;
esac
EOF
    chmod 0644 "$PROFILE_D"

    say "软链到 /usr/local/bin（非登录 shell 也能直接调用）"
    local f
    for f in "$PREFIX"/bin/*; do
        [ -x "$f" ] || continue
        ln -sf "$f" "/usr/local/bin/$(basename "$f")"
    done
    echo "   已生效于新 shell；当前 shell 立即生效： . $PROFILE_D"
}

do_check() {
    say "版本"
    local bin="$PREFIX/bin/verilator"
    [ -x "$bin" ] || bin="$(command -v verilator || true)"
    [ -x "$bin" ] || die "找不到 verilator（未安装？）"
    "$bin" --version

    say "仿真冒烟（--timing 必须可用，cocotb 台子依赖它）"
    local tmp rc
    tmp=$(mktemp -d)
    printf 'module t; initial begin #1 $finish; end endmodule\n' > "$tmp/t.v"
    if "$bin" --binary --timing -Wno-fatal --Mdir "$tmp/obj" -o tsim "$tmp/t.v" >"$tmp/build.log" 2>&1; then
        if "$tmp/obj/tsim" >/dev/null 2>&1; then
            printf '   \033[32mOK\033[0m  --binary --timing 可用\n'
            rc=0
        else
            printf '   \033[33mWARN\033[0m 生成成功但仿真运行失败\n'; rc=1
        fi
    else
        printf '   \033[31mFAIL\033[0m --binary --timing 不可用（日志 %s）\n' "$tmp/build.log"
        tail -5 "$tmp/build.log" | sed 's/^/        /'
        rc=1
    fi
    rm -rf "$tmp"
    printf '   VERILATOR_ROOT=%s\n   PATH 前缀=%s\n' "$PREFIX" "$PREFIX/bin"
    return $rc
}

do_uninstall() {
    require_root
    say "卸载 $PREFIX 与 $PROFILE_D"
    local f
    for f in "$PREFIX"/bin/*; do
        [ -e "$f" ] || continue
        rm -f "/usr/local/bin/$(basename "$f")"
    done
    rm -rf "$PREFIX"
    rm -f "$PROFILE_D"
    echo "   已删除。当前 shell 的 PATH 需重新登录或手动清理。"
}

do_clean()     { cd "$SRCDIR" && [ -f Makefile ] && make clean || true; }
do_distclean() { cd "$SRCDIR" && { [ -f Makefile ] && make distclean || true; }; rm -f configure aclocal.m4 config.log config.status; }

case "$STEP" in
    build)     do_build ;;
    install)   do_install ;;
    env)       do_env ;;
    check)     do_check ;;
    uninstall) do_uninstall ;;
    clean)     do_clean ;;
    distclean) do_distclean ;;
    all)
        do_build
        do_install
        do_env
        do_check
        ;;
esac
