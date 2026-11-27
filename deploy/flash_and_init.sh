#!/bin/bash
# FPGA 网卡上板固定流程：清理残留 -> 卸载驱动 -> [JTAG 烧写] -> PCIe 重新枚举
#                      -> 加载驱动 -> 网络初始化 -> 自检（含 GID 索引探测）
#
# 每次烧新 RTL 版本后，在跑 perftest 之前必须执行本脚本。
#
# **默认不烧写**：不带 --flash / --sram 时只做清理 → 重枚举 → 装驱动 → 配网 → 自检，
# 即日常「已经烧好了、重新拉一遍环境」的最常用路径。
#
# 两个烧写开关**互斥**，参数形式完全相同（完整镜像名 / B<Build> 简写 / 显式路径）：
#   --flash  烧 .jic 到板载配置 flash（**掉电保持**，才是真正换版本的方式）
#   --sram   烧 .sof 到 FPGA 易失配置（调试用，掉电回退到 flash 里的那版）
# 烧写必须显式加开关，因为烧写会覆盖镜像、还可能让卡掉出总线需要冷断电，
# 不该是默认动作。
#
# 用法：
#   ./flash_and_init.sh                              # 默认：不烧写，只清理+重枚举+驱动+配网
#   ./flash_and_init.sh --flash B6369                # 烧 flash（.jic），掉电保持
#   ./flash_and_init.sh --sram  B6369                # 烧 SRAM（.sof），掉电回退
#   ./flash_and_init.sh --flash <镜像名 | jic 路径 | Build 号>
#   ./flash_and_init.sh --sram  <镜像名 | sof 路径 | Build 号>
#   ./flash_and_init.sh --flash YN400GA7B041C-A26.12.02-B0116-20261123-1X400G-4203a24c      # .jic 是 A 型（boot+active 整片）
#   ./flash_and_init.sh --sram  YN400GA7B041C-R26.12.02-B0116-20261123-1X400G-4203a24c.sof  # .sof 用 R 型（active）
#                                                    # 完整镜像名（可带 .jic），从型号段
#                                                    # 型号段（YN400GA7B041C）认板，在
#                                                    # firmware/ 里找
#   ./flash_and_init.sh --flash B6369                # 简写：在 firmware/ 里按 Build 号找
#   ./flash_and_init.sh --flash path/to/xxx.jic      # 显式路径，由调用者负责
#   ./flash_and_init.sh --sram  path/to/xxx.sof      # 同上，烧 SRAM
#   ./flash_and_init.sh --no-flash                   # 兼容旧写法，等同不带参数（两个开关都关）
#   ./flash_and_init.sh --no-reload                  # 只清理+重枚举+配网（不动驱动）
#   ./flash_and_init.sh --flash --no-reload B6369    # 烧完不装驱动（只重新枚举）
#
# 给了镜像名却没加烧写开关会直接报错退出，不会静默跳过烧写——那种「以为烧了、
# 其实没烧」的误判比多打一个参数代价大得多。
#
# 关于 .jic：只有固件编译脚本的 `all` 模式会生成 JIC（Factory + Release 双镜像，
# AS x4）。`release` 单编只出 .sof/.rpd，那种情况想上板只能用 --sram 临时烧 SRAM。

# 环境变量：
#   CABLE         JTAG 线，默认取 `jtagconfig` 列出的第一根（USB 口号重启后会变，
#                 写死 [1-1] 会报 213013 cable not detected）
#   DEVICE_INDEX  器件索引（只对 --sram 烧 .sof 有意义），默认 1
#   CFG_DEVICE    配置器件名（只对 --flash 烧 .jic 有意义），默认 MX66U2G，与 JIC 里记录的
#                 flash 器件一致。**尚未在实卡上核对**，
#                 如果 quartus_pgm 报器件名不认识，用 `quartus_pgm --list` 或
#                 Programmer GUI 的 Auto Detect 看实际型号后覆盖本变量
#   QUARTUS_BIN   quartus_pgm 所在目录，默认 /home/quartus/program/quartus/bin
#   FLASH_TIMEOUT 单次烧写超时秒数，默认 900（jic 含擦除，可到 1800 以上）
#   NIC_IP / NIC_PREFIX   默认 192.168.50.1 / 24
#   PEER_IP       对端数据面地址，默认 192.168.50.2
#   RMMOD_TIMEOUT 单个模块卸载超时秒数，默认 20
#   BDF           PCI 地址，默认 0000:6f:00.0
#   BUILD_ROOT    镜像根目录，默认仓库根（镜像在其下 firmware/），测试时指向假的目录树
#   KO_SRC        驱动来源：build（默认，从 code/kernel 编译产物同步进包）/ package（直接用包里现有 ko）/
#                 <目录>（从该目录拷 yuanmcdma/yuannic/yuanrdma.ko）。换镜像和换驱动要分开验证时用
#                 UD 与 RC 自 2026-11-21 起同时支持，不再有 ENABLE_UD / ENABLE_CM_SUP 开关。
#                 CM 不上报：本卡没有 CQ 完成中断，req_notify_cq 无法投递事件，
#                 rping/ucmatose 会在 ibv_create_comp_channel 失败（见 yuanrdma_verbs.c 的 query_port）。
#                 只有烧了带 UD TX 的比特流（S7 之后）才该打开；老比特流上 WQE 5/6 无 case，
#                 会组 RC 形态的包发出去、对端静默不回——所以默认关，见 yuanrdma.h:34。

