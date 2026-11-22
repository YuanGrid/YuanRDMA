#!/bin/bash
# YuanNIC-NH400-C（AGIB041R29D1E2VB，AS x4）固件构建：
# 从 code/quartus/YuanNIC-NH400-C/boot 和 .../active 拷贝工程到本脚本所在目录编译。
# 编译目录固定在 build/YuanNIC-NH400-C，与从哪个目录调用无关。
#   boot    ：只编 boot 工程，出 Boot 的 SOF/RPD，并刷新 firmware/boot_images/<型号>/
#   active  ：只编 active 工程；若找到 firmware/boot_images 里的预置 boot 镜像，
#             再用它合成 All JIC，找不到就只出 Release 产物（原 active 逻辑）
#   all     ：boot 与 active 都重编，用本次编出的 boot 合成 All JIC

# 脚本所在目录（build/YuanNIC-NH400-C），也是编译目录
FWB_SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
FWB_PWD=${FWB_SCRIPT_DIR}

cd ${FWB_PWD} || exit 1

# 26.12.07
FPGA_BIN_VER=$1

# 6362
FPGA_BIN_BUILD=$2

# 1X400G
FPGA_BIN_SPEED=$3

# all/boot/active，缺省 active（兼容旧的三参数调用）
FPGA_BIN_TYPE=${4:-active}

# 20261021
FPGA_BIN_DATE=`date '+%Y%m%d'`

# Quartus Prime Pro 26.1.1 安装目录，可用环境变量 QUARTAS_PATH 覆盖
QUARTAS_PATH=${QUARTAS_PATH:-/home/quartus/program}

# Quartus 26.1 license，可用环境变量 LM_LICENSE_FILE 覆盖
export LM_LICENSE_FILE=${LM_LICENSE_FILE:-/home/quartus/software/ALTERA_LICENSE/license_26.1.dat}

export QSYS_ROOTDIR="${QUARTAS_PATH}/qsys/bin"
export PATH="${QUARTAS_PATH}/quartus/bin:$PATH"

function build_usage
{
    echo ""
    echo "Usage: "
    echo "    $0 VERSION BUILD SPEED [TYPE]"
    echo "    TYPE: boot/active/all, default active"
    echo "          boot   = 只重编 boot 并刷新 firmware/boot_images/<型号>/"
    echo "          active = 只编 active；有预置 boot 镜像就同时出 All JIC"
    echo "          all    = boot 与 active 都重编，并用本次 boot 出 All JIC"
    echo "    like: $0 26.12.07 6362 1X400G boot"
    echo "    like: $0 26.12.07 6362 1X400G active"
    echo ""
    exit 1
}

if [ "$FPGA_BIN_VER"x = ""x ]; then
     echo "FPGA bitstream version must be inputed"
     build_usage
fi

if [ "$FPGA_BIN_BUILD"x = ""x ]; then
     echo "FPGA bitstream build version must be inputed"
     build_usage
fi

if [ "$FPGA_BIN_SPEED"x = ""x ]; then
     echo "FPGA bitstream speed mode must be inputed, like 1X400G"
     build_usage
fi

if [ "$FPGA_BIN_TYPE" != "all" ] && [ "$FPGA_BIN_TYPE" != "boot" ] && [ "$FPGA_BIN_TYPE" != "active" ]; then
     echo "FPGA bitstream build type invalid: $FPGA_BIN_TYPE, must be all/boot/active"
     build_usage
fi

FPGA_NIC_NAME=${FPGA_NIC_NAME:-YN400GA7B027C}

# 工程目录名（code/quartus 下），拷贝到构建目录后换成带 boot_/active_ 前缀的目录名
PRO_DIR_NAME=YuanNIC-NH400-C
BASE_PRO_NAME=boot_yuanrdma_c_400g
RELS_PRO_NAME=active_yuanrdma_c_400g
# boot 工程已冻结（2026-11-21）：all 模式不再编译它，直接用这里预置的 Factory 镜像。
# 型号段与 FPGA_NIC_NAME 一致——A/C 两块的器件和 flash loader 不同，镜像不能混用。
BOOT_IMG_DIR=${BOOT_IMG_DIR:-${FWB_SCRIPT_DIR}/../../firmware/boot_images/${FPGA_NIC_NAME}}
BOOT_IMG_SOF=${BOOT_IMG_SOF:-${BOOT_IMG_DIR}/YuanRDMA_boot.sof}
BOOT_IMG_RPD=${BOOT_IMG_RPD:-${BOOT_IMG_DIR}/YuanRDMA_boot.rpd}

