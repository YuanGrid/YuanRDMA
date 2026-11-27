#!/bin/bash
# FPGA RoCE 网卡一版一测：加载驱动 + perftest 全套对比。
#
# 每个 RTL 优化版本（JTAG 烧 .sof 之后）跑一遍本脚本，把结果记到
# 结果日志（由 ROCE_PERF_LOG 指定），形成可横向对比的性能序列。
#
# 两个方向各跑一遍（见记忆 perftest-benchmark-convention）：
#   fpga-client  FPGA 当客户端、10.122 的 CX7 当服务端   ← 历史基线方向
#   fpga-server  FPGA 当服务端、10.122 的 CX7 当客户端   ← 2026-10-28 起加入
# 两个方向必须都测：TX 通路和 RX 通路的瓶颈不是一回事（TX 受每包组包开销、
# RX 受 roce_resp 串行搬运限制），只测一个方向看不出另一半。
# 默认先跑 fpga-client 再跑 fpga-server，与历史数字可比。
#
# 地址：
#   FPGA   yuanrdma0，192.168.50.1（GID 索引现场探测，见下）
#   CX7    mlx5_0，   192.168.50.2（GID 3）
# 数据面走 192.168.50.x 直连，10.122 只是管理地址。
#
# 用法：
#   ./roce_perf_test.sh                       # 两个方向都测（驱动已加载）
#   ./roce_perf_test.sh --build               # 先重编用户态栈再测
#   ./roce_perf_test.sh --load                # 先 insmod 驱动再测
#   ./roce_perf_test.sh --build --load
#   ./roce_perf_test.sh --label B6369-opt     # 结果标注版本号
#   ./roce_perf_test.sh --only write_bw,read_bw
#   ./roce_perf_test.sh --sides client        # 只测 FPGA 作客户端（回退到旧行为）
#   ./roce_perf_test.sh --sides server        # 只测 FPGA 作服务端
#   ./roce_perf_test.sh -s 1K,512K,1M -D 30   # 三个长度，各跑 30 秒
#   ./roce_perf_test.sh --keep-going          # 单个用例失败也继续跑完（默认立即停）
#   ./roce_perf_test.sh --mtu 2048            # 两侧 perftest 加 -m 2048（先 tool/roce_mtu.sh set 4082）
#   ./roce_perf_test.sh --mtu 4096            # 两侧 perftest 加 -m 4096（先 tool/roce_mtu.sh set 4200，需新 yuanmcdma.ko）
#   ./roce_perf_test.sh --ud                  # 只跑 UD：ud_send_bw + ud_pingpong
#   ./roce_perf_test.sh --only ud_send_bw --sides client
#   ./roce_perf_test.sh --ud --ud-size 512    # 指定 UD 报文长度（> active_mtu 会被截断并告警）
#
# UD 用例（ud_send_bw / ud_pingpong）与 RC 的差别：
#   - **报文长度不能超过 active_mtu**，perftest 直接拒绝 "Max message size in
#     UD cannot be greater than MTU"。所以 UD 的「1M」是 1 个 MTU，不是 1 MiB；
#     默认取当前 active_mtu（本卡 1024）。要更大就先 tool/roce_mtu.sh set 4200。
#   - UD 与 RC 同时支持（2026-11-21 起驱动不再有 enable_ud 开关），不需要额外加载参数。
#   - ud_send_bw 走 perftest（GID 选项 -x），ud_pingpong 走 rdma-core（选项 -g），
#     写错报 "Invalid Command line"。
#   - 基线口径：尺寸 = active_mtu、时长 30 s（同 DURATION）、机器空闲。
#
# 失败即停（默认）：
#   任何用例失败或带宽读数为 0，立刻停止后面的用例，并自动跑一遍 yuancli
#   诊断（probe_engine / 计数器 / 卡死快照 / 全量调试寄存器），输出落到
#   work/diag/diag-<用例>-<尺寸>-<时间>.txt。原因没查清之前继续跑剩下几个用例
#   只是把同一个故障重演五遍，还浪费三分钟。
#
# 环境变量：
#   SIDES       要测的方向，默认 "client server"（先 FPGA 作客户端，再作服务端）
#   PEER_HOST   对端管理地址，默认 192.168.10.122
#   PEER_PASS   对端密码，**必须显式给出**（不设默认值，避免明文口令入库）
#   PEER_IP     对端数据面地址，默认 192.168.50.2
#   NIC_IP      本机数据面地址，默认 192.168.50.1
#   GID_LOCAL   本机 GID 索引，默认现场探测 192.168.50.1 的 v2 那条
#   GID_REMOTE  对端 GID 索引，默认 3（192.168.50.2 v2）
#   BDF         卡在 PCIe 上的地址，yuancli 用，默认 0000:6f:00.0
#   DIAG_DIR    诊断输出目录，默认 build/user_tools/work/diag（开发期）或 <脚本目录>/work/diag（包内）

set -uo pipefail
# 判断模块是否已加载：直接读 /proc/modules，不要写成 `lsmod | grep -q`。
# pipefail 下 grep -q 命中即退出，lsmod 后续写入吃 SIGPIPE、管道返回 141，
# 本项目三个驱动排在 lsmod 最前面，实测 20 次约 17 次被误判为「未加载」
# （2026-11-12：第 2 步因此跳过 rmmod，第 4 步 PCI remove 卡在 unregister_netdev）。
mod_loaded() { grep -q "^$1 " /proc/modules; }

HERE=$(cd "$(dirname "$0")" && pwd)