set -uo pipefail
# 判断模块是否已加载：直接读 /proc/modules，不要写成 `lsmod | grep -q`。
# pipefail 下 grep -q 命中即退出，lsmod 后续写入吃 SIGPIPE、管道返回 141，
# 本项目三个驱动排在 lsmod 最前面，实测 20 次约 17 次被误判为「未加载」
# （2026-11-12：第 2 步因此跳过 rmmod，第 4 步 PCI remove 卡在 unregister_netdev）。
mod_loaded() { grep -q "^$1 " /proc/modules; }

HERE=$(cd "$(dirname "$0")" && pwd)

# 本脚本有两个合法的放置位置：
#   1) deploy/                  —— 开发期（2026-11-27 从 build/user_tools/ 移来）。脚本在 deploy/，
#                                  包与运行期状态（.gid_local）仍在 build/user_tools/
#   2) 包内 tools/                  —— 交付后在 YuanNIC_User_Package/tools/
# 用「同目录下有没有 ../bin + ../env.sh」判定是不是在包内，比猜路径更可靠。
if [ -d "$HERE/../bin" ] && [ -f "$HERE/../env.sh" ]; then
    IN_PACKAGE=1
    NIC=$(cd "$HERE/.." && pwd)
else
    IN_PACKAGE=0
    # 包仍由 yuannic_user_build.sh 出到 build/user_tools/YuanNIC_User_Package；
    # 构建时用 YUANNIC_PKG_OUT 改了产物位置的，这里跟着同一个变量走。
    UT="$(cd "$HERE/.." && pwd)/build/user_tools"
    NIC="${YUANNIC_PKG_OUT:-$UT/YuanNIC_User_Package}"
fi

KERNEL_OUT="$HERE/../code/kernel"
# 镜像归档目录在仓库根 firmware/（2026-11-19 从 firmware/ 上移）。
# BUILD_ROOT 保留给测试指向假的目录树：给了就以它为准，否则用仓库根（$HERE/..）
BUILD_ROOT_SET=${BUILD_ROOT:+1}
BUILD_ROOT=${BUILD_ROOT:-$HERE/..}
FW_BACKUP="$BUILD_ROOT/firmware"
# 在交付包里（tools/）时镜像就在包内 firmware/，不往包外找；显式给了 BUILD_ROOT 仍以它为准
if [ "$IN_PACKAGE" = 1 ] && [ -z "${BUILD_ROOT_SET:-}" ] && [ -d "$NIC/firmware" ]; then
    FW_BACKUP="$NIC/firmware"
fi
BDF=${BDF:-0000:6f:00.0}

CABLE=${CABLE:-}
DEVICE_INDEX=${DEVICE_INDEX:-1}
# 配置器件名，只用于 --flash 烧 .jic 的 `pvi;<cfg_dev>;<file>` 形式。
# 取值依据：fpga_gen_jic.pfg 的 <flash_device>，板载 flash 为 MX66U2G——这个值**没有在实卡上核对过**。
CFG_DEVICE=${CFG_DEVICE:-MX66U2G}
QUARTUS_BIN=${QUARTUS_BIN:-/home/quartus/program/quartus/bin}
NIC_IP=${NIC_IP:-192.168.50.1}
NIC_PREFIX=${NIC_PREFIX:-24}
NETDEV=${NETDEV:-eth0}
RMMOD_TIMEOUT=${RMMOD_TIMEOUT:-20}
# 烧 flash 要擦除 + 编程 + 校验，比 JTAG 配置 SRAM 慢得多，超时给宽一些
FLASH_TIMEOUT=${FLASH_TIMEOUT:-1800}
SRAM_TIMEOUT=${SRAM_TIMEOUT:-900}
# GID 缓存：开发期放包外（包目录要能整包交付，不能带本机状态）；
# 交付到客户机器后包已经是解压副本，缓存在包根目录即可。
if [ "$IN_PACKAGE" = 1 ]; then
    GID_CACHE="$NIC/.gid_local"
else
    GID_CACHE="$UT/.gid_local"
fi

IMG=""
IMG_MODEL=""
# 烧写模式：0=不烧写（默认），1=--flash 烧 .jic，2=--sram 烧 .sof。两者互斥。
FLASH_MODE=0
DO_RELOAD=1

say()  { printf '\n\033[1m== %s\033[0m\n' "$*"; }
ok()   { printf '   \033[32mOK\033[0m   %s\n' "$*"; }
warn() { printf '   \033[33mWARN\033[0m %s\n' "$*"; }
die()  { printf '   \033[31mFAIL\033[0m %s\n' "$*" >&2; exit 1; }

# 板卡标识（img_model 的输出：C）-> 板卡名。
board_name() {
    case "$1" in
        C) echo "YuanNIC-NH400-C" ;;
        *) echo "未知板卡" ;;
    esac
}

# 从文件名里取型号段（YN400GA7B041C），取不到返回空。
# .sof 和 .jic 两种名字都要认——同一个 Build 归档时两个文件同名不同后缀。
img_model() {
    local b
    b=$(basename -- "$1")
    b=${b%.sof}
    b=${b%.jic}
    # 型号段 YN400GA7B041C → 板卡标识 C。
    printf '%s\n' "$b" | sed -nE 's/^YN400GA7B041(C)-.*/\1/p'
}

while [ $# -gt 0 ]; do
    case "$1" in
        --flash)     if [ "$FLASH_MODE" = 2 ]; then die "--flash 与 --sram 互斥，只能给一个"; fi
                     FLASH_MODE=1 ;;
        --sram)      if [ "$FLASH_MODE" = 1 ]; then die "--flash 与 --sram 互斥，只能给一个"; fi
                     FLASH_MODE=2 ;;
        --no-flash)  FLASH_MODE=0 ;;
        --no-reload) DO_RELOAD=0 ;;
        -h|--help)   awk 'NR>1 && /^#/ {sub(/^# ?/, ""); print; next} NR>1 {exit}' "$0"; exit 0 ;;
        -*)          die "未知参数 $1" ;;
        *)           IMG="$1" ;;
    esac
    shift
