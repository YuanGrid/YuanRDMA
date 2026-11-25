#!/bin/bash
# yuanrdma_install.sh — 按 INSTALL.md 一键安装 YuanRDMA 研发与运行所需的软件环境
#
# 用途
#   在一台干净的 Ubuntu 22.04 上，把「编译固件 + 编译驱动/provider + 仿真验证 + 上板测试」
#   四类工作需要的软件装齐，并在每一步打印**正在装什么、结果成功还是失败**。
#   详细说明见仓库根目录 INSTALL.md。
#
# 用法
#   ./yuanrdma_install.sh                  # 装全部（apt + Python + Verilator + DPDK 依赖）
#   ./yuanrdma_install.sh --dry-run        # 只打印将要做什么，不改系统
#   ./yuanrdma_install.sh --check          # 只体检：报告哪些已装、哪些缺，不安装
#   ./yuanrdma_install.sh --only apt       # 只跑某一组，可重复
#                                          # 组名：apt python verilator quartus cuda
#   ./yuanrdma_install.sh --skip-cuda      # 跳过 CUDA（不需要 NCCL 的机器）
#   ./yuanrdma_install.sh --skip-verilator # 跳过 Verilator 源码编译（只做 RTL 不做仿真）
#   ./yuanrdma_install.sh -h|--help
#
# 退出码
#   0  全部成功        1  有步骤失败（会列出失败项）        2  用法/环境错误
#
# 设计原则
#   1. **缺少的软件直接用 apt 装**（用户明确要求），不手工下载源码包。
#   2. 每一步都幂等：已装好的会跳过并说明「已存在」，重复执行安全。
#   3. 非 root 时 apt 步骤用 sudo；没有 sudo 就报错退出，不静默降权。
#   4. **不烧写、不改 BMC、不动厂商固件**（安全规则）。
#      Quartus / CUDA 这类大件只做检测与提示，需要人工确认的会明确打出来。
#   5. 失败不吞：每一步记录状态，末尾汇总；有失败则退出码 1。

set -uo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$HERE/.." && pwd)

# ---------------------------------------------------------------- 输出

if [ -t 1 ]; then
    C_RED=$'\033[31m'; C_GRN=$'\033[32m'; C_YEL=$'\033[33m'
    C_BLU=$'\033[34m'; C_BLD=$'\033[1m'; C_RST=$'\033[0m'
else
    C_RED=; C_GRN=; C_YEL=; C_BLU=; C_BLD=; C_RST=
fi

STEP_NO=0
FAILED=()
SKIPPED=()
OK=()

say()  { printf '\n%s==> %s%s\n' "$C_BLD$C_BLU" "$*" "$C_RST"; }
info() { printf '    %s\n' "$*"; }
ok()   { printf '    %s[OK]%s   %s\n' "$C_GRN" "$C_RST" "$*"; OK+=("$*"); }
skip() { printf '    %s[SKIP]%s %s\n' "$C_YEL" "$C_RST" "$*"; SKIPPED+=("$*"); }
warn() { printf '    %s[WARN]%s %s\n' "$C_YEL" "$C_RST" "$*"; }
fail() { printf '    %s[FAIL]%s %s\n' "$C_RED" "$C_RST" "$*"; FAILED+=("$*"); }

# 一步一件事：先打印「正在做什么」，再执行，再打印结果。
# 用法：run_step "描述" <命令...>
run_step() {
    local desc="$1"; shift
    STEP_NO=$((STEP_NO + 1))
    printf '    %s(%02d)%s 正在%s ...\n' "$C_BLD" "$STEP_NO" "$C_RST" "$desc"
    if "$@" >/tmp/yuanrdma_install.last 2>&1; then
        ok "$desc"
        return 0
    else
        fail "$desc"
        sed 's/^/           | /' /tmp/yuanrdma_install.last | tail -12
        return 1
    fi
}

# ---------------------------------------------------------------- 参数