# 本脚本有三个合法的放置位置：
#   1) deploy/                      —— 开发期（2026-11-27 从 build/user_tools/ 移来），
#                                      包与运行期产物（.gid_local、work/）仍在 build/user_tools/
#   2) YuanNIC_User_Package/        —— 早期位置，包就是当前目录
#   3) YuanNIC_User_Package/tools/  —— 当前交付布局，包在上一级
# 用 env.sh + bin/ 是否存在来判定，比猜路径可靠。
UT=""
if [ -f "$HERE/env.sh" ] && [ -d "$HERE/bin" ]; then
    NIC="$HERE"                                   # 位置 2
    WORK_BASE="$HERE/work"
elif [ -f "$HERE/../env.sh" ] && [ -d "$HERE/../bin" ]; then
    NIC=$(cd "$HERE/.." && pwd)                   # 位置 3
    WORK_BASE="$HERE/work"
else
    # 位置 1：包由 yuannic_user_build.sh 出到 build/user_tools/YuanNIC_User_Package，
    # 构建时用 YUANNIC_PKG_OUT 改了位置的，这里跟着同一个变量走。
    UT="$(cd "$HERE/.." && pwd)/build/user_tools"
    NIC="${YUANNIC_PKG_OUT:-$UT/YuanNIC_User_Package}"
    WORK_BASE="$UT/work"
fi

# 结果日志：默认不写；需要留档时用 ROCE_PERF_LOG=<路径> 指定。
LOG=${ROCE_PERF_LOG:-}
[ -n "$LOG" ] && [ -f "$LOG" ] || LOG=""

PEER_HOST=${PEER_HOST:-192.168.10.122}
PEER_PASS=${PEER_PASS:-}
PEER_IP=${PEER_IP:-192.168.50.2}
NIC_IP=${NIC_IP:-192.168.50.1}
GID_REMOTE=${GID_REMOTE:-3}
# 要测的方向：client = FPGA 客户端 / CX7 服务端，server = FPGA 服务端 / CX7 客户端。
# 默认两个都测，顺序固定（先 client），这样历史数字和新增数字在一份输出里并列。
SIDES=${SIDES:-"client server"}

# 本机 GID 索引会随 IP 增减和驱动重载漂移（实测 192.168.50.1 在 2/3/5 之间变过）。
# 缓存文件由 flash_and_init.sh 写，可能在这几处，按顺序找：
#   $NIC/.gid_local   交付包内的位置（客户机器上）
#   $UT/.gid_local    开发期（脚本在 deploy/，flash_and_init.sh 写在 build/user_tools/）
#   $HERE/.gid_local  脚本就在包根目录时
#   $HERE/../.gid_local  早期布局
# 都没有才退回现场探测（见下面的 probe_gid），最后才是默认值。
GID_CACHE=""
for c in "$NIC/.gid_local" "${UT:+$UT/.gid_local}" "$HERE/.gid_local" "$HERE/../.gid_local"; do
    [ -f "$c" ] && { GID_CACHE=$c; break; }
done
if [ -z "${GID_LOCAL:-}" ] && [ -n "$GID_CACHE" ]; then
    GID_LOCAL=$(cat "$GID_CACHE" 2>/dev/null)
fi

# 没缓存就现场探测：找 192.168.50.x 对应的 **RoCE v2** GID。
# 坑：光按地址匹配会先命中 IB/RoCE v1 那一条（同一 IP 有两个 GID），
# 用 v1 索引去建 QP 会在 RTR 阶段失败——"Failed to modify QP to RTR"。
# 必须比对 gid_attrs/types/<i> 里的 v2。
probe_gid()
{
    local hex i g t addr
    addr=$(echo "${NIC_ADDR:-192.168.50.1}" | cut -d/ -f1)
    hex=$(python3 - "$addr" <<'PYEOF'
import sys, ipaddress
try:
    ip = ipaddress.IPv4Address(sys.argv[1])
except Exception:
    sys.exit(0)
print("%02x%02x:%02x%02x" % tuple(ip.packed))
PYEOF
)
    [ -n "$hex" ] || return 1
    for i in $(seq 0 31); do
        g=$(cat "/sys/class/infiniband/yuanrdma0/ports/1/gids/$i" 2>/dev/null) || break
        case "$g" in
            *"ffff:${hex}"|*"${hex}") ;;
            *) continue ;;
        esac
        t=$(cat "/sys/class/infiniband/yuanrdma0/ports/1/gid_attrs/types/$i" 2>/dev/null)
        case "$t" in *v2*) echo "$i"; return 0 ;; esac
    done
    return 1
}

if [ -z "${GID_LOCAL:-}" ]; then
    GID_LOCAL=$(probe_gid 2>/dev/null) || GID_LOCAL=""