done

# 烧哪个扩展名的镜像由开关决定，用户给的名字带不带后缀都行
if [ "$FLASH_MODE" = 1 ]; then
    IMG_EXT=jic
    IMG_KIND="flash（.jic，掉电保持）"
else
    IMG_EXT=sof
    IMG_KIND="SRAM（.sof，掉电回退到 flash 里的那版）"
fi

# 坑：默认改成不烧写之后，老习惯 `./flash_and_init.sh B6369` 会静默只做初始化，
# 很容易"以为烧了、其实跑的还是老镜像"。给了镜像名却没给烧写开关就直接报错。
if [ -n "$IMG" ] && [ "$FLASH_MODE" = 0 ]; then
    die "给了镜像「$IMG」但没加 --flash 或 --sram。
        默认不烧写（见 --help）。要烧 flash（掉电保持）：./flash_and_init.sh --flash $IMG
        只烧 SRAM 调试：./flash_and_init.sh --sram $IMG
        只想初始化环境：去掉镜像名，直接 ./flash_and_init.sh"
fi

# 后缀校验**必须放在清理/卸载驱动之前**：原来这条检查在第 3 步里，于是
# `--flash xxx.sof` 会先 kill 掉 tcpdump、rmmod 掉三个驱动、把 eth0 down 掉，
# 才报「需要 .jic」退出——环境已经被拆了。参数错误一律在动任何东西之前判掉。
# 只校验显式文件路径：B<Build> 简写和完整镜像名由后面的查找逻辑按 IMG_EXT 选文件，
# 这里看到的名字可能不带后缀，不能按后缀拒。
if [ "$FLASH_MODE" != 0 ] && [ -f "$IMG" ]; then
    case "$IMG" in
        *."$IMG_EXT") ;;
        *)  die "--$([ "$FLASH_MODE" = 1 ] && echo flash || echo sram) 需要 .$IMG_EXT 文件，给的是：$IMG
        --flash 烧 .jic（flash，掉电保持），--sram 烧 .sof（易失配置）" ;;
    esac
fi