DO_INSTALL=1
DO_CHECK=0
ONLY=()
SKIP_CUDA=0
SKIP_VERILATOR=0

usage() { sed -n '2,40p' "$0" | sed 's/^# \{0,1\}//'; }

while [ $# -gt 0 ]; do
    case "$1" in
        --dry-run)       DO_INSTALL=0 ;;
        --check)         DO_INSTALL=0; DO_CHECK=1 ;;
        --only)          ONLY+=("$2"); shift ;;
        --skip-cuda)     SKIP_CUDA=1 ;;
        --skip-verilator) SKIP_VERILATOR=1 ;;
        -h|--help)       usage; exit 0 ;;
        *) echo "未知参数: $1（用 -h 看用法）" >&2; exit 2 ;;
    esac
    shift
done

want() {
    [ ${#ONLY[@]} -eq 0 ] && return 0
    local g
    for g in "${ONLY[@]}"; do [ "$g" = "$1" ] && return 0; done
    return 1
}

# ---------------------------------------------------------------- 前置检查

say "环境自检"

if [ "$(id -u)" -ne 0 ] && ! command -v sudo >/dev/null 2>&1; then
    fail "非 root 且没有 sudo，无法安装软件包。请用 root 运行或先装 sudo。"
    exit 2
fi
SUDO=""
[ "$(id -u)" -ne 0 ] && SUDO="sudo"

OS_ID=$(lsb_release -is 2>/dev/null || echo unknown)
OS_VER=$(lsb_release -rs 2>/dev/null || echo unknown)
info "系统      ：$OS_ID $OS_VER（$(uname -r)）"
info "仓库根目录：$ROOT"
info "架构      ：$(uname -m)"
if [ "$OS_ID" != "Ubuntu" ]; then
    warn "本项目只在 Ubuntu 22.04 上验证过；当前是 $OS_ID，包名可能不同。"
fi
if [ "$OS_VER" != "22.04" ]; then
    warn "目标版本是 22.04，当前是 $OS_VER。cocotb / Verilator 的版本组合按 22.04 定。"
fi

# ---------------------------------------------------------------- 1. apt 基础依赖

if want apt; then
    say "1/5 系统软件包（apt）"

    # 分组与 README「软件环境」表逐项对应。缺什么装什么，用一行装完再由 apt 汇报。
    PKGS_BUILD=(build-essential gcc-12 g++-12 make pkg-config git rsync bc unzip ccache)
    PKGS_PYTHON=(python3 python3-pip python3-dev python3-venv python3-lxml python3-pyelftools)
    PKGS_RDMA=(libibverbs-dev librdmacm-dev libnl-3-dev libnl-route-3-dev cmake)
    PKGS_DPDK=(meson ninja-build libnuma-dev libelf-dev)
    PKGS_KERNEL=(linux-headers-generic)
    PKGS_DEBUG=(ethtool pciutils ipmitool tcpdump strace lsof psmisc procps xxd jq)
    PKGS_VERILATOR_BUILD=(autoconf flex bison help2man perl libfl-dev zlib1g-dev
                          libgoogle-perftools-dev)
    ALL_PKGS=("${PKGS_BUILD[@]}" "${PKGS_PYTHON[@]}" "${PKGS_RDMA[@]}" "${PKGS_DPDK[@]}"
              "${PKGS_KERNEL[@]}" "${PKGS_DEBUG[@]}" "${PKGS_VERILATOR_BUILD[@]}")

    # 先算出缺哪些，只装缺的，并逐个报出来
    MISSING=()
    for p in "${ALL_PKGS[@]}"; do
        dpkg -s "$p" >/dev/null 2>&1 || MISSING+=("$p")
    done

    if [ ${#MISSING[@]} -eq 0 ]; then
        ok "全部 ${#ALL_PKGS[@]} 个系统包已安装"
    else
        info "已装 ${#ALL_PKGS[@]} 个中缺 ${#MISSING[@]} 个："
        printf '           %s\n' "${MISSING[*]}"
        if [ "$DO_INSTALL" = 1 ]; then
            run_step "apt-get update" $SUDO apt-get update
            run_step "安装 ${#MISSING[@]} 个系统包" \
                $SUDO env DEBIAN_FRONTEND=noninteractive \
                apt-get install -y --no-install-recommends "${MISSING[@]}"
            # 复核
            STILL=()
            for p in "${MISSING[@]}"; do dpkg -s "$p" >/dev/null 2>&1 || STILL+=("$p"); done
            if [ ${#STILL[@]} -eq 0 ]; then
                ok "全部系统包安装完成"
            else
                fail "以下包安装后仍缺失：${STILL[*]}"
            fi
        else
            skip "（未安装，只列出）"
        fi
    fi

    # 内核头文件必须与运行内核同版本，否则 code/kernel 编不过
    RUNHDR="/usr/src/linux-headers-$(uname -r)"
    if [ -d "$RUNHDR" ]; then
        ok "当前内核头文件存在：$RUNHDR"
    else
        if [ "$DO_INSTALL" = 1 ]; then
            run_step "安装与运行内核匹配的头文件 linux-headers-$(uname -r)" \
                $SUDO env DEBIAN_FRONTEND=noninteractive \
                apt-get install -y "linux-headers-$(uname -r)"
        else
            warn "缺 $RUNHDR（code/kernel 编译会失败）"
        fi
    fi
fi

# ---------------------------------------------------------------- 2. Python 依赖

if want python; then
    say "2/5 Python 仿真依赖（cocotb 等）"
    # 直接内联版本号，不依赖外部 requirements 文件（少一个文件少一处不同步的机会）。
    # 台子按 cocotb 1.9 API 编写，2.x 移除了 cocotb.result 等模块，不能随手升大版本。
    PY_PKGS=("cocotb==1.9.2" "cocotb-bus==0.3.0" "cocotbext-axi==0.1.28" "scapy>=2.4,<3")
    if [ "$DO_INSTALL" = 1 ]; then
        run_step "pip3 install cocotb/cocotb-bus/cocotbext-axi/scapy" \
            $SUDO python3 -m pip install "${PY_PKGS[@]}"
    else
        skip "python 包安装（--check/--dry-run 模式不装）"
    fi

    # 复核三个最关键的版本（台子按 cocotb 1.9 API 写的）
    # 注意导入名与 pip 包名不同：cocotb-bus → cocotb_bus，
    # cocotbext-axi → cocotbext.axi（子模块，没有 __version__，用 importlib.metadata 取版本）
    chk_py() {
        local pipname="$1" importname="$2" want="$3"
        local got
        got=$(python3 -c "
import importlib.metadata as md
try:
    import ${importname}
except ImportError:
    raise SystemExit(1)
print(md.version('${pipname}'))
" 2>/dev/null)
        if [ "$want" = "__any__" ]; then
            if [ -n "$got" ]; then ok "$pipname $got"; else warn "$pipname 未安装"; fi
        elif [ "$got" = "$want" ]; then
            ok "$pipname $got"
        elif [ -n "$got" ]; then
            warn "$pipname 已装但是 $got（期望 $want，台子按 1.9 API 写的）"
        else
            warn "$pipname 未安装"
        fi
    }
    chk_py cocotb        cocotb        1.9.2
    chk_py cocotb-bus    cocotb_bus    0.3.0
    chk_py cocotbext-axi cocotbext.axi 0.1.28
    chk_py scapy         scapy          "__any__"
fi

# ---------------------------------------------------------------- 3. Verilator

if want verilator; then
    say "3/5 Verilator（仿真器，需 ≥5.0）"
    # apt 的 4.038 不支持 --timing，全部台子都用了这个开关，所以只能源码编。
    if command -v verilator >/dev/null 2>&1; then
        vv=$(verilator --version 2>/dev/null | awk '{print $2}')
        info "已装 verilator $vv（$(command -v verilator)）"
        # 5.0 以下不能用
        major=${vv%%.*}
        if [ "${major:-0}" -ge 5 ] 2>/dev/null; then
            ok "Verilator 版本满足要求（≥5.0）"
        else
            fail "Verilator $vv 太旧：apt 版不支持 --timing，必须 ≥5.0（推荐 5.032）"
        fi
    else
        warn "未安装 verilator"
        if [ "$SKIP_VERILATOR" = 1 ]; then
            skip "按 --skip-verilator 跳过"
        elif [ "$DO_INSTALL" = 1 ]; then
            info "apt 的 4.038 不支持 --timing，需从源码编译 5.032 到 /opt/verilator。"
            info "脚本将执行（约 5~10 分钟）："
            info "  git clone -b v5.032 https://github.com/verilator/verilator"
            info "  autoconf && ./configure --prefix=/opt/verilator && make -j\$(nproc) && make install"
            SRC=/tmp/verilator-5.032-build
            rm -rf "$SRC"
            if run_step "下载 Verilator v5.032 源码" \
                    git clone --depth 1 -b v5.032 https://github.com/verilator/verilator "$SRC"; then
                if run_step "编译 Verilator（autoconf/configure）" \
                        bash -c "cd '$SRC' && autoconf && ./configure --prefix=/opt/verilator"; then
                    if run_step "编译 Verilator（make，并行 $(nproc)）" \
                            bash -c "cd '$SRC' && make -j\$(nproc)"; then
                        run_step "安装 Verilator 到 /opt/verilator" \
                            $SUDO bash -c "cd '$SRC' && make install"
                    fi
                fi
            fi
            if [ -x /opt/verilator/bin/verilator ]; then
                /opt/verilator/bin/verilator --version >/dev/null 2>&1 && \
                    ok "/opt/verilator/bin/verilator 可用" || fail "/opt/verilator 安装后无法执行"
            fi
        else
            skip "verilator 安装（--check/--dry-run 模式不装）"
        fi
    fi

    # PATH 提示：装在 /opt 下不会自动进 PATH
    if [ -x /opt/verilator/bin/verilator ] && ! command -v verilator >/dev/null 2>&1; then
        warn "PATH 里没有 verilator。加入：export PATH=/opt/verilator/bin:\$PATH"
    fi
fi

# ---------------------------------------------------------------- 4. Quartus

if want quartus; then
    say "4/5 Quartus Prime Pro（仅编译固件需要）"
    QROOT=${QUARTUS_ROOT:-/home/quartus/program}
    if [ -x "$QROOT/quartus/bin/quartus_sh" ]; then
        qv=$("$QROOT/quartus/bin/quartus_sh" --version 2>/dev/null | head -1)
        ok "已安装：$qv"
        info "位置  ：$QROOT"
    elif command -v quartus_sh >/dev/null 2>&1; then
        ok "quartus_sh 在 PATH 中：$(command -v quartus_sh)"
    else
        warn "未检测到 Quartus（QUARTUS_ROOT=$QROOT）"
        info "Quartus Prime Pro 26.1.1 需手动安装（体积大、需 license），"
        info "本脚本不代为下载安装。安装后设置 QUARTUS_ROOT 指向安装根目录。"
        info "只做驱动/仿真/测试的话不需要 Quartus。"
        SKIPPED+=("Quartus 需手动安装")
    fi
    # license 同样需要人工提供
    LC=${LM_LICENSE_FILE:-/home/quartus/software/ALTERA_LICENSE/license_26.1.dat}
    if [ -f "$LC" ]; then
        ok "license 文件存在：$LC"
    else
        warn "未找到 license（$LC）。编固件时会报 Unknown device part AGIB..."
    fi
fi

# ---------------------------------------------------------------- 5. CUDA

if want cuda; then
    say "5/5 CUDA（仅 NCCL / GPUDirect 场景需要）"
    if [ "$SKIP_CUDA" = 1 ]; then
        skip "按 --skip-cuda 跳过"
    elif command -v nvcc >/dev/null 2>&1; then
        ok "已安装：$(nvcc --version | grep -o 'release [0-9.]*')"
    elif [ -x /usr/local/cuda-12.4/bin/nvcc ]; then
        ok "已安装于 /usr/local/cuda-12.4"
        if [ -f /etc/profile.d/cuda.sh ]; then
            ok "环境变量已持久化：/etc/profile.d/cuda.sh（新 shell 生效，当前 shell 需 source）"
        else
            warn "PATH 里还没有 nvcc，建议写入 /etc/profile.d/cuda.sh 或 export CUDA_HOME=..."
        fi
    else
        warn "未安装 CUDA。只有 NCCL / GPUDirect RDMA 需要它。"
        info "本项目目标版本 CUDA 12.4（T4 = sm_75，NVCC_GENCODE=compute_75,sm_75）"
        info "安装命令（需人工执行，因为要加 NVIDIA 官方源）："
        info "  wget https://developer.download.nvidia.com/compute/cuda/repos/ubuntu2204/x86_64/cuda-keyring_1.1-1_all.deb"
        info "  sudo dpkg -i cuda-keyring_1.1-1_all.deb && sudo apt-get update"
        info "  sudo apt-get install -y cuda-toolkit-12-4"
        info "注意装 cuda-toolkit-12-4，不要装 cuda 或 cuda-12-4（会替换现有显卡驱动）。"
        info "详见 INSTALL.md 第 6 节。"
        SKIPPED+=("CUDA 需人工安装")
    fi

    # 显卡与驱动只做报告
    if command -v nvidia-smi >/dev/null 2>&1; then
        info "GPU  ：$(nvidia-smi --query-gpu=name,driver_version,compute_cap --format=csv,noheader 2>/dev/null | head -1)"
    fi
fi

# ---------------------------------------------------------------- 汇总

say "安装结果汇总"
printf '    %s成功 %d 项%s\n' "$C_GRN" "${#OK[@]}" "$C_RST"
if [ ${#SKIPPED[@]} -gt 0 ]; then
    printf '    %s跳过 %d 项%s\n' "$C_YEL" "${#SKIPPED[@]}" "$C_RST"
    printf '           - %s\n' "${SKIPPED[@]}"
fi
if [ ${#FAILED[@]} -gt 0 ]; then
    printf '    %s失败 %d 项%s\n' "$C_RED" "${#FAILED[@]}" "$C_RST"
    printf '           - %s\n' "${FAILED[@]}"
    printf '\n%s安装未全部完成，请按上面 [FAIL] 项处理。详见 INSTALL.md。%s\n' "$C_RED" "$C_RST"
    exit 1
fi

if [ "$DO_CHECK" = 1 ]; then
    printf '\n%s自检完成：已装项均在位，未发现阻塞项。%s\n' "$C_GRN" "$C_RST"
elif [ "$DO_INSTALL" = 1 ]; then
    printf '\n%s依赖安装完成。后续步骤见 INSTALL.md：%s\n' "$C_GRN" "$C_RST"
else
    printf '\n%s演练结束（--dry-run，未改动系统）。%s\n' "$C_YEL" "$C_RST"
fi
printf '  1. 编译前门禁 ：test/sim/rtl_prebuild_gate.sh\n'
printf '  2. 编译用户态 ：cd deploy && ./yuannic_user_build.sh（产物仍出到 build/user_tools/YuanNIC_User_Package）\n'
printf '  3. 编译固件   ：cd build/YuanNIC-NH400-C && ./yuannic_build.sh <VER> <BUILD> 1X400G all\n'
printf '  4. 上板       ：./flash_and_init.sh\n'
exit 0