fi
GID_LOCAL=${GID_LOCAL:-3}
LABEL=${LABEL:-""}
DO_BUILD=0
DO_LOAD=0
ONLY=""
KEEP_GOING=0      # 默认失败即停，见文件头
NO_DIAG=0
BDF=${BDF:-0000:6f:00.0}
DIAG_DIR=${DIAG_DIR:-$WORK_BASE/diag}
# FPGA 当服务端时服务端日志落这里（原来服务端在 CX7，日志在对端 /tmp）。
SRV_LOG_DIR=${SRV_LOG_DIR:-$WORK_BASE/srv}
mkdir -p "$SRV_LOG_DIR" 2>/dev/null || SRV_LOG_DIR=/tmp
UD_LOG_DIR=${UD_LOG_DIR:-$WORK_BASE/ud}
mkdir -p "$UD_LOG_DIR" 2>/dev/null || UD_LOG_DIR=/tmp
MSG_SIZE=${MSG_SIZE:-65536}
ITERS=${ITERS:-5000}
# 消息长度列表（逗号分隔，可带 K/M/G 后缀）与每个长度跑多少秒。
# 带宽默认 1M / 30 秒，六个用例三分钟左右跑完，适合做版本间的对比基线。
# 参数名与 perftest 一致（-s 尺寸、-D 时长），需要更多维度时：-s 1K,512K,1M -D 30
#
# 延迟用例默认用 2 字节，不用 1M：延迟随消息长度线性增长（1M 时约 400 µs），
# 那个数字只反映带宽，跟"首包延迟"没关系，也没法和历史记录比。
# 显式给 -s 时一律照用（想测大包的延迟就 -s 1K）。
SIZE_BW=${SIZES:-1M}
SIZE_LAT=${LAT_SIZE:-2}
SIZE_EXPLICIT=0
[ -n "${SIZES:-}" ] && SIZE_EXPLICIT=1
# 每侧 QP 数（perftest -q）。0 = 不传 -q，用 perftest 默认（1）。
# 验证多 lane 时必须两侧给同一个值：perftest 的 QP 数是双端约定的，只改一侧会建链失败。
#   QPS=4 ./roce_perf_test.sh --only write_bw   # 或 --qp 4
QPS=${QPS:-0}
# 显式 path MTU（perftest -m，两侧同值）。0 = 不传，用两端 active_mtu 协商。
# -m 不能超过两端 active_mtu，先用 tool/roce_mtu.sh 把两端 netdev MTU 放开：
#   2048 → set 4082；4096 → set 4200（iboe_get_mtu 扣 96 字节，门槛 4192；yuanmcdma max_mtu 7168）。
IB_MTU=${IB_MTU:-0}
DURATION=${DURATION:-30}
# 单个（用例,长度）组合的客户端超时。正常 = 跑满 DURATION 再加握手/收尾余量。
CLI_TIMEOUT=${CLI_TIMEOUT:-$(( DURATION + 120 ))}

# ---- UD（Unreliable Datagram）----
# UD 用例与 RC 的差别不只是 connection type：
#   1) UD 与 RC 同时支持，驱动不再有 enable_ud 开关（2026-11-21 起）；
#   2) **报文长度不能超过 active_mtu**，perftest 会直接拒绝：
#      "Max message size in UD cannot be greater than MTU"。所以 UD 的 "1M" 是
#      **1 个 MTU 大小**，不是 1 MiB——本卡 active_mtu=1024 时就是 1024 B。
#      想测更大就把两端 MTU 放到 4096（tool/roce_mtu.sh set 4200，见 §8.1）。
#   3) 互通性用 ibv_ud_pingpong（rdma-core 示例），它的 GID 选项是 **-g**，
#      perftest 是 **-x**——写错报 "Invalid Command line"（2026-11-18 踩过）。
# 基线口径（2026-11-19）：MQ size = active_mtu、时长 30 s，同 DURATION。
UD_SIZE=${UD_SIZE:-0}      # 0 = 取当前 active_mtu
UD_ITERS=${UD_ITERS:-200}  # ibv_ud_pingpong 每个尺寸的次数
ALL_TESTS="write_bw read_bw send_bw write_lat read_lat send_lat"
UD_TESTS="ud_send_bw ud_pingpong"

# UD 尺寸解析：0/空/auto → active_mtu；超过 active_mtu 就截到 active_mtu 并告警。
# 不静默改数：perftest 自己也会截并打印，这里提前说清楚，免得记录里写错尺寸。
active_mtu()
{
    local v
    v=$(ibv_devinfo -d yuanrdma0 -v 2>/dev/null | awk '/active_mtu:/{print $2; exit}')
    echo "${v:-1024}"
}
ud_size()
{
    local want="${UD_SIZE:-0}"; [ "$want" = "0" ] && want=""
    local mtu; mtu=$(active_mtu)
    [ -z "$want" ] && { echo "$mtu"; return 0; }
    if [ "$want" -gt "$mtu" ] 2>/dev/null; then
        warn "UD_SIZE=$want 超过 active_mtu=$mtu，perftest 会拒绝；按 $mtu 跑"
        echo "$mtu"; return 0
    fi
    echo "$want"
}

usage()
{
    # 打印文件头的注释块，新增/删改说明不必再维护行号
    awk 'NR>1 && /^#/ {sub(/^# ?/, ""); print; next} NR>1 {exit}' "$0"
    exit "${1:-0}"
}

while [ $# -gt 0 ]; do
    case "$1" in
        --build)  DO_BUILD=1 ;;
        --load)   DO_LOAD=1 ;;
        --label)  LABEL="$2"; shift ;;
        --only)   ONLY="$2"; shift ;;
        -s|--size)     SIZES="$2"; SIZE_BW="$2"; SIZE_EXPLICIT=1; shift ;;
        -D|--duration) DURATION="$2"; CLI_TIMEOUT=$(( DURATION + 120 )); shift ;;
        --msg)    MSG_SIZE="$2"; shift ;;
        --sides)  SIDES="$2"; shift ;;
        --qp|--qps) QPS="$2"; shift ;;
        --mtu)    IB_MTU="$2"; shift ;;
        --keep-going) KEEP_GOING=1 ;;
        --no-diag)    NO_DIAG=1 ;;
        --ud)         ONLY="ud_send_bw ud_pingpong" ;;
        --ud-size)    UD_SIZE="$2"; shift ;;
        --ud-iters)   UD_ITERS="$2"; shift ;;
        -h|--help) usage 0 ;;
        *) echo "未知参数: $1"; usage 1 ;;
    esac
    shift
done

[ -n "$ONLY" ] || ONLY="$ALL_TESTS"

say()  { printf '\033[1m%s\033[0m\n' "$*"; }
warn() { printf '\033[33m%s\033[0m\n' "$*" >&2; }
die()  { printf '\033[31m%s\033[0m\n' "$*" >&2; exit 1; }