# 镜像参数还必须能归到「显式路径 / B<Build> 简写 / 完整镜像名」三种形式之一，
# 否则同样在动环境之前就退出。漏这一条时 `--sram /tmp/fake.jic`（文件不存在）
# 会一路走到卸载完驱动才报「认不出型号段」。
if [ "$FLASH_MODE" != 0 ] && [ -n "$IMG" ] && [ ! -f "$IMG" ]; then
    case "$IMG" in
        B[0-9]*) ;;
        YN400GA7B041C-*) ;;
        # 路径形式但文件不存在：报明确的「找不到文件」，不要等到后面
        */*) die "找不到镜像文件：$IMG" ;;
        *)   die "认不出镜像参数「$IMG」：应为 .${IMG_EXT} 路径、B<Build> 简写，
        或 YN400GA7B041C-… 形式的完整镜像名" ;;
    esac
fi

# ================================================================ 0. 清理残留
# 坑：tcpdump / ping / perftest 残留进程持有 netdev 或 AF_PACKET socket，
# 会让 rmmod 卡在 D 状态：内核反复打
#   "unregister_netdevice: waiting for eth0 to become free. Usage count = N"
# 此时进程杀不掉，只能重启。所以必须在卸载前先把它们清干净。
say "0/7 清理残留进程与引用"
for pat in tcpdump "ib_write_bw" "ib_read_bw" "ib_send_bw" "ib_write_lat" "ib_read_lat" "ib_send_lat" "yuancli"; do
    if pgrep -x "$pat" >/dev/null 2>&1; then
        pkill -x "$pat" 2>/dev/null && ok "kill $pat"
    fi
done
# ping 用 -x 会漏掉进程名带参数的情况，按进程名精确匹配即可
pkill -x ping 2>/dev/null && ok "kill ping"

# AF_PACKET socket 是抓包留下的，逐个数检查
if [ -s /proc/net/packet ]; then
    cnt=$(awk 'NR>1 && NF>0' /proc/net/packet | wc -l)
    [ "$cnt" -gt 0 ] && warn "/proc/net/packet 还有 $cnt 个 packet socket（若 rmmod 卡住，需重启）"
else
    ok "无残留 packet socket"
fi

# ================================================================ 1. 卸载前先降 netdev
# 先 down + flush 地址/邻居，能显著减少 unregister_netdevice 的等待。
say "1/7 降 $NETDEV 并清地址/邻居表"
if ip link show "$NETDEV" >/dev/null 2>&1; then
    ip link set "$NETDEV" down 2>/dev/null
    ip addr flush dev "$NETDEV" 2>/dev/null
    # 坑：之前为绕过 ARP 加过 "nud permanent" 表项，永久表项不会老化，
    # 会一直持有 netdev 引用，必须显式删除。
    ip neigh flush dev "$NETDEV" 2>/dev/null
    ok "$NETDEV 已 down、地址与邻居表已清"
fi

# ================================================================ 2. 卸载驱动
say "2/7 卸载驱动（顺序：yuanrdma -> yuannic -> yuanmcdma）"
for m in yuanrdma yuannic yuanmcdma; do
    mod_loaded "$m" || { ok "$m 未加载"; continue; }

    # timeout 保证不会挂死整个脚本；D 状态时 timeout 也救不了，但能给出明确提示
    if timeout "$RMMOD_TIMEOUT" rmmod "$m" 2>/dev/null; then
        ok "rmmod $m"
    else
        refs=$(dmesg 2>/dev/null | tail -3 | grep -o "Usage count = [0-9]*" | tail -1)
        die "rmmod $m 卡住${refs:+（$refs）}。这是 netdev 引用没释放，进程处于 D 状态无法 kill。
        排查：cat /proc/net/packet 看是否有残留 AF_PACKET socket；ss -tanp 看占用 $NETDEV 的进程。
        处理：只能重启。重启后先跑本脚本，不要先开 tcpdump/perftest。"
    fi
done
sleep 1

# ================================================================ 3. JTAG 烧写
if [ "$FLASH_MODE" != 0 ]; then
    [ -n "$IMG" ] || die "需要镜像名（YN400GA7B041C-…）、.${IMG_EXT} 路径或 Build 号，例：./flash_and_init.sh --$([ "$FLASH_MODE" = 1 ] && echo flash || echo sram) B0116"

    # 三种参数形式：显式文件路径 / 完整镜像名 / B<Build> 简写。
    # 完整镜像名按型号段（YN400GA7B041C）认板；不读板卡实际型号，型号对不对由调用者确认。
    if [ -f "$IMG" ]; then
        # 显式路径：板卡由调用者负责，型号段能认出就打出来。
        # 后缀必须和开关对上——--flash 给 .sof 会被烧成「烧 flash」的名义下的 SRAM 配置，
        # 掉电就没了，正是本脚本最想避免的误判，所以这里直接拒绝。
        case "$IMG" in
            *."$IMG_EXT") ;;
            *)  die "--$([ "$FLASH_MODE" = 1 ] && echo flash || echo sram) 需要 .$IMG_EXT 文件，给的是：$IMG
        --flash 烧 .jic（flash，掉电保持），--sram 烧 .sof（易失配置）" ;;
        esac
        IMG_MODEL=$(img_model "$IMG")
        title=$(basename -- "$IMG")
        IMG=$(cd "$(dirname "$IMG")" && pwd)/$(basename -- "$IMG")
    elif [[ "$IMG" =~ ^B[0-9]+$ ]]; then
        # 简写：只在 firmware/ 里找（编译脚本把镜像归档在这里）。
        # 匹配到多个型号段时报错退出并列出候选，不再静默取最新。
        build=$IMG
        found=""
        models=""
        for d in "$FW_BACKUP"; do
            for f in "$d"/*-${build}-*.${IMG_EXT}; do
                [ -f "$f" ] || continue
                # 同一 Build 归档里还有 Boot（Factory）镜像 <型号>-B<版本>-B<build>-…，按字母序它排在
                # Release（R）前面——不跳过的话 B<Build> 简写会把 boot 的 .sof 当成 active 烧进去。
                case "$(basename -- "$f" | sed -nE 's/^[A-Za-z0-9]+-([ABR])[0-9]+\.[0-9]+\.[0-9]+-.*/\1/p')" in
                    B) continue ;;
                esac
                m=$(img_model "$f")
                [ -n "$m" ] || continue
                case " $models " in *" $m "*) continue ;; esac
                models="$models $m"
                found="$found $f"
            done
        done
        [ -n "$found" ] || die "$FW_BACKUP 里没有 $build 的 .${IMG_EXT}（编译脚本会自动归档到 firmware/）"
        nmodel=$(echo $models | wc -w)
        if [ "$nmodel" -gt 1 ]; then
            echo "   $build 匹配到 $nmodel 块板，无法确定目标，请用完整镜像名：" >&2
            for f in $found; do
                printf '       %-20s %s\n' "$(board_name "$(img_model "$f")")" "$f" >&2
            done
            die "歧义退出，未烧写"
        fi
        IMG_MODEL=$(echo $models)
        # 同一块板有多个同名 Build（不同日期/githash）时取最新。
        # 从已收集的候选里按型号段筛，不再拼 glob：镜像名里型号段和
        # -B<Build>- 之间还夹着 R<VER>，拼 glob 容易漏。
        IMG=""
        for f in $found; do
            [ "$(img_model "$f")" = "$IMG_MODEL" ] || continue
            if [ -z "$IMG" ] || [ "$f" -nt "$IMG" ]; then
                IMG=$f
            fi
        done
        title=$(basename -- "$IMG")
    else
        # 完整镜像名，接受带不带 .sof/.jic
        base=${IMG%.sof}
        base=${base%.jic}
        IMG_MODEL=$(img_model "$base")
        [ -n "$IMG_MODEL" ] || die "认不出镜像名的型号段（期望 YN400GA7B041C-…）：$IMG"
        title=$base
        IMG="$FW_BACKUP/$base.${IMG_EXT}"
        [ -f "$IMG" ] || die "找不到 $base.${IMG_EXT}：
        到 $FW_BACKUP 里找过（编译脚本会把带版本号的镜像归档到这里）$( [ "$FLASH_MODE" = 1 ] && printf '\n        .jic 只有固件编译脚本的 all 模式才生成；release 单编的版本只能用 --sram 烧 .sof' )"
    fi

    [ -f "$IMG" ] || die "找不到 ${IMG_EXT^^}: $IMG"

    say "3/7 JTAG 烧写 $IMG_KIND $(basename "$IMG")  ($(du -h "$IMG" | cut -f1))"
    # 烧写前一行确认：识别到的板卡 + 镜像全名 + 实际文件路径
    if [ -n "$IMG_MODEL" ]; then
        printf '   目标板卡: %s（%s）\n' "$(board_name "$IMG_MODEL")" "$IMG_MODEL"
    else
        printf '   目标板卡: 未知（显式路径，未识别型号段）\n'
    fi
    printf '   镜像全名: %s\n' "$title"
    printf '   文件路径: %s\n' "$IMG"
    export PATH="$QUARTUS_BIN:$PATH"
    if [ -z "$CABLE" ]; then
        CABLE=$(jtagconfig 2>/dev/null | sed -n 's/^[0-9]*) \(USB-Blaster.*\)$/\1/p' | head -1)
        [ -n "$CABLE" ] || die "jtagconfig 没看到下载线（USB-Blaster），检查线缆与 jtagd"
    fi
    printf '   JTAG 线缆: %s\n' "$CABLE"

    # 两种烧写的 quartus_pgm 命令不一样，日志格式也不一样：
    #   .sof（F8.7 烧 SRAM）  -o "p;<file>@<device_index>"     日志出 "Configuration succeeded"
    #   .jic（烧配置 flash）   -o "pvi;<cfg_dev>;<file>"        日志走 erase -> program -> verify，
    #                                                          成功字样是 "Successfully performed operation(s)"
    # jic 的配置器件名由 CFG_DEVICE 决定（见文件头环境变量说明）；烧 jic 不需要 device index，
    # 器件在 JTAG 链上的位置由 SFL/load 决定。
    if [ "$FLASH_MODE" = 1 ]; then
        PGM_OP="pvi;$CFG_DEVICE;$IMG"
        PGM_TIMEOUT=$FLASH_TIMEOUT
        printf '   配置器件: %s（可用 CFG_DEVICE 覆盖）\n' "$CFG_DEVICE"
        warn "CFG_DEVICE=$CFG_DEVICE 未经实卡核对；若 quartus_pgm 报器件名不认识，用 Programmer GUI 的 Auto Detect 确认后覆盖该变量"
    else
        PGM_OP="p;$IMG@$DEVICE_INDEX"
        PGM_TIMEOUT=$SRAM_TIMEOUT
    fi

    # quartus_pgm 烧一个 ~100MB 的镜像要几分钟到十几分钟，这段时间原来什么都不打印，
    # 分不清是在烧还是卡死了。改成后台跑、日志落文件，前台每秒刷新一行：
    # 转轮 + 已用时间 + 日志里出现的百分比（有就显示，没有就只显示计时）。
    # 注意 .sof 的 JTAG 配置 quartus_pgm 不一定输出百分比，所以进度以计时为准；
    # .jic 走 flash 擦除/编程，日志里一般有 erase/program 的百分比，能显示出来。
    flap=$(mktemp -d /tmp/flash.XXXXXX) || die "mktemp 失败，无法记录烧写日志"
    trap 'rm -rf "$flap"' EXIT

    ( timeout "$PGM_TIMEOUT" quartus_pgm -c "$CABLE" -m jtag \
        -o "$PGM_OP" >"$flap/log" 2>&1; echo $? >"$flap/rc" ) &
    bgpid=$!

    spin='|/-\'
    tick=0
    pct=""
    seen=0          # 已打印过的日志行数
    t0=$(date +%s)
    while [ ! -s "$flap/rc" ]; do
        sleep 1
        tick=$((tick + 1))

        # 日志用 \r 刷新时一行能有多段，统一换成 \n 再按行编号
        tr '\r' '\n' <"$flap/log" >"$flap/lines" 2>/dev/null
        n=$(wc -l <"$flap/lines" 2>/dev/null || echo 0)
        if [ "${n:-0}" -gt "$seen" ]; then
            [ -t 1 ] && printf '\r\033[K'
            sed -n "$((seen + 1)),${n}p" "$flap/lines" \
                | grep -vE '^[[:space:]]*$|^Info: Quartus Prime Programmer|^----+' \
                | sed 's/^/        /'
            seen=$n
        fi

        p=$(grep -oE '[0-9]{1,3}%' "$flap/lines" 2>/dev/null | tail -1)
        [ -n "$p" ] && pct=$p

        el=$(( $(date +%s) - t0 ))
        msg="已用 $(printf '%02d:%02d' $((el / 60)) $((el % 60)))${pct:+  进度 $pct}"
        if [ -t 1 ]; then
            printf '\r  %s %s\033[K' "${spin:$((tick % 4)):1}" "$msg"
        elif [ $((tick % 15)) -eq 0 ]; then
            printf '   %s\n' "$msg"
        fi
        # 后台子 shell 被杀（极端情况）时防止死循环
        if ! kill -0 "$bgpid" 2>/dev/null; then
            sleep 1
            [ -s "$flap/rc" ] || echo 137 >"$flap/rc"
        fi
    done
    wait "$bgpid" 2>/dev/null
    [ -t 1 ] && printf '\r\033[K'

    rc=$(cat "$flap/rc" 2>/dev/null)
    el=$(( $(date +%s) - t0 ))
    tmsg="耗时 $(printf '%02d:%02d' $((el / 60)) $((el % 60)))"

    if [ "$rc" = 124 ]; then
        tail -20 "$flap/log" >&2
        die "quartus_pgm 超过 $PGM_TIMEOUT 秒未完成（$tmsg），已超时终止"
    fi
    if [ "$rc" != 0 ] || grep -qE '^Error' "$flap/log"; then
        echo "----------- quartus_pgm 日志 ----------" >&2
        cat "$flap/log" >&2
        echo "---------------------------------------" >&2
        die "quartus_pgm 失败（exit $rc，$tmsg）"
    fi
    # 成功字样两种烧写不一样：
    #   .sof -> "Configuration succeeded -- N device(s) configured"（209007）
    #   .jic -> 擦除/编程/校验走完出 "Successfully performed operation(s)"（209011）
    # 两种都认，避免烧 flash 成功却被判成失败。
    if grep -qE "Configuration succeeded|Successfully performed" "$flap/log"; then
        ok "烧写完成（$tmsg）"
    else
        # 没抓到成功字样也不一定是失败，把日志尾部交给人判断
        tail -10 "$flap/log" | sed 's/^/        /'
        warn "quartus_pgm exit 0 但没看到 Configuration succeeded / Successfully performed，请人工核对上面的日志"
    fi
    rm -rf "$flap"
    trap - EXIT