QUARTUS_SH=${QUARTAS_PATH}/quartus/bin/quartus_sh
QUARTUS_PFG=${QUARTAS_PATH}/quartus/bin/quartus_pfg
# 工程源码目录（本仓库的 code/quartus），可用环境变量 FPGA_PRO_ROOT 覆盖
FPGA_PRO_ROOT=${FPGA_PRO_ROOT:-$(cd "${FWB_SCRIPT_DIR}/../../code/quartus" && pwd)}

BASE_PRO_PATH=${FPGA_PRO_ROOT}/${PRO_DIR_NAME}/boot
RELS_PRO_PATH=${FPGA_PRO_ROOT}/${PRO_DIR_NAME}/active

if [ ! -x $QUARTUS_SH ]; then
    echo "quartus_sh not found: $QUARTUS_SH"
    exit 1
fi
quartus_sh -v

if [ "$FPGA_BIN_TYPE" = "boot" ] || [ "$FPGA_BIN_TYPE" = "all" ]; then
    if [ ! -e $BASE_PRO_PATH/project/YuanRDMA.qsf ]; then
        echo "FPGA boot project $BASE_PRO_PATH/project/YuanRDMA.qsf not exist"
        build_usage
    fi
fi

if [ "$FPGA_BIN_TYPE" = "active" ] || [ "$FPGA_BIN_TYPE" = "all" ]; then
    if [ ! -e $RELS_PRO_PATH/project/YuanRDMA.qsf ]; then
        echo "FPGA active project $RELS_PRO_PATH/project/YuanRDMA.qsf not exist"
        build_usage
    fi
fi