# ---------------------------------------------------------------- 编译
if [ "$DO_BUILD" = 1 ]; then
    # --build 只在开发期有意义：包内没有源码和构建脚本
    [ -x "$HERE/yuannic_user_build.sh" ] \
        || die "--build 需要在仓库的 deploy/ 下运行（包内只有二进制，无法重编）"
    say "== 重编 RDMA 用户态栈（yuannic_user_build.sh --no-ko）=="
    "$HERE/yuannic_user_build.sh" --no-ko || die "yuannic_user_build.sh 失败"
fi

# ---------------------------------------------------------------- 加载驱动
if [ "$DO_LOAD" = 1 ]; then
    say "== 加载驱动（ib_core -> ib_uverbs -> yuanmcdma -> yuannic -> yuanrdma）=="
    # 先卸（忽略未加载的报错），再按序装
    for m in yuanrdma yuannic yuanmcdma; do
        mod_loaded "$m" && rmmod "$m" 2>/dev/null
    done
    # yuanrdma 依赖内核自带的 ib_core / ib_uverbs，冷启动后它们不会自动加载，
    # 而 insmod 不处理依赖。缺了会报一串 "Unknown symbol ib_umem_get/rdma_user_mmap_*"。
    for m in ib_core ib_uverbs; do
        mod_loaded "$m" || modprobe "$m" || die "modprobe $m 失败"
    done
    insmod "$NIC/ko/yuanmcdma.ko"  || die "insmod yuanmcdma.ko 失败"
    [ -f "$NIC/ko/yuannic.ko" ] && { insmod "$NIC/ko/yuannic.ko" || warn "insmod yuannic.ko 失败（非致命）"; }
    insmod "$NIC/ko/yuanrdma.ko" || die "insmod yuanrdma.ko 失败"
    sleep 2
    dmesg | tail -5 | grep -i yuanrdma || true
fi

# ---------------------------------------------------------------- 环境
[ -f "$NIC/env.sh" ] || die "找不到 $NIC/env.sh，先跑 ./yuannic_user_build.sh"
# shellcheck disable=SC1090
source "$NIC/env.sh"

[ -d /sys/class/infiniband/yuanrdma0 ] || die "yuanrdma0 不存在，驱动未加载或 BAR2 不对"

STATE=$(cat /sys/class/infiniband/yuanrdma0/ports/1/state 2>/dev/null || echo unknown)
[ "${STATE%%:*}" = "4" ] || die "yuanrdma0 端口不是 ACTIVE（$STATE），先确认链路与 ip link"

NIC_ADDR=$(ip -o -4 addr show | awk -v ip="192.168.50.1" '$4 ~ ip {print $2; exit}')
[ -n "$NIC_ADDR" ] || warn "本机没找到 192.168.50.1，确认 yuanrdma 网口的 IP 配置"

say "== 环境 =="
printf '  FPGA   : yuanrdma0  %s  GID %s   port %s\n' "$NIC_IP" "$GID_LOCAL" "$STATE"
printf '  CX7    : %s  mlx5_0  %s  GID %s\n' "$PEER_HOST" "$PEER_IP" "$GID_REMOTE"
printf '  方向   : %s  （client = FPGA 客户端，server = FPGA 服务端）\n' "$SIDES"
[ -n "$LABEL" ] && printf '  label  : %s\n' "$LABEL"

[ -n "$PEER_PASS" ] || die "PEER_PASS 未设置：对端 root 密码必须显式给出，不再有内置默认值。
    用法：PEER_PASS=<密码> ./roce_perf_test.sh ...
    可通过前置环境变量或本地未入库的 env 文件提供。"

SSH="sshpass -p $PEER_PASS ssh -o StrictHostKeyChecking=no -o ConnectTimeout=8 root@$PEER_HOST"
timeout 20 $SSH 'ls /sys/class/infiniband/mlx5_0 >/dev/null 2>&1' 2>/dev/null \
    || die "连不上对端 $PEER_HOST 或对端没有 mlx5_0"

# ---------------------------------------------------------------- 测试
# 把 "1K" / "512K" / "1M" / "1048576" 换成 perftest 认的字节数。
# perftest 的 -s 只接受字节数，不认 K/M 后缀，所以这里做一次换算。
size_to_bytes()
{
    local v="$1" num suf
    num=${v%[KkMmGg]}
    suf=${v#"$num"}
    # 纯数字才接受：perftest 的 -s 只吃字节数，非数字会直接被它拒绝，
    # 这里提前挡掉并给出可读的错误（否则报错信息会埋在 perftest 输出里）
    case "$num" in
        ""|*[!0-9]*) echo ""; return 1 ;;
    esac
    [ "$num" -gt 0 ] 2>/dev/null || { echo ""; return 1; }
    case "$suf" in
        K|k) echo $(( num * 1024 )) ;;
        M|m) echo $(( num * 1024 * 1024 )) ;;
        G|g) echo $(( num * 1024 * 1024 * 1024 )) ;;
        "")  echo "$num" ;;
        *)   echo ""; return 1 ;;
    esac
}