else
    say "3/7 跳过烧写（默认行为，要烧 flash 加 --flash <镜像名>，只烧 SRAM 加 --sram <镜像名>）"
fi

# ================================================================ 4. PCIe 重新枚举
# 坑 1：JTAG 重配置后主机不会重新枚举，BAR 读回全 0xffffffff。
# 表现为 yuannic 报 "detect_pcie_mode: bar[0]=0xffffffff -> DEVICE NOT RESPONDING"、
# yuanrdma 报 "RoCE engine not present"，ynictrl 读到 CHIPVERSION ffffffff。
# 必须 remove + rescan 才能恢复；软复位和重新加载驱动都无效。
# 坑 2：rescan 只分配 BAR 地址，不会打开 COMMAND.MemEnable。这版卡 rescan 后
# altera-cvp 会探一次再 pci_disable_device，COMMAND 停在 0x0100（只剩 SERR）。
# 此时 BAR 一样读回全 0xffffffff，但卡其实完全正常 —— 2026-10-25 就因此误判
# 成"设备无应答、需冷断电"。所以探针前必须自己把内存解码打开。
say "4/7 PCIe 重新枚举 $BDF"
[ -e "/sys/bus/pci/devices/$BDF" ] && { echo 1 > "/sys/bus/pci/devices/$BDF/remove" 2>/dev/null; sleep 2; }
echo 1 > /sys/bus/pci/rescan
sleep 4