# 防止在源码所在目录运行时把源码工程当作拷贝目录删除
case "$FWB_PWD" in
    "$FPGA_PRO_ROOT"|"$FPGA_PRO_ROOT"/*)
        echo "Don't run in $FPGA_PRO_ROOT, build directory is fixed to the script directory: $FWB_SCRIPT_DIR"
        exit 1
        ;;
esac

ALL_NIC_NAME=${FPGA_NIC_NAME}_All
BASE_NIC_NAME=${FPGA_NIC_NAME}_Base
RELS_NIC_NAME=${FPGA_NIC_NAME}_Release

BASE_SOF_NAME=${BASE_NIC_NAME}.sof
RELS_SOF_NAME=${RELS_NIC_NAME}.sof

BASE_RPD_NAME=${BASE_NIC_NAME}.rpd
RELS_RPD_NAME=${RELS_NIC_NAME}.rpd

ALL_JIC_NAME=${ALL_NIC_NAME}.jic

# 取本地源码仓库的 HEAD
GIT_HEAD_VER=`git -C $FPGA_PRO_ROOT rev-parse HEAD 2>/dev/null | cut -c 1-8`
if [ "$GIT_HEAD_VER"x = ""x ]; then
    echo "Can't get git head version by command"
    echo "    git -C $FPGA_PRO_ROOT rev-parse HEAD | cut -c 1-8"
    echo ""
    exit 1
fi
if [ -n "`git -C $FPGA_PRO_ROOT status --porcelain -- ${PRO_DIR_NAME} 2>/dev/null`" ]; then
    echo "Warning: $FPGA_PRO_ROOT has uncommitted changes, image githash $GIT_HEAD_VER is not exact"
fi

ALL_IMG_PREF=${FPGA_NIC_NAME}-A${FPGA_BIN_VER}-B${FPGA_BIN_BUILD}-${FPGA_BIN_DATE}-${FPGA_BIN_SPEED}-${GIT_HEAD_VER}
BASE_IMG_PREF=${FPGA_NIC_NAME}-B${FPGA_BIN_VER}-B${FPGA_BIN_BUILD}-${FPGA_BIN_DATE}-${FPGA_BIN_SPEED}-${GIT_HEAD_VER}
RELS_IMG_PREF=${FPGA_NIC_NAME}-R${FPGA_BIN_VER}-B${FPGA_BIN_BUILD}-${FPGA_BIN_DATE}-${FPGA_BIN_SPEED}-${GIT_HEAD_VER}

COPY_PRO_RELS=${FWB_PWD}/${RELS_PRO_NAME}
COPY_PRO_BASE=${FWB_PWD}/${BASE_PRO_NAME}

# 拷贝工程到构建目录，不带 Quartus 生成物
function copy_project
{
    SRC_PRO=$1
    # 拷贝到 $COPY_PRO 指定的名字，而不是 rsync 到当前目录。
    # 目录重组后 SRC_PRO 的 basename 是 "active"/"boot"，直接 rsync 到 ./
    # 会生成 ./active，而调用方接着 cd $COPY_PRO/project（active_<board>_400g/project）
    # 失败，结果在构建目录根上跑 Quartus，报 "Top-level design entity is undefined"。
    test -n "$COPY_PRO" || { echo "copy_project: COPY_PRO 未设置"; exit 1; }
    mkdir -p "$COPY_PRO"
    rsync -a --exclude output --exclude qdb --exclude dni --exclude output_files \
        --exclude tmp-clearbox --exclude '*.log' "$SRC_PRO"/ "$COPY_PRO"/
}

# 编译当前目录下的 YuanRDMA，日志写 quartus_sh.log，并检查时序
function compile_project
{
    PRO_LABEL=$1
    OUTPUT_DIR=$2

    quartus_sh --flow compile YuanRDMA > ./quartus_sh.log 2>&1
    QSH_RET=$?
    cp ./quartus_sh.log $FWB_PWD/${PRO_LABEL}_quartus_sh.log
    if [ $QSH_RET -ne 0 ] || [ ! -e $OUTPUT_DIR/YuanRDMA.sof ]; then
        tail -n 100 ./quartus_sh.log
        echo "Firmware $PRO_LABEL building failed, see $FWB_PWD/${PRO_LABEL}_quartus_sh.log"
        exit 1
    fi

    if [ -e $OUTPUT_DIR/YuanRDMA.sta.summary ]; then
        cp $OUTPUT_DIR/YuanRDMA.sta.summary $FWB_PWD/${PRO_LABEL}_sta.summary
        if grep -q "Slack : -" $OUTPUT_DIR/YuanRDMA.sta.summary; then
            echo "Warning: $PRO_LABEL has negative slack, see $FWB_PWD/${PRO_LABEL}_sta.summary"
        fi
    fi

    # 全量时序报告一并留存：summary 只到 clock 级 slack，看不出违例端点是哪个模块。
    # 2026-11-20 追 B6457 的 −0.114 时，只有 summary 归档，最后靠翻编译机上的临时
    # 工作目录（/home/roce_build/qf）才把路径找回来——那个目录随时会被清掉。
    if [ -e $OUTPUT_DIR/YuanRDMA.sta.rpt ]; then
        cp $OUTPUT_DIR/YuanRDMA.sta.rpt $FWB_PWD/${PRO_LABEL}_sta.rpt
        if grep -q "Slack : -" $OUTPUT_DIR/YuanRDMA.sta.summary 2>/dev/null; then
            echo "  违例路径见 $FWB_PWD/${PRO_LABEL}_sta.rpt（VIOLATED 命中 $(grep -c VIOLATED $OUTPUT_DIR/YuanRDMA.sta.rpt) 处）"
        fi
    else
        echo "Warning: $PRO_LABEL 没产出 YuanRDMA.sta.rpt，违例无法追到端点，请查 quartus_sh.log 里 STA 是否被跳过"
    fi
}

# 拷贝并编译一个工程，SOF 放到 sof2rpd/YuanRDMA_<label>.sof
function build_sof_file
{
    PRO_LABEL=$1
    SRC_PRO=$2
    COPY_PRO=$3

    echo "FPGA firmware $PRO_LABEL will be built by quartus_sh ..."

    cd $FWB_PWD
    if [ -e $COPY_PRO ]; then
        rm -rf $COPY_PRO
    fi
    copy_project $SRC_PRO

    cd $COPY_PRO/project
    compile_project $PRO_LABEL $COPY_PRO/output

    echo "================================================="
    echo "Firmware $PRO_LABEL building successfully."
    echo "================================================="

    cp $COPY_PRO/output/YuanRDMA.sof $FWB_PWD/sof2rpd/YuanRDMA_${PRO_LABEL}.sof

    cd $FWB_PWD
}

echo ""
echo "FWB_PWD: $FWB_PWD ..."
echo "Build type: $FPGA_BIN_TYPE"
echo ""

# 删除上次build的临时文件
rm -rf *.log *.jic *.sof *.rpd *.map *.summary

if [ -e $COPY_PRO_BASE ]; then
    rm -rf $COPY_PRO_BASE
fi
if [ -e $COPY_PRO_RELS ]; then
    rm -rf $COPY_PRO_RELS
fi
if [ -e $FWB_PWD/sof2rpd ]; then
    rm -rf $FWB_PWD/sof2rpd
fi
mkdir -p $FWB_PWD/sof2rpd

# 按类型编译
if [ "$FPGA_BIN_TYPE" = "boot" ] || [ "$FPGA_BIN_TYPE" = "all" ]; then
    build_sof_file boot $BASE_PRO_PATH $COPY_PRO_BASE
fi

if [ "$FPGA_BIN_TYPE" = "active" ] || [ "$FPGA_BIN_TYPE" = "all" ]; then
    build_sof_file active $RELS_PRO_PATH $COPY_PRO_RELS
fi

# JIC 的 Factory 镜像来源：
#   all    → 本次刚编出的 boot（sof2rpd/YuanRDMA_boot.sof）
#   active → firmware/boot_images 里的预置镜像；没有就只出 Release 产物
GEN_JIC=0
if [ "$FPGA_BIN_TYPE" = "all" ]; then
    GEN_JIC=1
elif [ "$FPGA_BIN_TYPE" = "active" ]; then
    if [ -f "$BOOT_IMG_SOF" ]; then
        GEN_JIC=1
        cp "$BOOT_IMG_SOF" $FWB_PWD/sof2rpd/YuanRDMA_boot.sof || exit 1
        echo "Using prebuilt boot image: $BOOT_IMG_SOF"
    else
        echo ""
        echo "Warning: 找不到预置 boot 镜像 $BOOT_IMG_SOF"
        echo "         本次只出 Release 产物，不生成 All JIC。"
        echo "         先跑一次 boot 模式生成并归档：$0 <VER> <BUILD> $FPGA_BIN_SPEED boot"
        echo ""
    fi
fi

cd $FWB_PWD/sof2rpd

# 生成JIC（预置 boot + 本次 active 双 SOF）
if [ "$GEN_JIC" = "1" ]; then
    quartus_pfg -c ${FWB_SCRIPT_DIR}/fpga_gen_jic.pfg > $FWB_PWD/all_pfg.log 2>&1
    if [ ! -e output_file_all.jic ]; then
        cat $FWB_PWD/all_pfg.log
        echo "Firmware all jic generating failed."
        exit 1
    fi
fi

# 生成RPD（AS x4，与 QSF 的 ACTIVE SERIAL X4 一致）
if [ "$FPGA_BIN_TYPE" = "boot" ] || [ "$FPGA_BIN_TYPE" = "all" ]; then
    quartus_pfg -c YuanRDMA_boot.sof YuanRDMA_boot.rpd -o mode=asx4 -o bitswap=ON > $FWB_PWD/boot_pfg.log 2>&1
    if [ ! -e YuanRDMA_boot.rpd ]; then
        cat $FWB_PWD/boot_pfg.log
        echo "Firmware boot rpd generating failed."
        exit 1
    fi
fi

if [ "$FPGA_BIN_TYPE" = "active" ] || [ "$FPGA_BIN_TYPE" = "all" ]; then
    quartus_pfg -c YuanRDMA_active.sof YuanRDMA_active.rpd -o mode=asx4 -o bitswap=ON > $FWB_PWD/active_pfg.log 2>&1
    if [ ! -e YuanRDMA_active.rpd ]; then
        cat $FWB_PWD/active_pfg.log
        echo "Firmware active rpd generating failed."
        exit 1
    fi
fi

# 拷贝产物到build目录，同时按版本命名
if [ "$GEN_JIC" = "1" ]; then
    cp output_file_all.jic $FWB_PWD/$ALL_JIC_NAME
    cp output_file_all.jic $FWB_PWD/${ALL_IMG_PREF}.jic
fi

if [ "$FPGA_BIN_TYPE" = "boot" ] || [ "$FPGA_BIN_TYPE" = "all" ]; then
    cp YuanRDMA_boot.sof $FWB_PWD/$BASE_SOF_NAME
    cp YuanRDMA_boot.rpd $FWB_PWD/$BASE_RPD_NAME
    cp YuanRDMA_boot.sof $FWB_PWD/${BASE_IMG_PREF}.sof
    cp YuanRDMA_boot.rpd $FWB_PWD/${BASE_IMG_PREF}.rpd
    [ -e $FWB_PWD/boot_sta.rpt ] && cp $FWB_PWD/boot_sta.rpt $FWB_PWD/${BASE_IMG_PREF}.sta.rpt
fi

if [ "$FPGA_BIN_TYPE" = "boot" ]; then
    mkdir -p "$BOOT_IMG_DIR"
    cp $FWB_PWD/sof2rpd/YuanRDMA_boot.sof "$BOOT_IMG_DIR/YuanRDMA_boot.sof"
    cp $FWB_PWD/sof2rpd/YuanRDMA_boot.rpd "$BOOT_IMG_DIR/YuanRDMA_boot.rpd"
    echo ""
    echo "Refreshed prebuilt boot image in $BOOT_IMG_DIR:"
    md5sum "$BOOT_IMG_DIR"/YuanRDMA_boot.sof "$BOOT_IMG_DIR"/YuanRDMA_boot.rpd
fi

if [ "$FPGA_BIN_TYPE" = "active" ] || [ "$FPGA_BIN_TYPE" = "all" ]; then
    cp YuanRDMA_active.sof $FWB_PWD/$RELS_SOF_NAME
    cp YuanRDMA_active.rpd $FWB_PWD/$RELS_RPD_NAME
    cp YuanRDMA_active.sof $FWB_PWD/${RELS_IMG_PREF}.sof
    cp YuanRDMA_active.rpd $FWB_PWD/${RELS_IMG_PREF}.rpd
    [ -e $FWB_PWD/active_sta.rpt ] && cp $FWB_PWD/active_sta.rpt $FWB_PWD/${RELS_IMG_PREF}.sta.rpt
fi

echo ""
echo "Images in $FWB_PWD:"
ls -l $FWB_PWD/${FPGA_NIC_NAME}*

# ---------------------------------------------------------------
# 归档：把带版本号的镜像另存到公共的仓库根 firmware/，避免下次编译
# 被脚本开头的 rm *.sof *.rpd 清掉。三块板（LA/LC/LD）的镜像汇总到同一个
# 目录，烧写脚本按镜像名里的型号段直接定位，不必去各板目录里翻。
# 文件名已含 Build 号、日期和 githash，本身就是唯一标识，同名直接覆盖。
# 只归档带版本号的副本，固定名（*_Base/_Release/_All）只留在运行目录。
# 归档目录不在运行目录里，脚本开头的 rm *.sof 清不到它。
# ---------------------------------------------------------------
IMG_ARCHIVE=${IMG_ARCHIVE:-$FWB_PWD/../../firmware}
mkdir -p "$IMG_ARCHIVE"

archived=""
if [ "$FPGA_BIN_TYPE" = "boot" ] || [ "$FPGA_BIN_TYPE" = "all" ]; then
    for f in ${BASE_IMG_PREF}.sof ${BASE_IMG_PREF}.rpd ${BASE_IMG_PREF}.sta.rpt; do
        if [ -e "$FWB_PWD/$f" ]; then
            cp -f "$FWB_PWD/$f" "$IMG_ARCHIVE/$f"
            archived="$archived $IMG_ARCHIVE/$f"
        fi
    done
fi

if [ "$FPGA_BIN_TYPE" = "active" ] || [ "$FPGA_BIN_TYPE" = "all" ]; then
    for f in ${RELS_IMG_PREF}.sof ${RELS_IMG_PREF}.rpd ${RELS_IMG_PREF}.sta.rpt; do
        if [ -e "$FWB_PWD/$f" ]; then
            cp -f "$FWB_PWD/$f" "$IMG_ARCHIVE/$f"
            archived="$archived $IMG_ARCHIVE/$f"
        fi
    done
fi

if [ "$GEN_JIC" = "1" ]; then
    if [ -e "$FWB_PWD/${ALL_IMG_PREF}.jic" ]; then
        cp -f "$FWB_PWD/${ALL_IMG_PREF}.jic" "$IMG_ARCHIVE/${ALL_IMG_PREF}.jic"
        archived="$archived $IMG_ARCHIVE/${ALL_IMG_PREF}.jic"
    fi
fi

if [ -n "$archived" ]; then
    echo ""
    echo "Archived images in $IMG_ARCHIVE:"
    for f in $archived; do ls -l "$f"; done
fi

exit 0