# 跑一个（用例, 尺寸）组合。参数名沿用 perftest：-s 尺寸、-D 时长（带宽）
# 或 -n 次数（延迟）。
run_pair()
{
    local test="$1"   # 例：write_bw
    local size="$2"   # 例：1M
    local proto="${test%_*}"   # write / read / send
    local kind="${test#*_}"    # bw / lat
    local tool="ib_${proto}_${kind}"
    local port=$(( 18515 + RANDOM % 200 ))
    local side="$3"   # client = FPGA 客户端 / CX7 服务端；server = 反之
    local bytes logf rc

    bytes=$(size_to_bytes "$size")
    [ -n "$bytes" ] || { printf '  %-12s %-8s FAIL  无法识别的尺寸 %s\n' "$test" "$size" "$size"; return 1; }

    logf=$(mktemp)
    local fpga_args cx7_args
    # -x 是**本端** GID 索引（perftest 用它 ibv_query_gid 查自己的 GID，对端 GID 由
    # TCP 控制通道交换），所以每侧永远填自己那张表里的索引，与谁当服务端无关：
    #   FPGA 侧 = GID_LOCAL（192.168.50.1 的 v2 那条，现场探测）
    #   CX7  侧 = GID_REMOTE（192.168.50.2 的 v2，固定 3）
    fpga_args="-d yuanrdma0 -x $GID_LOCAL -p $port -s $bytes"
    cx7_args="-d mlx5_0 -x $GID_REMOTE -p $port -s $bytes"
    # 多 QP：两侧必须同值（perftest 的 QP 数是双端约定）
    if [ "$QPS" -gt 0 ] 2>/dev/null; then
        fpga_args="$fpga_args -q $QPS"
        cx7_args="$cx7_args -q $QPS"
    fi
    if [ "$IB_MTU" -gt 0 ] 2>/dev/null; then
        fpga_args="$fpga_args -m $IB_MTU"
        cx7_args="$cx7_args -m $IB_MTU"
    fi

    if [ "$kind" = "bw" ]; then
        # 只用 -s 指定单一尺寸 + -D 控制时长，不再用 -a 全尺寸扫描
        fpga_args="$fpga_args -D $DURATION --report_gbits -F"
        cx7_args="$cx7_args -D $DURATION --report_gbits -F"
    else
        fpga_args="$fpga_args -n $ITERS -F --report_gbits"
        cx7_args="$cx7_args -n $ITERS -F --report_gbits"
    fi

    if [ "$side" = "client" ]; then
        # 服务端在 CX7：setsid 脱离 ssh 会话，否则 ssh 退出就被连带杀掉。
        # 末尾必须留 sleep——ssh 收到 EOF 就关通道，setsid 还来不及脱离，
        # 服务端会被连带杀掉（表现为客户端 "Unable to init the socket connection"）。
        timeout 25 $SSH "pkill -x $tool 2>/dev/null; sleep 0.5; \
            setsid nohup /usr/bin/$tool $cx7_args > /tmp/srv_${test}_${size}.log 2>&1 < /dev/null & \
            disown; sleep 2; pgrep -x $tool >/dev/null && echo SRV_OK || { echo SRV_FAIL; cat /tmp/srv_${test}_${size}.log; }" \
            2>&1 | grep -E "SRV_OK|SRV_FAIL" || warn "服务端启动异常"
        sleep 1

        timeout "$CLI_TIMEOUT" "$NIC/bin/$tool" $fpga_args "$PEER_IP" > "$logf" 2>&1
        rc=$?
    else
        # 服务端在 FPGA：本机后台起。同样用 setsid 脱离当前会话，否则被 Ctrl-C 或
        # 父 shell 退出连带杀掉，客户端会报 "Unable to init the socket connection"。
        local srvlog
        srvlog="$SRV_LOG_DIR/srv_${test}_${size}.log"
        pkill -x "$tool" 2>/dev/null
        sleep 0.5
        setsid nohup "$NIC/bin/$tool" $fpga_args > "$srvlog" 2>&1 < /dev/null &
        disown 2>/dev/null
        sleep 2
        pgrep -x "$tool" >/dev/null 2>&1 \
            || warn "本机服务端没起来，日志见 $srvlog"

        timeout "$CLI_TIMEOUT" $SSH "/usr/bin/$tool $cx7_args $NIC_IP 2>&1 | tee /tmp/cli_${test}_${size}.log" > "$logf" 2>&1
        rc=$?
        pkill -x "$tool" 2>/dev/null
        timeout 15 $SSH "pkill -x $tool 2>/dev/null" >/dev/null 2>&1
    fi

    if [ $rc -ne 0 ] || ! grep -q "bytes\|Average" "$logf"; then
        # 不要只打最后一行：perftest 失败时最后一行常是 "-----" 分隔线，
        # 真正的原因（Couldn't connect / Unable to find device）在前面几行。
        # 超时(124)单独说清楚，否则会被误当成"连不上"。
        local why
        if [ "$rc" = "124" ]; then
            why="客户端 ${CLI_TIMEOUT}s 超时（可用 CLI_TIMEOUT=... 放宽）"
        else
            why=$(grep -vE '^[-=]*$' "$logf" 2>/dev/null | head -3 | tr '\n' ' ')
            [ -n "$why" ] || why="无输出"
        fi
        printf '  %-12s %-8s FAIL (rc=%s)  %s\n' "$test" "$size" "$rc" "$why"
        LAST_WHY="rc=$rc $why"
        rm -f "$logf"
        timeout 15 $SSH "pkill -x $tool 2>/dev/null" >/dev/null 2>&1
        return 1
    fi

    if [ "$kind" = "bw" ]; then
        # --report_gbits 下每行是：size iters 峰值Gb/s 均值Gb/s Mpps
        # 单尺寸模式下只有一行数据，取最后一个数据行的均值 Gb/s，
        # 同时换算出 MiB/s 便于和旧记录对比
        local line iters gbs
        line=$(awk '/^ *[0-9]+ / {last=$0} END{print last}' "$logf")
        iters=$(echo "$line" | awk '{print $2}')
        gbs=$(echo "$line" | awk '{print $(NF-1)}')
        # 带宽为 0 是"跑完了但一个包都没过去"，比连不上更难发现：
        # perftest 照常打印结果行、退出码 0，只有数字是 0.00。
        # 判据：均值带宽不是正数，或者迭代次数为 0。
        if ! awk -v v="$gbs" 'BEGIN{exit !(v+0 > 0)}' || [ "${iters:-0}" = "0" ]; then
            LAST_WHY="带宽为 0（iters=${iters:-?}，峰值 $(echo "$line" | awk '{print $3}') Gb/s）"
            printf '  %-12s %-8s FAIL  %s\n' "$test" "$size" "$LAST_WHY"
            rm -f "$logf"
            timeout 15 $SSH "pkill -x $tool 2>/dev/null" >/dev/null 2>&1
            return 1
        fi
        printf '  %-12s %-8s %s\n' "$test" "$size" "$(echo "$line" | awk '{
            gbs=$(NF-1); mibs=gbs*1000000000/8/1048576;
            printf "%9.2f Gb/s  %9.0f MiB/s", gbs, mibs}')"
    else
        local line iters tp99
        line=$(awk '/^ *[0-9]+ +[0-9]+/ {last=$0} END{print last}' "$logf")
        # perftest 延迟结果行 9 列：
        #   #bytes #iter t_min t_max t_typical t_avg t_stdev 99% 99.9%
        # 历史上打印的「延迟」一直是 $(NF-1) = **99% 分位**（变量曾误名 tavg）。
        # 2026-11-08 起照旧把 p99 放在第一列保持与 roce-optimization-log 历史数可比，
        # 后面补 typical（中位）/ avg / min——跨版本比 RTL 延迟看 typical，p99 受主机抖动影响大。
        # 延迟用例没有带宽数字，用"迭代次数为 0"当流量判据：一次都没完成说明帧没过去。
        iters=$(echo "$line" | awk '{print $2}')
        tp99=$(echo "$line" | awk '{print $(NF-1)}')
        if [ "${iters:-0}" = "0" ] || ! awk -v v="$tp99" 'BEGIN{exit !(v+0 > 0)}'; then
            LAST_WHY="无流量（iters=${iters:-?}，p99=${tp99:-?}）"
            printf '  %-12s %-8s FAIL  %s\n' "$test" "$size" "$LAST_WHY"
            rm -f "$logf"
            timeout 15 $SSH "pkill -x $tool 2>/dev/null" >/dev/null 2>&1
            return 1
        fi
        printf '  %-12s %-8s %s\n' "$test" "$size" "$(echo "$line" | awk '{
            if (NF >= 9) printf "%9.2f us  (p99; typical %.2f / avg %.2f / min %.2f)", $(NF-1), $5, $6, $3;
            else         printf "%9.2f us", $(NF-1)}')"
    fi

    rm -f "$logf"
    timeout 15 $SSH "pkill -x $tool 2>/dev/null" >/dev/null 2>&1
    return 0
}