[ -e "/sys/bus/pci/devices/$BDF" ] || die "rescan 后 $BDF 不存在，卡掉出总线（看 lspci 与 dmesg）"
ok "设备在总线上"

command -v setpci >/dev/null || die "缺 setpci（装 pciutils）"

# 配置空间读得出来才算真的在总线上；VENDOR_ID 全 1 才是掉线
vid=$(setpci -s "$BDF" VENDOR_ID 2>/dev/null)
[ "$vid" = "ffff" ] && die "配置空间 VENDOR_ID=ffff：设备无应答，需冷断电（重启不能复位 FPGA 的 PCIe Hard IP）"
ok "配置空间可读（VENDOR_ID=$vid）"

cmd=$(setpci -s "$BDF" COMMAND 2>/dev/null)
if [ $(( 0x${cmd:-0} & 0x2 )) -eq 0 ]; then
    setpci -s "$BDF" COMMAND=0x0002:0x0002 2>/dev/null
    cmd2=$(setpci -s "$BDF" COMMAND 2>/dev/null)
    [ $(( 0x${cmd2:-0} & 0x2 )) -eq 2 ] \
        || die "打不开内存解码：COMMAND=$cmd2（期望 bit1=1）"
    ok "COMMAND $cmd -> $cmd2，内存解码已打开"
else
    ok "COMMAND=$cmd，内存解码已开"
fi

# 上游桥非预取窗口：flash 里旧镜像 BAR 是 prefetchable、JTAG 灌的新镜像是
# non-prefetchable 时，BIOS 只开了桥的 pref 窗口；rescan 后内核在 sysfs 里记了
# 新的 mem 窗口却没写进桥寄存器（MEMORY_BASE=fff0/LIMIT=0000），BAR 读全 ff。
# 这种情况不需要冷断电，按内核的分配补写桥窗口即可。
br=$(basename "$(dirname "$(readlink -f "/sys/bus/pci/devices/$BDF")")")
if [ -r "/sys/bus/pci/devices/$br/resource" ]; then
    read -r wst wen _ < <(sed -n 15p "/sys/bus/pci/devices/$br/resource")
    hwb=$(setpci -s "$br" MEMORY_BASE 2>/dev/null)
    hwl=$(setpci -s "$br" MEMORY_LIMIT 2>/dev/null)
    if [ $(( ${wen:-0} )) -ne 0 ] && [ $(( 0x${hwb:-0} & 0xfff0 )) -gt $(( 0x${hwl:-0} & 0xfff0 )) ]; then
        nb=$(printf '%04x' $(( (wst >> 16) & 0xfff0 )))
        nl=$(printf '%04x' $(( (wen >> 16) & 0xfff0 )))
        setpci -s "$br" MEMORY_BASE="$nb" MEMORY_LIMIT="$nl"
        warn "桥 $br 非预取窗口未生效（硬件 $hwb/$hwl），已按内核分配补写 $wst-$wen"
    fi
fi

# 只读探针：BAR2 读不到就别往下走
probe=$(python3 - "$BDF" <<'EOF'
import sys, mmap, struct
bdf = sys.argv[1]
try:
    f = open(f"/sys/bus/pci/devices/{bdf}/resource2", "rb", 0)
    m = mmap.mmap(f.fileno(), 0, prot=mmap.PROT_READ)
    out = [struct.unpack("<I", m[o:o+4])[0] for o in (0x0, 0x8, 0x2E00000, 0x2600000)]
    m.close()
except Exception as e:
    print("ERR", e); sys.exit(1)
print(" ".join(f"0x{v:08x}" for v in out))
EOF
)
case "$probe" in
    *ERR*) die "BAR2 打不开：$probe" ;;
esac
echo "$probe" | grep -q "0xffffffff.*0xffffffff.*0xffffffff" \
    && die "BAR2 全 0xffffffff：设备无应答，需冷断电（重启不能复位 FPGA 的 PCIe Hard IP）"
ok "BAR2: $probe   (csr00 / 版本日期 / RoCE ID / slot2 桩)"

# slot2 桩是新旧镜像的判别点：删 pkt_gen 后返回 0xdeadbeef
slot2=$(echo "$probe" | awk '{print $4}')
[ "$slot2" = "0xdeadbeef" ] && warn "slot2=0xdeadbeef → 这是删除 pkt_gen 之后的镜像"
[ "$slot2" = "0x0" ] && warn "slot2=0x0 → 这是删除 pkt_gen 之前的镜像（B6367 及更早）"

# ================================================================ 5. 加载驱动
if [ "$DO_RELOAD" = 1 ]; then
    say "5/7 加载驱动（ib_core -> ib_uverbs -> yuanmcdma -> yuannic -> yuanrdma）"
    uname_v=$(uname -r)
    # 坑：内核升级后 YuanNIC_User_Package/ko 里的旧模块会 "Invalid module format" /
    # "disagrees about version of symbol module_layout"。vermagic 不符就换新版。
    #
    # KO_SRC（2026-11-09）：默认 build = 从 code/kernel 的编译产物同步到包里（原行为）；
    # KO_SRC=package 时不同步，直接装包里现有的 ko（换镜像与换驱动分开验证时用，
    # 例如 B6420 首次上板用已验证的旧 yuanmcdma，MTU 4096 的新 yuanmcdma 另起一轮）；
    # KO_SRC=<目录> 时从该目录拷 yuanmcdma/yuannic/yuanrdma.ko。
    KO_SRC=${KO_SRC:-build}
    # 2026-11-21 起 UD 与 RC 同时支持，驱动里已经没有 enable_ud 参数：
    # B6458/B6459 比特流的 UD TX 已实测可用（UD 收发、ud_pingpong 都跑过）。
    # 注意老比特流（WQE 5/6 无 case）上不要建 UD QP——会静默组出 RC 形态的包。
    for m in yuanmcdma yuannic yuanrdma; do
        case "$KO_SRC" in
            package) src="" ;;
            build)
                case "$m" in
                    yuanrdma) src="$KERNEL_OUT/yuanrdma/yuanrdma.ko" ;;
                    *)        src="$KERNEL_OUT/output/$m.ko" ;;
                esac ;;
            *)       src="$KO_SRC/$m.ko" ;;
        esac
        if [ -n "$src" ] && [ -f "$src" ]; then
            src_v=$(modinfo "$src" 2>/dev/null | awk '/^vermagic:/{print $2}')
            if [ "$src_v" = "$uname_v" ]; then
                cp -f "$src" "$NIC/ko/$m.ko"
            else
                warn "$src 是 $src_v 编的，当前内核 $uname_v"
            fi
        elif [ -n "$src" ] && [ "$KO_SRC" != build ]; then
            die "KO_SRC=$KO_SRC 下没有 $m.ko"
        fi
        ko_v=$(modinfo "$NIC/ko/$m.ko" 2>/dev/null | awk '/^vermagic:/{print $2}')
        [ "$ko_v" = "$uname_v" ] || die "$m.ko vermagic=$ko_v 与内核 $uname_v 不符，先 make -C code/kernel"
        ok "$m.ko  srcversion $(modinfo "$NIC/ko/$m.ko" 2>/dev/null | awk '/^srcversion:/{print $2}')（KO_SRC=$KO_SRC）"
    done

    # 坑：yuanrdma.ko 依赖 ib_core / ib_uverbs（modinfo 的 depends 字段），
    # 而这两者是内核自带的，不在 ko/ 目录里。冷启动后它们默认不会自动加载，
    # insmod 又不像 modprobe 那样处理依赖，于是 yuanrdma 报一串
    #   "Unknown symbol ib_umem_get / _ib_alloc_device / rdma_user_mmap_entry_insert ..."
    # （ib_umem_* 由 ib_uverbs 导出，其余由 ib_core 导出）。
    # 必须先 modprobe 把这两个装上，且 ib_uverbs 要排在 ib_core 之后。
    for m in ib_core ib_uverbs; do
        if mod_loaded "$m"; then
            ok "$m 已加载"
        else
            modprobe "$m" 2>/dev/null || die "modprobe $m 失败（内核缺该模块？看 /lib/modules/$uname_v）"
            ok "modprobe $m"
        fi
    done

    # rdma_cm / rdma_ucm：RDMA CM 用户态接口（/dev/infiniband/rdma_cm）。
    # 缺了它 rping / ucmatose / rdma_server 一律报 "failed to create RDMA CM event
    # channel: No such file or directory"——那是缺设备节点，不是 CM 实现的问题
    # （2026-11-18 B6502 首轮踩到）。perftest 不走 CM，所以此前没人需要它。
    # 内核自带的这两个模块按需加载，加载失败只告警：不装 CM 也能跑 perftest。
    for m in rdma_cm rdma_ucm; do
        if mod_loaded "$m"; then
            ok "$m 已加载"
        elif modprobe "$m" 2>/dev/null; then
            ok "modprobe $m"
        else
            warn "modprobe $m 失败（rping/ucmatose 会报 'failed to create RDMA CM event channel'）"
        fi
    done

    insmod "$NIC/ko/yuanmcdma.ko"  || die "insmod yuanmcdma.ko 失败"
    sleep 2
    insmod "$NIC/ko/yuannic.ko"  || warn "insmod yuannic.ko 失败（仅 ynictrl 不可用，perftest 不受影响）"
    sleep 1
    # UD/RC 同时支持，不再传 enable_ud；CM 不上报，也不再传 enable_cm_sup。
    # 本卡没有 CQ 完成中断，req_notify_cq 投递不了事件，rping/ucmatose 会在
    # ibv_create_comp_channel 失败（见 yuanrdma_verbs.c 的 query_port 注释）。
    insmod "$NIC/ko/yuanrdma.ko" || die "insmod yuanrdma.ko 失败"

    sleep 3
    ok "驱动已加载"