# 用例失败后自动取证。手工排查时人也是这套顺序：先看引擎在不在，
# 再看计数器涨没涨（区分"发不出去"和"发出去但对端不认"），
# 然后读卡死快照（哪一级流水卡住），最后全量调试寄存器兜底。
# 输出同时打屏和落盘——屏幕看结论，落盘留给事后对照。
run_diag()
{
    local test="$1" size="$2" side="${3:-client}"
    [ "$NO_DIAG" = 1 ] && return 0
    [ -x "$NIC/bin/yuancli" ] || { warn "包内没有 yuancli，跳过自动诊断"; return 1; }

    local ts out
    ts=$(date '+%Y%m%d-%H%M%S')
    mkdir -p "$DIAG_DIR" 2>/dev/null || { warn "建不了 $DIAG_DIR，诊断只打屏"; DIAG_DIR=/dev/null; }
    out="$DIAG_DIR/diag-${test}-${size}-${side}-${ts}.txt"

    say "== 自动诊断：${test}@${size}（FPGA 作 ${side}）失败，读卡状态 =="
    {
        printf '### %s   %s@%s   side=fpga-%s   label=%s   %s\n' \
            "$(date '+%F %T')" "$test" "$size" "$side" "${LABEL:-none}" "$(uname -r)"
        printf '### 失败原因：%s\n\n' "${LAST_WHY:-未记录}"
        # 服务端日志能区分"对端没收到"和"对端收到了但回不了 ACK"。
        # 服务端在 CX7 时日志在对端 /tmp；服务端在 FPGA 时日志在本机 work/srv。
        if [ "$side" = "client" ]; then
            printf '### 对端服务端日志 /tmp/srv_%s_%s.log\n' "$test" "$size"
            timeout 15 $SSH "tail -30 /tmp/srv_${test}_${size}.log 2>/dev/null || echo '(无)'" 2>&1
        else
            printf '### 本机服务端日志 %s\n' "$SRV_LOG_DIR/srv_${test}_${size}.log"
            tail -30 "$SRV_LOG_DIR/srv_${test}_${size}.log" 2>/dev/null || echo '(无)'
            printf '\n### 对端客户端输出\n'
            timeout 15 $SSH "cat /tmp/cli_${test}_${size}.log 2>/dev/null || echo '(无)'" 2>&1
        fi
        printf '\n### probe_engine\n'
        timeout 20 "$NIC/bin/yuancli" register probe_engine -d "$BDF" 2>&1
        printf '\n### 计数器（对比失败前的快照看哪个不涨）\n'
        timeout 20 "$NIC/bin/yuancli" register read_counters -d "$BDF" 2>&1
        printf '\n### 卡死快照\n'
        timeout 30 "$NIC/bin/yuancli" register dump_stall_snapshot -d "$BDF" 2>&1
    } | tee "$out" | sed 's/^/    /'

    # 全量调试寄存器单独落盘：几十行，读的人未必需要，但事后对比很有用
    timeout 30 "$NIC/bin/yuancli" register dump_debug_registers -d "$BDF" \
        > "$DIAG_DIR/dbgall-${test}-${size}-${ts}.txt" 2>&1

    printf '\n'
    say "诊断结果：$out"
    printf '    全量调试寄存器：%s\n' "$DIAG_DIR/dbgall-${test}-${size}-${ts}.txt"
    printf '    对照排查：见使用手册的故障排查章节\n'
}