else
    say "5/7 跳过驱动重载（--no-reload）"
fi

[ -d /sys/class/infiniband/yuanrdma0 ] || die "yuanrdma0 不存在（dmesg 里常见 RoCE engine not present）"
[ -e "/sys/class/net/$NETDEV" ] || die "netdev $NETDEV 不存在，用 ip -br link 确认网口名"
ok "yuanrdma0 与 $NETDEV 均在位"

# ================================================================ 6. 网络初始化
say "6/7 网络初始化 $NETDEV"
ip link set "$NETDEV" up 2>/dev/null || die "ip link set $NETDEV up 失败"
sleep 1
ip addr flush dev "$NETDEV" 2>/dev/null
ip addr add "$NIC_IP/$NIC_PREFIX" dev "$NETDEV" 2>/dev/null || warn "add $NIC_IP 失败（可能已存在）"
sleep 1
ok "地址：$(ip -br addr show "$NETDEV" | awk '{print $3}')   MTU $(cat /sys/class/net/$NETDEV/mtu)"

# 坑：MTU 受驱动限制（当前 yuanmcdma 上限 1500），改不动。
# RoCE 的 IB MTU 是另一回事，由 QPC 配置，不受 netdev MTU 影响，perftest 照常。
mtu_now=$(cat /sys/class/net/$NETDEV/mtu 2>/dev/null)
[ "$mtu_now" = "1500" ] && warn "netdev MTU=1500（yuanmcdma 上限），不影响 RoCE IB MTU"

state=$(cat /sys/class/infiniband/yuanrdma0/ports/1/state 2>/dev/null)
[ "${state%%:*}" = "4" ] && ok "IB 端口 ACTIVE" || warn "IB 端口状态 $state（期望 4: ACTIVE）"

# ================================================================ 7. 自检 + GID 探测
say "7/7 自检与 GID 索引"
# shellcheck disable=SC1090
source "$NIC/env.sh"
ibv_devices 2>/dev/null | grep -q yuanrdma0 && ok "ibv_devices 能看到 yuanrdma0" \
    || warn "ibv_devices 看不到设备（env.sh 里的 RDMAV_DRIVERS 没生效？）"

# 坑：GID 索引会随 IP 增减和驱动重载漂移。实测过 192.168.50.1 在
# 索引 5（一次加载）和索引 2（另一次加载）之间变化，perftest -x 用错
# 会连不上却不报错原因。所以每次初始化都重新探测并缓存到 YuanNIC_User_Package/.gid_local。
gid_hex=$(python3 - "$NIC_IP" <<'EOF'
import sys, ipaddress
ip = ipaddress.IPv4Address(sys.argv[1])
print("%02x%02x:%02x%02x" % tuple(ip.packed))
EOF
)
gid_v2=""; gid_any=""
for i in $(seq 0 31); do
    g=$(cat "/sys/class/infiniband/yuanrdma0/ports/1/gids/$i" 2>/dev/null) || break
    case "$g" in
        *"ffff:${gid_hex}")
            [ -z "$gid_any" ] && gid_any="$i"
            t=$(cat "/sys/class/infiniband/yuanrdma0/ports/1/gid_attrs/types/$i" 2>/dev/null)
            case "$t" in
                *"v2"*) [ -z "$gid_v2" ] && gid_v2="$i" ;;
            esac
            ;;
    esac
done
gid=${gid_v2:-$gid_any}
if [ -n "$gid" ]; then
    echo "$gid" > "$GID_CACHE"
    ok "GID 索引 = $gid（$NIC_IP，RoCEv2），已写入 $GID_CACHE"
else
    warn "没找到 $NIC_IP 对应的 GID，roce_perf_test.sh 会用默认值"
fi

if [ -x "$NIC/bin/ynictrl" ]; then
    ver=$("$NIC/bin/ynictrl" -c YN400GA7B041C -a 0 -q 2>/dev/null | grep -E "VERSION|CHIPVERSION")
    [ -n "$ver" ] && echo "$ver" | sed 's/^/        /' || warn "ynictrl 读不到版本（yuannic 没加载？）"
fi

printf '\n'
warn "CHIPVERSION 读的是 flash 里的版本；--sram 用 .sof 烧的是易失镜像，"
warn "掉电会回到 flash 那版。判断当前跑哪版看上面的 slot2 值，不要看 CHIPVERSION。"
warn "--flash 烧 .jic 才是改 flash 内容，烧完要冷断电一次再测性能。"
printf '\n'
if [ "$IN_PACKAGE" = 1 ]; then
    ok "初始化完成 → ./tools/roce_perf_test.sh --label <版本>"
else
    ok "初始化完成 → ./roce_perf_test.sh --label <Build>"
fi