# ---------------------------------------------------------------- UD
# 运行一个 UD 组合。两个用例各有自己的工具与 GID 选项：
#   ud_send_bw   perftest ib_send_bw -c UD，GID 选项 -x，时长 -D
#   ud_pingpong  rdma-core ibv_ud_pingpong，GID 选项 -g，次数 -n
# 两个方向都支持：client = FPGA 客户端；server = FPGA 服务端。
run_ud()
{
    local test="$1" side="$2"
    local size; size=$(ud_size)
    local port=$(( 21000 + RANDOM % 2000 ))
    local tool extra gidopt logf rc
    case "$test" in
        ud_send_bw)  tool=ib_send_bw;        extra="-c UD -D $DURATION --report_gbits"; gidopt="-x" ;;
        ud_pingpong) tool=ibv_ud_pingpong;   extra="-n $UD_ITERS";                     gidopt="-g" ;;
        *) printf '  %-12s FAIL  未知 UD 用例 %s\n' "$test" "$test"; return 1 ;;
    esac
    logf="$UD_LOG_DIR/$test-$side-$size-$(date +%H%M%S).log"

    if [ "$side" = "client" ]; then
        # 服务端在 CX7
        timeout 25 $SSH "pkill -x $tool 2>/dev/null; sleep 0.5; \
            setsid nohup /usr/bin/$tool -d mlx5_0 $gidopt $GID_REMOTE -p $port -s $size $extra \
            > /tmp/ud_srv.log 2>&1 < /dev/null & disown; sleep 2; \
            pgrep -x $tool >/dev/null && echo SRV_OK || { echo SRV_FAIL; tail -5 /tmp/ud_srv.log; }" \
            2>&1 | grep -q SRV_OK || { printf '  %-12s %-8s FAIL  对端起不来\n' "$test" "$size"; return 1; }
        sleep 1
        timeout $((DURATION + 120)) "$NIC/bin/$tool" -d yuanrdma0 $gidopt "$GID_LOCAL" \
            -p "$port" -s "$size" $extra "$PEER_IP" > "$logf" 2>&1
        rc=$?
        pkill -x "$tool" 2>/dev/null
        timeout 15 $SSH "pkill -x $tool 2>/dev/null" >/dev/null 2>&1
    else
        # 服务端在 FPGA：先本机起，再让对端以客户端身份连 192.168.50.1。
        # ibv_ud_pingpong / ib_send_bw 的服务端不带主机参数、客户端必须带。
        pkill -x "$tool" 2>/dev/null
        sleep 0.5
        setsid nohup "$NIC/bin/$tool" -d yuanrdma0 $gidopt "$GID_LOCAL" -p "$port" -s "$size" \
            $extra > "$logf.srv" 2>&1 < /dev/null &
        disown 2>/dev/null
        sleep 3
        pgrep -x "$tool" >/dev/null 2>&1 || { printf '  %-12s %-8s FAIL  本机服务端起不来\n' "$test" "$size"; return 1; }
        timeout $((DURATION + 120)) $SSH "/usr/bin/$tool -d mlx5_0 $gidopt $GID_REMOTE -p $port \
            -s $size $extra $NIC_IP 2>&1" > "$logf.cli" 2>&1
        rc=$?
        wait 2>/dev/null
        pkill -x "$tool" 2>/dev/null
    fi

    # 结果判读：ud_send_bw 取客户端侧数据行；ud_pingpong 看 "iters in"。
    local line out
    if [ "$test" = "ud_send_bw" ]; then
        [ "$side" = "server" ] && out="$logf.cli" || out="$logf"
        line=$(awk '/^ *[0-9]+ /{last=$0} END{print last}' "$out" 2>/dev/null)
        local gbs mpps
        gbs=$(echo "$line" | awk '{print $4}')
        mpps=$(echo "$line" | awk '{print $5}')
        if [ $rc -ne 0 ] || [ -z "$line" ] || ! awk -v v="${gbs:-0}" 'BEGIN{exit !(v+0>0)}'; then
            why=$(grep -vE '^[-=]*$' "$out" 2>/dev/null | head -3 | tr '\n' ' ')
            printf '  %-12s %-8s FAIL  rc=%s %s\n' "$test" "$size" "$rc" "${why:-无输出}"
            LAST_WHY="rc=$rc ${why:-无输出}"
            return 1
        fi
        printf '  %-12s %-8s %8.2f Gbps  %6.2f Mpps  (UD, %s)\n' \
            "$test" "$size" "$gbs" "$mpps" "FPGA 作 $side"
    else
        [ "$side" = "server" ] && out="$logf.cli" || out="$logf"
        line=$(grep -o '[0-9.]* usec/iter' "$out" 2>/dev/null | tail -1)
        if [ $rc -ne 0 ] || [ -z "$line" ]; then
            why=$(grep -vE '^[-=]*$' "$out" 2>/dev/null | head -3 | tr '\n' ' ')
            printf '  %-12s %-8s FAIL  rc=%s %s\n' "$test" "$size" "$rc" "${why:-无输出}"
            LAST_WHY="rc=$rc ${why:-无输出}"
            return 1
        fi
        printf '  %-12s %-8s %s  (UD, FPGA 作 %s)\n' "$test" "$size" "$line" "$side"
    fi
    return 0
}

say "== perftest =="
RESULT_TS=$(date '+%Y-%m-%d %H:%M')
FAILED=""

# 用例列表既接受逗号也接受空格分隔（--only write_bw,read_bw 或 "write_bw read_bw"）。
# 坑：ALL_TESTS 是用空格分隔的，早先这里只按逗号切，整串被当成一个用例名，
# 于是拼出 "bin/ib_write_bw read_bw send_bw ..." 这种不存在的路径，
# timeout 执行失败返回 127，六个用例全报 FAIL 且看不出原因。
IFS=', ' read -ra TESTS <<< "$ONLY"

# 每个用例自带尺寸列表：给了 -s 就全都用它；没给则带宽走 1M、延迟走 2 字节。
sizes_of()
{
    case "${1##*_}" in
        lat) [ "$SIZE_EXPLICIT" = 1 ] && echo "$SIZE_BW" || echo "$SIZE_LAT" ;;
        *)   echo "$SIZE_BW" ;;
    esac
}

# perftest 的 -q 只在带宽用例上有效，延迟用例直接拒绝：
#   "Multiple QPs only available on bw tests"
# 这不是硬件问题，走不到诊断那一步，所以事先把 *_lat 剔掉并说明，
# 否则多 QP 的每一轮都要白跑三次失败 + 三份自动诊断（各十几秒的打屏）。
if [ "$QPS" -gt 1 ] 2>/dev/null; then
    FILTERED=()
    for t in "${TESTS[@]}"; do
        case "$t" in
            ""|*_lat) ;;
            *) FILTERED+=("$t") ;;
        esac
    done
    DROPPED_LAT=$(printf '%s\n' "${TESTS[@]}" | grep -c '_lat$')
    if [ "${DROPPED_LAT:-0}" -gt 0 ]; then
        warn "跳过 ${DROPPED_LAT} 个延迟用例：perftest 的 -q 只支持带宽用例（Multiple QPs only available on bw tests）"
    fi
    TESTS=("${FILTERED[@]}")
    [ ${#TESTS[@]} -gt 0 ] || die "多 QP 模式下没有可跑的用例（延迟用例不支持 -q）"
fi

printf '  用例: %s\n' "${TESTS[*]}"
printf '  方向: %s\n' "$SIDES"
if [ "$SIZE_EXPLICIT" = 1 ]; then
    printf '  尺寸: %s（显式指定，带宽与延迟同用）   时长: %s\n\n' "$SIZE_BW" "$DURATION"
else
    printf '  尺寸: 带宽 %s / 延迟 %s   时长: %s\n\n' "$SIZE_BW" "$SIZE_LAT" "$DURATION"
fi

# 失败即停：任何一项没流量/报错都不再往下跑。
# 理由是本项目 400G 一路跑下来，第一项没流量时后面五项不会自己好，
# 一路跑完只是把同一个现象看六遍，还多花三分钟；异常状态先看诊断更好。
#
# 方向循环在最外层：--keep-going 时失败只跳过当前方向剩下的用例，另一个方向照跑
# （另一个方向走的是另一条数据通路，不受这边故障影响，值得单独取数）。
STOPPED=""
IFS=', ' read -ra SIDELIST <<< "$SIDES"
for side in "${SIDELIST[@]}"; do
    [ -n "$side" ] || continue
    case "$side" in
        client|server) ;;
        *) die "未知方向 $side（只认 client / server）" ;;
    esac
    if [ "$side" = "client" ]; then
        say "== FPGA 作客户端（服务端 = $PEER_HOST / CX7）=="
    else
        say "== FPGA 作服务端（客户端 = $PEER_HOST / CX7）=="
    fi

    for t in "${TESTS[@]}"; do
        [ -n "$t" ] || continue
        # UD 用例走 run_ud：尺寸由 active_mtu 定、工具与 GID 选项都不同。
        case "$t" in
            ud_*)
                if run_ud "$t" "$side"; then continue; fi
                FAILED="$FAILED fpga-${side}:${t}"
                if [ "$KEEP_GOING" = 1 ]; then
                    warn "继续下一个用例（--keep-going）"
                else
                    STOPPED="$side"; break 2
                fi
                continue ;;
        esac
        IFS=', ' read -ra SZLIST <<< "$(sizes_of "$t")"
        for sz in "${SZLIST[@]}"; do
            [ -n "$sz" ] || continue
            if run_pair "$t" "$sz" "$side"; then
                continue
            fi
            FAILED="$FAILED fpga-${side}:${t}@${sz}"
            run_diag "$t" "$sz" "$side"
            if [ "$KEEP_GOING" = 1 ]; then
                warn "继续下一个用例（--keep-going）"
            else
                STOPPED="$side"
                break 2
            fi
        done
    done
done

if [ -n "$STOPPED" ]; then
    warn "失败的用例:$FAILED —— fpga-${STOPPED} 方向已停止后续用例（--keep-going 可跑完）"
elif [ -n "$FAILED" ]; then
    warn "失败的用例:$FAILED"
fi

if [ -n "$FAILED" ] && [ -n "$LOG" ]; then
    say "结果未更新：先按上面的诊断定位，修好后重跑"
fi

# 有失败就以非 0 退出：脚本要能被上层脚本/CI 判断成败，
# 之前一律 exit 0，六项全 FAIL 也返回成功。
[ -n "$FAILED" ] && exit 1

[ -n "$LOG" ] && say "== 结果已打印，按需手工追加到 $LOG =="
exit 0
