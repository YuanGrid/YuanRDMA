#include <linux/version.h>
#include <linux/module.h>
#include <linux/compat.h>
#include <asm/tlbflush.h>
#include <linux/fs.h>
#include <linux/uaccess.h>
#include <linux/miscdevice.h>
#include <linux/cdev.h>
#include <linux/syscalls.h>
#include <linux/pci.h>
#include <linux/workqueue.h>
#include <linux/pci_regs.h>
#include <linux/kernel.h>
#include <linux/mod_devicetable.h>
#include <linux/netdevice.h>
#include <linux/etherdevice.h>
#include <linux/rtnetlink.h>
#include <linux/spinlock.h>
#include <linux/bitmap.h>
#include <linux/slab.h>
#include <linux/string.h>
#include <linux/ktime.h>
#include <linux/time64.h>
#include <linux/bitfield.h>
#include <asm/uaccess.h>
#if LINUX_VERSION_CODE >= KERNEL_VERSION(2, 6, 26)
#include <linux/nsproxy.h>
#endif

#include <linux/in.h>
#include <linux/poll.h>
#include <linux/inet.h>
// #include "linux/ntos_compat.h" /* RHEL_RELEASE_CODE */

#include <asm/byteorder.h>
#include "onic_driver.h"
#include "onic_register.h"
#include "ifc_mcdma_net.h"




#ifdef __BIG_ENDIAN
#define __BYTE_ORDER __BIG_ENDIAN
#else
#define __BYTE_ORDER __LITTLE_ENDIAN
#endif

#include "ynic_net_base.h"

//#define DEBUG_ON

#ifdef DEBUG_ON
#define KDBG printk
#else
#define KDBG(string, args...)
#endif

/*
 * ---- 上板调试插桩（2026-10-22）----
 *
 * 背景：C 型板（0000:6f:00.0）在 insmod 后短时间内静默掉出总线（rev ff，配置空间全 ff），
 * dmesg 无 AER / link down。需要在不干扰现场的前提下拿到：
 *   1) 掉线发生的精确时间点（相对模块加载的毫秒数）；
 *   2) 掉线前最后一次 MMIO / ioctl 是什么；
 *   3) 是配置空间先失效还是 MMIO 先失效。
 *
 * 用法：
 *   insmod yuannic.ko dbg=0x1F          # 全开（默认）
 *   insmod yuannic.ko dbg=0x0           # 全关，走生产路径
 *   insmod yuannic.ko dbg=0x8 watch_ms=200   # 只开配置空间监视
 * 所有输出带 "[+1234ms]" 前缀，单位是模块加载后的毫秒。
 */
#define YNIC_DBG_LIFE        BIT(0)  /* init/exit/资源映射 */
#define YNIC_DBG_MMIO        BIT(1)  /* 单次 MMIO 读写 */
#define YNIC_DBG_IOCTL       BIT(2)  /* ioctl 命令 */
#define YNIC_DBG_WATCH       BIT(3)  /* 配置空间/链路状态变化 */
#define YNIC_DBG_MMIO_HEART  BIT(4)  /* MMIO 心跳（每 watch_ms 读一次 bar[0]） */

static int dbg = 0x1F;
module_param(dbg, int, 0644);
MODULE_PARM_DESC(dbg, "debug bitmask: 1=life 2=mmio 4=ioctl 8=watch 16=mmio-heartbeat");

static int dbg_mmio_max = 64;
module_param(dbg_mmio_max, int, 0644);
MODULE_PARM_DESC(dbg_mmio_max, "max MMIO accesses logged in full (anomalies always logged)");

static int watch_ms = 1000;
module_param(watch_ms, int, 0644);
MODULE_PARM_DESC(watch_ms, "config-space watchdog period in ms (0=off)");

static ktime_t ynic_dbg_t0;
static atomic_t ynic_dbg_mmio_logged = ATOMIC_INIT(0);
static atomic_t ynic_dbg_mmio_anom = ATOMIC_INIT(0);
static atomic_t ynic_dbg_mmio_total = ATOMIC_INIT(0);

static inline u64 ynic_dbg_ms(void)
{
    return (u64)ktime_to_ms(ktime_sub(ktime_get(), ynic_dbg_t0));
}

#define YNIC_LOG(mask, fmt, ...)                                            \
    do {                                                                   \
        if (unlikely((dbg) & (mask)))                                      \
            pr_info("[yuannic +%llums] " fmt, ynic_dbg_ms(), ##__VA_ARGS__); \
    } while (0)

#define YNIC_ERRL(mask, fmt, ...)                                           \
    do {                                                                   \
        if (unlikely((dbg) & (mask)))                                      \
            pr_err("[yuannic +%llums] " fmt, ynic_dbg_ms(), ##__VA_ARGS__);  \
    } while (0)


#define YNIC_DRVIER_NAME1         "ifc_mcdma_netdev"
#define YNIC_DRVIER_NAME2         "yuanmcdma"

#define YNIC_TOTAL_PORT_NUM                  (MAX_PORT_PER_ADP * MAX_FPGA_ADAPTER)
#define YNIC_TOTAL_STREAM_NUM                (MAX_STREAM_PER_PORT * YNIC_TOTAL_PORT_NUM)
#define YNIC_TOTAL_STREAM_NUM_100G           (MAX_STREAM_PER_PORT_100G * YNIC_TOTAL_PORT_NUM)
#define YNIC_TOTAL_STREAM_NUM_400G           (MAX_STREAM_PER_PORT_400G * YNIC_TOTAL_PORT_NUM)

#define YNIC_TX_STREAM_MDF_LENGTH            41    //按uint8_t计算长度
#define YNIC_RX_STREAM_MDF_LENGTH            13     //2+2+4+1*5
#define YNIC_RX_STREAM_FLT_NUM               32
#define YNIC_RX_STREAM_FLT_LEN               10

#define NET_VENDOR_ID                       0x10EE  /* Xilinx Corporation */
#define NET_DEVICE_ID0                      0x903F  /* Xilinx Card port 0*/
#define NET_DEVICE_ID1                      0x913F  /* Xilinx Card port 1*/
#define ALTERA_VENDOR_ID                    0x1172

#define FPGA_CONTROL_TX_STREAM
#define FPGA_CONTROL_RX_STREAM

/*************************system*******************************/
#define FPGA_SYS_BASE_ALTERA                0x1200000
#define FPGA_SECTOR_REG_ALTERA              0x1600000
#define FPGA_VERSION_REG                    0x0
#define FPGA_SECTOR_REG                     0xB000
#define FPGA_MAC_SIZE                       (16)
#define FPGA_SERNUM_REG                     (FPGA_SECTOR_REG + 0x80)
#define FPGA_FIRMWARE_REG                   (FPGA_SERNUM_REG + 0x10)
#define FPGA_SERNUM_REG_ALTERA              (FPGA_SECTOR_REG_ALTERA + 0x80)
#define FPGA_FIRMWARE_REG_ALTERA            (FPGA_SERNUM_REG_ALTERA + 0x10)
#define FPGA_MODEL_REG                      0x002C
#define FPGA_LINK_REG                       0x01BC
#define FPGA_AUNE_REG                       0x003C
#define FPGA_IMAGE_REG                      0x8
#define YNIC_VERSION_LEN                     24
#define FPGA_JUMP_LEN                       2

#define FPGA_TIME_LOW_REG                   0x001C
#define FPGA_TIME_HIGH_REG                  0x0020
#define FPGA_TIME_SYN_ENABLE                0x0028
//one to multiple
#define FPGA_CLEAR_STATIS_REG               0x0030
#define FPGA_TEMPERATURE_REG                0x0038
#define FPGA_PORT_PF0_NUM_REG               0x0040
#define FPGA_PORT_PF1_NUM_REG               0x0044
#define FPGA_PORT_PF2_NUM_REG               0x0048
#define FPGA_PORT_PF3_NUM_REG               0x004C
#define FPGA_PORT_SPEED_REG                 0x0050
#define FPGA_TX_ROCE_EN                     0x0060
#define FPGA_PFC_STATS_REG0                 0x0080
#define FPGA_RSFEC_REG                      0x107C
#define XILINX_100G_PFC_TX_CTRL             0x0030
#define XILINX_100G_PFC_RX_CTRL             0x0084
#define XILINX_100G_PFC_PAUSE_ENABLE        BIT(8)
#define XILINX_100G_PFC_RX_GCP_PCP_GPP_PPP  GENMASK(13, 10)
#define ALTERA_FPGA_LINK_REG                0x110014
#define ALTERA_400G_PFC_MB_CTL_REG          0x110000
#define ALTERA_400G_PFC_MB_ADDR_REG         0x110004
#define ALTERA_400G_PFC_MB_DATA_REG         0x110008
#define ALTERA_400G_PFC_MB_WRITE_REQ        0x80000000
#define ALTERA_400G_PFC_SPEED_50G_OFFSET    0x2000
#define ALTERA_400G_PFC_SPEED_100G_OFFSET   0x3000
#define ALTERA_400G_PFC_SPEED_200G_OFFSET   0x4000
#define ALTERA_400G_PFC_SPEED_400G_OFFSET   0x5000
#define ALTERA_400G_PFC_TX_PAUSE_EN         0x022c
#define ALTERA_400G_PFC_TXSFC_EHIP_CFG      0x025c
#define ALTERA_400G_PFC_RX_PAUSE_ENABLE     0x0260
#define ALTERA_400G_PFC_RX_PAUSE_FWD        0x0264
#define ALTERA_400G_PFC_RXSFC_EHIP_CFG      0x0270
/*************************system*******************************/

/*************************tx stream****************************/
#define FPGA_TX_BASE_XILINX                 0x100000
#define FPGA_TX_BASE_ALTERA                 0x1300000

#define FPGA_TX_OFFSET                      0x1000
#define FPGA_TX_START_ADDR                  0x00
#define FPGA_TX_STATUS_ADDR                 0x08
#define FPGA_TX_PKTS_LOW_ADDR               0x0C
#define FPGA_TX_PKTS_HIGH_ADDR              0x10
#define FPGA_TX_BYTES_LOW_ADDR              0x14
#define FPGA_TX_BYTES_HIGH_ADDR             0x18
#define FPGA_TX_BYTES_SPEED_LOW_ADDR        0x1C
#define FPGA_TX_BYTES_SPEED_HIGH_ADDR       0x20
#define FPGA_TX_PKTS_SPEED_LOW_ADDR         0x24
#define FPGA_TX_PKTS_SPEED_HIGH_ADDR        0x28
#define FPGA_TX_TIME_START_LOW              0x2C
#define FPGA_TX_TIME_START_HIGH             0x30
#define FPGA_TX_TIME_STOP_LOW               0x34
#define FPGA_TX_TIME_STOP_HIGH              0x38
#define FPGA_TX_PKTS_MUL_LOW_ADDR           0x3C
#define FPGA_TX_PKTS_MUL_HIGH_ADDR          0x40
#define FPGA_TX_BYTES_MUL_LOW_ADDR          0x44
#define FPGA_TX_BYTES_MUL_HIGH_ADDR         0x48
#define FPGA_TX_PKT_LEN_LOW_ADDR            0x50
#define FPGA_TX_PKT_LEN_HIGH_ADDR           0x54
#define FPGA_TX_SEND_TIME_LOW_ADDR          0x58
#define FPGA_TX_SEND_TIME_HIGH_ADDR         0x5C
#define FPGA_TX_TD_TYPE                     0x70
#define FPGA_TX_GAPNUM_ADDR                 0xFC
#define FPGA_TX_PKTS_MUL_SPEED_LOW_ADDR     0x80
#define FPGA_TX_PKTS_MUL_SPEED_HIGH_ADDR    0x84
#define FPGA_TX_BYTES_MUL_SPEED_LOW_ADDR    0x88
#define FPGA_TX_BYTES_MUL_SPEED_HIGH_ADDR   0x8C
#define FPGA_TX_K5TUPLE_NUM_ADDR            0x100
#define FPGA_TX_PKT_LENGTH_ADDR             0x104
#define FPGA_TX_GAPA_ADDR                   0x108
#define FPGA_TX_GAPB_ADDR                   0x10C
#define FPGA_TX_SIP_START_ADDR              0x110
#define FPGA_TX_SIP_END_ADDR                0x114
#define FPGA_TX_SIP_STEP_ADDR               0x118
#define FPGA_TX_DIP_START_ADDR              0x11C
#define FPGA_TX_DIP_END_ADDR                0x120
#define FPGA_TX_DIP_STEP_ADDR               0x124
#define FPGA_TX_SPORT_START_ADDR            0x128
#define FPGA_TX_SPORT_END_ADDR              0x12C
#define FPGA_TX_SPORT_STEP_ADDR             0x130
#define FPGA_TX_DPORT_START_ADDR            0x134
#define FPGA_TX_DPORT_END_ADDR              0x138
#define FPGA_TX_DPORT_STEP_ADDR             0x13C
#define FPGA_TX_1to4_EN_ADDR                0x148
#define FPGA_TX_1to4_SEL_ADDR               0x14C
#define FPGA_TX_SIPv6_START0_ADDR           0x150
#define FPGA_TX_SIPv6_START1_ADDR           0x154
#define FPGA_TX_SIPv6_START2_ADDR           0x158
#define FPGA_TX_SIPv6_START3_ADDR           0x15C
#define FPGA_TX_SIPv6_END0_ADDR             0x160
#define FPGA_TX_SIPv6_END1_ADDR             0x164
#define FPGA_TX_SIPv6_END2_ADDR             0x168
#define FPGA_TX_SIPv6_END3_ADDR             0x16C
#define FPGA_TX_SIPv6_STEP_ADDR             0x170
#define FPGA_TX_DIPv6_START0_ADDR           0x174
#define FPGA_TX_DIPv6_START1_ADDR           0x178
#define FPGA_TX_DIPv6_START2_ADDR           0x17C
#define FPGA_TX_DIPv6_START3_ADDR           0x180
#define FPGA_TX_DIPv6_END0_ADDR             0x184
#define FPGA_TX_DIPv6_END1_ADDR             0x188
#define FPGA_TX_DIPv6_END2_ADDR             0x18C
#define FPGA_TX_DIPv6_END3_ADDR             0x190
#define FPGA_TX_DIPv6_STEP_ADDR             0x194
#define FPGA_TX_SPORTv6_START_ADDR          0x198
#define FPGA_TX_SPORTv6_END_ADDR            0x19C
#define FPGA_TX_SPORTv6_STEP_ADDR           0x1A0
#define FPGA_TX_DPORTv6_START_ADDR          0x1A4
#define FPGA_TX_DPORTv6_END_ADDR            0x1A8
#define FPGA_TX_DPORTv6_STEP_ADDR           0x1AC
#define FPGA_TX_DIRECT_ADDR                 0x140
#define FPGA_TX_IPTYPE_ADDR                 0x144
#define FPGA_TX_STREAM_NUM                  0x10050
#define FPGA_TX_STREAM_INFO_ITEEM0          0x1002C
#define FPGA_TX_STREAM_INFO_WRITE0          0x10030
#define FPGA_TX_STREAM_INFO_WDONE0          0x10034
#define FPGA_TX_PKT_CTRL_ITEEM0             0x10038
#define FPGA_TX_PKT_CTRL_WRITE0             0x1003C
#define FPGA_TX_PKT_CTRL_WDONE0             0x10040
#define FPGA_TX_PKT_TEMPLATE_BASE           0x10044 //fpga stream id
#define FPGA_TX_PKT_TEMPLATE_WRITE0         0x10048
#define FPGA_TX_PKT_TEMPLATE_WDONE0         0x1004C
#define FPGA_TX_PKT_PTR_RESET               0x10054
#define FPGA_TX_PKT_LW_WRITE                0x10058
#define FPGA_TX_PKT_LW_WDONE                0x1005C
#define FPGA_TX_PKT_JUMP_ITEEM0             0x10064
#define FPGA_TX_PKT_JUMP_WRITE0             0x10068
#define FPGA_TX_PKT_JUMP_WDONE0             0x1006C
#define FPGA_TX_PKT_JUMP_INDEX              0x10070
/*************************tx stream****************************/

/*************************rx stream****************************/
#define FPGA_RX_BASE_XILINX                 0x200000
#define FPGA_RX_BASE_ALTERA                 0x1400000

#define FPGA_RX_OFFSET                      0x40000
#define FPGA_RX_ENB                         0x00
#define FPGA_RX_PROMISC_ENB                 0x04
#define FPGA_RX_STA_CLEAR                   0x08
#define FPGA_RX_FLT_ENB                     0x0C
#define FPGA_RX_1to4                        0x10
#define FPGA_RX_1to4_READ                   0x14
#define FPGA_RX_FLT_IPTYPE                  0x18
#define FPGA_RX_FLT_BASE                    0x1C
#define FPGA_RX_FLT_INFO                    0x20
#define FPGA_RX_FLT_DONE                    0x24
#define FPGA_RX_FLT_ENB_BIT                 0x28
#define FPGA_RX_FLT_ACTION                  0x2C
#define FPGA_RX_FLT_RELATION                0xF0
#define FPGA_RX_FILTER_COUNT                4
#define FPGA_PKTS_LOW_ADDR                  0x30
#define FPGA_RX_PKTS_HIGH_ADDR              0x34
#define FPGA_RX_BYTES_LOW_ADDR              0x38
#define FPGA_RX_BYTES_HIGH_ADDR             0x3C
#define FPGA_RX_PKTS_DROP_LOW_ADDR          0x40
#define FPGA_RX_PKTS_DROP_HIGH_ADDR         0x44
#define FPGA_RX_BYTES_DROP_LOW_ADDR         0x48
#define FPGA_RX_BYTES_DROP_HIGH_ADDR        0x4C
#define FPGA_RX_PKTS_ERR_LOW_ADDR           0x50
#define FPGA_RX_PKTS_ERR_HIGH_ADDR          0x54
#define FPGA_RX_BYTES_ERR_LOW_ADDR          0x58
#define FPGA_RX_BYTES_ERR_HIGH_ADDR         0x5C
#define FPGA_RX_IP_CKSUM_ERR_LOW_ADDR       0x60
#define FPGA_RX_IP_CKSUM_ERR_HIGH_ADDR      0x64
#define FPGA_RX_1G_SPEED                    0x80
#define FPGA_RX_QUEUE_ID                    0x90
#define FPGA_RX_TEST_MODE                   0x94
#define FPGA_RX_TD_TYPE                     0x98
#define FPGA_RX_1G_TYPE                     0x1A8
#define FPGA_RX_BYTES_SPEED_LOW_ADDR        0xA0
#define FPGA_RX_BYTES_SPEED_HIGH_ADDR       0xA4
#define FPGA_RX_PKTS_SPEED_LOW_ADDR         0xA8
#define FPGA_RX_PKTS_SPEED_HIGH_ADDR        0xAC
#define FPGA_RX_TIME_START_LOW_ADDR         0xB0
#define FPGA_RX_TIME_START_HIGH_ADDR        0xB4
#define FPGA_RX_TIME_STOP_LOW_ADDR          0xB8
#define FPGA_RX_TIME_STOP_HIGH_ADDR         0xBC
#define FPGA_RX_TS_SUM_LOW_ADDR             0x100
#define FPGA_RX_TS_SUM_HIGH_ADDR            0x104
#define FPGA_RX_TS_MAX_LOW_ADDR             0x108
#define FPGA_RX_TS_MAX_HIGH_ADDR            0x10C
#define FPGA_RX_TS_MIN_LOW_ADDR             0x110
#define FPGA_RX_TS_MIN_HIGH_ADDR            0x114
#define FPGA_RX_JT_SUM_LOW_ADDR             0x118
#define FPGA_RX_JT_SUM_HIGH_ADDR            0x11C
#define FPGA_RX_JT_MAX_LOW_ADDR             0x120
#define FPGA_RX_JT_MAX_HIGH_ADDR            0x124
#define FPGA_RX_JT_MIN_LOW_ADDR             0x128
#define FPGA_RX_JT_MIN_HIGH_ADDR            0x12C
#define FPGA_RX_TS_BASE                     0x9C
#define FPGA_RX_ENABLE_REG                  0x200
#define FPGA_RX_WORK_MODE                   0x204
#define FPGA_RX_FLT_SPORT_ADDR              0x210
#define FPGA_ROCE_TS_REAL_LOW_ADDR          0x130
#define FPGA_ROCE_TS_REAL_HIGH_ADDR         0x134
#define FPGA_ROCE_TS_MAX_LOW_ADDR           0x138
#define FPGA_ROCE_TS_MAX_HIGH_ADDR          0x13C
#define FPGA_ROCE_TS_MIN_LOW_ADDR           0x140
#define FPGA_ROCE_TS_MIN_HIGH_ADDR          0x144
#define FPGA_ROCE_JT_REAL_LOW_ADDR          0x148
#define FPGA_ROCE_JT_REAL_HIGH_ADDR         0x14C
#define FPGA_ROCE_JT_MAX_LOW_ADDR           0x150
#define FPGA_ROCE_JT_MAX_HIGH_ADDR          0x154
#define FPGA_ROCE_JT_MIN_LOW_ADDR           0x158
#define FPGA_ROCE_JT_MIN_HIGH_ADDR          0x15C
#define FPGA_ROCE_PKT_LOW_ADDR              0x190
#define FPGA_ROCE_PKT_HIGH_ADDR             0x194
#define FPGA_ROCE_TS_SUM_LOW_ADDR           0x198
#define FPGA_ROCE_TS_SUM_HIGH_ADDR          0x19C
#define FPGA_ROCE_JT_SUM_LOW_ADDR           0x1A0
#define FPGA_ROCE_JT_SUM_HIGH_ADDR          0x1A4
#define FPGA_RX_PAUSE_START_ADDR             0x210
#define FPGA_RX_PFC_START_ADDR(_priority)    (0x214 + ((_priority) * 4))
#define FPGA_RX_PAUSE_STOP_ADDR              0x234
#define FPGA_RX_PFC_STOP_ADDR(_priority)     (0x238 + ((_priority) * 4))
#define FPGA_RX_PKTS_MUL_LOW_ADDR           0x070
#define FPGA_RX_PKTS_MUL_HIGH_ADDR          0x074
#define FPGA_RX_BYTES_MUL_LOW_ADDR          0x078
#define FPGA_RX_BYTES_MUL_HIGH_ADDR         0x07C
#define FPGA_RX_TS_SUM_MUL_LOW_ADDR         0x160
#define FPGA_RX_TS_SUM_MUL_HIGH_ADDR        0x164
#define FPGA_RX_TS_MAX_MUL_LOW_ADDR         0x168
#define FPGA_RX_TS_MAX_MUL_HIGH_ADDR        0x16C
#define FPGA_RX_TS_MIN_MUL_LOW_ADDR         0x170
#define FPGA_RX_TS_MIN_MUL_HIGH_ADDR        0x174
#define FPGA_RX_JT_SUM_MUL_LOW_ADDR         0x178
#define FPGA_RX_JT_SUM_MUL_HIGH_ADDR        0x17C
#define FPGA_RX_JT_MAX_MUL_LOW_ADDR         0x180
#define FPGA_RX_JT_MAX_MUL_HIGH_ADDR        0x184
#define FPGA_RX_JT_MIN_MUL_LOW_ADDR         0x188
#define FPGA_RX_JT_MIN_MUL_HIGH_ADDR        0x18C
#define FPGA_RX_DROP_MUL_LOW_ADDR           0x1B0
#define FPGA_RX_PKTS_SPEED_MUL_LOW_ADDR     0x1B4
#define FPGA_RX_BYTES_SPEED_MUL_LOW_ADDR    0x1B8
#define FPGA_RX_BYTES_SPEED_MUL_HIGH_ADDR   0x1BC

#define FPGA_RX_FLT_DMAC_EN                 0x400
#define FPGA_RX_FLT_DMAC_MODE               0x404 //== != > <
#define FPGA_RX_FLT_DMAC_MSK0               0x408 //0-31
#define FPGA_RX_FLT_DMAC_MSK1               0x40C
#define FPGA_RX_FLT_DMAC_VAL0               0x410
#define FPGA_RX_FLT_DMAC_VAL1               0x414
#define FPGA_RX_FLT_SMAC_EN                 0x418
#define FPGA_RX_FLT_SMAC_MODE               0x41C
#define FPGA_RX_FLT_SMAC_MSK0               0x420
#define FPGA_RX_FLT_SMAC_MSK1               0x424
#define FPGA_RX_FLT_SMAC_VAL0               0x428
#define FPGA_RX_FLT_SMAC_VAL1               0x42C
#define FPGA_RX_FLT_VLAN_EN                 0x430
#define FPGA_RX_FLT_VLAN_MODE               0x434
#define FPGA_RX_FLT_VLAN_MSK                0x438
#define FPGA_RX_FLT_VLAN_VAL                0x43C
#define FPGA_RX_FLT_PROTO_EN                0x450
#define FPGA_RX_FLT_PROTO_MODE              0x454
#define FPGA_RX_FLT_PROTO_MSK               0x458
#define FPGA_RX_FLT_PROTO_VAL               0x45C
#define FPGA_RX_FLT_SIPV4_EN                0x460
#define FPGA_RX_FLT_SIPV4_MODE              0x464
#define FPGA_RX_FLT_SIPV4_MSK               0x468
#define FPGA_RX_FLT_SIPV4_VAL               0x46C
#define FPGA_RX_FLT_DIPV4_EN                0x470
#define FPGA_RX_FLT_DIPV4_MODE              0x474
#define FPGA_RX_FLT_DIPV4_MSK               0x478
#define FPGA_RX_FLT_DIPV4_VAL               0x47C
#define FPGA_RX_FLT_SIPV6_EN                0x480
#define FPGA_RX_FLT_SIPV6_MODE              0x484
#define FPGA_RX_FLT_SIPV6_MSK0              0x488
#define FPGA_RX_FLT_SIPV6_MSK1              0x48C
#define FPGA_RX_FLT_SIPV6_MSK2              0x490
#define FPGA_RX_FLT_SIPV6_MSK3              0x494
#define FPGA_RX_FLT_SIPV6_VAL0              0x498
#define FPGA_RX_FLT_SIPV6_VAL1              0x49C
#define FPGA_RX_FLT_SIPV6_VAL2              0x4A0
#define FPGA_RX_FLT_SIPV6_VAL3              0x4A4
#define FPGA_RX_FLT_DIPV6_EN                0x4A8
#define FPGA_RX_FLT_DIPV6_MODE              0x4AC
#define FPGA_RX_FLT_DIPV6_MSK0              0x4B0
#define FPGA_RX_FLT_DIPV6_MSK1              0x4B4
#define FPGA_RX_FLT_DIPV6_MSK2              0x4B8
#define FPGA_RX_FLT_DIPV6_MSK3              0x4BC
#define FPGA_RX_FLT_DIPV6_VAL0              0x4C0
#define FPGA_RX_FLT_DIPV6_VAL1              0x4C4
#define FPGA_RX_FLT_DIPV6_VAL2              0x4C8
#define FPGA_RX_FLT_DIPV6_VAL3              0x4CC
#define FPGA_RX_FLT_SPORT_EN                0x4D0
#define FPGA_RX_FLT_SPORT_MODE              0x4D4
#define FPGA_RX_FLT_SPORT_MSK               0x4D8
#define FPGA_RX_FLT_SPORT_VAL               0x4DC
#define FPGA_RX_FLT_DPORT_EN                0x4E0
#define FPGA_RX_FLT_DPORT_MODE              0x4E4
#define FPGA_RX_FLT_DPORT_MSK               0x4E8
#define FPGA_RX_FLT_DPORT_VAL               0x4EC
#define FPGA_RX_FLT_LEN_EN                  0x4F0
#define FPGA_RX_FLT_LEN_MODE                0x4F4
#define FPGA_RX_FLT_LEN_MSK                 0x4F8
#define FPGA_RX_FLT_LEN_VAL                 0x4FC

#define FPGA_RX_FLT0_PKT_LOW                0x380
#define FPGA_RX_FLT0_PKT_HIGH               0x384
#define FPGA_RX_FLT0_BYTE_LOW               0x300
#define FPGA_RX_FLT0_BYTE_HIGH              0x304

/*************************rx stream****************************/
/*************************tx/rx statictis**********************/
#define DEBUG_H2C_TREADY_LOW_SUM_CNT        0x0100
#define DEBUG_H2C_TREADY_HIGH_SUM_CNT       0x0104
#define DEBUG_C2H_TREADY_LOW_SUM_CNT        0x0108
#define DEBUG_C2H_TREADY_HIGH_SUM_CNT       0x010C
#define DEBUG_H2C_TREADY_SEC_CNT            0x0110
#define DEBUG_C2H_TREADY_SEC_CNT            0x0114
#define DEBUG_QDMA0_LOW_TX_CNT              0x0118
#define DEBUG_QDMA0_HIGH_TX_CNT             0x011C
#define DEBUG_QDMA1_LOW_TX_CNT              0x0120
#define DEBUG_QDMA1_HIGH_TX_CNT             0x0124
#define DEBUG_QDMA2_LOW_TX_CNT              0x0128
#define DEBUG_QDMA2_HIGH_TX_CNT             0x012C
#define DEBUG_QDMA3_LOW_TX_CNT              0x0130
#define DEBUG_QDMA3_HIGH_TX_CNT             0x0134
#define DEBUG_QDMA0_LOW_RX_CNT              0x0138
#define DEBUG_QDMA0_HIGH_RX_CNT             0x013C
#define DEBUG_QDMA1_LOW_RX_CNT              0x0140
#define DEBUG_QDMA1_HIGH_RX_CNT             0x0144
#define DEBUG_QDMA2_LOW_RX_CNT              0x0148
#define DEBUG_QDMA2_HIGH_RX_CNT             0x014C
#define DEBUG_QDMA3_LOW_RX_CNT              0x0150
#define DEBUG_QDMA3_HIGH_RX_CNT             0x0154
#define DEBUG_MAC0_LOW_TX_CNT               0x0158
#define DEBUG_MAC0_HIGH_TX_CNT              0x015C
#define DEBUG_MAC1_LOW_TX_CNT               0x0160
#define DEBUG_MAC1_HIGH_TX_CNT              0x0164
#define DEBUG_MAC2_LOW_TX_CNT               0x0168
#define DEBUG_MAC2_HIGH_TX_CNT              0x016C
#define DEBUG_MAC3_LOW_TX_CNT               0x0170
#define DEBUG_MAC3_HIGH_TX_CNT              0x0174
#define DEBUG_MAC0_LOW_RX_CNT               0x0178
#define DEBUG_MAC0_HIGH_RX_CNT              0x017C
#define DEBUG_MAC1_LOW_RX_CNT               0x0180
#define DEBUG_MAC1_HIGH_RX_CNT              0x0184
#define DEBUG_MAC2_LOW_RX_CNT               0x0188
#define DEBUG_MAC2_HIGH_RX_CNT              0x018C
#define DEBUG_MAC3_LOW_RX_CNT               0x0190
#define DEBUG_MAC3_HIGH_RX_CNT              0x0194
#define DEBUG_ADAPTER0_LOW_RX_CNT           0x0198
#define DEBUG_ADAPTER0_HIGH_RX_CNT          0x019C
#define DEBUG_ADAPTER1_LOW_RX_CNT           0x01A0
#define DEBUG_ADAPTER1_HIGH_RX_CNT          0x01A4
#define DEBUG_ADAPTER2_LOW_RX_CNT           0x01A8
#define DEBUG_ADAPTER2_HIGH_RX_CNT          0x01AC
#define DEBUG_ADAPTER3_LOW_RX_CNT           0x01B0
#define DEBUG_ADAPTER3_HIGH_RX_CNT          0x01B4
/*************************tx/rx statictis**********************/

#define FPGA_TX_PKT_LW_WEIGHT_MASK          GENMASK(15, 0)
#define FPGA_TX_PKT_LW_LEN_MASK             GENMASK(31, 16)
#define FPGA_TX_PKT_JUMP_STEP_MASK          GENMASK(15, 0)
#define FPGA_TX_PKT_JUMP_LEN_MASK           GENMASK(19, 16) //4bit
#define FPGA_TX_PKT_JUMP_OFFSET_MASK        GENMASK(30, 24)
#define FPGA_TX_PKT_JUMP_ENABLE_MASK        GENMASK(31, 31)


enum {
    STREAM_TX,
    STREAM_RX,
};

enum card_type {
    XILINX_10G = 0,
    XILINX_25G,
    XILINX_100G,
    ALTERA_400G,
};

enum ynic_pcie_mode {
    YNIC_PCIE4_MODE = 0,
    YNIC_PCIE5_MODE,
};

#define YNIC_PCIE5_BAR2_MAGIC               0x4e540000U

typedef struct port_name {
    u8 port_id;
    u8 adapter_id; //fpga 1分4使用id.
    u8 pf_num;     //fpga 1个pf port数量.
    u8 pcie_mode;  //pcie4/pcie5寄存器访问模式
    //u8 func_id;
    char port_bdf[16]; //0000:01:00.0; port对应的bdf.
    char port_net[20]; //网口的名字.
    void __iomem *bar; //每个网卡的bar空间地址.
    u32 speed;
    enum card_type type;

} port_info;

static const struct pci_device_id md_card_id_table[] = {
    {PCI_DEVICE(NET_VENDOR_ID, PCI_ANY_ID) },
    {PCI_DEVICE(ALTERA_VENDOR_ID, PCI_ANY_ID) },
    {0, }
};
//MODULE_DEVICE_TABLE(pci, md_card_id_table);


static struct cdev cdev;
static uint16_t majorNumber;
static struct class* myClass = NULL;
static struct device* myDevice = NULL;
static unsigned long *ktx_bitmap[YNIC_TOTAL_PORT_NUM]; //tx stream id per port
static unsigned long *krx_bitmap[YNIC_TOTAL_PORT_NUM]; //rx stream id per port
static uint16_t ktx_bitmap_size[YNIC_TOTAL_PORT_NUM];
static uint16_t krx_bitmap_size[YNIC_TOTAL_PORT_NUM];
static spinlock_t ktx_spinlock;
static spinlock_t krx_spinlock;
static struct pci_dev *net_pci_dev = NULL;
static struct port_name *kptnm = NULL;

/*
 * ---- 配置空间监视器（2026-10-22 上板调试）----
 *
 * 目的：卡是"静默"掉线的，dmesg 里没有 AER / link down，说明根端口根本没报事件。
 * 这里用定时器每 watch_ms 读一次端点配置空间 dword0 + 上游桥的 LnkSta/LnkCap，
 * 只在状态变化时打印，从而把"掉线时刻"和"最后一次 MMIO 时刻"对齐。
 *
 * 为什么读配置空间是安全的：pci_bus_read_config_dword() 走 root complex 的 CFG 周期，
 * 不经过 FPGA 的 BAR 解码逻辑；设备已经不在总线上时返回全 1，不会挂死。
 *
 * 持有 pci_dev 引用保证 dev 结构在设备被移除后仍然有效（只是读配置会失败）。
 */
#define YNIC_WATCH_MAX_DEVS  8

struct ynic_watch_dev {
    struct pci_dev *dev;
    struct pci_dev *bridge;   /* 上游根端口，用来读 LnkSta / AER */
    void __iomem   *bar;      /* MMIO 心跳用，可为 NULL */
    int  aer_pos;             /* 根端口 AER 扩展能力偏移，0 = 不支持 */
    u32 last_cfg;
    u32 last_sts;
    u16 last_lnksta;
    u16 last_lnkcap;
    u32 last_ue_sta;          /* AER Uncorrectable Error Status */
    u32 last_ce_sta;          /* AER Correctable Error Status */
    u16 last_sec_sts;         /* Bridge Secondary Status（含 MAbort） */
    u32 last_beat;
    bool last_present;
    bool primed;
};

static struct ynic_watch_dev ynic_watch[YNIC_WATCH_MAX_DEVS];
static int ynic_watch_n;
static struct delayed_work ynic_watch_work;
static int ynic_watch_started;

static void ynic_watch_add(struct pci_dev *dev, void __iomem *bar);
static void ynic_watch_start(void);
static void ynic_watch_stop(void);

static inline bool ynic_is_pcie5_mode(u8 pcie_mode)
{
    return pcie_mode == YNIC_PCIE5_MODE;
}

static inline u64 ynic_adjust_reg_offset(u8 pcie_mode, u64 offset)
{
    return ynic_is_pcie5_mode(pcie_mode) ? (offset << 1) : offset;
}

static inline u32 ynic_hw_read32_mode(void __iomem *bar, u8 pcie_mode, u64 offset)
{
    u64 adj = ynic_adjust_reg_offset(pcie_mode, offset);
    void __iomem *addr = bar + adj;
    u32 val;
    int n;

    val = ioread32(addr);

    atomic_inc(&ynic_dbg_mmio_total);
    /* 全 1 / deadbeef 是链路已断的典型读数，无论是否超限都记录 */
    if (unlikely(val == 0xffffffffU || val == 0xdeadbeefU)) {
        n = atomic_inc_return(&ynic_dbg_mmio_anom);
        if (n <= 32)
            YNIC_ERRL(YNIC_DBG_MMIO, "MMIO RD  ANOMALY off=0x%llx(adj=0x%llx) val=0x%08x (mode=%u, count=%d)\n",
                     (unsigned long long)offset, (unsigned long long)adj, val, pcie_mode, n);
    } else {
        n = atomic_inc_return(&ynic_dbg_mmio_logged);
        if (n <= dbg_mmio_max)
            YNIC_LOG(YNIC_DBG_MMIO, "MMIO RD  off=0x%llx(adj=0x%llx) val=0x%08x (mode=%u)\n",
                    (unsigned long long)offset, (unsigned long long)adj, val, pcie_mode);
    }

    return val;
}

static inline void ynic_hw_write32_mode(void __iomem *bar, u8 pcie_mode, u32 val, u64 offset)
{
    u64 adj = ynic_adjust_reg_offset(pcie_mode, offset);
    void __iomem *addr = bar + adj;
    int n;

    n = atomic_inc_return(&ynic_dbg_mmio_logged);
    if (n <= dbg_mmio_max)
        YNIC_LOG(YNIC_DBG_MMIO, "MMIO WR  off=0x%llx(adj=0x%llx) val=0x%08x (mode=%u)\n",
                (unsigned long long)offset, (unsigned long long)adj, val, pcie_mode);

    if (ynic_is_pcie5_mode(pcie_mode)) {
        /* pcie5 currently keeps 32-bit MMIO accesses; preserve the branch for future 64-bit access enablement. */
        iowrite32(val, addr);
        return;
    }

    iowrite32(val, addr);
}

static inline u8 ynic_detect_pcie_mode(void __iomem *bar)
{
    u32 magic = ioread32(bar);
    u8 mode = (magic == YNIC_PCIE5_BAR2_MAGIC) ? YNIC_PCIE5_MODE : YNIC_PCIE4_MODE;

    /* 这一步是模块加载后第一条 MMIO 读，单独记录，便于区分"卡在 ioremap 之后就没响应" */
    if (unlikely(magic == 0xffffffffU))
        YNIC_ERRL(YNIC_DBG_LIFE, "detect_pcie_mode: bar[0]=0x%08x -> DEVICE NOT RESPONDING (pcie4 assumed)\n", magic);
    else
        YNIC_LOG(YNIC_DBG_LIFE, "detect_pcie_mode: bar[0]=0x%08x -> %s\n",
                magic, mode == YNIC_PCIE5_MODE ? "PCIE5" : "PCIE4");

    return mode;
}


/* Net device */
struct nt_net_struct
{
    char *name;
    int refcnt;
    wait_queue_head_t read_wait;
    unsigned char rx_data;
    struct net_device *dev;
#if LINUX_VERSION_CODE >= KERNEL_VERSION(2, 6, 30)
    struct net *net;
#endif
#if LINUX_VERSION_CODE < KERNEL_VERSION(2, 6, 26)
    struct net_device_stats stats;
#endif
};

#ifndef NETDEV_TX_OK
#define NETDEV_TX_OK 0
#endif

#if LINUX_VERSION_CODE < KERNEL_VERSION(2, 6, 26)
static struct net_device_stats *ntnet_net_stats(struct net_device *dev)
{
    struct nt_net_struct *ntnet = netdev_priv(dev);
    return &ntnet->stats;
}
#endif

static int ynic_open(struct inode *inode, struct file *file)
{
    //KDBG("ntnetdrv device has been opened\n");
    file->private_data = NULL;
    return 0;
}

static int ynic_close(struct inode *inode, struct file *file)
{
    struct nt_net_struct *ntnet = (struct nt_net_struct *)file->private_data;
    //KDBG("ntnetdrv device has been closed\n");

    if (ntnet)
    {
        rtnl_lock();
        if (--ntnet->refcnt == 0)
        {
            KDBG("unregister ntnet\n");
            dev_close(ntnet->dev);
            unregister_netdevice(ntnet->dev);
            file->private_data = NULL;
        }
        rtnl_unlock();
    }
    return 0;
}

/* Helper function to get stream capacity based on link speed */
static inline uint16_t ynic_get_stream_capacity(u32 speed)
{
    if (speed & (MD_LINK_SPEED_400G | MD_LINK_SPEED_200G))
        return MAX_STREAM_PER_PORT_400G;
    else if (speed & (MD_LINK_SPEED_100G | MD_LINK_SPEED_50G | MD_LINK_SPEED_40G))
        return MAX_STREAM_PER_PORT_100G;
    else
        return MAX_STREAM_PER_PORT;
}

/*
 * get stream bus number and func id
 */
static int ynic_get_net_bdf(uint8_t flag, uint32_t stream_id, port_info *info)
{
    int ret = YNIC_ERR;
    uint8_t port_id;
    uint32_t domain,bus,dev,func;

    if(!info) {
        printk(KERN_ERR "[%s] input paras is NULL.\n",__func__);
        return YNIC_ERR;
    }

    if(flag == STREAM_TX) {
        port_id = (stream_id - 1) / MAX_STREAM_PER_PORT_400G;
    } else if(flag == STREAM_RX) {
        port_id = (stream_id - 1) / MAX_STREAM_PER_PORT_400G;
    }

    if(port_id != kptnm[port_id].port_id) {
        printk(KERN_ERR "[%s] port id Invalid,user:%d,kernel:%d,stream_id=%d\n", 
                __func__, port_id, kptnm[port_id].port_id, stream_id);
        return YNIC_ERR;

    }

    if(kptnm[port_id].port_bdf == NULL || kptnm[port_id].port_bdf[0] == '\0') {
        printk(KERN_ERR "[%s] stream id %d,port id %d Invalid.\n", __func__, stream_id, port_id);
        return YNIC_ERR;
    }
    strscpy(info->port_bdf, kptnm[port_id].port_bdf, sizeof(kptnm[port_id].port_bdf));
    info->port_id = kptnm[port_id].port_id;
    info->adapter_id = kptnm[port_id].adapter_id;
    info->pf_num = kptnm[port_id].pf_num;
    info->type = kptnm[port_id].type;
    info->pcie_mode = kptnm[port_id].pcie_mode;

    if (sscanf(kptnm[port_id].port_bdf, "%04x:%02x:%02x.%01x", &domain, &bus, &dev, &func) != 4) {
        printk(KERN_ERR "pci device %s Invalid.\n", kptnm[port_id].port_bdf);
        return -EINVAL;
    }

    if(func >=0 && func <= 7) {
        ret = func;
    }

    return ret;
}

/*
 * 向fpga网卡写入一个数据
 */
static int ynic_write_fpga_byte(uint8_t flag, uint32_t stream_id, uint32_t val, uint64_t offset)
{
    void __iomem *bar = NULL;
    uint8_t port_id;

    if(flag == STREAM_TX) {
        port_id = (stream_id - 1) / MAX_STREAM_PER_PORT_400G;
    } else if(flag == STREAM_RX) {
        port_id = (stream_id - 1) / MAX_STREAM_PER_PORT_400G;
    }

    bar = kptnm[port_id].bar;
    if (!bar) {
        pr_err("Failed to map BAR\n");
        return -ENOMEM;
    }

    //printk("write addr=0x%llx,offset=0x%08x,val=0x%08x\n",(unsigned long long)(bar + offset),offset, val);
    //写单个数据
    ynic_hw_write32_mode(bar, kptnm[port_id].pcie_mode, val, offset); // offset 是要写入的偏移量

    return 0;
}

/*
 * 向fpga网卡写入多个数据
 */
static int ynic_write_fpga_data(int flag, int stream_id, uint32_t *val, uint32_t len, uint64_t offset)
{
    void __iomem *bar = NULL;
    void __iomem *write_addr = NULL;
    int i = 0;
    uint8_t port_id;

    if(flag == STREAM_TX) {
        port_id = (stream_id - 1) / MAX_STREAM_PER_PORT_400G;
    } else if(flag == STREAM_RX) {
        port_id = (stream_id - 1) / MAX_STREAM_PER_PORT_400G;
    }

    bar = kptnm[port_id].bar;
    if (!bar) {
        pr_err("Failed to map BAR\n");
        return -ENOMEM;
    }
    //printk("KERN_ess: bar: 0x%llx\n", (unsigned long long)bar);

    write_addr = bar + ynic_adjust_reg_offset(kptnm[port_id].pcie_mode, offset);
    for(i=0; i<len; i++) {
        // printk(KERN_INFO " 0x%08x,",val[i]);
        // iowrite32(*(val+i), (write_addr+(i * 4)));
        if (ynic_is_pcie5_mode(kptnm[port_id].pcie_mode))
            iowrite32(*(val+i), write_addr); // pcie5 keeps 32-bit MMIO for now
        else
            iowrite32(*(val+i), write_addr); //向同一个地址循环写数据
        // printk(" 0x%04x",(0xa0+i*16));
    }

    return 0;
}

/*
 * 从fpga网卡读取一个数据
 */
static int ynic_read_fpga_byte(uint8_t flag, uint32_t stream_id, uint32_t *val, uint64_t offset)
{
    void __iomem *bar = NULL;
    uint8_t port_id;

    if(flag == STREAM_TX) {
        port_id = (stream_id - 1) / MAX_STREAM_PER_PORT_400G;
    } else if(flag == STREAM_RX) {
        port_id = (stream_id - 1) / MAX_STREAM_PER_PORT_400G;
    }

    bar = kptnm[port_id].bar;
    if (!bar) {
        pr_err("Failed to map BAR\n");
        return -ENOMEM;
    }

    //读单个数据
    *val = ynic_hw_read32_mode(bar, kptnm[port_id].pcie_mode, offset);
    //printk("read addr=0x%llx,offset=0x%08x,val=0x%08x\n",(unsigned long long)(bar + offset), offset, *val);

    return 0;
}


/*
 * 从fpga网卡读取多个数据
 */
static inline int
ynic_read_fpga_data(uint8_t flag, uint32_t stream_id, uint32_t *val, uint32_t len, uint64_t offset)
{
    void __iomem *bar = NULL;
    void __iomem *read_addr = NULL;
    int i = 0;
    uint8_t port_id;

    if(flag == STREAM_TX) {
        port_id = (stream_id - 1) / MAX_STREAM_PER_PORT_400G;
    } else if(flag == STREAM_RX) {
        port_id = (stream_id - 1) / MAX_STREAM_PER_PORT_400G;
    }

    bar = kptnm[port_id].bar;
    if (!bar) {
        pr_err("Failed to map BAR\n");
        return -ENOMEM;
    }

    read_addr = bar + ynic_adjust_reg_offset(kptnm[port_id].pcie_mode, offset);
    for(i=0; i < len; i++) {
        // printk(KERN_INFO " 0x%08x,",val[i]);
        // *(val+i) = ioread32(write_addr+(i * 4));
        if (ynic_is_pcie5_mode(kptnm[port_id].pcie_mode))
            *(val+i) = ioread32(read_addr); // pcie5 keeps 32-bit MMIO for now
        else
            *(val+i) = ioread32(read_addr);
    }

    return 0;
}

static int ynic_write_byte_by_pciid(char *pciid, uint32_t val, uint64_t offset, uint64_t off_base)
{
    struct pci_dev *pdev = NULL;
    void __iomem *bar;
    uint32_t domain,bus,devfn,dev,func;
    uint8_t i;
    uint8_t port_id = 0;

    if(!pciid) {
        printk(KERN_ERR "pci device Invalid.\n");
    }

    if (sscanf(pciid, "%04x:%02x:%02x.%01x", &domain, &bus, &dev, &func) != 4) {
        printk(KERN_ERR "pci device %s Invalid.\n", pciid);
        return -EINVAL;
    }

    devfn = PCI_DEVFN(dev, func);
    pdev = pci_get_domain_bus_and_slot(domain, bus, devfn);
    if(!pdev) {
        printk(KERN_ERR "pci device not found.\n");
        return -EINVAL;
    }

    for(i=0;i<YNIC_TOTAL_PORT_NUM;i++) {
        if(strncmp(pciid, kptnm[i].port_bdf, strlen(pciid)) == 0) {
            port_id = i;
        }
    }
    if((kptnm[port_id].type >= XILINX_10G) && (kptnm[port_id].type <= ALTERA_400G)) {
        if(kptnm[port_id].type == ALTERA_400G) {
            if(off_base == FPGA_TX_OFFSET) {
                offset += (func * off_base + FPGA_TX_BASE_ALTERA);
            } else if(off_base == FPGA_RX_OFFSET) {
                offset += (func * off_base + FPGA_RX_BASE_ALTERA);
            } else {
                offset += (func * off_base + FPGA_SYS_BASE_ALTERA);
            }
        } else {
            if(off_base == FPGA_TX_OFFSET) {
                offset += (func * off_base + FPGA_TX_BASE_XILINX);
            } else if(off_base == FPGA_RX_OFFSET) {
                offset += (func * off_base + FPGA_RX_BASE_XILINX);
            } else {
                offset += (func * off_base);
            }
        }
    }

    bar = kptnm[port_id].bar;
    if (!bar) {
        pr_err("Failed to map BAR\n");
        return -ENOMEM;
    }

    //写单个数据
    ynic_hw_write32_mode(bar, kptnm[port_id].pcie_mode, val, offset);

    pci_dev_put(pdev);

    return 0;
}

static int ynic_read_byte_by_pciid(char *pciid, uint32_t *val, uint64_t offset, uint64_t off_base)
{
    struct pci_dev *pdev = NULL;
    void __iomem *bar;
    uint32_t domain,bus,devfn,dev,func;
    uint8_t i;
    uint8_t port_id = 0;

    if(!pciid) {
        printk(KERN_ERR "pci device Invalid.\n");
    }

    if (sscanf(pciid, "%04x:%02x:%02x.%01x", &domain, &bus, &dev, &func) != 4) {
        printk(KERN_ERR "pci device %s Invalid.\n", pciid);
        return -EINVAL;
    }

    devfn = PCI_DEVFN(dev, func);
    pdev = pci_get_domain_bus_and_slot(domain, bus, devfn);
    if(!pdev) {
        printk(KERN_ERR "pci device not found.\n");
        return -EINVAL;
    }

    for(i=0;i<YNIC_TOTAL_PORT_NUM;i++) {
        if(strncmp(pciid, kptnm[i].port_bdf, strlen(pciid)) == 0) {
            port_id = i;
        }
    }
    if((kptnm[port_id].type >= XILINX_10G) && (kptnm[port_id].type <= ALTERA_400G)) {
        if(kptnm[port_id].type == ALTERA_400G) {
            if(off_base == FPGA_TX_OFFSET) {
                offset += (func * off_base + FPGA_TX_BASE_ALTERA);
            } else if(off_base == FPGA_RX_OFFSET) {
                offset += (func * off_base + FPGA_RX_BASE_ALTERA);
            } else {
                offset += (func * off_base + FPGA_SYS_BASE_ALTERA);
            }
        } else {
            if(off_base == FPGA_TX_OFFSET) {
                offset += (func * off_base + FPGA_TX_BASE_XILINX);
            } else if(off_base == FPGA_RX_OFFSET) {
                offset += (func * off_base + FPGA_RX_BASE_XILINX);
            } else {
                offset += (func * off_base);
            }
        }
    }

    bar = kptnm[port_id].bar;
    if (!bar) {
        pr_err("Failed to map BAR\n");
        return -ENOMEM;
    }

    //读单个数据
    *val = ynic_hw_read32_mode(bar, kptnm[port_id].pcie_mode, offset);

    pci_dev_put(pdev);

    return 0;
}

/*
 * 大端字节序
 */
static void ynic_convert_to_uint32(uint8_t *data, uint32_t *result, uint32_t length)
{
    uint32_t i = 0;
    uint32_t index = 0;
    uint32_t count = length / 4;
    uint32_t remain = length % 4;
    for (i = 0; i < count; i++) {
        index = i * 4;
        // 将四个 uint8_t 合并为一个 uint32_t
        result[i] = data[index] | (data[index + 1] << 8) | (data[index + 2] << 16) | (data[index + 3] << 24);
        // printk(KERN_INFO " 0x%08x", result[i]);
    }
    if(remain > 0) {
        // 处理剩余的数据
        index = count * 4;
        result[count] = 0;
        for(i = 0; i < remain; i++) {
            result[count] |= data[index + i] << (i * 8);
        }
    }
}

/*
 * 获取新的mac地址
 */
int ynic_get_mac(char *base_mac, char *new_mac, uint32_t count)
{
    int ret = YNIC_SUC;
    unsigned char mac_bytes[6];
    uint64_t mac_num;
    int len;

    if (sscanf(base_mac, "%02hhx:%02hhx:%02hhx:%02hhx:%02hhx:%02hhx",
               &mac_bytes[0], &mac_bytes[1], &mac_bytes[2],
               &mac_bytes[3], &mac_bytes[4], &mac_bytes[5]) != 6) {
        printk("MAC address Invalid\n");
        ret = YNIC_ERR;
        return ret;
    }

    mac_num = ((uint64_t)mac_bytes[0] << 40) |
              ((uint64_t)mac_bytes[1] << 32) |
              ((uint64_t)mac_bytes[2] << 24) |
              ((uint64_t)mac_bytes[3] << 16) |
              ((uint64_t)mac_bytes[4] << 8)  |
                         mac_bytes[5];

    mac_num += count;

    mac_bytes[0] = (mac_num >> 40) & 0xFF;
    mac_bytes[1] = (mac_num >> 32) & 0xFF;
    mac_bytes[2] = (mac_num >> 24) & 0xFF;
    mac_bytes[3] = (mac_num >> 16) & 0xFF;
    mac_bytes[4] = (mac_num >> 8) & 0xFF;
    mac_bytes[5] = mac_num & 0xFF;


    len = snprintf(NULL, 0, "%02hhx:%02hhx:%02hhx:%02hhx:%02hhx:%02hhx",
            mac_bytes[0], mac_bytes[1], mac_bytes[2], mac_bytes[3], mac_bytes[4], mac_bytes[5]);
    snprintf(new_mac, (len+1), "%02hhx:%02hhx:%02hhx:%02hhx:%02hhx:%02hhx",
            mac_bytes[0], mac_bytes[1], mac_bytes[2], mac_bytes[3], mac_bytes[4], mac_bytes[5]);

    return ret;
}

/*
 * 获取系统中NUMA节点的数量
 */
int ynic_get_sys_numa(void)
{
    int node;
    int cnt = 0;

    for_each_online_node(node) {
        cnt++;
        //printk(KERN_INFO "Online NUMA node: %d,count: %d\n", node, cnt);
    }
    return cnt;
}

/* 获取网卡信息
 * 多个网卡信息处理
 * 系统中NUMA节点
 * 系统中网卡：bus number+vendor_id
 * 系统中网口：pci扫描的同一个厂家的设备数量
 */
int ynic_get_sys_card_info(uint32_t vendor_id, ynic_nsdev_t *knsdev)
{
    int ret = YNIC_SUC;
    struct pci_dev *dev = NULL;
    int domain = 0;
    int num = 0;
    int prev_domain = -1;
    int prev_num = -1;
    int nic = -1;   //第n个网卡的网卡号，从0开始
    int prev_nic = -1;
    int port = 0;   //每个网卡的网口号
    void __iomem *bar = NULL;
    u8 pcie_mode = YNIC_PCIE4_MODE;
    uint32_t val,val1;
    int func_id;
    uint32_t kspd = 0;
    uint32_t model = 0;
    uint16_t mport=0, mspeed=0, miftype=0, mhwver=0;
    uint16_t kmulpt = 0;
    char ori_mac[40] = {0},new_mac[40] = {0};
    // pcie5 uses 64-bit accesses on BAR2 with shifted register offsets.
    char kspeed[20] = {0};
    uint16_t link = 0,link_pos = 0;
    uint8_t count = 0;
    int j;
    const struct pci_device_id *id;

    for(id = md_card_id_table; id->vendor != 0; id++) {
        // 使用 pci_get_device 遍历所有设备
        dev = pci_get_device(id->vendor, PCI_ANY_ID, NULL);
        while (dev) {
            domain = pci_domain_nr(dev->bus);
            num = dev->bus->number; //设备总线号
            if(prev_domain != domain || prev_num != num) {
                prev_domain = domain;
                prev_num = num;
                nic++; //bus号改变，网卡数量+1
                if (nic >= MAX_FPGA_ADAPTER) {
                    pr_err("Adapter index overflow: nic=%d max=%d for %04x:%02x:%02x.%01x\n",
                           nic, MAX_FPGA_ADAPTER, pci_domain_nr(dev->bus), dev->bus->number,
                           PCI_SLOT(dev->devfn), PCI_FUNC(dev->devfn));
                    if (bar != NULL)
                        iounmap(bar);
                    return -EINVAL;
                }
                port = 0; //每个网卡port从0开始
                (knsdev->nb_adapters)++;

                if(bar != NULL) {
                    iounmap(bar);
                }
                bar = pci_ioremap_bar(dev, 2);
                if (!bar) {
                    pr_err("Failed to map BAR\n");
                    return -ENOMEM;
                }
                pcie_mode = ynic_detect_pcie_mode(bar);
                link_pos = 0;
                if(id->vendor == ALTERA_VENDOR_ID) {
                    link = ynic_hw_read32_mode(bar, pcie_mode, ALTERA_FPGA_LINK_REG) & 0x1;
                    kspd = ynic_hw_read32_mode(bar, pcie_mode, FPGA_PORT_SPEED_REG + FPGA_SYS_BASE_ALTERA);
                } else {
                    link = ynic_hw_read32_mode(bar, pcie_mode, FPGA_LINK_REG);
                    kspd = ynic_hw_read32_mode(bar, pcie_mode, FPGA_PORT_SPEED_REG);
                }
                if((kspd > MD_LINK_SPEED_UNKNOWN) && (kspd < MD_LINK_SPEED_END)) {
                    if(kspd == MD_LINK_SPEED_10M) {
                        snprintf(kspeed, sizeof(kspeed), "%s", "10");
                    } else if(kspd == MD_LINK_SPEED_100M) {
                        snprintf(kspeed, sizeof(kspeed), "%s", "100");
                    } else if(kspd == MD_LINK_SPEED_1G) {
                        snprintf(kspeed, sizeof(kspeed), "%s", "1000");
                    } else if(kspd == MD_LINK_SPEED_10G) {
                        snprintf(kspeed, sizeof(kspeed), "%s", "10000");
                    } else if(kspd == MD_LINK_SPEED_40G) {
                        snprintf(kspeed, sizeof(kspeed), "%s", "40000");
                    } else if(kspd == MD_LINK_SPEED_100G) {
                        snprintf(kspeed, sizeof(kspeed), "%s", "100000");
                    } else if(kspd == MD_LINK_SPEED_50G) {
                        snprintf(kspeed, sizeof(kspeed), "%s", "50000");
                    } else if(kspd == MD_LINK_SPEED_25G) {
                        snprintf(kspeed, sizeof(kspeed), "%s", "25000");
                    } else if(kspd == MD_LINK_SPEED_200G) {
                        snprintf(kspeed, sizeof(kspeed), "%s", "200000");
                    } else if(kspd == MD_LINK_SPEED_400G) {
                        snprintf(kspeed, sizeof(kspeed), "%s", "400000");
                    } else if(kspd == MD_LINK_SPEED_2D5G) {
                        snprintf(kspeed, sizeof(kspeed), "%s", "2500");
                    }
                } else {
                    snprintf(kspeed, sizeof(kspeed), "%s", "unknown");
                }
                //pr_cont("nic%d,speed=%s,",nic,kspeed);
            }

                //网卡的网口处理
            func_id = PCI_FUNC(dev->devfn);
            if(id->vendor == ALTERA_VENDOR_ID) {
                kmulpt = ynic_hw_read32_mode(bar, pcie_mode, FPGA_PORT_PF0_NUM_REG + (func_id * 4) + FPGA_SYS_BASE_ALTERA); //每个pf分出几个port
                val = ynic_hw_read32_mode(bar, pcie_mode, FPGA_SECTOR_REG_ALTERA + (func_id * FPGA_MAC_SIZE));
                val1 = ynic_hw_read32_mode(bar, pcie_mode, FPGA_SECTOR_REG_ALTERA + (func_id * FPGA_MAC_SIZE) + 4);
            } else {
                kmulpt = ynic_hw_read32_mode(bar, pcie_mode, FPGA_PORT_PF0_NUM_REG + (func_id * 4)); //每个pf分出几个port
                val = ynic_hw_read32_mode(bar, pcie_mode, FPGA_SECTOR_REG + (func_id * FPGA_MAC_SIZE));
                val1 = ynic_hw_read32_mode(bar, pcie_mode, FPGA_SECTOR_REG + (func_id * FPGA_MAC_SIZE) + 4);
            }
            if (kmulpt == 0 || kmulpt > MAX_PORT_PER_ADP) {
                pr_err("Invalid kmulpt=%u for %04x:%02x:%02x.%01x\n",
                       kmulpt, pci_domain_nr(dev->bus), dev->bus->number,
                       PCI_SLOT(dev->devfn), PCI_FUNC(dev->devfn));
                if (bar != NULL)
                    iounmap(bar);
                return -EINVAL;
            }
            if (port >= MAX_PORT_PER_ADP || knsdev->nb_ports >= YNIC_TOTAL_PORT_NUM) {
                pr_err("Port index overflow before PF init: nic=%d port=%d nb_ports=%d max_port=%d max_sysport=%d for %04x:%02x:%02x.%01x\n",
                       nic, port, knsdev->nb_ports, MAX_PORT_PER_ADP, YNIC_TOTAL_PORT_NUM,
                       pci_domain_nr(dev->bus), dev->bus->number, PCI_SLOT(dev->devfn), PCI_FUNC(dev->devfn));
                if (bar != NULL)
                    iounmap(bar);
                return -EINVAL;
            }
            knsdev->ynic_adapter[nic].ynic_port[port].system_portid = knsdev->nb_ports; /*系统id号,不重复*/
            knsdev->ynic_adapter[nic].ynic_port[port].adapter_portid = port; /*每个网卡的port号*/
            knsdev->ynic_adapter[nic].ynic_port[port].enable = 1;
            knsdev->ynic_adapter[nic].ynic_port[port].ispcie5 = pcie_mode;
            strscpy(knsdev->ynic_adapter[nic].ynic_port[port].port_speed, kspeed, sizeof(knsdev->ynic_adapter[nic].ynic_port[port].port_speed));
            snprintf(knsdev->ynic_adapter[nic].ynic_port[port].port_status, sizeof(knsdev->ynic_adapter[nic].ynic_port[port].port_status), "%s" , ((((link >> link_pos) & 0x1) == 0x1) ? "up" : "down"));
            link_pos++;
            snprintf(knsdev->ynic_adapter[nic].ynic_port[port].port_duplex, sizeof(knsdev->ynic_adapter[nic].ynic_port[port].port_duplex), "%d" , 0x1);
            snprintf(knsdev->ynic_adapter[nic].ynic_port[port].port_mac, sizeof(knsdev->ynic_adapter[nic].ynic_port[port].port_mac), "%02x:%02x:%02x:%02x:%02x:%02x",
                    (val & 0xff), ((val >> 8) & 0xff), ((val >> 16) & 0xff), ((val >> 24) & 0xff),
                    (val1 & 0xff), ((val1 >> 8) & 0xff));
            snprintf(knsdev->ynic_adapter[nic].ynic_port[port].port_bus, sizeof(knsdev->ynic_adapter[nic].ynic_port[port].port_bus),
                    "%04x:%02x:%02x.%01x", pci_domain_nr(dev->bus), dev->bus->number, PCI_SLOT(dev->devfn), PCI_FUNC(dev->devfn));
            if(kmulpt > 1) {
                knsdev->ynic_adapter[nic].ynic_port[port].portoffset = (func_id * kmulpt);
            }
            //获取系统上Xilinx卡的bdf.
            port++;
            knsdev->ynic_adapter[nic].nb_ports = port;//每个网卡网口总数量
            (knsdev->nb_ports)++;

            if(kmulpt > 1) {
                strscpy(ori_mac, knsdev->ynic_adapter[nic].ynic_port[port-1].port_mac, sizeof(knsdev->ynic_adapter[nic].ynic_port[port-1].port_mac));
                //strscpy(ori_name, knsdev->ynic_adapter[nic].ynic_port[port-1].port_name, sizeof(knsdev->ynic_adapter[nic].ynic_port[port-1].port_name));
                for(int i=1;i<kmulpt;i++) {
                    if (port >= MAX_PORT_PER_ADP || knsdev->nb_ports >= YNIC_TOTAL_PORT_NUM) {
                        pr_err("Port index overflow during PF expansion: nic=%d port=%d nb_ports=%d max_port=%d max_sysport=%d for %04x:%02x:%02x.%01x\n",
                               nic, port, knsdev->nb_ports, MAX_PORT_PER_ADP, YNIC_TOTAL_PORT_NUM,
                               pci_domain_nr(dev->bus), dev->bus->number, PCI_SLOT(dev->devfn), PCI_FUNC(dev->devfn));
                        if (bar != NULL)
                            iounmap(bar);
                        return -EINVAL;
                    }
                    knsdev->ynic_adapter[nic].ynic_port[port].system_portid = knsdev->nb_ports; /*系统id号,不重复*/
                    knsdev->ynic_adapter[nic].ynic_port[port].adapter_portid = port; /*每个网卡的port号*/
                    knsdev->ynic_adapter[nic].ynic_port[port].enable = 1;
                    knsdev->ynic_adapter[nic].ynic_port[port].ispcie5 = pcie_mode;
                    strscpy(knsdev->ynic_adapter[nic].ynic_port[port].port_speed, kspeed, sizeof(knsdev->ynic_adapter[nic].ynic_port[port].port_speed));
                    snprintf(knsdev->ynic_adapter[nic].ynic_port[port].port_status, sizeof(knsdev->ynic_adapter[nic].ynic_port[port].port_status), "%s" , ((((link >> link_pos) & 0x1) == 0x1) ? "up" : "down"));
                    snprintf(knsdev->ynic_adapter[nic].ynic_port[port].port_duplex, sizeof(knsdev->ynic_adapter[nic].ynic_port[port].port_duplex), "%d" , 0x1);
                    //snprintf(knsdev->ynic_adapter[nic].ynic_port[port].port_name, sizeof(knsdev->ynic_adapter[nic].ynic_port[port].port_name), "%s", ori_name);
                    ynic_get_mac(ori_mac, new_mac, i);
                    snprintf(knsdev->ynic_adapter[nic].ynic_port[port].port_mac, sizeof(knsdev->ynic_adapter[nic].ynic_port[port].port_mac), "%s", new_mac);
                    snprintf(knsdev->ynic_adapter[nic].ynic_port[port].port_bus, sizeof(knsdev->ynic_adapter[nic].ynic_port[port].port_bus),
                        "%04x:%02x:%02x.%01x", pci_domain_nr(dev->bus), dev->bus->number, PCI_SLOT(dev->devfn), PCI_FUNC(dev->devfn));
                    knsdev->ynic_adapter[nic].ynic_port[port].portoffset = (func_id * kmulpt);
                    link_pos++;

                    port++;
                    knsdev->ynic_adapter[nic].nb_ports = port;
                    (knsdev->nb_ports)++;
                }
            }

            //网卡处理
            if(prev_nic != nic) {
                prev_nic = nic;
                //第一个网卡的第一个网口
                if(id->vendor == ALTERA_VENDOR_ID) {
                    model = ynic_hw_read32_mode(bar, pcie_mode, FPGA_MODEL_REG + FPGA_SYS_BASE_ALTERA);
                    count = ynic_hw_read32_mode(bar, pcie_mode, FPGA_SECTOR_REG_ALTERA + FPGA_IMAGE_REG);
                    for(j=0;j<YNIC_VERSION_LEN;j+=4) {

                        if(count == 2 || count == 3) {
                            val = ynic_hw_read32_mode(bar, pcie_mode, (FPGA_FIRMWARE_REG_ALTERA * (count-1)) + j);
                        } else {
                            val = ynic_hw_read32_mode(bar, pcie_mode, FPGA_FIRMWARE_REG_ALTERA + j);
                        }
                        memcpy((knsdev->ynic_adapter[nic].fpga_partnum + j), &val, 4);
                    }
                } else {
                    model = ynic_hw_read32_mode(bar, pcie_mode, FPGA_MODEL_REG);
                    count = ynic_hw_read32_mode(bar, pcie_mode, FPGA_SECTOR_REG + FPGA_IMAGE_REG);
                    for(j=0;j<YNIC_VERSION_LEN;j+=4) {

                        if(count == 2 || count == 3) {
                            val = ynic_hw_read32_mode(bar, pcie_mode, (FPGA_FIRMWARE_REG * (count-1)) + j);
                        } else {
                            val = ynic_hw_read32_mode(bar, pcie_mode, FPGA_FIRMWARE_REG + j);
                        }
                        memcpy((knsdev->ynic_adapter[nic].fpga_partnum + j), &val, 4);
                    }
                }
                mspeed = (model >> 12) & 0xf;   //网卡类型:速度
                mport = (model >> 8) & 0xf;     //网卡类型:port数量
                miftype = (model >> 6) & 0x3;   //网卡类型:光或电
                mhwver =  model & 0xf;          //网卡类型:A,B,C
                //printk("model=0x%08x,mspeed=%d,mport=%d,miftype=%d\n",model,mspeed,mport,miftype);
                switch (mspeed) {
                    case 0: /* 10G card */
                        if (mport != 4) {
                            printk(KERN_ERR "Network Card port %u speed %u Invalid.\n", mport, mspeed);
                            knsdev->ynic_adapter[nic].adapter_type = YNIC_ADAPTER_TYPE_UNKNOWN;
                            break;
                        }
                        if (kspd == MD_LINK_SPEED_10G) {
                            knsdev->ynic_adapter[nic].adapter_type = YNIC_ADAPTER_MD4X010GF27LA_4X10G;
                        } else if (kspd == MD_LINK_SPEED_1G) {
                            if (miftype == 0) {
                                knsdev->ynic_adapter[nic].adapter_type = YNIC_ADAPTER_MD4X010GF27LA_4X1G;
                            } else if (miftype == 1) {
                                knsdev->ynic_adapter[nic].adapter_type = YNIC_ADAPTER_MD4X001GC27LA_4X1G;
                            } else {
                                printk(KERN_ERR "Network Card iftype %u Invalid.\n", miftype);
                                knsdev->ynic_adapter[nic].adapter_type = YNIC_ADAPTER_TYPE_UNKNOWN;
                            }
                        } else {
                            printk(KERN_ERR "Network Card actual speed %u Invalid.\n", kspd);
                            knsdev->ynic_adapter[nic].adapter_type = YNIC_ADAPTER_TYPE_UNKNOWN;
                        }
                        break;

                    case 1: /* 25G card */
                        if (mport == 2) {
                            if (kspd == MD_LINK_SPEED_25G) {
                                knsdev->ynic_adapter[nic].adapter_type = YNIC_ADAPTER_MD2X025GF27LA_2X25G;
                            } else if (kspd == MD_LINK_SPEED_10G) {
                                knsdev->ynic_adapter[nic].adapter_type = YNIC_ADAPTER_MD2X025GF27LA_2X10G;
                            } else if (kspd == MD_LINK_SPEED_1G) {
                                knsdev->ynic_adapter[nic].adapter_type = YNIC_ADAPTER_MD2X025GF27LA_2X1G;
                            } else if (kspd == MD_LINK_SPEED_2D5G) {
                                knsdev->ynic_adapter[nic].adapter_type = YNIC_ADAPTER_MD2X025GF27LA_2X2D5G;
                            } else {
                                printk(KERN_ERR "Network Card actual speed %u Invalid.\n", kspd);
                                knsdev->ynic_adapter[nic].adapter_type = YNIC_ADAPTER_TYPE_UNKNOWN;
                            }
                        } else if (mport == 4) {
                            if (mhwver == 0) {
                                if (kspd == MD_LINK_SPEED_25G) {
                                    knsdev->ynic_adapter[nic].adapter_type = YNIC_ADAPTER_MD4X025GF27LA_4X25G;
                                } else if (kspd == MD_LINK_SPEED_10G) {
                                    knsdev->ynic_adapter[nic].adapter_type = YNIC_ADAPTER_MD4X025GF27LA_4X10G;
                                } else if (kspd == MD_LINK_SPEED_1G) {
                                    knsdev->ynic_adapter[nic].adapter_type = YNIC_ADAPTER_MD4X025GF27LA_4X1G;
                                } else if (kspd == MD_LINK_SPEED_2D5G) {
                                    knsdev->ynic_adapter[nic].adapter_type = YNIC_ADAPTER_MD4X025GF27LA_4X2D5G;
                                } else {
                                    printk(KERN_ERR "Network Card actual speed %u Invalid.\n", kspd);
                                    knsdev->ynic_adapter[nic].adapter_type = YNIC_ADAPTER_TYPE_UNKNOWN;
                                }
                            } else if (mhwver == 1) {
                                if (kspd == MD_LINK_SPEED_25G) {
                                    knsdev->ynic_adapter[nic].adapter_type = YNIC_ADAPTER_MD4X025GF27LB_4X25G;
                                } else if (kspd == MD_LINK_SPEED_10G) {
                                    knsdev->ynic_adapter[nic].adapter_type = YNIC_ADAPTER_MD4X025GF27LB_4X10G;
                                } else if (kspd == MD_LINK_SPEED_1G) {
                                    knsdev->ynic_adapter[nic].adapter_type = YNIC_ADAPTER_MD4X025GF27LB_4X1G;
                                } else if (kspd == MD_LINK_SPEED_2D5G) {
                                    knsdev->ynic_adapter[nic].adapter_type = YNIC_ADAPTER_MD4X025GF27LB_4X2D5G;
                                } else {
                                    printk(KERN_ERR "Network Card actual speed %u Invalid.\n", kspd);
                                    knsdev->ynic_adapter[nic].adapter_type = YNIC_ADAPTER_TYPE_UNKNOWN;
                                }
                            } else {
                                printk(KERN_ERR "Network Card actual hw version %u Invalid.\n", mhwver);
                                knsdev->ynic_adapter[nic].adapter_type = YNIC_ADAPTER_TYPE_UNKNOWN;
                            }
                        } else {
                            printk(KERN_ERR "Network Card port %u speed %u Invalid.\n", mport, mspeed);
                            knsdev->ynic_adapter[nic].adapter_type = YNIC_ADAPTER_TYPE_UNKNOWN;
                        }
                        break;

                    case 2: /* 1G card */
                        if (mport != 4) {
                            printk(KERN_ERR "Network Card port %u speed %u Invalid.\n", mport, mspeed);
                            knsdev->ynic_adapter[nic].adapter_type = YNIC_ADAPTER_TYPE_UNKNOWN;
                            break;
                        }
                        if (kspd == MD_LINK_SPEED_1G) {
                            knsdev->ynic_adapter[nic].adapter_type = YNIC_ADAPTER_MD4X001GC27LA_4X1G;
                        } else {
                            printk(KERN_ERR "Network Card actual speed %u Invalid.\n", kspd);
                            knsdev->ynic_adapter[nic].adapter_type = YNIC_ADAPTER_TYPE_UNKNOWN;
                        }
                        break;

                    case 3: /* 100G card */
                        if (mport != 2) {
                            printk(KERN_ERR "Network Card port %u speed %u Invalid.\n", mport, mspeed);
                            knsdev->ynic_adapter[nic].adapter_type = YNIC_ADAPTER_TYPE_UNKNOWN;
                            break;
                        }
                        if (kspd == MD_LINK_SPEED_100G) {
                            knsdev->ynic_adapter[nic].adapter_type = YNIC_ADAPTER_MD2X100GF27LA_2X100G;
                        } else if (kspd == MD_LINK_SPEED_50G) {
                            knsdev->ynic_adapter[nic].adapter_type = YNIC_ADAPTER_MD2X100GF27LA_2X50G;
                        } else if (kspd == MD_LINK_SPEED_40G) {
                            knsdev->ynic_adapter[nic].adapter_type = YNIC_ADAPTER_MD2X100GF27LA_2X40G;
                        } else if (kspd == MD_LINK_SPEED_25G) {
                            if (kmulpt > 1) {
                                knsdev->ynic_adapter[nic].adapter_type = YNIC_ADAPTER_MD2X100GF27LA_8X25G;
                            } else {
                                knsdev->ynic_adapter[nic].adapter_type = YNIC_ADAPTER_MD2X100GF27LA_4X25G;
                            }
                        } else if (kspd == MD_LINK_SPEED_10G) {
                            if (kmulpt > 1) {
                                knsdev->ynic_adapter[nic].adapter_type = YNIC_ADAPTER_MD2X100GF27LA_8X10G;
                            } else {
                                knsdev->ynic_adapter[nic].adapter_type = YNIC_ADAPTER_MD2X100GF27LA_4X10G;
                            }
                        } else {
                            printk(KERN_ERR "Network Card actual speed %u Invalid.\n", kspd);
                            knsdev->ynic_adapter[nic].adapter_type = YNIC_ADAPTER_TYPE_UNKNOWN;
                        }
                        break;

                    case 4: /* 400G card */
                        if (mport != 1) {
                            printk(KERN_ERR "Network Card port %u speed %u Invalid.\n", mport, mspeed);
                            knsdev->ynic_adapter[nic].adapter_type = YNIC_ADAPTER_TYPE_UNKNOWN;
                            break;
                        }
                        if (mhwver == 0) {
                            if (kspd == MD_LINK_SPEED_400G) {
                                knsdev->ynic_adapter[nic].adapter_type = YNIC_ADAPTER_YN400GA7B027A_1X400G;
                            } else if (kspd == MD_LINK_SPEED_200G) {
                                knsdev->ynic_adapter[nic].adapter_type = YNIC_ADAPTER_YN400GA7B027A_1X200G;
                            } else if (kspd == MD_LINK_SPEED_100G) {
                                if (kmulpt > 1) {
                                    knsdev->ynic_adapter[nic].adapter_type = YNIC_ADAPTER_YN400GA7B027A_4X100G;
                                } else {
                                    knsdev->ynic_adapter[nic].adapter_type = YNIC_ADAPTER_YN400GA7B027A_1X100G;
                                }
                            } else if (kspd == MD_LINK_SPEED_50G) {
                                knsdev->ynic_adapter[nic].adapter_type = YNIC_ADAPTER_YN400GA7B027A_1X50G;
                            } else {
                                printk(KERN_ERR "Network Card actual speed %u Invalid.\n", kspd);
                                knsdev->ynic_adapter[nic].adapter_type = YNIC_ADAPTER_TYPE_UNKNOWN;
                            }
                        } else if (mhwver == 1) {
                            if (kspd == MD_LINK_SPEED_400G) {
                                knsdev->ynic_adapter[nic].adapter_type = YNIC_ADAPTER_YN400GA7B027B_1X400G;
                            } else if (kspd == MD_LINK_SPEED_200G) {
                                knsdev->ynic_adapter[nic].adapter_type = YNIC_ADAPTER_YN400GA7B027B_1X200G;
                            } else if (kspd == MD_LINK_SPEED_100G) {
                                if (kmulpt > 1) {
                                    knsdev->ynic_adapter[nic].adapter_type = YNIC_ADAPTER_YN400GA7B027B_4X100G;
                                } else {
                                    knsdev->ynic_adapter[nic].adapter_type = YNIC_ADAPTER_YN400GA7B027B_1X100G;
                                }
                            } else if (kspd == MD_LINK_SPEED_50G) {
                                knsdev->ynic_adapter[nic].adapter_type = YNIC_ADAPTER_YN400GA7B027B_1X50G;
                            } else {
                                printk(KERN_ERR "Network Card actual speed %u Invalid.\n", kspd);
                                knsdev->ynic_adapter[nic].adapter_type = YNIC_ADAPTER_TYPE_UNKNOWN;
                            }
                        } else if (mhwver == 2) {
                            if (kspd == MD_LINK_SPEED_400G) {
                                knsdev->ynic_adapter[nic].adapter_type = YNIC_ADAPTER_YN400GA7B027C_1X400G;
                            } else if (kspd == MD_LINK_SPEED_200G) {
                                knsdev->ynic_adapter[nic].adapter_type = YNIC_ADAPTER_YN400GA7B027C_1X200G;
                            } else if (kspd == MD_LINK_SPEED_100G) {
                                if (kmulpt > 1) {
                                    knsdev->ynic_adapter[nic].adapter_type = YNIC_ADAPTER_YN400GA7B027C_4X100G;
                                } else {
                                    knsdev->ynic_adapter[nic].adapter_type = YNIC_ADAPTER_YN400GA7B027C_1X100G;
                                }
                            } else if (kspd == MD_LINK_SPEED_50G) {
                                knsdev->ynic_adapter[nic].adapter_type = YNIC_ADAPTER_YN400GA7B027C_1X50G;
                            } else {
                                printk(KERN_ERR "Network Card actual speed %u Invalid.\n", kspd);
                                knsdev->ynic_adapter[nic].adapter_type = YNIC_ADAPTER_TYPE_UNKNOWN;
                            }
                        } else {
                            printk(KERN_ERR "Network Card actual hw version %u Invalid.\n", mhwver);
                            knsdev->ynic_adapter[nic].adapter_type = YNIC_ADAPTER_TYPE_UNKNOWN;
                        }
                        break;

                    default:
                        printk(KERN_ERR "Network Card port %u speed %u Invalid.\n", mport, mspeed);
                        knsdev->ynic_adapter[nic].adapter_type = YNIC_ADAPTER_TYPE_UNKNOWN;
                        break;
                }
                //pr_cont("adapter_type=%d ",knsdev->ynic_adapter[nic].adapter_type);
                knsdev->ynic_adapter[nic].adapter_id = nic;
                snprintf(knsdev->ynic_adapter[nic].adapter_name, 6, "enp%d", nic);//获取net_device 的netdev->name的前3位

                knsdev->ynic_adapter[nic].enable = 1;
                {
                    int numa = dev_to_node(&dev->dev);

                    if (numa < 0 || numa >= knsdev->nb_numa) {
                        printk(KERN_WARNING
                               "PCI device %04x:%02x:%02x.%01x has invalid NUMA node %d, fallback to 0\n",
                               pci_domain_nr(dev->bus), dev->bus->number,
                               PCI_SLOT(dev->devfn), PCI_FUNC(dev->devfn), numa);
                        numa = 0;
                    }

                    knsdev->ynic_adapter[nic].numa_id = numa;
                }

                snprintf(knsdev->ynic_adapter[nic].bus_id, sizeof(knsdev->ynic_adapter[nic].bus_id), "%02x", dev->bus->number);
                snprintf(knsdev->ynic_adapter[nic].busdev, sizeof(knsdev->ynic_adapter[nic].busdev), "%02x", PCI_SLOT(dev->devfn));
                snprintf(knsdev->ynic_adapter[nic].busfuc, sizeof(knsdev->ynic_adapter[nic].busfuc), "%01x", PCI_FUNC(dev->devfn));
                snprintf(knsdev->ynic_adapter[nic].busadr, sizeof(knsdev->ynic_adapter[nic].busadr), "%04x:%02x:%02x.%01x", pci_domain_nr(dev->bus), dev->bus->number, PCI_SLOT(dev->devfn), PCI_FUNC(dev->devfn));

            }

            //printk(KERN_INFO "Found device: %04x:%02x:%02x:%02x.%d\n",
            //       dev->vendor, dev->device, dev->bus->number, PCI_SLOT(dev->devfn), PCI_FUNC(dev->devfn));
            dev = pci_get_device(id->vendor, PCI_ANY_ID, dev); // 获取下一个同厂商的设备
        }
        dev = NULL;
    }
    if(bar != NULL)
        iounmap(bar);

    //printk(KERN_INFO "vendor %04x total number of devices: %d,nic number:%d\n", vendor_id, knsdev->nb_ports, knsdev->nb_adapters);
    //printk("\n");

    return ret;
}

/*
 * 根据网卡名称获取当前pci设备的pci_dev
 */
int nfc_get_sys_pcidev(uint32_t count)
{
    struct pci_dev *dev;
    uint32_t domain;
    uint32_t bus;
    uint32_t devfn;

    domain = (count >> 24) & 0xff;
    bus  = (count >> 16) & 0xff;
    devfn = PCI_DEVFN(((count >> 8) & 0xff),(count & 0xff));

    dev = pci_get_domain_bus_and_slot(domain, bus, devfn);
    if(!dev) {
        printk(KERN_ERR "pci device %08x not found.\n", count);
        return -EINVAL;
    } else {
        net_pci_dev = pci_dev_get(dev);
        pci_dev_put(dev);
    }

    KDBG(KERN_INFO "found pci device :%02x:%02x:%01x\n", net_pci_dev->bus->number,  PCI_SLOT(net_pci_dev->devfn), PCI_FUNC(net_pci_dev->devfn));

    return 0;

}

/*
 * 获取adapter信息，包括fpga固件等信息
 */
int nfc_get_sys_hw_info(uint32_t vendor_id, void __user *argp)
{
    int ret = YNIC_SUC;
    nf_adapters *kadapt = NULL;
    nf_sys_info *knfsys[MAX_PORT_PER_ADP] = {NULL};
    struct pci_dev *dev = NULL;
    int domain = 0;
    int num = 0;
    int prev_domain = -1;
    int prev_num = -1;
    int nic = -1;   //第n个网卡的网卡号，从0开始
    int prev_nic = -1;
    int i,j;
    int port = 0;   //每个网卡的网口号
    void __iomem *bar = NULL;
    u8 pcie_mode = YNIC_PCIE4_MODE;
    uint32_t val,val1;
    int func_id;
    uint8_t count = 0;
    const struct pci_device_id *id;


    kadapt = kmalloc(sizeof(nf_adapters), GFP_KERNEL);
    if (!kadapt) {
        ret = YNIC_ERR;
        goto kfree_ret;
    }
    memset(kadapt, 0, sizeof(nf_adapters));

    for(i=0;i<MAX_PORT_PER_ADP;i++) {
        knfsys[i] = kmalloc(sizeof(nf_sys_info) * MAX_FPGA_ADAPTER, GFP_KERNEL);
        if (!knfsys[i]) {
            ret = YNIC_ERR;
            goto kfree_ret;
        }
        memset(knfsys[i], 0, sizeof(nf_sys_info) * MAX_FPGA_ADAPTER);
        //kadapt->info[i] = knfsys;
    }

    if(copy_from_user(kadapt, argp, sizeof(nf_adapters))) {
        ret = YNIC_ERR;
        goto kfree_ret;
    }

    for(id = md_card_id_table; id->vendor != 0; id++) {
        // 使用 pci_get_device 遍历所有设备
        dev = pci_get_device(id->vendor, PCI_ANY_ID, NULL);
        while (dev) {
            domain = pci_domain_nr(dev->bus);
            num = dev->bus->number; //设备总线号
            if(prev_domain != domain || prev_num != num) {
                prev_domain = domain;
                prev_num = num;
                nic++; //bus号改变，网卡数量+1
                if (nic >= MAX_FPGA_ADAPTER) {
                    pr_err("Adapter index overflow: nic=%d max=%d for %04x:%02x:%02x.%01x\n",
                           nic, MAX_FPGA_ADAPTER, pci_domain_nr(dev->bus), dev->bus->number,
                           PCI_SLOT(dev->devfn), PCI_FUNC(dev->devfn));
                    if (bar != NULL)
                        iounmap(bar);
                    ret = YNIC_ERR;
                    goto kfree_ret;
                }
                (kadapt->num)++; //bus号改变，网卡数量+1
                port = 0;

                if(bar != NULL) {
                    iounmap(bar);
                }
                bar = pci_ioremap_bar(dev, 2);
                if (!bar) {
                    pr_err("Failed to map BAR\n");
                    return -ENOMEM;
                }
                pcie_mode = ynic_detect_pcie_mode(bar);
            }
            if(WARN_ON(nic < 0)) {
                printk(KERN_ERR "Network Card bus number %d Invalid.\n", num);
                ret = YNIC_ERR;
                goto kfree_ret;
            }

            func_id = PCI_FUNC(dev->devfn);
            if (port >= MAX_PORT_PER_ADP) {
                pr_err("Port index overflow in nfc_get_sys_hw_info: nic=%d port=%d max_port=%d for %04x:%02x:%02x.%01x\n",
                       nic, port, MAX_PORT_PER_ADP, pci_domain_nr(dev->bus), dev->bus->number,
                       PCI_SLOT(dev->devfn), PCI_FUNC(dev->devfn));
                if (bar != NULL)
                    iounmap(bar);
                ret = YNIC_ERR;
                goto kfree_ret;
            }
            if(id->vendor == ALTERA_VENDOR_ID) {
                knfsys[nic][port].status = ynic_hw_read32_mode(bar, pcie_mode, ALTERA_FPGA_LINK_REG) & 0x1;
                knfsys[nic][port].mulport = ynic_hw_read32_mode(bar, pcie_mode, FPGA_PORT_PF0_NUM_REG + (func_id * 4) + FPGA_SYS_BASE_ALTERA);
                val = ynic_hw_read32_mode(bar, pcie_mode, FPGA_SECTOR_REG_ALTERA + (func_id * FPGA_MAC_SIZE));
                val1 = ynic_hw_read32_mode(bar, pcie_mode, FPGA_SECTOR_REG_ALTERA + (func_id * FPGA_MAC_SIZE) + 4);
            } else {
                knfsys[nic][port].status = ynic_hw_read32_mode(bar, pcie_mode, FPGA_LINK_REG);
                knfsys[nic][port].mulport = ynic_hw_read32_mode(bar, pcie_mode, FPGA_PORT_PF0_NUM_REG + (func_id * 4));
                val = ynic_hw_read32_mode(bar, pcie_mode, FPGA_SECTOR_REG + (func_id * FPGA_MAC_SIZE));
                val1 = ynic_hw_read32_mode(bar, pcie_mode, FPGA_SECTOR_REG + (func_id * FPGA_MAC_SIZE) + 4);
            }

            //解析所有网卡的所有网口
            snprintf(knfsys[nic][port].slot, sizeof(knfsys[nic][port].slot), "%04x:%02x:%02x.%01x", pci_domain_nr(dev->bus), dev->bus->number, PCI_SLOT(dev->devfn), PCI_FUNC(dev->devfn));
            snprintf(knfsys[nic][port].id, sizeof(knfsys[nic][port].id), "%04x", dev->device);
            snprintf(knfsys[nic][port].mac, sizeof(knfsys[nic][port].mac), "%02x:%02x:%02x:%02x:%02x:%02x",
                    (val & 0xff), ((val >> 8) & 0xff), ((val >> 16) & 0xff), ((val >> 24) & 0xff),
                    (val1 & 0xff), ((val1 >> 8) & 0xff));
            kadapt->totalport[nic] += knfsys[nic][port].mulport;

            if(prev_nic != nic) {
                prev_nic = nic;

                if(id->vendor == ALTERA_VENDOR_ID) {
                    kadapt->model[nic] = ynic_hw_read32_mode(bar, pcie_mode, FPGA_MODEL_REG + FPGA_SYS_BASE_ALTERA);
                    kadapt->version[nic] = ynic_hw_read32_mode(bar, pcie_mode, FPGA_VERSION_REG + FPGA_SYS_BASE_ALTERA);
                    kadapt->speed[nic] = ynic_hw_read32_mode(bar, pcie_mode, FPGA_PORT_SPEED_REG + FPGA_SYS_BASE_ALTERA);
                    count = ynic_hw_read32_mode(bar, pcie_mode, FPGA_SECTOR_REG_ALTERA + FPGA_IMAGE_REG);
                    for(j=0;j<NF_SERNUM_LEN_RU;j+=4) {

                        val = ynic_hw_read32_mode(bar, pcie_mode, FPGA_SERNUM_REG_ALTERA + j);
                        kadapt->sernum[nic][j] = val & 0xff;
                        kadapt->sernum[nic][j+1] = (val >> 8) & 0xff;
                        kadapt->sernum[nic][j+2] = (val >> 16) & 0xff;
                        kadapt->sernum[nic][j+3] = (val >> 24) & 0xff;
                    }
                    for(j=0;j<NF_FIRMWARE_LEN;j+=4) {

                        if(count == 2 || count == 3) {
                            val = ynic_hw_read32_mode(bar, pcie_mode, (FPGA_FIRMWARE_REG_ALTERA * (count-1)) + j);
                        } else {
                            val = ynic_hw_read32_mode(bar, pcie_mode, FPGA_FIRMWARE_REG_ALTERA + j);
                        }
                        kadapt->firmware[nic][j] = val & 0xff;
                        kadapt->firmware[nic][j+1] = (val >> 8) & 0xff;
                        kadapt->firmware[nic][j+2] = (val >> 16) & 0xff;
                        kadapt->firmware[nic][j+3] = (val >> 24) & 0xff;
                    }
                } else {
                    kadapt->model[nic] = ynic_hw_read32_mode(bar, pcie_mode, FPGA_MODEL_REG);
                    kadapt->version[nic] = ynic_hw_read32_mode(bar, pcie_mode, FPGA_VERSION_REG);
                    kadapt->speed[nic] = ynic_hw_read32_mode(bar, pcie_mode, FPGA_PORT_SPEED_REG);
                    count = ynic_hw_read32_mode(bar, pcie_mode, FPGA_SECTOR_REG + FPGA_IMAGE_REG);
                    for(j=0;j<NF_SERNUM_LEN_RU;j+=4) {

                        val = ynic_hw_read32_mode(bar, pcie_mode, FPGA_SERNUM_REG + j);
                        kadapt->sernum[nic][j] = val & 0xff;
                        kadapt->sernum[nic][j+1] = (val >> 8) & 0xff;
                        kadapt->sernum[nic][j+2] = (val >> 16) & 0xff;
                        kadapt->sernum[nic][j+3] = (val >> 24) & 0xff;
                    }
                    for(j=0;j<NF_FIRMWARE_LEN;j+=4) {

                        if(count == 2 || count == 3) {
                            val = ynic_hw_read32_mode(bar, pcie_mode, (FPGA_FIRMWARE_REG * (count-1)) + j);
                        } else {
                            val = ynic_hw_read32_mode(bar, pcie_mode, FPGA_FIRMWARE_REG + j);
                        }
                        kadapt->firmware[nic][j] = val & 0xff;
                        kadapt->firmware[nic][j+1] = (val >> 8) & 0xff;
                        kadapt->firmware[nic][j+2] = (val >> 16) & 0xff;
                        kadapt->firmware[nic][j+3] = (val >> 24) & 0xff;
                    }
                }
                //for(j=0;j<16;j++)
                //    pr_cont("0x%02x ",kadapt->sernum[nic][j]);
                //printk("\n");
                //printk("model=0x%08x,version=0x%08x,speed=0x%08x,totalport=%d\n",
                //        kadapt->model[nic],kadapt->version[nic],kadapt->speed[nic],kadapt->totalport[nic]);

            }
            port++;
            kadapt->pnum[nic] = port;
            //printk(KERN_INFO "ynictrl found device: %04x:%02x/%02x:%02x.%d\n",
            //       dev->vendor, dev->device, dev->bus->number, PCI_SLOT(dev->devfn), PCI_FUNC(dev->devfn));
            dev = pci_get_device(id->vendor, PCI_ANY_ID, dev); // 获取下一个同厂商的设备
        }
        dev = NULL;
    }
    if(bar != NULL)
        iounmap(bar);
    //printk("zc-hw-num=%d,slot=%s,id=%s,nic=%d,port=%d", kadapt->num, knfsys[0]->slot, knfsys[0]->id, nic, port);

    for(i=0;i<kadapt->num;i++) {

        if(!access_ok(kadapt->info[i], sizeof(nf_sys_info) * MAX_PORT_PER_ADP)) {
            printk(KERN_ERR "Invalid addr\n");
            ret = YNIC_ERR;
            goto kfree_ret;
        }

        if (copy_to_user(kadapt->info[i], knfsys[i], sizeof(nf_sys_info) * MAX_PORT_PER_ADP )) {
            ret = YNIC_ERR;
            goto kfree_ret;
        }
    }

    if (copy_to_user(argp, kadapt, sizeof(nf_adapters))) {
        ret = YNIC_ERR;
        goto kfree_ret;
    }

kfree_ret:
    if (kadapt) {
        kfree(kadapt);
    }
    for(i=0;i<MAX_PORT_PER_ADP;i++) {
        if (knfsys[i]) {
            kfree(knfsys[i]);
        }
    }

    return ret;
}

/*
 * 时钟同步
 */
static inline int nfc_card_sync_clocks(void)
{
    int ret = YNIC_SUC;
    struct pci_dev *dev = NULL;
    int domain = 0;
    int num = 0;
    int prev_domain = -1;
    int prev_num = -1;
    int nic = -1;
    int nic_num = 0;
    int i;
    void __iomem **bar_array;
    u8 pcie_mode_array[MAX_FPGA_ADAPTER] = {0};
    void __iomem *bar = NULL;
    uint64_t time_ns;
    ktime_t start, end;
    s64 execution_time_ns;
    const struct pci_device_id *id;
    uint32_t val = 0;

    bar_array = kmalloc(sizeof(*bar_array) * MAX_FPGA_ADAPTER, GFP_KERNEL);
    if (!bar_array) {
        ret = YNIC_ERR;
        goto kfree_ret;
    }

    for(id = md_card_id_table; id->vendor != 0; id++) {
        // 使用 pci_get_device 遍历所有设备
        dev = pci_get_device(id->vendor, PCI_ANY_ID, NULL);
        while (dev) {
            domain = pci_domain_nr(dev->bus);
            num = dev->bus->number; //设备总线号
            if(prev_domain != domain || prev_num != num) {
                prev_domain = domain;
                prev_num = num;
                nic++; //bus号改变，网卡数量+1

                bar = pci_ioremap_bar(dev, 2);
                if (!bar) {
                    pr_err("Failed to map BAR\n");
                    return -ENOMEM;
                }

                pcie_mode_array[nic] = ynic_detect_pcie_mode(bar);
                if(id->vendor == ALTERA_VENDOR_ID) {
                    bar_array[nic] = bar + FPGA_SYS_BASE_ALTERA;
                } else {
                    bar_array[nic] = bar;
                }
            }

            //printk(KERN_INFO "ynictrl found device: %04x:%02x/%02x:%02x.%d\n",
            //       dev->vendor, dev->device, dev->bus->number, PCI_SLOT(dev->devfn), PCI_FUNC(dev->devfn));
            dev = pci_get_device(id->vendor, PCI_ANY_ID, dev); // 获取下一个同厂商的设备
        }
    }

    nic_num = nic + 1;
    time_ns = ktime_get_real_ns();
    for(i=0;i<nic_num;i++) {
        ynic_hw_write32_mode(bar_array[i], pcie_mode_array[i], (time_ns & 0xffffffff), FPGA_TIME_LOW_REG);
        ynic_hw_write32_mode(bar_array[i], pcie_mode_array[i], ((time_ns >> 32) & 0xffffffff), FPGA_TIME_HIGH_REG);
        //iowrite32(1, (bar_array[i] + FPGA_TIME_SYN_ENABLE));
    }

    start = ktime_get(); // 获取当前内核时间
    for(i=0;i<nic_num;i++) {
        ynic_hw_write32_mode(bar_array[i], pcie_mode_array[i], (i << 8) | 0x1, FPGA_TIME_SYN_ENABLE);
        //ioread32((bar_array[i] + FPGA_TIME_SYN_ENABLE));
    }
    //2card:2.5us
    end = ktime_get(); // 获取命令执行后的内核时间
    execution_time_ns = ktime_to_ns(ktime_sub(end, start)); // 计算执行时间（纳秒）
    printk(KERN_INFO "sync clock: %lld nsecs\n", execution_time_ns);

    for(i=0;i<nic_num;i++) {
        val = ynic_hw_read32_mode(bar_array[i], pcie_mode_array[i], FPGA_TIME_SYN_ENABLE);
        val &= ~BIT(0);
        ynic_hw_write32_mode(bar_array[i], pcie_mode_array[i], val, FPGA_TIME_SYN_ENABLE);
    }

    for(i=0;i<nic_num;i++) {
        iounmap(bar_array[i]);
    }
    //__flush_tlb_all();


kfree_ret:
    if (bar_array) {
        kfree(bar_array);
    }

    return ret;
}

static int nfc_card_set_fec(uint32_t port_flag)
{
    int ret = YNIC_SUC;
    struct pci_dev *dev;
    void __iomem *bar;
    u8 pcie_mode;
    uint32_t val;
    uint8_t port,flag;
    uint32_t kspd = 0;

    if(net_pci_dev) {
        dev = net_pci_dev;
    } else {
        printk(KERN_ERR "Network Card not exist!!!\n");
        return -ENODEV;
    }

    bar = pci_ioremap_bar(dev, 2);
    if (!bar) {
        pci_dev_put(dev);
        pr_err("Failed to map BAR\n");
        return -ENOMEM;
    }
    pcie_mode = ynic_detect_pcie_mode(bar);

    if(net_pci_dev->vendor == ALTERA_VENDOR_ID) {
        printk(KERN_ERR "ALTERA Card mode not support fec!!!\n");
        return YNIC_ERR;
    } else {
        kspd = ynic_hw_read32_mode(bar, pcie_mode, FPGA_PORT_SPEED_REG);
    }
    if((kspd != MD_LINK_SPEED_100G) && (kspd != MD_LINK_SPEED_200G)) {
        printk(KERN_ERR "Network Card mode not support fec!!!\n");
        return YNIC_ERR;
    }
    port = (port_flag >> 8) & 0xff;
    flag = port_flag & 0xff;
    if(flag) {
        val = ynic_hw_read32_mode(bar, pcie_mode, CMAC_SUBSYSTEM_OFFSET(port) + FPGA_RSFEC_REG);
        val |= 0x3;
        ynic_hw_write32_mode(bar, pcie_mode, val, CMAC_SUBSYSTEM_OFFSET(port) + FPGA_RSFEC_REG);
    } else {
        val = ynic_hw_read32_mode(bar, pcie_mode, CMAC_SUBSYSTEM_OFFSET(port) + FPGA_RSFEC_REG);
        val &= 0xc;
        ynic_hw_write32_mode(bar, pcie_mode, val, CMAC_SUBSYSTEM_OFFSET(port) + FPGA_RSFEC_REG);
    }
    KDBG("port %d set fec flag=%d\n",port, flag);

    iounmap(bar);

    return ret;

}

static int nfc_card_set_up(uint32_t port_flag)
{
    int ret = YNIC_SUC;
    struct pci_dev *dev;
    void __iomem *bar;
    u8 pcie_mode;
    uint8_t port,flag;
    uint32_t asta;

    if(net_pci_dev) {
        dev = net_pci_dev;
    } else {
        printk(KERN_ERR "Network Card not exist!!!\n");
        return -ENODEV;
    }

    bar = pci_ioremap_bar(dev, 2);
    if (!bar) {
        pci_dev_put(dev);
        pr_err("Failed to map BAR\n");
        return -ENOMEM;
    }
    pcie_mode = ynic_detect_pcie_mode(bar);

    port = (port_flag >> 8) & 0xff;
    flag = port_flag & 0xff;
    if(net_pci_dev->vendor == ALTERA_VENDOR_ID) {
        pr_warn_once("ALTERA Card: Auto-negotiation not supported, ignoring\n");
        iounmap(bar);
        return YNIC_SUC;
    } else {

        asta = ynic_hw_read32_mode(bar, pcie_mode, FPGA_AUNE_REG);
    }
    if(flag) {
        asta |= (1 << port);
    } else {
        asta &= ~(1 << port);
    }
    ynic_hw_write32_mode(bar, pcie_mode, asta, FPGA_AUNE_REG);

    KDBG("port %d Auto-negotiation=%d\n", port, flag);

    iounmap(bar);

    return ret;

}

static int
ynic_get_net_dev_info(ynic_ukcmd_t *ukcmd)
{
    int ret = YNIC_SUC;
    ynic_nsdev_t *knsdev = NULL;
    uint8_t *u2k_mem = NULL;

    knsdev = kmalloc(sizeof(ynic_nsdev_t), GFP_KERNEL);
    if (knsdev == NULL) {
        ret = YNIC_ERR;
        goto kfree_ret;
    }

    u2k_mem = kmalloc(ukcmd->u2k_len, GFP_KERNEL);
    if (u2k_mem == NULL) {
        ret = YNIC_ERR;
        goto kfree_ret;
    }

    if (copy_from_user(u2k_mem, ukcmd->u2k_mem, ukcmd->u2k_len)) {
        ret = YNIC_ERR;
        goto kfree_ret;
    }
    // printk("user data=%s\n", u2k_mem);

    memset(knsdev, 0, sizeof(ynic_nsdev_t));

    knsdev->nb_numa = ynic_get_sys_numa();
    ret = ynic_get_sys_card_info(NET_VENDOR_ID, knsdev);
    if(!ret) {
        //printk("send len=%d,recv len=%d\n",ukcmd->u2k_len,ukcmd->k2u_len);
    } else {
        ret = YNIC_ERR;
        goto kfree_ret;
    }

    if (copy_to_user(ukcmd->k2u_mem, (uint8_t *)knsdev, ukcmd->k2u_len)) {
        ret = YNIC_ERR;
        goto kfree_ret;
    }

kfree_ret:
    if (u2k_mem) {
        kfree(u2k_mem);
    }

    if (knsdev) {
        kfree(knsdev);
    }

    return ret;
}

static int
yuannic_netdev_open_tx_stream(ynic_ukcmd_t *ukcmd)
{
    int ret = YNIC_SUC;
    uint32_t kstm_id;
    uint8_t *u2k_mem = NULL;
    ynic_tx_stream_t *ktx_stream = NULL;
    ynic_nserr_t *kerr = NULL;
    uint8_t port_id;

    kerr = kmalloc(sizeof(ynic_nserr_t), GFP_KERNEL);
    if(!kerr) {
        snprintf(kerr->err_mesg, sizeof(kerr->err_mesg), "kmalloc failed,line:%d",__LINE__);
        ret = YNIC_ERR;
        goto kfree_ret;
    }


    ktx_stream = kmalloc(sizeof(ynic_tx_stream_t), GFP_KERNEL);
    if (ktx_stream == NULL) {
        snprintf(kerr->err_mesg, sizeof(kerr->err_mesg), "kmalloc failed,line:%d",__LINE__);
        ret = YNIC_ERR;
        goto kfree_ret;
    }
    memset(ktx_stream, 0 ,sizeof(ynic_tx_stream_t));


    u2k_mem = kmalloc(ukcmd->u2k_len, GFP_KERNEL);
    if (u2k_mem == NULL) {
        snprintf(kerr->err_mesg, sizeof(kerr->err_mesg), "kmalloc failed,line:%d",__LINE__);
        ret = YNIC_ERR;
        goto kfree_ret;
    }

    if (copy_from_user(u2k_mem, ukcmd->u2k_mem, ukcmd->u2k_len)) {
        snprintf(kerr->err_mesg, sizeof(kerr->err_mesg), "kmalloc failed,line:%d",__LINE__);
        ret = YNIC_ERR;
        goto kfree_ret;
    }

    port_id = ((ynic_tx_stream_t *)u2k_mem)->fpga_portid;

    spin_lock(&ktx_spinlock);

    /* Lazy allocation of bitmap for this port */
    if(!ktx_bitmap[port_id]) {
        uint16_t capacity = ynic_get_stream_capacity(kptnm[port_id].speed);
        ktx_bitmap[port_id] = kmalloc(BITS_TO_LONGS(capacity) * sizeof(unsigned long), GFP_ATOMIC);
        if(!ktx_bitmap[port_id]) {
            spin_unlock(&ktx_spinlock);
            snprintf(kerr->err_mesg, sizeof(kerr->err_mesg), "alloc bitmap failed for port %d", port_id);
            ret = YNIC_ERR;
            goto kfree_ret;
        }
        ktx_bitmap_size[port_id] = capacity;
        bitmap_zero(ktx_bitmap[port_id], capacity);
    }

    kstm_id = find_next_zero_bit(ktx_bitmap[port_id], ktx_bitmap_size[port_id], 0);
    if(kstm_id < ktx_bitmap_size[port_id]) {
        set_bit(kstm_id, ktx_bitmap[port_id]);
        ktx_stream->stream_id = port_id * MAX_STREAM_PER_PORT_400G + kstm_id + 1;
        KDBG(KERN_INFO "alloc tx stream id: %d\n", ktx_stream->stream_id);

    } else {
        spin_unlock(&ktx_spinlock);
        printk("failed,open-tx-port_id=%d,kstm_id=%d,capacity=%d\n",
                port_id, kstm_id, ktx_bitmap_size[port_id]);
        snprintf(kerr->err_mesg, sizeof(kerr->err_mesg), "alloc stream id failed,id=%d",kstm_id);
        return YNIC_ERR;
        goto kfree_ret;
    }
    spin_unlock(&ktx_spinlock);

    if (copy_to_user(ukcmd->k2u_mem, (uint8_t *)&(ktx_stream->stream_id), sizeof(ktx_stream->stream_id))) {
        snprintf(kerr->err_mesg, sizeof(kerr->err_mesg), "copy k2u_mem data failed,line:%d",__LINE__);
        ret = YNIC_ERR;
        goto kfree_ret;
    }

    KDBG("zc-10-open tx stream,stream_id=%d,port_id=%d,stream_name=%s\n",ktx_stream->stream_id, port_id, ((ynic_tx_stream_t *)u2k_mem)->stream_name);

kfree_ret:
    if(ret) {
        kerr->err_code = ret;
        if (copy_to_user(ukcmd->k2u_err, kerr, sizeof(ynic_nserr_t))) {
            ret = YNIC_ERR;
        }
    }
    if (u2k_mem) {
        kfree(u2k_mem);
    }
    if(ktx_stream) {
        kfree(ktx_stream);
    }
    if(kerr) {
        kfree(kerr);
    }

    return ret;

}

static int
yuannic_netdev_set_tx_stream_cfg(ynic_ukcmd_t *ukcmd)
{
    int ret = YNIC_SUC;
    ynic_stream_cfg_t *kstream_cfg = NULL;   //stream配置信息
    ynic_nic_txd_t *ktxd_array = NULL;       //报文模板数组
    uint8_t kmsg_mode = 0;                  //使用mdf还是五元组
    uint16_t knb_txd = 0;                   //报文模板数量
    uint8_t *kpkt = NULL;                   //报文内容
    uint16_t kpkt_len = 0;                  //报文长度
    uint16_t khdr_len = 0;                  //报文头长度
    uint32_t kpkt_total_len = 0;            //报文总长度
    uint32_t *kpkt_fpga = NULL;             //报文内容需要转换
    uint32_t *kgap = NULL;
    uint16_t kgap_len = 0;
    uint32_t kgap_total_len = 0;
#ifdef FPGA_CONTROL_TX_STREAM
    uint32_t kpkt_fpga_len = 0;             //fpga发送报文长度
    uint64_t kpkt_sdpkt = 0;
    uint64_t kpkt_sdtime = 0;
#endif
    uint8_t *ktmp = NULL;                   //报文临时指针
    int i,j = 0;
    uint16_t knb_zones = 0;                 //跳变域数量
    mdf_zone_var_t *kmdf_array = NULL;
    uint8_t *kmdf = NULL;                   //跳变域内容
    uint64_t kmdf_total_len = 0;            //跳变域内容最大总长度
    uint64_t kmdf_actual_len = 0;           //跳变域内容实际长度
    uint32_t *kmdf_fpga = NULL;             //跳变域内容需要转换
    uint64_t kmdf_fpga_len = 0;             //跳变域内容fpga发送长度
    uint8_t *kmdf_tmp = NULL;               //跳变域临时指针
    void *kmdf_type_ptr = NULL;             //跳变域跳变类型指针
    int k,m = 0;

    void *kmdf_ptr = NULL;
    uint16_t ktype = 0xFFFF;
    uint16_t kmode = 0xFFFF;
    void *klist_ptr = NULL;
    uint32_t stream_id;
    simuser_5tuple_t *k5tuple = NULL;
    uint32_t knbuser = 0;
    uint32_t kdirect = 0;
    uint32_t kactnum =0,kremain = 0,kfactor = 0;
    port_info info = {0};
    int func_id = -1;
    uint32_t offset = 0;
    uint16_t knb_streams = 0;
    uint16_t fpga_id = 0;
    uint32_t ktx_en = 0;
#ifdef DEBUG_ON
    uint32_t val1,val2,val3;
#endif
    uint128_t tmp_value_start = 0;
    uint128_t tmp_value_end = 0;
    uint128_t tmp_value_step = 0;
    uint128_t tmp_value_mask = 0;
    uint32_t tmp_value_count = 0;
    uint16_t tmp_value_off = 0;
    uint8_t knb_mix = 0;
    uint8_t ksrm_idx = 0;
    md_imix_cfg_t *kmix = NULL;
    uint32_t kdata = 0;
    uint32_t kjump[FPGA_JUMP_LEN] = {0};
    uint8_t kset = 0;
    uint8_t kbwr_en = 0;

    uint8_t *u2k_mem = kmalloc(ukcmd->u2k_len, GFP_KERNEL);
    if (u2k_mem == NULL) {
        ret = YNIC_ERR;
        goto kfree_ret;
    }

    if (copy_from_user(u2k_mem, ukcmd->u2k_mem, ukcmd->u2k_len)) {
        ret = YNIC_ERR;
        goto kfree_ret;
    }

    kstream_cfg = kmalloc(sizeof(ynic_stream_cfg_t), GFP_KERNEL);
    if(kstream_cfg == NULL) {
        ret = YNIC_ERR;
        goto kfree_ret;
    }


    if (copy_from_user(kstream_cfg, ((ynic_tx_stream_t *)u2k_mem)->stream_cfg, sizeof(ynic_stream_cfg_t))) {
        ret = YNIC_ERR;
        goto kfree_ret;
    }
    stream_id = ((ynic_tx_stream_t *)u2k_mem)->stream_id;
    //数据处理
    knb_txd = kstream_cfg->nb_txd;
    if(knb_txd < 1) {   //这个值必须大于等于1才正确，需要判断
        printk(KERN_ERR "Invalid nb_txd value: %d\n",knb_txd);
        ret = YNIC_ERR;
        goto kfree_ret;
    }
    knb_zones = kstream_cfg->nb_mdf_zones; //跳变域数量可以为0
    kmsg_mode = kstream_cfg->msg_mode;
    knb_streams = kstream_cfg->nb_streams;
    knb_mix = kstream_cfg->nb_mix;
    kset = kstream_cfg->is_rebind;
    kbwr_en = kstream_cfg->bwr_en;
    ksrm_idx = kstream_cfg->srm_idx;

    ktxd_array = kmalloc(sizeof(ynic_nic_txd_t) * knb_txd, GFP_KERNEL);
    if(!ktxd_array) {
        ret = YNIC_ERR;
        goto kfree_ret;
    }
    KDBG("zc-11-stream_id=%d,knb_txd=%d,knb_zones=%d, knb_streams=%d,kmsg_mode=%d,knb_mix=%d,txd_array=%p\n",
            stream_id,knb_txd, knb_zones, knb_streams,kmsg_mode,knb_mix,kstream_cfg->txd_array);

    if(copy_from_user(ktxd_array, kstream_cfg->txd_array, sizeof(ynic_nic_txd_t) * knb_txd)) {
        ret = YNIC_ERR;
        goto kfree_ret;
    }

    KDBG("zc-12\n");

    for(i=0; i < knb_txd; i++) {
        kpkt_total_len += ktxd_array[i].pkt_len;
        kgap_total_len += ktxd_array[i].gap_len;

    }
    KDBG("zc-13-pkt total len=%d,gap total len=%d\n", kpkt_total_len,kgap_total_len);

    kpkt = kmalloc(sizeof(uint8_t) * kpkt_total_len, GFP_KERNEL);
    if(!kpkt) {
        ret = YNIC_ERR;
        goto kfree_ret;
    }
    kpkt_fpga = kmalloc(sizeof(uint32_t) * (kpkt_total_len / 4), GFP_KERNEL);
    if(!kpkt_fpga) {
        ret = YNIC_ERR;
        goto kfree_ret;
    }
    kgap = kmalloc(sizeof(uint32_t) * kgap_total_len, GFP_KERNEL);
    if(!kgap) {
        ret = YNIC_ERR;
        goto kfree_ret;
    }

    func_id = ynic_get_net_bdf(STREAM_TX, stream_id, &info);
    if(func_id >= 0) {
        if(info.type == ALTERA_400G) {
            offset = func_id * FPGA_TX_OFFSET + FPGA_TX_BASE_ALTERA;
        } else {
            offset = func_id * FPGA_TX_OFFSET + FPGA_TX_BASE_XILINX;
        }
    } else {
        printk(KERN_ERR "%s get func_id %d Invalid\n",__func__, func_id);
        ret = YNIC_ERR;
        goto kfree_ret;
    }
    fpga_id = stream_id - (info.port_id * MAX_STREAM_PER_PORT_400G) - 1;
    //1 divided into 4
    if(info.pf_num > 1) {
        ynic_write_fpga_byte(STREAM_TX, stream_id, (info.adapter_id - func_id * 4), (FPGA_TX_1to4_SEL_ADDR + offset));
        ynic_read_fpga_byte(STREAM_TX, stream_id, &ktx_en, (FPGA_TX_1to4_EN_ADDR + offset));
        printk("%s init value,ktx_en=0x%02x\n",info.port_bdf, ktx_en);
        ktx_en |= 1 << (info.adapter_id - func_id * 4);
        ynic_write_fpga_byte(STREAM_TX, stream_id, ktx_en, (FPGA_TX_1to4_EN_ADDR + offset));
        if(kmsg_mode == 0) { /*1分4 2544*/
            knb_streams = 4;
        } else {
            knb_streams *= 4;
        }
        KDBG("zc-70-set-tx-stream_id=%d,adapter_id=%d,bdf=%s,func_id=%d,port_id=%d,ktx_en=0x%02x\n",
                stream_id,info.adapter_id,info.port_bdf,func_id,info.port_id,ktx_en);
    }


    //报文解析
    ynic_write_fpga_byte(STREAM_TX, stream_id, knb_streams, (FPGA_TX_STREAM_NUM + offset));
    ktmp = kpkt;
    for(j=0; j < knb_txd; j++) {
        kpkt_len = ktxd_array[j].pkt_len;
        khdr_len = ktxd_array[j].hdr_len;
        kgap_len = ktxd_array[j].gap_len;
        KDBG("zc-14-kpkt_len=%d,khdr_len=%d,gap_len=%d\n",kpkt_len, khdr_len, kgap_len);

        if(kset) { //用例过程中限速

            if((kgap != ZERO_SIZE_PTR) && (kgap_len > 0)) {
                if(copy_from_user(kgap, ktxd_array[j].gap_array, (kgap_len * sizeof(uint32_t)))) {
                    printk(KERN_ERR "kgap copy failed,num=%d", j);
                    ret = YNIC_ERR;
                    goto kfree_ret;
                }
                #ifdef FPGA_CONTROL_TX_STREAM
                //1 divided into 4
                #if 0
                if(info.pf_num > 1) {
                    if(kmsg_mode == 0) { /*1分4 2544*/
                        kgap[0] = 0;
                        kgap[1] = 0;
                        kgap[2] = 0;
                        kgap[3] = 0;
                    }
                }
                #endif
                ynic_write_fpga_byte(STREAM_TX, stream_id, kgap[0], (FPGA_TX_GAPA_ADDR + offset));
                ynic_write_fpga_byte(STREAM_TX, stream_id, kgap[2], (FPGA_TX_GAPB_ADDR + offset));
                ynic_write_fpga_byte(STREAM_TX, stream_id, ((uint32_t)kgap[3] << 16 | kgap[1]), (FPGA_TX_GAPNUM_ADDR + offset));
                #endif
                KDBG("zc-15-pkt_gap=");
                #ifdef DEBUG_ON
                for(i=0;i<kgap_len;i++) {
                    pr_cont("%d ",kgap[i]);
                }
                #endif
            } else {
                #ifdef FPGA_CONTROL_TX_STREAM
                ynic_write_fpga_byte(STREAM_TX, stream_id, 0, (FPGA_TX_GAPA_ADDR + offset));
                ynic_write_fpga_byte(STREAM_TX, stream_id, 0, (FPGA_TX_GAPB_ADDR + offset));
                ynic_write_fpga_byte(STREAM_TX, stream_id, 0, (FPGA_TX_GAPNUM_ADDR + offset));
                #endif
            }
            ret = YNIC_SUC;
            goto kfree_ret;

        } else {

            //向fpga发送报文头长度和总长度
            #ifdef FPGA_CONTROL_TX_STREAM
            #if 0
            ynic_write_fpga_byte(STREAM_TX, stream_id, ((uint32_t)khdr_len << 16 | kpkt_len), (FPGA_TX_PKT_LENGTH_ADDR + offset));
            #else
            if(knb_mix == 0) {
                kdata = FIELD_PREP(FPGA_TX_PKT_LW_WEIGHT_MASK, 1);
                kdata |= FIELD_PREP(FPGA_TX_PKT_LW_LEN_MASK, kpkt_len);
                ynic_write_fpga_byte(STREAM_TX, stream_id, 0, (FPGA_TX_PKT_PTR_RESET + offset));
                ynic_write_fpga_byte(STREAM_TX, stream_id, kdata, (FPGA_TX_PKT_LW_WRITE + offset));
                ynic_write_fpga_byte(STREAM_TX, stream_id, 1, (FPGA_TX_PKT_LW_WDONE + offset));
            }
            ynic_write_fpga_byte(STREAM_TX, stream_id, ((uint32_t)khdr_len << 16 | kpkt_len), (FPGA_TX_PKT_LENGTH_ADDR + offset));
            #endif
            #endif

            if(copy_from_user(ktmp, ktxd_array[j].pkt_cnt, kpkt_len)) {
                printk(KERN_ERR "kpt copy failed,num=%d", j);
                ret = YNIC_ERR;
                goto kfree_ret;
            }
            ktmp += kpkt_len;

            if((kgap != ZERO_SIZE_PTR) && (kgap_len > 0)) {
                if(copy_from_user(kgap, ktxd_array[j].gap_array, (kgap_len * sizeof(uint32_t)))) {
                    printk(KERN_ERR "kgap copy failed,num=%d", j);
                    ret = YNIC_ERR;
                    goto kfree_ret;
                }
                #ifdef FPGA_CONTROL_TX_STREAM
                #if 0
                //1 divided into 4
                if(info.pf_num > 1) {
                    if(kmsg_mode == 0) { /*1分4 2544*/
                        kgap[0] = 0;
                        kgap[1] = 0;
                        kgap[2] = 0;
                        kgap[3] = 0;
                    }
                }
                #endif
                ynic_write_fpga_byte(STREAM_TX, stream_id, kgap[0], (FPGA_TX_GAPA_ADDR + offset));
                ynic_write_fpga_byte(STREAM_TX, stream_id, kgap[2], (FPGA_TX_GAPB_ADDR + offset));
                ynic_write_fpga_byte(STREAM_TX, stream_id, ((uint32_t)kgap[3] << 16 | kgap[1]), (FPGA_TX_GAPNUM_ADDR + offset));
                #endif
                KDBG("zc-16-pkt_gap=");
                #ifdef DEBUG_ON
                for(i=0;i<kgap_len;i++) {
                    pr_cont("%d ",kgap[i]);
                }
                #endif
            } else {
                #ifdef FPGA_CONTROL_TX_STREAM
                ynic_write_fpga_byte(STREAM_TX, stream_id, 0, (FPGA_TX_GAPA_ADDR + offset));
                ynic_write_fpga_byte(STREAM_TX, stream_id, 0, (FPGA_TX_GAPB_ADDR + offset));
                ynic_write_fpga_byte(STREAM_TX, stream_id, 0, (FPGA_TX_GAPNUM_ADDR + offset));
                #endif
            }
        }
    }

    KDBG("zc-18-pkt_cnt-start\n");

    // for(i = 0; i < kpkt_total_len; i++) {
    //     printk(" 0x%02x",kpkt[i]);
    // }
    if(kbwr_en || (knb_mix > 0)) {
        uint32_t kmix_cnt = kbwr_en ? 1 : knb_mix;

        kmix = kcalloc(kmix_cnt, sizeof(md_imix_cfg_t), GFP_KERNEL);
        if(!kmix) {
            ret = YNIC_ERR;
            goto kfree_ret;
        }
        if(kbwr_en) {
            if(ksrm_idx >= knb_mix) {
                printk(KERN_ERR "Invalid srm_idx value: %u, nb_mix=%u\n", ksrm_idx, knb_mix);
                ret = YNIC_ERR;
                goto kfree_ret;
            }

            if(copy_from_user(kmix, kstream_cfg->md_imix_cfg + ksrm_idx, sizeof(md_imix_cfg_t))) {
                ret = YNIC_ERR;
                goto kfree_ret;
            }
        } else if(copy_from_user(kmix, kstream_cfg->md_imix_cfg, sizeof(md_imix_cfg_t) * kmix_cnt)) {
            ret = YNIC_ERR;
            goto kfree_ret;
        }

        ynic_write_fpga_byte(STREAM_TX, stream_id, 0, (FPGA_TX_PKT_PTR_RESET + offset));
        for(i=0; i<kmix_cnt; i++) {
            kdata = FIELD_PREP(FPGA_TX_PKT_LW_WEIGHT_MASK, kmix[i].proportion);
            kdata |= FIELD_PREP(FPGA_TX_PKT_LW_LEN_MASK, kmix[i].frm_size);
            ynic_write_fpga_byte(STREAM_TX, stream_id, kdata, (FPGA_TX_PKT_LW_WRITE + offset));
            KDBG("i=%d,portion=%u,frame=%u,kdata=0x%08x\n", i, kmix[i].proportion, kmix[i].frm_size, kdata);
        }
        ynic_write_fpga_byte(STREAM_TX, stream_id, 1, (FPGA_TX_PKT_LW_WDONE + offset));
    }

    if(kmsg_mode == 0) {
        //5元组
        k5tuple = kmalloc(sizeof(simuser_5tuple_t), GFP_KERNEL);
        if(!k5tuple) {
            ret = YNIC_ERR;
            goto kfree_ret;
        }

        if(copy_from_user(k5tuple, kstream_cfg->simuser_5tuple, sizeof(simuser_5tuple_t))) {
            ret = YNIC_ERR;
            goto kfree_ret;
        }
        knbuser = k5tuple->nb_simuser;
        KDBG("zc-60-user=%d,sip-count=%llu,dip-count=%llu,sport-count=%d,dport-count=%d\n",
                    knbuser, k5tuple->src_ipaddr.nb_ipaddr,k5tuple->dst_ipaddr.nb_ipaddr,
                    k5tuple->src_port.port_count,k5tuple->dst_port.port_count);
        if(knbuser > 0) {
            #ifdef FPGA_CONTROL_TX_STREAM
            ynic_write_fpga_byte(STREAM_TX, stream_id, knbuser, (FPGA_TX_K5TUPLE_NUM_ADDR + offset));
            #endif
            ynic_read_fpga_byte(STREAM_TX, stream_id, &kdirect, (FPGA_TX_DIRECT_ADDR + offset));
            KDBG("zc-60-user=%d,direct=%d\n",knbuser,kdirect);

            if(kdirect == 0) {
                if(k5tuple->src_ipaddr.domain == AF_INET) {
                    ynic_write_fpga_byte(STREAM_TX, stream_id, 0, (FPGA_TX_IPTYPE_ADDR + offset));
                } else {
                    ynic_write_fpga_byte(STREAM_TX, stream_id, 1, (FPGA_TX_IPTYPE_ADDR + offset));
                }

                if(knbuser <= k5tuple->src_ipaddr.nb_ipaddr) {
                    if(k5tuple->src_ipaddr.domain == AF_INET) {
                        ynic_write_fpga_byte(STREAM_TX, stream_id, k5tuple->src_ipaddr.min_ipv4_addr, (FPGA_TX_SIP_START_ADDR + offset));
                        ynic_write_fpga_byte(STREAM_TX, stream_id, (k5tuple->src_ipaddr.min_ipv4_addr + ((knbuser-1) * k5tuple->src_ipaddr.step_addr)), (FPGA_TX_SIP_END_ADDR + offset));
                        ynic_write_fpga_byte(STREAM_TX, stream_id, ((k5tuple->src_ipaddr.step_addr << 16) | 0x1), (FPGA_TX_SIP_STEP_ADDR + offset));
                    } else if(k5tuple->src_ipaddr.domain == AF_INET6) {
                        uint32_t val = 0;
                        uint128_t tmp_max;
                        val = k5tuple->src_ipaddr.min_ipv6_addr.s6_addr32[0];
                        ynic_write_fpga_byte(STREAM_TX, stream_id, val, (FPGA_TX_SIPv6_START0_ADDR + offset));
                        val = k5tuple->src_ipaddr.min_ipv6_addr.s6_addr32[1];
                        ynic_write_fpga_byte(STREAM_TX, stream_id, val, (FPGA_TX_SIPv6_START1_ADDR + offset));
                        val = k5tuple->src_ipaddr.min_ipv6_addr.s6_addr32[2];
                        ynic_write_fpga_byte(STREAM_TX, stream_id, val, (FPGA_TX_SIPv6_START2_ADDR + offset));
                        val = k5tuple->src_ipaddr.min_ipv6_addr.s6_addr32[3];
                        ynic_write_fpga_byte(STREAM_TX, stream_id, val, (FPGA_TX_SIPv6_START3_ADDR + offset));

                        tmp_max = k5tuple->src_ipaddr.min_ipv6_uint128;
                        tmp_max += (knbuser-1) * k5tuple->src_ipaddr.step_ipv6_uint128;
                        val = tmp_max & 0xFFFFFFFF;
                        ynic_write_fpga_byte(STREAM_TX, stream_id, val, (FPGA_TX_SIPv6_END0_ADDR + offset));
                        val = (tmp_max >> 32) & 0xFFFFFFFF;
                        ynic_write_fpga_byte(STREAM_TX, stream_id, val, (FPGA_TX_SIPv6_END1_ADDR + offset));
                        val = (tmp_max >> 64) & 0xFFFFFFFF;
                        ynic_write_fpga_byte(STREAM_TX, stream_id, val, (FPGA_TX_SIPv6_END2_ADDR + offset));
                        val = (tmp_max >> 96) & 0xFFFFFFFF;
                        ynic_write_fpga_byte(STREAM_TX, stream_id, val, (FPGA_TX_SIPv6_END3_ADDR + offset));

                        ynic_write_fpga_byte(STREAM_TX, stream_id, ((k5tuple->src_ipaddr.step_ipv6_uint128 << 16) | 0x1), (FPGA_TX_SIPv6_STEP_ADDR + offset));
                    } else {
                        printk(KERN_ERR "simuser domain %d Invalid\n", k5tuple->src_ipaddr.domain);
                        ret = YNIC_ERR;
                        goto kfree_ret;
                    }
                } else {
                    if(k5tuple->src_ipaddr.domain == AF_INET) {
                        ynic_write_fpga_byte(STREAM_TX, stream_id, k5tuple->src_ipaddr.min_ipv4_addr, (FPGA_TX_SIP_START_ADDR + offset));
                        ynic_write_fpga_byte(STREAM_TX, stream_id, k5tuple->src_ipaddr.max_ipv4_addr, (FPGA_TX_SIP_END_ADDR + offset));
                        ynic_write_fpga_byte(STREAM_TX, stream_id, ((k5tuple->src_ipaddr.step_addr << 16) | 0x1), (FPGA_TX_SIP_STEP_ADDR + offset));
                    } else if(k5tuple->src_ipaddr.domain == AF_INET6) {
                        uint32_t val = 0;
                        val = k5tuple->src_ipaddr.min_ipv6_addr.s6_addr32[0];
                        ynic_write_fpga_byte(STREAM_TX, stream_id, val, (FPGA_TX_SIPv6_START0_ADDR + offset));
                        val = k5tuple->src_ipaddr.min_ipv6_addr.s6_addr32[1];
                        ynic_write_fpga_byte(STREAM_TX, stream_id, val, (FPGA_TX_SIPv6_START1_ADDR + offset));
                        val = k5tuple->src_ipaddr.min_ipv6_addr.s6_addr32[2];
                        ynic_write_fpga_byte(STREAM_TX, stream_id, val, (FPGA_TX_SIPv6_START2_ADDR + offset));
                        val = k5tuple->src_ipaddr.min_ipv6_addr.s6_addr32[3];
                        ynic_write_fpga_byte(STREAM_TX, stream_id, val, (FPGA_TX_SIPv6_START3_ADDR + offset));

                        val = k5tuple->src_ipaddr.max_ipv6_addr.s6_addr32[0];
                        ynic_write_fpga_byte(STREAM_TX, stream_id, val, (FPGA_TX_SIPv6_END0_ADDR + offset));
                        val = k5tuple->src_ipaddr.max_ipv6_addr.s6_addr32[1];
                        ynic_write_fpga_byte(STREAM_TX, stream_id, val, (FPGA_TX_SIPv6_END1_ADDR + offset));
                        val = k5tuple->src_ipaddr.max_ipv6_addr.s6_addr32[2];
                        ynic_write_fpga_byte(STREAM_TX, stream_id, val, (FPGA_TX_SIPv6_END2_ADDR + offset));
                        val = k5tuple->src_ipaddr.max_ipv6_addr.s6_addr32[3];
                        ynic_write_fpga_byte(STREAM_TX, stream_id, val, (FPGA_TX_SIPv6_END3_ADDR + offset));

                        ynic_write_fpga_byte(STREAM_TX, stream_id, ((k5tuple->src_ipaddr.step_ipv6_uint128 << 16) | 0x1), (FPGA_TX_SIPv6_STEP_ADDR + offset));
                    } else {
                        printk(KERN_ERR "simuser domain %d Invalid\n", k5tuple->src_ipaddr.domain);
                        ret = YNIC_ERR;
                        goto kfree_ret;
                    }

                    kfactor = knbuser / k5tuple->src_ipaddr.nb_ipaddr;
                    kremain = knbuser % k5tuple->src_ipaddr.nb_ipaddr;
                    if(kremain == 0) {
                        kactnum = kfactor;
                    } else {
                        kactnum = kfactor + 1;
                    }
                    if(kactnum < k5tuple->dst_ipaddr.nb_ipaddr) {
                        if(k5tuple->dst_ipaddr.domain == AF_INET) {
                            ynic_write_fpga_byte(STREAM_TX, stream_id, k5tuple->dst_ipaddr.min_ipv4_addr, (FPGA_TX_DIP_START_ADDR + offset));
                            ynic_write_fpga_byte(STREAM_TX, stream_id, (k5tuple->dst_ipaddr.min_ipv4_addr + ((kactnum-1) * k5tuple->dst_ipaddr.step_addr)), (FPGA_TX_DIP_END_ADDR + offset));
                            ynic_write_fpga_byte(STREAM_TX, stream_id, ((k5tuple->dst_ipaddr.step_addr << 16) | 0x1), (FPGA_TX_DIP_STEP_ADDR + offset));
                        } else if(k5tuple->dst_ipaddr.domain == AF_INET6) {
                            uint32_t val = 0;
                            uint128_t tmp_max;
                            val = k5tuple->dst_ipaddr.min_ipv6_addr.s6_addr32[0];
                            ynic_write_fpga_byte(STREAM_TX, stream_id, val, (FPGA_TX_DIPv6_START0_ADDR + offset));
                            val = k5tuple->dst_ipaddr.min_ipv6_addr.s6_addr32[1];
                            ynic_write_fpga_byte(STREAM_TX, stream_id, val, (FPGA_TX_DIPv6_START1_ADDR + offset));
                            val = k5tuple->dst_ipaddr.min_ipv6_addr.s6_addr32[2];
                            ynic_write_fpga_byte(STREAM_TX, stream_id, val, (FPGA_TX_DIPv6_START2_ADDR + offset));
                            val = k5tuple->dst_ipaddr.min_ipv6_addr.s6_addr32[3];
                            ynic_write_fpga_byte(STREAM_TX, stream_id, val, (FPGA_TX_DIPv6_START3_ADDR + offset));

                            tmp_max = k5tuple->dst_ipaddr.min_ipv6_uint128;
                            tmp_max += (kactnum-1) * k5tuple->dst_ipaddr.step_ipv6_uint128;
                            val = tmp_max & 0xFFFFFFFF;
                            ynic_write_fpga_byte(STREAM_TX, stream_id, val, (FPGA_TX_DIPv6_END0_ADDR + offset));
                            val = (tmp_max >> 32) & 0xFFFFFFFF;
                            ynic_write_fpga_byte(STREAM_TX, stream_id, val, (FPGA_TX_DIPv6_END1_ADDR + offset));
                            val = (tmp_max >> 64) & 0xFFFFFFFF;
                            ynic_write_fpga_byte(STREAM_TX, stream_id, val, (FPGA_TX_DIPv6_END2_ADDR + offset));
                            val = (tmp_max >> 96) & 0xFFFFFFFF;
                            ynic_write_fpga_byte(STREAM_TX, stream_id, val, (FPGA_TX_DIPv6_END3_ADDR + offset));

                            ynic_write_fpga_byte(STREAM_TX, stream_id, ((k5tuple->dst_ipaddr.step_ipv6_uint128 << 16) | 0x1), (FPGA_TX_DIPv6_STEP_ADDR + offset));
                        } else {
                            printk(KERN_ERR "simuser domain %d Invalid\n", k5tuple->dst_ipaddr.domain);
                            ret = YNIC_ERR;
                            goto kfree_ret;
                        }
                    } else {
                        if(k5tuple->dst_ipaddr.domain == AF_INET) {
                            ynic_write_fpga_byte(STREAM_TX, stream_id, k5tuple->dst_ipaddr.min_ipv4_addr, (FPGA_TX_DIP_START_ADDR + offset));
                            ynic_write_fpga_byte(STREAM_TX, stream_id, k5tuple->dst_ipaddr.max_ipv4_addr, (FPGA_TX_DIP_END_ADDR + offset));
                            ynic_write_fpga_byte(STREAM_TX, stream_id, ((k5tuple->dst_ipaddr.step_addr << 16) | 0x1), (FPGA_TX_DIP_STEP_ADDR + offset));
                        } else if(k5tuple->dst_ipaddr.domain == AF_INET6) {
                            uint32_t val = 0;
                            val = k5tuple->dst_ipaddr.min_ipv6_addr.s6_addr32[0];
                            ynic_write_fpga_byte(STREAM_TX, stream_id, val, (FPGA_TX_DIPv6_START0_ADDR + offset));
                            val = k5tuple->dst_ipaddr.min_ipv6_addr.s6_addr32[1];
                            ynic_write_fpga_byte(STREAM_TX, stream_id, val, (FPGA_TX_DIPv6_START1_ADDR + offset));
                            val = k5tuple->dst_ipaddr.min_ipv6_addr.s6_addr32[2];
                            ynic_write_fpga_byte(STREAM_TX, stream_id, val, (FPGA_TX_DIPv6_START2_ADDR + offset));
                            val = k5tuple->dst_ipaddr.min_ipv6_addr.s6_addr32[3];
                            ynic_write_fpga_byte(STREAM_TX, stream_id, val, (FPGA_TX_DIPv6_START3_ADDR + offset));

                            val = k5tuple->dst_ipaddr.max_ipv6_addr.s6_addr32[0];
                            ynic_write_fpga_byte(STREAM_TX, stream_id, val, (FPGA_TX_DIPv6_END0_ADDR + offset));
                            val = k5tuple->dst_ipaddr.max_ipv6_addr.s6_addr32[1];
                            ynic_write_fpga_byte(STREAM_TX, stream_id, val, (FPGA_TX_DIPv6_END1_ADDR + offset));
                            val = k5tuple->dst_ipaddr.max_ipv6_addr.s6_addr32[2];
                            ynic_write_fpga_byte(STREAM_TX, stream_id, val, (FPGA_TX_DIPv6_END2_ADDR + offset));
                            val = k5tuple->dst_ipaddr.max_ipv6_addr.s6_addr32[3];
                            ynic_write_fpga_byte(STREAM_TX, stream_id, val, (FPGA_TX_DIPv6_END3_ADDR + offset));

                            ynic_write_fpga_byte(STREAM_TX, stream_id, ((k5tuple->dst_ipaddr.step_ipv6_uint128 << 16) | 0x1), (FPGA_TX_DIPv6_STEP_ADDR + offset));
                        } else {
                            printk(KERN_ERR "simuser domain %d Invalid\n", k5tuple->dst_ipaddr.domain);
                            ret = YNIC_ERR;
                            goto kfree_ret;
                        }

                        kfactor = kactnum / k5tuple->dst_ipaddr.nb_ipaddr;
                        kremain = kactnum % k5tuple->dst_ipaddr.nb_ipaddr;
                        if(kremain == 0) {
                            kactnum = kfactor;
                        } else {
                            kactnum = kfactor + 1;
                        }
                        if(kactnum <= k5tuple->src_port.port_count) {
                            if(k5tuple->src_ipaddr.domain == AF_INET) {
                                ynic_write_fpga_byte(STREAM_TX, stream_id, k5tuple->src_port.min_port, (FPGA_TX_SPORT_START_ADDR + offset));
                                ynic_write_fpga_byte(STREAM_TX, stream_id, (k5tuple->src_port.min_port + ((kactnum-1) * k5tuple->src_port.port_step)), (FPGA_TX_SPORT_END_ADDR + offset));
                                ynic_write_fpga_byte(STREAM_TX, stream_id, ((k5tuple->src_port.port_step << 16) | 0x1), (FPGA_TX_SPORT_STEP_ADDR + offset));
                            } else {
                                ynic_write_fpga_byte(STREAM_TX, stream_id, k5tuple->src_port.min_port, (FPGA_TX_SPORTv6_START_ADDR + offset));
                                ynic_write_fpga_byte(STREAM_TX, stream_id, (k5tuple->src_port.min_port + ((kactnum-1) * k5tuple->src_port.port_step)), (FPGA_TX_SPORTv6_END_ADDR + offset));
                                ynic_write_fpga_byte(STREAM_TX, stream_id, ((k5tuple->src_port.port_step << 16) | 0x1), (FPGA_TX_SPORTv6_STEP_ADDR + offset));
                            }
                        } else {
                            if(k5tuple->src_ipaddr.domain == AF_INET) {
                                ynic_write_fpga_byte(STREAM_TX, stream_id, k5tuple->src_port.min_port, (FPGA_TX_SPORT_START_ADDR + offset));
                                ynic_write_fpga_byte(STREAM_TX, stream_id, k5tuple->src_port.max_port, (FPGA_TX_SPORT_END_ADDR + offset));
                                ynic_write_fpga_byte(STREAM_TX, stream_id, ((k5tuple->src_port.port_step << 16) | 0x1), (FPGA_TX_SPORT_STEP_ADDR + offset));
                            } else {
                                ynic_write_fpga_byte(STREAM_TX, stream_id, k5tuple->src_port.min_port, (FPGA_TX_SPORTv6_START_ADDR + offset));
                                ynic_write_fpga_byte(STREAM_TX, stream_id, k5tuple->src_port.max_port, (FPGA_TX_SPORTv6_END_ADDR + offset));
                                ynic_write_fpga_byte(STREAM_TX, stream_id, ((k5tuple->src_port.port_step << 16) | 0x1), (FPGA_TX_SPORTv6_STEP_ADDR + offset));
                            }

                            kfactor = kactnum / k5tuple->src_port.port_count;
                            kremain = kactnum % k5tuple->src_port.port_count;
                            if(kremain == 0) {
                                kactnum = kfactor;
                            } else {
                                kactnum = kfactor + 1;
                            }
                            if(kactnum <= k5tuple->dst_port.port_count) {
                                if(k5tuple->src_ipaddr.domain == AF_INET) {
                                    ynic_write_fpga_byte(STREAM_TX, stream_id, k5tuple->dst_port.min_port, (FPGA_TX_DPORT_START_ADDR + offset));
                                    ynic_write_fpga_byte(STREAM_TX, stream_id, (k5tuple->dst_port.min_port + ((kactnum-1) *k5tuple->dst_port.port_step)), (FPGA_TX_DPORT_END_ADDR + offset));
                                    ynic_write_fpga_byte(STREAM_TX, stream_id, ((k5tuple->dst_port.port_step << 16) | 0x1), (FPGA_TX_DPORT_STEP_ADDR + offset));
                                } else {
                                    ynic_write_fpga_byte(STREAM_TX, stream_id, k5tuple->dst_port.min_port, (FPGA_TX_DPORTv6_START_ADDR + offset));
                                    ynic_write_fpga_byte(STREAM_TX, stream_id, (k5tuple->dst_port.min_port + ((kactnum-1) *k5tuple->dst_port.port_step)), (FPGA_TX_DPORTv6_END_ADDR + offset));
                                    ynic_write_fpga_byte(STREAM_TX, stream_id, ((k5tuple->dst_port.port_step << 16) | 0x1), (FPGA_TX_DPORTv6_STEP_ADDR + offset));
                                }
                            } else {
                                if(k5tuple->src_ipaddr.domain == AF_INET) {
                                    ynic_write_fpga_byte(STREAM_TX, stream_id, k5tuple->dst_port.min_port, (FPGA_TX_DPORT_START_ADDR + offset));
                                    ynic_write_fpga_byte(STREAM_TX, stream_id, k5tuple->dst_port.max_port, (FPGA_TX_DPORT_END_ADDR + offset));
                                    ynic_write_fpga_byte(STREAM_TX, stream_id, ((k5tuple->dst_port.port_step << 16) | 0x1), (FPGA_TX_DPORT_STEP_ADDR + offset));
                                } else {
                                    ynic_write_fpga_byte(STREAM_TX, stream_id, k5tuple->dst_port.min_port, (FPGA_TX_DPORTv6_START_ADDR + offset));
                                    ynic_write_fpga_byte(STREAM_TX, stream_id, k5tuple->dst_port.max_port, (FPGA_TX_DPORTv6_END_ADDR + offset));
                                    ynic_write_fpga_byte(STREAM_TX, stream_id, ((k5tuple->dst_port.port_step << 16) | 0x1), (FPGA_TX_DPORTv6_STEP_ADDR + offset));
                                }
                                printk(KERN_INFO "simuser number too many\n");
                            }
                        }
                    }
                }
            } else if(kdirect == 1) {
                if(k5tuple->src_ipaddr.domain == AF_INET) {
                    ynic_write_fpga_byte(STREAM_TX, stream_id, 0, (FPGA_TX_IPTYPE_ADDR + offset));
                } else {
                    ynic_write_fpga_byte(STREAM_TX, stream_id, 1, (FPGA_TX_IPTYPE_ADDR + offset));
                }

                if(knbuser < k5tuple->dst_ipaddr.nb_ipaddr) {
                    if(k5tuple->dst_ipaddr.domain == AF_INET) {
                        ynic_write_fpga_byte(STREAM_TX, stream_id, k5tuple->dst_ipaddr.min_ipv4_addr, (FPGA_TX_DIP_START_ADDR + offset));
                        ynic_write_fpga_byte(STREAM_TX, stream_id, (k5tuple->dst_ipaddr.min_ipv4_addr + ((knbuser-1) * k5tuple->dst_ipaddr.step_addr)), (FPGA_TX_DIP_END_ADDR + offset));
                        ynic_write_fpga_byte(STREAM_TX, stream_id, ((k5tuple->dst_ipaddr.step_addr << 16) | 0x1), (FPGA_TX_DIP_STEP_ADDR + offset));
                    } else if(k5tuple->dst_ipaddr.domain == AF_INET6) {
                        uint32_t val = 0;
                        uint128_t tmp_max;
                        val = k5tuple->dst_ipaddr.min_ipv6_addr.s6_addr32[0];
                        ynic_write_fpga_byte(STREAM_TX, stream_id, val, (FPGA_TX_DIPv6_START0_ADDR + offset));
                        val = k5tuple->dst_ipaddr.min_ipv6_addr.s6_addr32[1];
                        ynic_write_fpga_byte(STREAM_TX, stream_id, val, (FPGA_TX_DIPv6_START1_ADDR + offset));
                        val = k5tuple->dst_ipaddr.min_ipv6_addr.s6_addr32[2];
                        ynic_write_fpga_byte(STREAM_TX, stream_id, val, (FPGA_TX_DIPv6_START2_ADDR + offset));
                        val = k5tuple->dst_ipaddr.min_ipv6_addr.s6_addr32[3];
                        ynic_write_fpga_byte(STREAM_TX, stream_id, val, (FPGA_TX_DIPv6_START3_ADDR + offset));

                        tmp_max = k5tuple->dst_ipaddr.min_ipv6_uint128;
                        tmp_max += (knbuser-1) * k5tuple->dst_ipaddr.step_ipv6_uint128;
                        val = tmp_max & 0xFFFFFFFF;
                        ynic_write_fpga_byte(STREAM_TX, stream_id, val, (FPGA_TX_DIPv6_END0_ADDR + offset));
                        val = (tmp_max >> 32) & 0xFFFFFFFF;
                        ynic_write_fpga_byte(STREAM_TX, stream_id, val, (FPGA_TX_DIPv6_END1_ADDR + offset));
                        val = (tmp_max >> 64) & 0xFFFFFFFF;
                        ynic_write_fpga_byte(STREAM_TX, stream_id, val, (FPGA_TX_DIPv6_END2_ADDR + offset));
                        val = (tmp_max >> 96) & 0xFFFFFFFF;
                        ynic_write_fpga_byte(STREAM_TX, stream_id, val, (FPGA_TX_DIPv6_END3_ADDR + offset));

                        ynic_write_fpga_byte(STREAM_TX, stream_id, ((k5tuple->dst_ipaddr.step_ipv6_uint128 << 16) | 0x1), (FPGA_TX_DIPv6_STEP_ADDR + offset));
                    } else {
                        printk(KERN_ERR "simuser domain %d Invalid\n", k5tuple->dst_ipaddr.domain);
                        ret = YNIC_ERR;
                        goto kfree_ret;
                    }
                } else {
                    if(k5tuple->dst_ipaddr.domain == AF_INET) {
                        ynic_write_fpga_byte(STREAM_TX, stream_id, k5tuple->dst_ipaddr.min_ipv4_addr, (FPGA_TX_DIP_START_ADDR + offset));
                        ynic_write_fpga_byte(STREAM_TX, stream_id, k5tuple->dst_ipaddr.max_ipv4_addr, (FPGA_TX_DIP_END_ADDR + offset));
                        ynic_write_fpga_byte(STREAM_TX, stream_id, ((k5tuple->dst_ipaddr.step_addr << 16) | 0x1), (FPGA_TX_DIP_STEP_ADDR + offset));
                    } else if(k5tuple->dst_ipaddr.domain == AF_INET6) {
                        uint32_t val = 0;
                        val = k5tuple->dst_ipaddr.min_ipv6_addr.s6_addr32[0];
                        ynic_write_fpga_byte(STREAM_TX, stream_id, val, (FPGA_TX_DIPv6_START0_ADDR + offset));
                        val = k5tuple->dst_ipaddr.min_ipv6_addr.s6_addr32[1];
                        ynic_write_fpga_byte(STREAM_TX, stream_id, val, (FPGA_TX_DIPv6_START1_ADDR + offset));
                        val = k5tuple->dst_ipaddr.min_ipv6_addr.s6_addr32[2];
                        ynic_write_fpga_byte(STREAM_TX, stream_id, val, (FPGA_TX_DIPv6_START2_ADDR + offset));
                        val = k5tuple->dst_ipaddr.min_ipv6_addr.s6_addr32[3];
                        ynic_write_fpga_byte(STREAM_TX, stream_id, val, (FPGA_TX_DIPv6_START3_ADDR + offset));

                        val = k5tuple->dst_ipaddr.max_ipv6_addr.s6_addr32[0];
                        ynic_write_fpga_byte(STREAM_TX, stream_id, val, (FPGA_TX_DIPv6_END0_ADDR + offset));
                        val = k5tuple->dst_ipaddr.max_ipv6_addr.s6_addr32[1];
                        ynic_write_fpga_byte(STREAM_TX, stream_id, val, (FPGA_TX_DIPv6_END1_ADDR + offset));
                        val = k5tuple->dst_ipaddr.max_ipv6_addr.s6_addr32[2];
                        ynic_write_fpga_byte(STREAM_TX, stream_id, val, (FPGA_TX_DIPv6_END2_ADDR + offset));
                        val = k5tuple->dst_ipaddr.max_ipv6_addr.s6_addr32[3];
                        ynic_write_fpga_byte(STREAM_TX, stream_id, val, (FPGA_TX_DIPv6_END3_ADDR + offset));

                        ynic_write_fpga_byte(STREAM_TX, stream_id, ((k5tuple->dst_ipaddr.step_ipv6_uint128 << 16) | 0x1), (FPGA_TX_DIPv6_STEP_ADDR + offset));
                    } else {
                        printk(KERN_ERR "simuser domain %d Invalid\n", k5tuple->dst_ipaddr.domain);
                        ret = YNIC_ERR;
                        goto kfree_ret;
                    }

                    kfactor = knbuser / k5tuple->dst_ipaddr.nb_ipaddr;
                    kremain = knbuser % k5tuple->dst_ipaddr.nb_ipaddr;
                    if(kremain == 0) {
                        kactnum = kfactor;
                    } else {
                        kactnum = kfactor + 1;
                    }

                    if(kactnum < k5tuple->src_ipaddr.nb_ipaddr) {
                        if(k5tuple->src_ipaddr.domain == AF_INET) {
                            ynic_write_fpga_byte(STREAM_TX, stream_id, k5tuple->src_ipaddr.min_ipv4_addr, (FPGA_TX_SIP_START_ADDR + offset));
                            ynic_write_fpga_byte(STREAM_TX, stream_id, (k5tuple->src_ipaddr.min_ipv4_addr + ((kactnum-1) * k5tuple->src_ipaddr.step_addr)), (FPGA_TX_SIP_END_ADDR + offset));
                            ynic_write_fpga_byte(STREAM_TX, stream_id, ((k5tuple->src_ipaddr.step_addr << 16) | 0x1), (FPGA_TX_SIP_STEP_ADDR + offset));
                        } else if(k5tuple->src_ipaddr.domain == AF_INET6) {
                            uint32_t val = 0;
                            uint128_t tmp_max;
                            val = k5tuple->src_ipaddr.min_ipv6_addr.s6_addr32[0];
                            ynic_write_fpga_byte(STREAM_TX, stream_id, val, (FPGA_TX_SIPv6_START0_ADDR + offset));
                            val = k5tuple->src_ipaddr.min_ipv6_addr.s6_addr32[1];
                            ynic_write_fpga_byte(STREAM_TX, stream_id, val, (FPGA_TX_SIPv6_START1_ADDR + offset));
                            val = k5tuple->src_ipaddr.min_ipv6_addr.s6_addr32[2];
                            ynic_write_fpga_byte(STREAM_TX, stream_id, val, (FPGA_TX_SIPv6_START2_ADDR + offset));
                            val = k5tuple->src_ipaddr.min_ipv6_addr.s6_addr32[3];
                            ynic_write_fpga_byte(STREAM_TX, stream_id, val, (FPGA_TX_SIPv6_START3_ADDR + offset));

                            tmp_max = k5tuple->src_ipaddr.min_ipv6_uint128;
                            tmp_max += (kactnum-1) * k5tuple->src_ipaddr.step_ipv6_uint128;
                            val = tmp_max & 0xFFFFFFFF;
                            ynic_write_fpga_byte(STREAM_TX, stream_id, val, (FPGA_TX_SIPv6_END0_ADDR + offset));
                            val = (tmp_max >> 32) & 0xFFFFFFFF;
                            ynic_write_fpga_byte(STREAM_TX, stream_id, val, (FPGA_TX_SIPv6_END1_ADDR + offset));
                            val = (tmp_max >> 64) & 0xFFFFFFFF;
                            ynic_write_fpga_byte(STREAM_TX, stream_id, val, (FPGA_TX_SIPv6_END2_ADDR + offset));
                            val = (tmp_max >> 96) & 0xFFFFFFFF;
                            ynic_write_fpga_byte(STREAM_TX, stream_id, val, (FPGA_TX_SIPv6_END3_ADDR + offset));

                            ynic_write_fpga_byte(STREAM_TX, stream_id, ((k5tuple->src_ipaddr.step_ipv6_uint128 << 16) | 0x1), (FPGA_TX_SIPv6_STEP_ADDR + offset));
                        } else {
                            printk(KERN_ERR "simuser domain %d Invalid\n", k5tuple->src_ipaddr.domain);
                            ret = YNIC_ERR;
                            goto kfree_ret;
                        }
                    } else {
                        if(k5tuple->src_ipaddr.domain == AF_INET) {
                            ynic_write_fpga_byte(STREAM_TX, stream_id, k5tuple->src_ipaddr.min_ipv4_addr, (FPGA_TX_SIP_START_ADDR + offset));
                            ynic_write_fpga_byte(STREAM_TX, stream_id, k5tuple->src_ipaddr.max_ipv4_addr, (FPGA_TX_SIP_END_ADDR + offset));
                            ynic_write_fpga_byte(STREAM_TX, stream_id, ((k5tuple->src_ipaddr.step_addr << 16) | 0x1), (FPGA_TX_SIP_STEP_ADDR + offset));
                        } else if(k5tuple->src_ipaddr.domain == AF_INET6) {
                            uint32_t val = 0;
                            val = k5tuple->src_ipaddr.min_ipv6_addr.s6_addr32[0];
                            ynic_write_fpga_byte(STREAM_TX, stream_id, val, (FPGA_TX_SIPv6_START0_ADDR + offset));
                            val = k5tuple->src_ipaddr.min_ipv6_addr.s6_addr32[1];
                            ynic_write_fpga_byte(STREAM_TX, stream_id, val, (FPGA_TX_SIPv6_START1_ADDR + offset));
                            val = k5tuple->src_ipaddr.min_ipv6_addr.s6_addr32[2];
                            ynic_write_fpga_byte(STREAM_TX, stream_id, val, (FPGA_TX_SIPv6_START2_ADDR + offset));
                            val = k5tuple->src_ipaddr.min_ipv6_addr.s6_addr32[3];
                            ynic_write_fpga_byte(STREAM_TX, stream_id, val, (FPGA_TX_SIPv6_START3_ADDR + offset));

                            val = k5tuple->src_ipaddr.max_ipv6_addr.s6_addr32[0];
                            ynic_write_fpga_byte(STREAM_TX, stream_id, val, (FPGA_TX_SIPv6_END0_ADDR + offset));
                            val = k5tuple->src_ipaddr.max_ipv6_addr.s6_addr32[1];
                            ynic_write_fpga_byte(STREAM_TX, stream_id, val, (FPGA_TX_SIPv6_END1_ADDR + offset));
                            val = k5tuple->src_ipaddr.max_ipv6_addr.s6_addr32[2];
                            ynic_write_fpga_byte(STREAM_TX, stream_id, val, (FPGA_TX_SIPv6_END2_ADDR + offset));
                            val = k5tuple->src_ipaddr.max_ipv6_addr.s6_addr32[3];
                            ynic_write_fpga_byte(STREAM_TX, stream_id, val, (FPGA_TX_SIPv6_END3_ADDR + offset));

                            ynic_write_fpga_byte(STREAM_TX, stream_id, ((k5tuple->src_ipaddr.step_ipv6_uint128 << 16) | 0x1), (FPGA_TX_SIPv6_STEP_ADDR + offset));
                        } else {
                            printk(KERN_ERR "simuser domain %d Invalid\n", k5tuple->src_ipaddr.domain);
                            ret = YNIC_ERR;
                            goto kfree_ret;
                        }

                        kfactor = kactnum / k5tuple->src_ipaddr.nb_ipaddr;
                        kremain = kactnum % k5tuple->src_ipaddr.nb_ipaddr;
                        if(kremain == 0) {
                            kactnum = kfactor;
                        } else {
                            kactnum = kfactor + 1;
                        }
                        if(kactnum <= k5tuple->dst_port.port_count) {
                            if(k5tuple->src_ipaddr.domain == AF_INET) {
                                ynic_write_fpga_byte(STREAM_TX, stream_id, k5tuple->dst_port.min_port, (FPGA_TX_DPORT_START_ADDR + offset));
                                ynic_write_fpga_byte(STREAM_TX, stream_id, (k5tuple->dst_port.min_port + ((kactnum-1) *k5tuple->dst_port.port_step)), (FPGA_TX_DPORT_END_ADDR + offset));
                                ynic_write_fpga_byte(STREAM_TX, stream_id, ((k5tuple->dst_port.port_step << 16) | 0x1), (FPGA_TX_DPORT_STEP_ADDR + offset));
                            } else {
                                ynic_write_fpga_byte(STREAM_TX, stream_id, k5tuple->dst_port.min_port, (FPGA_TX_DPORTv6_START_ADDR + offset));
                                ynic_write_fpga_byte(STREAM_TX, stream_id, (k5tuple->dst_port.min_port + ((kactnum-1) *k5tuple->dst_port.port_step)), (FPGA_TX_DPORTv6_END_ADDR + offset));
                                ynic_write_fpga_byte(STREAM_TX, stream_id, ((k5tuple->dst_port.port_step << 16) | 0x1), (FPGA_TX_DPORTv6_STEP_ADDR + offset));
                            }
                        } else {
                            if(k5tuple->src_ipaddr.domain == AF_INET) {
                                ynic_write_fpga_byte(STREAM_TX, stream_id, k5tuple->dst_port.min_port, (FPGA_TX_DPORT_START_ADDR + offset));
                                ynic_write_fpga_byte(STREAM_TX, stream_id, k5tuple->dst_port.max_port, (FPGA_TX_DPORT_END_ADDR + offset));
                                ynic_write_fpga_byte(STREAM_TX, stream_id, ((k5tuple->dst_port.port_step << 16) | 0x1), (FPGA_TX_DPORT_STEP_ADDR + offset));
                            } else {
                                ynic_write_fpga_byte(STREAM_TX, stream_id, k5tuple->dst_port.min_port, (FPGA_TX_DPORTv6_START_ADDR + offset));
                                ynic_write_fpga_byte(STREAM_TX, stream_id, k5tuple->dst_port.max_port, (FPGA_TX_DPORTv6_END_ADDR + offset));
                                ynic_write_fpga_byte(STREAM_TX, stream_id, ((k5tuple->dst_port.port_step << 16) | 0x1), (FPGA_TX_DPORTv6_STEP_ADDR + offset));
                            }
                            printk(KERN_INFO "simuser number too many\n");

                            kfactor = kactnum / k5tuple->dst_port.port_count;
                            kremain = kactnum % k5tuple->dst_port.port_count;
                            if(kremain == 0) {
                                kactnum = kfactor;
                            } else {
                                kactnum = kfactor + 1;
                            }

                            if(kactnum <= k5tuple->src_port.port_count) {
                                if(k5tuple->src_ipaddr.domain == AF_INET) {
                                    ynic_write_fpga_byte(STREAM_TX, stream_id, k5tuple->src_port.min_port, (FPGA_TX_SPORT_START_ADDR + offset));
                                    ynic_write_fpga_byte(STREAM_TX, stream_id, (k5tuple->src_port.min_port + ((kactnum-1) * k5tuple->src_port.port_step)), (FPGA_TX_SPORT_END_ADDR + offset));
                                    ynic_write_fpga_byte(STREAM_TX, stream_id, ((k5tuple->src_port.port_step << 16) | 0x1), (FPGA_TX_SPORT_STEP_ADDR + offset));
                                } else {
                                    ynic_write_fpga_byte(STREAM_TX, stream_id, k5tuple->src_port.min_port, (FPGA_TX_SPORTv6_START_ADDR + offset));
                                    ynic_write_fpga_byte(STREAM_TX, stream_id, (k5tuple->src_port.min_port + ((kactnum-1) * k5tuple->src_port.port_step)), (FPGA_TX_SPORTv6_END_ADDR + offset));
                                    ynic_write_fpga_byte(STREAM_TX, stream_id, ((k5tuple->src_port.port_step << 16) | 0x1), (FPGA_TX_SPORTv6_STEP_ADDR + offset));
                                }
                            } else {
                                if(k5tuple->src_ipaddr.domain == AF_INET) {
                                    ynic_write_fpga_byte(STREAM_TX, stream_id, k5tuple->src_port.min_port, (FPGA_TX_SPORT_START_ADDR + offset));
                                    ynic_write_fpga_byte(STREAM_TX, stream_id, k5tuple->src_port.max_port, (FPGA_TX_SPORT_END_ADDR + offset));


                                    ynic_write_fpga_byte(STREAM_TX, stream_id, ((k5tuple->src_port.port_step << 16) | 0x1), (FPGA_TX_SPORT_STEP_ADDR + offset));
                                } else {
                                    ynic_write_fpga_byte(STREAM_TX, stream_id, k5tuple->src_port.min_port, (FPGA_TX_SPORTv6_START_ADDR + offset));
                                    ynic_write_fpga_byte(STREAM_TX, stream_id, k5tuple->src_port.max_port, (FPGA_TX_SPORTv6_END_ADDR + offset));
                                    ynic_write_fpga_byte(STREAM_TX, stream_id, ((k5tuple->src_port.port_step << 16) | 0x1), (FPGA_TX_SPORTv6_STEP_ADDR + offset));
                                }
                                printk(KERN_INFO "simuser number too many\n");
                            }
                        }
                    }
                }
            } else {
                printk(KERN_ERR "tx direct err,%d\n", kdirect);
            }
        } else {
            printk(KERN_ERR "simuser is %d Invalid\n", knbuser);
        }

#ifdef DEBUG_ON
        ynic_read_fpga_byte(STREAM_TX, stream_id, &val1,(FPGA_TX_SIP_START_ADDR + offset));
        ynic_read_fpga_byte(STREAM_TX, stream_id, &val2,(FPGA_TX_SIP_END_ADDR + offset));
        ynic_read_fpga_byte(STREAM_TX, stream_id, &val3,(FPGA_TX_SIP_STEP_ADDR + offset));
        printk("zc-61-sip-min=0x%08x-max=0x%08x-step=0x%08x\n",val1,val2,val3);
        ynic_read_fpga_byte(STREAM_TX, stream_id, &val1,(FPGA_TX_DIP_START_ADDR + offset));
        ynic_read_fpga_byte(STREAM_TX, stream_id, &val2,(FPGA_TX_DIP_END_ADDR + offset));
        ynic_read_fpga_byte(STREAM_TX, stream_id, &val3,(FPGA_TX_DIP_STEP_ADDR + offset));
        printk("zc-62-dip-min=0x%08x-max=0x%08x-step=0x%08x\n",val1,val2,val3);
        ynic_read_fpga_byte(STREAM_TX, stream_id,&val1, (FPGA_TX_SPORT_START_ADDR + offset));
        ynic_read_fpga_byte(STREAM_TX, stream_id,&val2, (FPGA_TX_SPORT_END_ADDR + offset));
        ynic_read_fpga_byte(STREAM_TX, stream_id,&val3, (FPGA_TX_SPORT_STEP_ADDR + offset));
        printk("zc-63-sport-min=0x%08x-max=0x%08x-step=0x%08x\n",val1,val2,val3);
        ynic_read_fpga_byte(STREAM_TX, stream_id, &val1,(FPGA_TX_DPORT_START_ADDR + offset));
        ynic_read_fpga_byte(STREAM_TX, stream_id, &val2,(FPGA_TX_DPORT_END_ADDR + offset));
        ynic_read_fpga_byte(STREAM_TX, stream_id, &val3,(FPGA_TX_DPORT_STEP_ADDR + offset));
        printk("zc-64-dport-min=0x%08x-max=0x%08x-step=0x%08x\n",val1,val2,val3);
#endif

    } else if((kmsg_mode == 1) && (knb_zones > 0)) { //流模板
    //多个跳变域,数据按实际长度下发。
        kmdf_array = kmalloc(sizeof(mdf_zone_var_t) * knb_zones, GFP_KERNEL);
        if(!kmdf_array) {
            ret = YNIC_ERR;
            goto kfree_ret;
        }

        if(copy_from_user(kmdf_array, kstream_cfg->nsnic_mdf_zone_array, sizeof(mdf_zone_var_t) * knb_zones)) {
            ret = YNIC_ERR;
            goto kfree_ret;
        }

        // ktype = kmdf_array->value_type;
        // kmode = kmdf_array->value_mode;
        //todo跳变方式区分：列表和非列表
        for(k=0; k < knb_zones; k++) {

            ktype = kmdf_array[k].value_type;
            if(MDF_ZONE_UINT8_TYPE == ktype) {
                kmdf_total_len += sizeof(mdf_uint8_zone_t)/sizeof(uint8_t);
            } else if(MDF_ZONE_UINT16_TYPE == ktype) {
                kmdf_total_len += sizeof(mdf_uint16_zone_t)/sizeof(uint8_t);
            } else if(MDF_ZONE_UINT32_TYPE == ktype) {
                kmdf_total_len += sizeof(mdf_uint32_zone_t)/sizeof(uint8_t);
            } else if(MDF_ZONE_IP4_ADR_TYPE == ktype) {
                kmdf_total_len += sizeof(mdf_ipaddr_zone_t)/sizeof(uint8_t);
            } else if(MDF_ZONE_IP6_ADR_TYPE == ktype) {
                kmdf_total_len += sizeof(mdf_ipaddr_zone_t)/sizeof(uint8_t);
            } else if(MDF_ZONE_MAC_ADR_TYPE == ktype) {
                kmdf_total_len += sizeof(mdf_macaddr_zone_t)/sizeof(uint8_t);
            } else {
                printk(KERN_ERR "[%s] Invalid mdf type: %d", __func__, ktype);
                ret = YNIC_ERR;
                goto kfree_ret;
            }

        }
        kmdf_total_len += knb_zones * YNIC_TX_STREAM_MDF_LENGTH;
        KDBG("zc-21-mdf,k=%d,ktype=%d,knb_zones=%d, kmdf_total_len=%lld\n",k, ktype, knb_zones, kmdf_total_len);

        kmdf = kmalloc(sizeof(uint8_t) * kmdf_total_len, GFP_KERNEL);
        if(!kmdf) {
            printk(KERN_ERR "kmdf kmalloc error,line=%d\n", __LINE__);
            ret = YNIC_ERR;
            goto kfree_ret;
        }

        /*val:0x00,0x00,0x02,0x00,0x02,0x00,0x00,0x00,
              0x15,0x00,0x01,0x00,0x00,0x00,0x01,0x00,
              0x00,0x00,0x01,0x00,0x01,0xff,*/
        kmdf_tmp = kmdf;
        for(m=0; m < knb_zones; m++) {
            ktype = kmdf_array[m].value_type;
            kmode = kmdf_array[m].value_mode;

            memcpy(kmdf_tmp, &(kmdf_array[m].priority), sizeof(uint16_t));
            kmdf_tmp += sizeof(uint16_t);
            kmdf_actual_len += sizeof(uint16_t);

            memcpy(kmdf_tmp, &(kmdf_array[m].value_type), sizeof(uint16_t));
            kmdf_tmp += sizeof(uint16_t);
            kmdf_actual_len += sizeof(uint16_t);

            memcpy(kmdf_tmp, &(kmdf_array[m].value_mode), sizeof(uint16_t));
            kmdf_tmp += sizeof(uint16_t);
            kmdf_actual_len += sizeof(uint16_t);

            memcpy(kmdf_tmp, &(kmdf_array[m].value_count), sizeof(uint16_t));
            kmdf_tmp += sizeof(uint16_t);
            kmdf_actual_len += sizeof(uint16_t);

            memcpy(kmdf_tmp, &(kmdf_array[m].buf_pos), sizeof(uint16_t));
            kmdf_tmp += sizeof(uint16_t);
            kmdf_actual_len += sizeof(uint16_t);
            tmp_value_off = kmdf_array[m].buf_pos;

            memcpy(kmdf_tmp, &(kmdf_array[m].buf_size), sizeof(uint32_t));
            kmdf_tmp += sizeof(uint32_t);
            kmdf_actual_len += sizeof(uint32_t);



            if(MDF_ZONE_UINT8_TYPE == ktype) {
                kmdf_type_ptr = kmalloc(sizeof(mdf_uint8_zone_t), GFP_KERNEL);
                if(!kmdf_type_ptr) {
                    printk(KERN_ERR "mdf_zone_type_t kmalloc error,line:%d\n",__LINE__);
                    ret = YNIC_ERR;
                    goto kfree_ret;
                }
                if(copy_from_user(kmdf_type_ptr, kmdf_array[m].mdf_uint8_zone, sizeof(mdf_uint8_zone_t))) {
                    ret = YNIC_ERR;
                    goto kfree_ret;
                }

                memcpy(kmdf_tmp, &((mdf_uint8_zone_t *)kmdf_type_ptr)->zone_count, sizeof(uint32_t)); //数据类型为little endian
                kmdf_tmp += sizeof(uint32_t);
                kmdf_actual_len += sizeof(uint32_t);
                tmp_value_count = ((mdf_uint8_zone_t *)kmdf_type_ptr)->zone_count;

                memcpy(kmdf_tmp, &((mdf_uint8_zone_t *)kmdf_type_ptr)->value_start, sizeof(uint8_t));
                kmdf_tmp += sizeof(uint8_t);
                kmdf_actual_len += sizeof(uint8_t);
                tmp_value_start = ((mdf_uint8_zone_t *)kmdf_type_ptr)->value_start;

                memcpy(kmdf_tmp, &((mdf_uint8_zone_t *)kmdf_type_ptr)->value_end, sizeof(uint8_t));
                kmdf_tmp += sizeof(uint8_t);
                kmdf_actual_len += sizeof(uint8_t);
                tmp_value_end = ((mdf_uint8_zone_t *)kmdf_type_ptr)->value_end;

                memcpy(kmdf_tmp, &((mdf_uint8_zone_t *)kmdf_type_ptr)->value_step, sizeof(uint8_t));
                kmdf_tmp += sizeof(uint8_t);
                kmdf_actual_len += sizeof(uint8_t);
                tmp_value_step = ((mdf_uint8_zone_t *)kmdf_type_ptr)->value_step;

                memcpy(kmdf_tmp, &((mdf_uint8_zone_t *)kmdf_type_ptr)->value_mask, sizeof(uint8_t));
                kmdf_tmp += sizeof(uint8_t);
                kmdf_actual_len += sizeof(uint8_t);
                tmp_value_mask = ((mdf_uint8_zone_t *)kmdf_type_ptr)->value_mask;

                KDBG("zc-22-uint8\n");
                KDBG("zc-23-ktype=0x%08x,start=0x%02x,count=%u,step=0x%02x,mask=0x%02x\n", 
                        ktype, (uint8_t)tmp_value_start,tmp_value_count,(uint8_t)tmp_value_step,(uint8_t)tmp_value_mask);

            } else if(MDF_ZONE_UINT16_TYPE == ktype) {
                kmdf_type_ptr = kmalloc(sizeof(mdf_uint16_zone_t), GFP_KERNEL);
                if(!kmdf_type_ptr) {
                    printk(KERN_ERR "mdf_zone_type_t kmalloc error,line:%d\n",__LINE__);
                    ret = YNIC_ERR;
                    goto kfree_ret;
                }
                if(copy_from_user(kmdf_type_ptr, kmdf_array[m].mdf_uint16_zone, sizeof(mdf_uint16_zone_t))) {
                    ret = YNIC_ERR;
                    goto kfree_ret;
                }

                memcpy(kmdf_tmp, &((mdf_uint16_zone_t *)kmdf_type_ptr)->zone_count, sizeof(uint32_t));
                kmdf_tmp += sizeof(uint32_t);
                kmdf_actual_len += sizeof(uint32_t);
                tmp_value_count = ((mdf_uint16_zone_t *)kmdf_type_ptr)->zone_count;

                memcpy(kmdf_tmp, &((mdf_uint16_zone_t *)kmdf_type_ptr)->value_start, sizeof(uint16_t));
                kmdf_tmp += sizeof(uint16_t);
                kmdf_actual_len += sizeof(uint16_t);
                tmp_value_start = ((mdf_uint16_zone_t *)kmdf_type_ptr)->value_start;

                memcpy(kmdf_tmp, &((mdf_uint16_zone_t *)kmdf_type_ptr)->value_end, sizeof(uint16_t));
                kmdf_tmp += sizeof(uint16_t);
                kmdf_actual_len += sizeof(uint16_t);
                tmp_value_end = ((mdf_uint16_zone_t *)kmdf_type_ptr)->value_end;


                memcpy(kmdf_tmp, &((mdf_uint16_zone_t *)kmdf_type_ptr)->value_step, sizeof(uint16_t));
                kmdf_tmp += sizeof(uint16_t);
                kmdf_actual_len += sizeof(uint16_t);
                tmp_value_step = ((mdf_uint16_zone_t *)kmdf_type_ptr)->value_step;

                memcpy(kmdf_tmp, &((mdf_uint16_zone_t *)kmdf_type_ptr)->value_mask, sizeof(uint16_t));
                kmdf_tmp += sizeof(uint16_t);
                kmdf_actual_len += sizeof(uint16_t);
                tmp_value_mask = ((mdf_uint16_zone_t *)kmdf_type_ptr)->value_mask;

                KDBG("zc-22-uint16\n");
                KDBG("zc-23-ktype=0x%08x,start=0x%04x,count=%u,step=0x%04x,mask=0x%04x\n",
                        ktype, (uint16_t)tmp_value_start,tmp_value_count,(uint16_t)tmp_value_step,(uint16_t)tmp_value_mask);


            } else if(MDF_ZONE_UINT32_TYPE == ktype) {

                kmdf_type_ptr = kmalloc(sizeof(mdf_uint32_zone_t), GFP_KERNEL);
                if(!kmdf_type_ptr) {
                    printk(KERN_ERR "mdf_zone_type_t kmalloc error,line:%d\n",__LINE__);
                    ret = YNIC_ERR;
                    goto kfree_ret;
                }
                if(copy_from_user(kmdf_type_ptr, kmdf_array[m].mdf_uint32_zone, sizeof(mdf_uint32_zone_t))) {
                    ret = YNIC_ERR;
                    goto kfree_ret;
                }

                memcpy(kmdf_tmp, &((mdf_uint32_zone_t *)kmdf_type_ptr)->zone_count, sizeof(uint32_t));
                kmdf_tmp += sizeof(uint32_t);
                kmdf_actual_len += sizeof(uint32_t);
                tmp_value_count = ((mdf_uint32_zone_t *)kmdf_type_ptr)->zone_count;

                memcpy(kmdf_tmp, &((mdf_uint32_zone_t *)kmdf_type_ptr)->value_start, sizeof(uint32_t));
                kmdf_tmp += sizeof(uint32_t);
                kmdf_actual_len += sizeof(uint32_t);
                tmp_value_start = ((mdf_uint32_zone_t *)kmdf_type_ptr)->value_start;

                memcpy(kmdf_tmp, &((mdf_uint32_zone_t *)kmdf_type_ptr)->value_end, sizeof(uint32_t));
                kmdf_tmp += sizeof(uint32_t);
                kmdf_actual_len += sizeof(uint32_t);
                tmp_value_end = ((mdf_uint32_zone_t *)kmdf_type_ptr)->value_end;

                memcpy(kmdf_tmp, &((mdf_uint32_zone_t *)kmdf_type_ptr)->value_step, sizeof(uint32_t));
                kmdf_tmp += sizeof(uint32_t);
                kmdf_actual_len += sizeof(uint32_t);
                tmp_value_step = ((mdf_uint32_zone_t *)kmdf_type_ptr)->value_step;

                memcpy(kmdf_tmp, &((mdf_uint32_zone_t *)kmdf_type_ptr)->value_mask, sizeof(uint32_t));
                kmdf_tmp += sizeof(uint32_t);
                kmdf_actual_len += sizeof(uint32_t);
                tmp_value_mask = ((mdf_uint32_zone_t *)kmdf_type_ptr)->value_mask;

                KDBG("zc-22-uint32\n");
                KDBG("zc-23-ktype=0x%08x,start=0x%08x,count=%u,step=0x%08x,mask=0x%08x\n",
                        ktype, (uint32_t)tmp_value_start,tmp_value_count,(uint32_t)tmp_value_step,(uint32_t)tmp_value_mask);

            } else if(MDF_ZONE_IP4_ADR_TYPE ==ktype) {
                kmdf_type_ptr = kmalloc(sizeof(mdf_ipaddr_zone_t), GFP_KERNEL);
                if(!kmdf_type_ptr) {
                    printk(KERN_ERR "mdf_zone_type_t kmalloc error,line:%d\n",__LINE__);
                    ret = YNIC_ERR;
                    goto kfree_ret;
                }
                if(copy_from_user(kmdf_type_ptr, kmdf_array[m].mdf_ip4adr_zone, sizeof(mdf_ipaddr_zone_t))) {
                    ret = YNIC_ERR;
                    goto kfree_ret;
                }

                memcpy(kmdf_tmp, &((mdf_ipaddr_zone_t *)kmdf_type_ptr)->zone_count, sizeof(uint32_t));
                kmdf_tmp += sizeof(uint32_t);
                kmdf_actual_len += sizeof(uint32_t);
                tmp_value_count = ((mdf_ipaddr_zone_t *)kmdf_type_ptr)->zone_count;

                memcpy(kmdf_tmp, &((mdf_ipaddr_zone_t *)kmdf_type_ptr)->ip_domain, sizeof(uint8_t));
                kmdf_tmp += sizeof(uint8_t);
                kmdf_actual_len += sizeof(uint8_t);

                memcpy(kmdf_tmp, &((mdf_ipaddr_zone_t *)kmdf_type_ptr)->value_start, sizeof(ip_addr_t));
                kmdf_tmp += sizeof(ip_addr_t);
                kmdf_actual_len += sizeof(ip_addr_t);
                tmp_value_start = (((mdf_ipaddr_zone_t *)kmdf_type_ptr)->value_start.net_ipv4_addr);

                memcpy(kmdf_tmp, &((mdf_ipaddr_zone_t *)kmdf_type_ptr)->value_end, sizeof(ip_addr_t));
                kmdf_tmp += sizeof(ip_addr_t);
                kmdf_actual_len += sizeof(ip_addr_t);
                tmp_value_end = (((mdf_ipaddr_zone_t *)kmdf_type_ptr)->value_end.net_ipv4_addr);

                memcpy(kmdf_tmp, &((mdf_ipaddr_zone_t *)kmdf_type_ptr)->value_step, sizeof(ip_addr_t));
                kmdf_tmp += sizeof(ip_addr_t);
                kmdf_actual_len += sizeof(ip_addr_t);
                tmp_value_step = (((mdf_ipaddr_zone_t *)kmdf_type_ptr)->value_step.net_ipv4_addr);

                memcpy(kmdf_tmp, &((mdf_ipaddr_zone_t *)kmdf_type_ptr)->value_mask, sizeof(ip_addr_t));
                kmdf_tmp += sizeof(ip_addr_t);
                kmdf_actual_len += sizeof(ip_addr_t);
                tmp_value_mask = (((mdf_ipaddr_zone_t *)kmdf_type_ptr)->value_mask.net_ipv4_addr);

                KDBG("zc-22-ip4\n");
                KDBG("zc-23-ktype=0x%08x,start=0x%08x,count=%u,step=0x%08x,mask=0x%08x\n", 
                        ktype, (uint32_t)tmp_value_start,tmp_value_count,(uint32_t)tmp_value_step,(uint32_t)tmp_value_mask);

            } else if(MDF_ZONE_IP6_ADR_TYPE == ktype) {
                kmdf_type_ptr = kmalloc(sizeof(mdf_ipaddr_zone_t), GFP_KERNEL);
                if(!kmdf_type_ptr) {
                    printk(KERN_ERR "mdf_zone_type_t kmalloc error,line:%d\n",__LINE__);
                    ret = YNIC_ERR;
                    goto kfree_ret;
                }
                if(copy_from_user(kmdf_type_ptr, kmdf_array[m].mdf_ip6adr_zone, sizeof(mdf_ipaddr_zone_t))) {
                    ret = YNIC_ERR;
                    goto kfree_ret;
                }

                memcpy(kmdf_tmp, &((mdf_ipaddr_zone_t *)kmdf_type_ptr)->zone_count, sizeof(uint32_t));
                kmdf_tmp += sizeof(uint32_t);
                kmdf_actual_len += sizeof(uint32_t);
                tmp_value_count = ((mdf_ipaddr_zone_t *)kmdf_type_ptr)->zone_count;

                memcpy(kmdf_tmp, &((mdf_ipaddr_zone_t *)kmdf_type_ptr)->ip_domain, sizeof(uint8_t));
                kmdf_tmp += sizeof(uint8_t);
                kmdf_actual_len += sizeof(uint8_t);

                memcpy(kmdf_tmp, &((mdf_ipaddr_zone_t *)kmdf_type_ptr)->value_start, sizeof(ip_addr_t));
                kmdf_tmp += sizeof(ip_addr_t);
                kmdf_actual_len += sizeof(ip_addr_t);
                tmp_value_start = (((mdf_ipaddr_zone_t *)kmdf_type_ptr)->value_start.ipv6_uint128);

                memcpy(kmdf_tmp, &((mdf_ipaddr_zone_t *)kmdf_type_ptr)->value_end, sizeof(ip_addr_t));
                kmdf_tmp += sizeof(ip_addr_t);
                kmdf_actual_len += sizeof(ip_addr_t);
                tmp_value_end = (((mdf_ipaddr_zone_t *)kmdf_type_ptr)->value_end.ipv6_uint128);

                memcpy(kmdf_tmp, &((mdf_ipaddr_zone_t *)kmdf_type_ptr)->value_step, sizeof(ip_addr_t));
                kmdf_tmp += sizeof(ip_addr_t);
                kmdf_actual_len += sizeof(ip_addr_t);
                tmp_value_step = (((mdf_ipaddr_zone_t *)kmdf_type_ptr)->value_step.ipv6_uint128);

                memcpy(kmdf_tmp, &((mdf_ipaddr_zone_t *)kmdf_type_ptr)->value_mask, sizeof(ip_addr_t));
                kmdf_tmp += sizeof(ip_addr_t);
                kmdf_actual_len += sizeof(ip_addr_t);
                tmp_value_mask = (((mdf_ipaddr_zone_t *)kmdf_type_ptr)->value_mask.ipv6_uint128);

                KDBG("zc-22-ip6\n");
                KDBG("zc-23-ktype=0x%08x,start=0x%llx,count=%u,step=0x%llx,mask=0x%llx\n",
                        ktype, (unsigned long long)tmp_value_start,tmp_value_count,(unsigned long long)tmp_value_step,(unsigned long long)tmp_value_mask);

            } else if(MDF_ZONE_MAC_ADR_TYPE == ktype) {
                kmdf_type_ptr = kmalloc(sizeof(mdf_macaddr_zone_t), GFP_KERNEL);
                if(!kmdf_type_ptr) {
                    printk(KERN_ERR "mdf_zone_type_t kmalloc error,line:%d\n",__LINE__);
                    ret = YNIC_ERR;
                    goto kfree_ret;
                }
                if(copy_from_user(kmdf_type_ptr, kmdf_array[m].mdf_macaddr_zone, sizeof(mdf_macaddr_zone_t))) {
                    ret = YNIC_ERR;
                    goto kfree_ret;
                }

                memcpy(kmdf_tmp, &((mdf_macaddr_zone_t *)kmdf_type_ptr)->zone_count, sizeof(uint32_t));
                kmdf_tmp += sizeof(uint32_t);
                kmdf_actual_len += sizeof(uint32_t);
                tmp_value_count = ((mdf_ipaddr_zone_t *)kmdf_type_ptr)->zone_count;

                memcpy(kmdf_tmp, &((mdf_macaddr_zone_t *)kmdf_type_ptr)->value_start, sizeof(eth_adr_t));
                kmdf_tmp += sizeof(eth_adr_t);
                kmdf_actual_len += sizeof(eth_adr_t);
                memcpy(&tmp_value_start, &((mdf_macaddr_zone_t *)kmdf_type_ptr)->value_start, sizeof(eth_adr_t));

                memcpy(kmdf_tmp, &((mdf_macaddr_zone_t *)kmdf_type_ptr)->value_end, sizeof(eth_adr_t));
                kmdf_tmp += sizeof(eth_adr_t);
                kmdf_actual_len += sizeof(eth_adr_t);
                memcpy(&tmp_value_end, &((mdf_macaddr_zone_t *)kmdf_type_ptr)->value_end, sizeof(eth_adr_t));

                memcpy(kmdf_tmp, &((mdf_macaddr_zone_t *)kmdf_type_ptr)->value_step, sizeof(eth_adr_t));
                kmdf_tmp += sizeof(eth_adr_t);
                kmdf_actual_len += sizeof(eth_adr_t);
                memcpy(&tmp_value_step, &((mdf_macaddr_zone_t *)kmdf_type_ptr)->value_step, sizeof(eth_adr_t));

                memcpy(kmdf_tmp, &((mdf_macaddr_zone_t *)kmdf_type_ptr)->value_mask, sizeof(eth_adr_t));
                kmdf_tmp += sizeof(eth_adr_t);
                kmdf_actual_len += sizeof(eth_adr_t);
                memcpy(&tmp_value_mask, &((mdf_macaddr_zone_t *)kmdf_type_ptr)->value_mask, sizeof(eth_adr_t));

                KDBG("zc-22-mac\n");
                KDBG("zc-23-ktype=0x%08x,start=0x%016llx,count=%u,step=0x%016llx,mask=0x%016llx\n", ktype, 
                        (unsigned long long)tmp_value_start,tmp_value_count,(unsigned long long)tmp_value_step,(unsigned long long)tmp_value_mask);

            } else {
                printk(KERN_ERR "mdf_zone_type_t union error,line:%d\n",__LINE__);
                ret = YNIC_ERR;
                goto kfree_ret;
            }

            KDBG("zc-24-1-total_len:%lld,actual_len:%lld\n",kmdf_total_len,kmdf_actual_len);

            //释放kmd_type_ptr;
            if(kmdf_type_ptr) {
                kfree(kmdf_type_ptr);
                kmdf_type_ptr = NULL;
            }

            kjump[0] = tmp_value_count << 16;
            if(MDF_ZONE_IP4_ADR_TYPE == ktype) {
                kjump[1] = FIELD_PREP(FPGA_TX_PKT_JUMP_STEP_MASK, (be32_to_cpu(tmp_value_step) & 0xffff));
                kjump[1] |= FIELD_PREP(FPGA_TX_PKT_JUMP_LEN_MASK, (be32_to_cpu(tmp_value_mask) & 0xf));
            } else if(MDF_ZONE_IP6_ADR_TYPE == ktype) {
                kjump[1] = FIELD_PREP(FPGA_TX_PKT_JUMP_STEP_MASK, (tmp_value_step & 0xffff));
                kjump[1] |= FIELD_PREP(FPGA_TX_PKT_JUMP_LEN_MASK, (tmp_value_mask & 0xf));
            } else if(MDF_ZONE_MAC_ADR_TYPE == ktype) {
                kjump[1] = FIELD_PREP(FPGA_TX_PKT_JUMP_STEP_MASK, ((cpu_to_be64(tmp_value_step & 0xffffffffffffffff) >> 16) & 0xffff));
                kjump[1] |= FIELD_PREP(FPGA_TX_PKT_JUMP_LEN_MASK, (tmp_value_mask & 0xf));
            } else {
                kjump[1] = FIELD_PREP(FPGA_TX_PKT_JUMP_STEP_MASK, ((tmp_value_step) & 0xffff));
                kjump[1] |= FIELD_PREP(FPGA_TX_PKT_JUMP_LEN_MASK, ((tmp_value_mask) & 0xf));
            }
            kjump[1] |= FIELD_PREP(FPGA_TX_PKT_JUMP_OFFSET_MASK, tmp_value_off);
            kjump[1] |= FIELD_PREP(FPGA_TX_PKT_JUMP_ENABLE_MASK, 1);
            #if 0
            for(i=0;i<2;i++)
            {
                pr_cont("kjump[%d]=0x%08x ",i,kjump[i]);
            }
            printk("\n");
            #endif

            ynic_write_fpga_byte(STREAM_TX, stream_id, m, (FPGA_TX_PKT_JUMP_INDEX + offset));
            ynic_write_fpga_byte(STREAM_TX, stream_id, fpga_id, (FPGA_TX_PKT_JUMP_ITEEM0 + offset));
            ynic_write_fpga_data(STREAM_TX, stream_id, kjump, FPGA_JUMP_LEN, (FPGA_TX_PKT_JUMP_WRITE0 + offset));

        }
        #if 0   //todo跳变域序列化内容打印
        uint8_t *kptr_tmp = kmdf;
        pr_cont("val:");
        for(i=0;i<kmdf_actual_len;i++) {

            pr_cont("0x%02x,",*kptr_tmp);
            kptr_tmp++;
        }
        #endif


        //列表操作
        #if 0
        if(MDF_ZONE_LST_MODE = kmode) {
            if(MDF_ZONE_UINT8_TYPE == ktype) {
                klist_ptr = kmalloc(sizeof(uint8_t) * klist_cnt, GFP_KERNEL);
                if(!kmdf_ptr) {
                    printk(KERN_ERR "mdf_xxx_type_t kmalloc error,line:%d\n",__LINE__);
                    ret = YNIC_ERR;
                    goto kfree_ret;
                }
                if(copy_from_user(kmdf_ptr, ((mdf_uint8_zone_t *)kmdf_ptr)->value_list, sizeof(uint8_t) * klist_cnt)) {
                    ret = YNIC_ERR;
                    goto kfree_ret;
                }

            } else if(MDF_ZONE_UINT16_TYPE == ktype) {
                klist_ptr = kmalloc(sizeof(uint16_t) * klist_cnt, GFP_KERNEL);
                if(!kmdf_ptr) {
                    printk(KERN_ERR "mdf_xxx_type_t kmalloc error,line:%d\n",__LINE__);
                    ret = YNIC_ERR;
                    goto kfree_ret;
                }
                if(copy_from_user(kmdf_ptr, ((mdf_uint16_zone_t *)kmdf_ptr)->value_list, sizeof(uint16_t) * klist_cnt)) {
                    ret = YNIC_ERR;
                    goto kfree_ret;
                }
            } else if(MDF_ZONE_UINT32_TYPE == ktype) {
                klist_ptr = kmalloc(sizeof(uint32_t) * klist_cnt, GFP_KERNEL);
                if(!kmdf_ptr) {
                    printk(KERN_ERR "mdf_xxx_type_t kmalloc error,line:%d\n",__LINE__);
                    ret = YNIC_ERR;
                    goto kfree_ret;
                }
                if(copy_from_user(kmdf_ptr, ((mdf_uint32_zone_t *)kmdf_ptr)->value_list, sizeof(uint32_t) * klist_cnt)) {
                    ret = YNIC_ERR;
                    goto kfree_ret;
                }
            } else if(MDF_ZONE_IP4_ADR_TYPE ==ktype) {
                klist_ptr = kmalloc(sizeof(ip_addr_t) * klist_cnt, GFP_KERNEL);
                if(!kmdf_ptr) {
                    printk(KERN_ERR "mdf_xxx_type_t kmalloc error,line:%d\n",__LINE__);
                    ret = YNIC_ERR;
                    goto kfree_ret;
                }
                if(copy_from_user(kmdf_ptr, ((mdf_ipaddr_zone_t *)kmdf_ptr)->value_list, sizeof(ip_addr_t) * klist_cnt)) {
                    ret = YNIC_ERR;
                    goto kfree_ret;
                }
            } else if(MDF_ZONE_IP6_ADR_TYPE == ktype) {
                klist_ptr = kmalloc(sizeof(ip_addr_t) * klist_cnt, GFP_KERNEL);
                if(!kmdf_ptr) {
                    printk(KERN_ERR "mdf_xxx_type_t kmalloc error,line:%d\n",__LINE__);
                    ret = YNIC_ERR;
                    goto kfree_ret;
                }
                if(copy_from_user(kmdf_ptr, ((mdf_ipaddr_zone_t *)kmdf_ptr)->value_list, sizeof(ip_addr_t) * klist_cnt)) {
                    ret = YNIC_ERR;
                    goto kfree_ret;
                }
            } else if(MDF_ZONE_MAC_ADR_TYPE == ktype) {
                klist_ptr = kmalloc(sizeof(eth_adr_t) * klist_cnt, GFP_KERNEL);
                if(!kmdf_ptr) {
                    printk(KERN_ERR "mdf_xxx_type_t kmalloc error,line:%d\n",__LINE__);
                    ret = YNIC_ERR;
                    goto kfree_ret;
                }
                if(copy_from_user(kmdf_ptr, ((mdf_macaddr_zone_t *)kmdf_ptr)->value_list, sizeof(eth_adr_t) * klist_cnt)) {
                    ret = YNIC_ERR;
                    goto kfree_ret;
                }
            } else {
                printk(KERN_ERR "mdf_xxx_type_t list error\n");
                ret = YNIC_ERR;
                goto kfree_ret;
            }
        }
        #endif

        kmdf_fpga_len  = (kmdf_actual_len % 4) ? (kmdf_actual_len / 4) + 1 : (kmdf_actual_len / 4);
        KDBG("zc-25,kmdf_fpga_len=%lld\n", kmdf_fpga_len);
        kmdf_fpga = kmalloc(sizeof(uint32_t) * kmdf_fpga_len, GFP_KERNEL);
        if(!kmdf_fpga) {
            printk(KERN_ERR "kmdf fpga kmalloc error,line=%d\n", __LINE__);
            ret = YNIC_ERR;
            goto kfree_ret;
        }

        KDBG("zc-27-mdf\n");

        KDBG("zc-30-mdf\n");
        KDBG("mdf_type=%d,name=%s\n",kmdf_array->value_type,kmdf_array->field_name);
        KDBG("mdf_mode=%d,mdf_count=%d,mdf_pos=%d,mdf_size=%d\n",kmdf_array->value_mode,kmdf_array->value_count,kmdf_array->buf_pos, kmdf_array->buf_size);

        //跳变域数据发送
        #if 0
        ynic_write_fpga_byte(1, FPGA_TX_PKT_CTRL_ITEEM0);
        ynic_convert_to_uint32(kmdf, kmdf_fpga, kmdf_actual_len);
        ynic_write_fpga_data(kmdf_fpga, kmdf_fpga_len, FPGA_TX_PKT_CTRL_WRITE0);
        ynic_write_fpga_byte(1, FPGA_TX_PKT_CTRL_WDONE0);
        #endif
    } else {
        /*do nothing*/
    }

    //send pkts and time
    #ifdef FPGA_CONTROL_TX_STREAM
    kpkt_sdpkt = kstream_cfg->need_send;
    ynic_write_fpga_byte(STREAM_TX, stream_id, (kpkt_sdpkt & 0xffffffff), (FPGA_TX_PKT_LEN_LOW_ADDR + offset));
    ynic_write_fpga_byte(STREAM_TX, stream_id, ((kpkt_sdpkt >> 32) & 0xffffffff), (FPGA_TX_PKT_LEN_HIGH_ADDR + offset));
    kpkt_sdtime = kstream_cfg->send_time;
    kpkt_sdtime *= NSEC_PER_SEC;
    ynic_write_fpga_byte(STREAM_TX, stream_id, (kpkt_sdtime & 0xffffffff), (FPGA_TX_SEND_TIME_LOW_ADDR + offset));
    ynic_write_fpga_byte(STREAM_TX, stream_id, ((kpkt_sdtime >> 32) & 0xffffffff), (FPGA_TX_SEND_TIME_HIGH_ADDR + offset));
    KDBG("zc-19-pkt_cnt-end,send packet=%llu,send time=%llu\n", kpkt_sdpkt, kpkt_sdtime);
    #endif

    #if 0
    printk("zc-65-bdf=%s,stream_id=%d,port_id=%d,fpga_id=%d,adapter_id=%d,func_id=%d\n",
            info.port_bdf,stream_id,info.port_id,fpga_id,info.adapter_id,func_id);
    for(i=0;i<64;i++) {
        if(i%16 == 0)
            printk("\n");
        pr_cont("%02x ",kpkt[i]);
    }
    printk("\n");
    #endif

    //报文发送
    #ifdef FPGA_CONTROL_TX_STREAM
    if(info.pf_num > 1) {
        if(kmsg_mode == 0) {
            kpkt_fpga_len = (kpkt_total_len % 4) ? (kpkt_total_len / 4) + 1 : (kpkt_total_len / 4);
            ynic_write_fpga_byte(STREAM_TX, stream_id, (info.adapter_id - func_id * 4), (FPGA_TX_PKT_TEMPLATE_BASE + offset));
            ynic_convert_to_uint32(kpkt, kpkt_fpga, kpkt_total_len);
            ynic_write_fpga_data(STREAM_TX, stream_id, kpkt_fpga, kpkt_fpga_len, (FPGA_TX_PKT_TEMPLATE_WRITE0 + offset));
        } else {
            kpkt_fpga_len = (kpkt_total_len % 4) ? (kpkt_total_len / 4) + 1 : (kpkt_total_len / 4);
            ynic_write_fpga_byte(STREAM_TX, stream_id, ((info.adapter_id - func_id * 4) + fpga_id * 4), (FPGA_TX_PKT_TEMPLATE_BASE + offset));
            ynic_convert_to_uint32(kpkt, kpkt_fpga, kpkt_total_len);
            ynic_write_fpga_data(STREAM_TX, stream_id, kpkt_fpga, kpkt_fpga_len, (FPGA_TX_PKT_TEMPLATE_WRITE0 + offset));
        }
    } else {
        if(kmsg_mode == 0) {
            kpkt_fpga_len = (kpkt_total_len % 4) ? (kpkt_total_len / 4) + 1 : (kpkt_total_len / 4);
            ynic_write_fpga_byte(STREAM_TX, stream_id, 0, (FPGA_TX_PKT_TEMPLATE_BASE + offset));
            ynic_convert_to_uint32(kpkt, kpkt_fpga, kpkt_total_len);
            ynic_write_fpga_data(STREAM_TX, stream_id, kpkt_fpga, kpkt_fpga_len, (FPGA_TX_PKT_TEMPLATE_WRITE0 + offset));
        } else {
            kpkt_fpga_len = (kpkt_total_len % 4) ? (kpkt_total_len / 4) + 1 : (kpkt_total_len / 4);
            ynic_write_fpga_byte(STREAM_TX, stream_id, fpga_id, (FPGA_TX_PKT_TEMPLATE_BASE + offset));
            ynic_convert_to_uint32(kpkt, kpkt_fpga, kpkt_total_len);
            ynic_write_fpga_data(STREAM_TX, stream_id, kpkt_fpga, kpkt_fpga_len, (FPGA_TX_PKT_TEMPLATE_WRITE0 + offset));
        }
    }
    #endif


    // if (copy_to_user(ukcmd->k2u_mem, u2k_mem, ukcmd->u2k_len)) {
    //     ret = YNIC_ERR;
    //     goto kfree_ret;
    // }


kfree_ret:
    if (u2k_mem) {
        kfree(u2k_mem);
    }
    if(kstream_cfg) {
        kfree(kstream_cfg);
    }
    if(ktxd_array) {
        kfree(ktxd_array);
    }
    if(kpkt) {
        kfree(kpkt);
    }
    if(kgap) {
        kfree(kgap);
    }
    if(kpkt_fpga) {
        kfree(kpkt_fpga);
    }
    if(kmdf_array) {
        kfree(kmdf_array);
    }
    if(kmdf_ptr) {
        kfree(kmdf_ptr);
    }
    if(kmdf) {
        kfree(kmdf);
    }
    if(kmdf_fpga) {
        kfree(kmdf_fpga);
    }
    if(klist_ptr) {
        kfree(klist_ptr);
    }
    if(k5tuple) {
        kfree(k5tuple);
    }
    if(kmix) {
        kfree(kmix);
    }
    return ret;
}

static int
yuannic_netdev_start_tx_stream(ynic_ukcmd_t *ukcmd)
{
    int ret = YNIC_SUC;
    uint32_t stream_id;
    port_info info = {0};
    int func_id = -1;
    uint32_t offset = 0;

    uint8_t *u2k_mem = kmalloc(ukcmd->u2k_len, GFP_KERNEL);
    if (u2k_mem == NULL) {
        ret = YNIC_ERR;
        goto kfree_ret;
    }

    if (copy_from_user(u2k_mem, ukcmd->u2k_mem, ukcmd->u2k_len)) {
        ret = YNIC_ERR;
        goto kfree_ret;
    }

    stream_id = ((uint32_t)u2k_mem[3] << 24) |
                ((uint32_t)u2k_mem[2] << 16) |
                ((uint32_t)u2k_mem[1] << 8)  |
                ((uint32_t)u2k_mem[0]);
    KDBG("zc-tx_stream_start:%d\n", stream_id);

    #ifdef FPGA_CONTROL_TX_STREAM
    //先发送stop,再开始
    func_id = ynic_get_net_bdf(STREAM_TX, stream_id, &info);
    if(func_id >= 0) {
        if(info.type == ALTERA_400G) {
            offset = func_id * FPGA_TX_OFFSET + FPGA_TX_BASE_ALTERA;
        } else {
            offset = func_id * FPGA_TX_OFFSET + FPGA_TX_BASE_XILINX;
        }
    } else {
        printk(KERN_ERR "%s get func_id %d Invalid\n",__func__, func_id);
        ret = YNIC_ERR;
        goto kfree_ret;
    }
    if(info.pf_num > 1) {
        //ynic_write_fpga_byte(STREAM_TX, stream_id, ktx_en, (FPGA_TX_1to4_EN_ADDR + offset));
        KDBG("zc-66-start-tx-stream_id=%d,adapter_id=%d,bdf=%s,func_id=%d,port_id=%d\n",
                stream_id,info.adapter_id,info.port_bdf,func_id,info.port_id);
    }

    ynic_write_fpga_byte(STREAM_TX, stream_id, 1, (FPGA_TX_PKT_TEMPLATE_WDONE0 + offset));
    ynic_write_fpga_byte(STREAM_TX, stream_id, 1, (FPGA_TX_PKT_JUMP_WDONE0 + offset));
    mdelay(100);
    //ynic_write_fpga_byte(STREAM_TX, stream_id, 0x00, (FPGA_TX_START_ADDR + offset));
    ynic_write_fpga_byte(STREAM_TX, stream_id, 0x01, (FPGA_TX_START_ADDR + offset));
    #endif

    // if (copy_to_user(ukcmd->k2u_mem, u2k_mem, ukcmd->u2k_len)) {
    //     ret = YNIC_ERR;
    //     goto kfree_ret;
    // }

kfree_ret:
    if (u2k_mem) {
        kfree(u2k_mem);
    }
    return ret;
}

static int 
yuannic_netdev_monitor_tx_stream(ynic_ukcmd_t *ukcmd)
{
    int ret = YNIC_SUC;
    uint32_t stream_id;
    ynic_txrx_stats_t *kstats = NULL;
#ifdef FPGA_CONTROL_TX_STREAM
    uint32_t val_high;
    uint32_t val_low;
#endif
    port_info info = {0};
    int func_id = -1;
    uint32_t offset = 0;
    uint8_t kmonitor_id = 0;

    uint8_t *u2k_mem = kmalloc(ukcmd->u2k_len, GFP_KERNEL);
    if (u2k_mem == NULL) {
        ret = YNIC_ERR;
        goto kfree_ret;
    }

    if (copy_from_user(u2k_mem, ukcmd->u2k_mem, ukcmd->u2k_len)) {
        ret = YNIC_ERR;
        goto kfree_ret;
    }

    stream_id = ((uint32_t)u2k_mem[3] << 24) |
                ((uint32_t)u2k_mem[2] << 16) |
                ((uint32_t)u2k_mem[1] << 8)  |
                ((uint32_t)u2k_mem[0]);
    KDBG("zc-monitor_tx_stream:%d,stat=0x%x\n", stream_id, (stream_id & ~(0x10000)));

    kstats = kmalloc(sizeof(ynic_txrx_stats_t), GFP_KERNEL);
    if (!kstats) {
        ret = YNIC_ERR;
        goto kfree_ret;
    }
    memset(kstats, 0, sizeof(ynic_txrx_stats_t));

    #ifdef FPGA_CONTROL_TX_STREAM
    ynic_read_fpga_byte(STREAM_TX, stream_id, &val_low,0);
    #endif
    KDBG("zc-fpga ver=0x%08x\n", val_low);

    #ifdef FPGA_CONTROL_TX_STREAM
    func_id = ynic_get_net_bdf(STREAM_TX, stream_id, &info);
    if(func_id >= 0) {
        if(info.type == ALTERA_400G) {
            offset = func_id * FPGA_TX_OFFSET + FPGA_TX_BASE_ALTERA;
        } else {
            offset = func_id * FPGA_TX_OFFSET + FPGA_TX_BASE_XILINX;
        }
    } else {
        printk(KERN_ERR "%s get func_id %d Invalid\n",__func__, func_id);
        ret = YNIC_ERR;
        goto kfree_ret;
    }
    if(info.pf_num > 1) {
        kmonitor_id = (info.adapter_id - func_id * 4) + 1;
        ynic_write_fpga_byte(STREAM_TX, stream_id, (kmonitor_id & ~(0x10000)), (FPGA_TX_STATUS_ADDR + offset));
    } else {
        ynic_write_fpga_byte(STREAM_TX, stream_id, (1 & ~(0x10000)), (FPGA_TX_STATUS_ADDR + offset));
    }

    ynic_read_fpga_byte(STREAM_TX, stream_id, &val_low, (FPGA_TX_PKTS_LOW_ADDR + offset));
    ynic_read_fpga_byte(STREAM_TX, stream_id, &val_high, (FPGA_TX_PKTS_HIGH_ADDR + offset));
    kstats->send_packets = ((uint64_t)val_high << 32) | val_low;
    KDBG("zc-100-bdf=%s,adapter_id=%d,stream=%d,low=0x%08x,high=0x%08x,packet=%llu",
            info.port_bdf,info.adapter_id,stream_id, val_low, val_high, kstats->send_packets);
    ynic_read_fpga_byte(STREAM_TX, stream_id, &val_low, (FPGA_TX_BYTES_LOW_ADDR + offset));
    ynic_read_fpga_byte(STREAM_TX, stream_id, &val_high, (FPGA_TX_BYTES_HIGH_ADDR + offset));
    kstats->send_bytes = ((uint64_t)val_high << 32) | val_low;
    KDBG("zc-101-bdf=%s,adapter_id=%d,stream=%d,low=0x%08x,high=0x%08x,bytes=%llu",
            info.port_bdf,info.adapter_id,stream_id, val_low, val_high, kstats->send_bytes);
    ynic_read_fpga_byte(STREAM_TX, stream_id, &val_low, (FPGA_TX_BYTES_SPEED_LOW_ADDR + offset));
    ynic_read_fpga_byte(STREAM_TX, stream_id, &val_high, (FPGA_TX_BYTES_SPEED_HIGH_ADDR + offset));
    kstats->tx_bytes_speed = ((uint64_t)val_high << 32) | val_low;
    KDBG("zc-102-bdf=%s,adapter_id=%d,stream=%d,low=0x%08x,high=0x%08x,bytes_speed=%llu",
            info.port_bdf,info.adapter_id,stream_id, val_low, val_high, kstats->tx_bytes_speed);
    ynic_read_fpga_byte(STREAM_TX, stream_id, &val_low, (FPGA_TX_PKTS_SPEED_LOW_ADDR + offset));
    ynic_read_fpga_byte(STREAM_TX, stream_id, &val_high, (FPGA_TX_PKTS_SPEED_HIGH_ADDR + offset));
    kstats->tx_pkts_speed = ((uint64_t)val_high << 32) | val_low;
    KDBG("zc-103-bdf=%s,adapter_id=%d,stream=%d,low=0x%08x,high=0x%08x,pkts_speed=%llu",
            info.port_bdf,info.adapter_id,stream_id, val_low, val_high, kstats->tx_pkts_speed);
    ynic_read_fpga_byte(STREAM_TX, stream_id, &val_low, (FPGA_TX_TIME_START_LOW + offset));
    ynic_read_fpga_byte(STREAM_TX, stream_id, &val_high, (FPGA_TX_TIME_START_HIGH + offset));
    kstats->tx_time_start = ((uint64_t)val_high << 32) | val_low;
    KDBG("zc-104-bdf=%s,adapter_id=%d,stream=%d,low=0x%08x,high=0x%08x,tx_time_start=%llu",
            info.port_bdf,info.adapter_id,stream_id, val_low, val_high, kstats->tx_time_start);
    ynic_read_fpga_byte(STREAM_TX, stream_id, &val_low, (FPGA_TX_TIME_STOP_LOW + offset));
    ynic_read_fpga_byte(STREAM_TX, stream_id, &val_high, (FPGA_TX_TIME_STOP_HIGH + offset));
    kstats->tx_time_stop = ((uint64_t)val_high << 32) | val_low;
    KDBG("zc-105-bdf=%s,adapter_id=%d,stream=%d,low=0x%08x,high=0x%08x,tx_time_stop=%llu,stop-start=0x%llx~~%llu",
            info.port_bdf,info.adapter_id,stream_id, val_low, val_high, kstats->tx_time_stop,
            (kstats->tx_time_stop-kstats->tx_time_start),(kstats->tx_time_stop-kstats->tx_time_start));
    #endif

    if (copy_to_user(ukcmd->k2u_mem, (uint8_t *)kstats, ukcmd->k2u_len)) {
        ret = YNIC_ERR;
        goto kfree_ret;
    }

kfree_ret:
    if (u2k_mem) {
        kfree(u2k_mem);
    }
    if(kstats) {
        kfree(kstats);
    }

    return ret;
}

static int 
yuannic_netdev_monitor_tx_mul_streams(ynic_ukcmd_t *ukcmd)
{
    int ret = YNIC_SUC;
    uint32_t stream_id;
    uint32_t min_id = 0, max_id = 0, nb_stream = 0;
    ynic_encap_tx_stats_t *kstats = NULL;
#ifdef FPGA_CONTROL_TX_STREAM
    uint32_t val_high;
    uint32_t val_low;
#endif
    port_info info = {0};
    int func_id = -1;
    uint32_t offset = 0;
    uint16_t fpga_id = 0;
    int i;

    uint8_t *u2k_mem = kmalloc(ukcmd->u2k_len, GFP_KERNEL);
    if (u2k_mem == NULL) {
        ret = YNIC_ERR;
        goto kfree_ret;
    }

    if (copy_from_user(u2k_mem, ukcmd->u2k_mem, ukcmd->u2k_len)) {
        ret = YNIC_ERR;
        goto kfree_ret;
    }

    stream_id = ((uint32_t)u2k_mem[3] << 24) |
                ((uint32_t)u2k_mem[2] << 16) |
                ((uint32_t)u2k_mem[1] << 8)  |
                ((uint32_t)u2k_mem[0]);
    min_id = stream_id;
    max_id = ((uint32_t)u2k_mem[7] << 24) |
             ((uint32_t)u2k_mem[6] << 16) |
             ((uint32_t)u2k_mem[5] << 8)  |
             ((uint32_t)u2k_mem[4]);
    if(min_id > max_id) {
        ret = YNIC_ERR;
        printk(KERN_ERR "%s stream id err,min:%d-max:%d\n",__func__, min_id, max_id);
        goto kfree_ret;
    }
    nb_stream = max_id - min_id + 1;

    kstats = kcalloc(nb_stream, sizeof(ynic_encap_tx_stats_t), GFP_KERNEL);
    if (!kstats) {
        ret = YNIC_ERR;
        goto kfree_ret;
    }

    #ifdef FPGA_CONTROL_TX_STREAM
    func_id = ynic_get_net_bdf(STREAM_TX, stream_id, &info);
    if(func_id >= 0) {
        if(info.type == ALTERA_400G) {
            offset = func_id * FPGA_TX_OFFSET + FPGA_TX_BASE_ALTERA;
        } else {
            offset = func_id * FPGA_TX_OFFSET + FPGA_TX_BASE_XILINX;
        }
    } else {
        printk(KERN_ERR "%s get func_id %d Invalid\n",__func__, func_id);
        ret = YNIC_ERR;
        goto kfree_ret;
    }
    fpga_id = stream_id - (info.port_id * MAX_STREAM_PER_PORT_400G) - 1;
    KDBG("zc-monitor_tx_mul_streams,id=%d,fpga_id=%d\n", stream_id, fpga_id);
    if(info.pf_num > 1) {
        ynic_write_fpga_byte(STREAM_TX, stream_id, (info.adapter_id - func_id * 4), (FPGA_TX_1to4_SEL_ADDR + offset));
    }

    for(i=0;i<nb_stream;i++) {
        ynic_write_fpga_byte(STREAM_TX, stream_id, ((fpga_id+i) & ~(0x10000)), (FPGA_TX_STATUS_ADDR + offset));

        ynic_read_fpga_byte(STREAM_TX, stream_id, &val_low, (FPGA_TX_PKTS_MUL_LOW_ADDR + offset));
        ynic_read_fpga_byte(STREAM_TX, stream_id, &val_high, (FPGA_TX_PKTS_MUL_HIGH_ADDR + offset));
        kstats[i].tx_mul_pkts = ((uint64_t)val_high << 32) | val_low;
        KDBG("zc-120-bdf=%s,adapter_id=%d,stream=%d,i=%d,low=0x%08x,high=0x%08x,tx_mul_pkts=%llu",
                info.port_bdf,info.adapter_id,stream_id, i, val_low, val_high, kstats[i].tx_mul_pkts);
        ynic_read_fpga_byte(STREAM_TX, stream_id, &val_low, (FPGA_TX_BYTES_MUL_LOW_ADDR + offset));
        ynic_read_fpga_byte(STREAM_TX, stream_id, &val_high, (FPGA_TX_BYTES_MUL_HIGH_ADDR + offset));
        kstats[i].tx_mul_bytes = ((uint64_t)val_high << 32) | val_low;
        KDBG("zc-121-bdf=%s,adapter_id=%d,stream=%d,i=%d,low=0x%08x,high=0x%08x,tx_mul_bytes=%llu",
                info.port_bdf,info.adapter_id,stream_id, i, val_low, val_high, kstats[i].tx_mul_bytes);
        ynic_read_fpga_byte(STREAM_TX, stream_id, &val_low, (FPGA_TX_PKTS_MUL_SPEED_LOW_ADDR + offset));
        ynic_read_fpga_byte(STREAM_TX, stream_id, &val_high, (FPGA_TX_PKTS_MUL_SPEED_HIGH_ADDR + offset));
        kstats[i].tx_pkts_speed = ((uint64_t)val_high << 32) | val_low;
        KDBG("zc-122-bdf=%s,adapter_id=%d,stream=%d,i=%d,low=0x%08x,high=0x%08x,tx_pkts_speed=%llu",
                info.port_bdf,info.adapter_id,stream_id, i, val_low, val_high, kstats[i].tx_pkts_speed);
        ynic_read_fpga_byte(STREAM_TX, stream_id, &val_low, (FPGA_TX_BYTES_MUL_SPEED_LOW_ADDR + offset));
        ynic_read_fpga_byte(STREAM_TX, stream_id, &val_high, (FPGA_TX_BYTES_MUL_SPEED_HIGH_ADDR + offset));
        kstats[i].tx_bytes_speed = ((uint64_t)val_high << 32) | val_low;
        KDBG("zc-123-bdf=%s,adapter_id=%d,stream=%d,i=%d,low=0x%08x,high=0x%08x,tx_bytes_speed=%llu",
                info.port_bdf,info.adapter_id,stream_id, i, val_low, val_high, kstats[i].tx_bytes_speed);
    }
    #endif

    if (copy_to_user(ukcmd->k2u_mem, (uint8_t *)kstats, ukcmd->k2u_len)) {
        ret = YNIC_ERR;
        goto kfree_ret;
    }

kfree_ret:
    if (u2k_mem) {
        kfree(u2k_mem);
    }
    if(kstats) {
        kfree(kstats);
    }

    return ret;
}

static int
yuannic_netdev_stop_tx_stream(ynic_ukcmd_t *ukcmd)
{
    int ret = YNIC_SUC;
    uint32_t stream_id;
    port_info info = {0};
    int func_id = -1;
    uint32_t offset = 0;
    uint32_t ktx_en = 0;

    uint8_t *u2k_mem = kmalloc(ukcmd->u2k_len, GFP_KERNEL);
    if (u2k_mem == NULL) {
        ret = YNIC_ERR;
        goto kfree_ret;
    }

    if (copy_from_user(u2k_mem, ukcmd->u2k_mem, ukcmd->u2k_len)) {
        ret = YNIC_ERR;
        goto kfree_ret;
    }

    stream_id = ((uint32_t)u2k_mem[3] << 24) |
                ((uint32_t)u2k_mem[2] << 16) |
                ((uint32_t)u2k_mem[1] << 8)  |
                ((uint32_t)u2k_mem[0]);
    KDBG("zc-tx_stream_stop:%d\n", stream_id);

    #ifdef FPGA_CONTROL_TX_STREAM
    func_id = ynic_get_net_bdf(STREAM_TX, stream_id, &info);
    if(func_id >= 0) {
        if(info.type == ALTERA_400G) {
            offset = func_id * FPGA_TX_OFFSET + FPGA_TX_BASE_ALTERA;
        } else {
            offset = func_id * FPGA_TX_OFFSET + FPGA_TX_BASE_XILINX;
        }
    } else {
        printk(KERN_ERR "%s get func_id %d Invalid\n",__func__, func_id);
        ret = YNIC_ERR;
        goto kfree_ret;
    }
    if(info.pf_num > 1) {
        ynic_read_fpga_byte(STREAM_TX, stream_id, &ktx_en, (FPGA_TX_1to4_EN_ADDR + offset));
        ktx_en &= ~(1 << (info.adapter_id - func_id * 4));
        ynic_write_fpga_byte(STREAM_TX, stream_id, ktx_en, (FPGA_TX_1to4_EN_ADDR + offset));
        KDBG("zc-67-stop-tx-stream_id=%d,adapter_id=%d,bdf=%s,func_id=%d,port_id=%d,ktx_en=0x%02x\n",
                stream_id,info.adapter_id,info.port_bdf,func_id,info.port_id,ktx_en);
    }
    ynic_write_fpga_byte(STREAM_TX, stream_id, 0x00, (FPGA_TX_START_ADDR + offset));

    //reset reg
    ynic_write_fpga_byte(STREAM_TX, stream_id, 0x00, (FPGA_TX_PKT_LEN_LOW_ADDR + offset));
    ynic_write_fpga_byte(STREAM_TX, stream_id, 0x00, (FPGA_TX_PKT_LEN_HIGH_ADDR + offset));
    ynic_write_fpga_byte(STREAM_TX, stream_id, 0x00, (FPGA_TX_SEND_TIME_LOW_ADDR + offset));
    ynic_write_fpga_byte(STREAM_TX, stream_id, 0x00, (FPGA_TX_SEND_TIME_HIGH_ADDR + offset));
    ynic_write_fpga_byte(STREAM_TX, stream_id, 0x00, (FPGA_TX_GAPA_ADDR + offset));
    ynic_write_fpga_byte(STREAM_TX, stream_id, 0x00, (FPGA_TX_GAPB_ADDR + offset));
    ynic_write_fpga_byte(STREAM_TX, stream_id, 0x00, (FPGA_TX_GAPNUM_ADDR + offset));
    ynic_write_fpga_byte(STREAM_TX, stream_id, 0x00, (FPGA_TX_SIP_START_ADDR + offset));
    ynic_write_fpga_byte(STREAM_TX, stream_id, 0x00, (FPGA_TX_SIP_END_ADDR + offset));
    ynic_write_fpga_byte(STREAM_TX, stream_id, 0x00, (FPGA_TX_SIP_STEP_ADDR + offset));
    ynic_write_fpga_byte(STREAM_TX, stream_id, 0x00, (FPGA_TX_DIP_START_ADDR + offset));
    ynic_write_fpga_byte(STREAM_TX, stream_id, 0x00, (FPGA_TX_DIP_END_ADDR + offset));
    ynic_write_fpga_byte(STREAM_TX, stream_id, 0x00, (FPGA_TX_DIP_STEP_ADDR + offset));
    ynic_write_fpga_byte(STREAM_TX, stream_id, 0x00, (FPGA_TX_SPORT_START_ADDR + offset));
    ynic_write_fpga_byte(STREAM_TX, stream_id, 0x00, (FPGA_TX_SPORT_END_ADDR + offset));
    ynic_write_fpga_byte(STREAM_TX, stream_id, 0x00, (FPGA_TX_SPORT_STEP_ADDR + offset));
    ynic_write_fpga_byte(STREAM_TX, stream_id, 0x00, (FPGA_TX_DPORT_START_ADDR + offset));
    ynic_write_fpga_byte(STREAM_TX, stream_id, 0x00, (FPGA_TX_DPORT_END_ADDR + offset));
    ynic_write_fpga_byte(STREAM_TX, stream_id, 0x00, (FPGA_TX_DPORT_STEP_ADDR + offset));
    ynic_write_fpga_byte(STREAM_TX, stream_id, 0x00, (FPGA_TX_K5TUPLE_NUM_ADDR + offset));
    #endif

    // if (copy_to_user(ukcmd->k2u_mem, u2k_mem, ukcmd->u2k_len)) {
    //     ret = YNIC_ERR;
    //     goto kfree_ret;
    // }

kfree_ret:
    if (u2k_mem) {
        kfree(u2k_mem);
    }
    return ret;
}

static int
yuannic_netdev_close_tx_stream(ynic_ukcmd_t *ukcmd)
{
    int ret = YNIC_SUC;
    uint32_t kstm_id;

    uint8_t *u2k_mem = kmalloc(ukcmd->u2k_len, GFP_KERNEL);
    if (u2k_mem == NULL) {
        ret = YNIC_ERR;
        goto kfree_ret;
    }

    if (copy_from_user(u2k_mem, ukcmd->u2k_mem, ukcmd->u2k_len)) {
        ret = YNIC_ERR;
        goto kfree_ret;
    }
    kstm_id =   ((uint32_t)u2k_mem[3] << 24) |
                ((uint32_t)u2k_mem[2] << 16) |
                ((uint32_t)u2k_mem[1] << 8)  |
                ((uint32_t)u2k_mem[0]);
    KDBG("zc-close-tx stream id=%d\n", kstm_id);

    if (kstm_id > 0 && kstm_id <= YNIC_TOTAL_STREAM_NUM_400G) {
        uint8_t port_id = (kstm_id - 1) / MAX_STREAM_PER_PORT_400G;
        uint32_t local_id = (kstm_id - 1) % MAX_STREAM_PER_PORT_400G;
        spin_lock(&ktx_spinlock);
        if(ktx_bitmap[port_id]) {
            clear_bit(local_id, ktx_bitmap[port_id]);
        }

        spin_unlock(&ktx_spinlock);
        KDBG(KERN_INFO "release tx stream id: %d\n", kstm_id);
    } else {
        printk(KERN_ERR "invalid tx stream id: %d\n", kstm_id);
        ret = YNIC_ERR;
        goto kfree_ret;
    }

    // if (copy_to_user(ukcmd->k2u_mem, u2k_mem, ukcmd->u2k_len)) {
    //     ret = YNIC_ERR;
    //     goto kfree_ret;
    // }

kfree_ret:
    if (u2k_mem) {
        kfree(u2k_mem);
    }
    return ret;
}

static int
yuannic_netdev_clear_tx_stream(ynic_ukcmd_t *ukcmd)
{
    int ret = YNIC_SUC;
    uint32_t stream_id;
    port_info info = {0};
    int func_id = -1;
    uint32_t offset = 0;

    uint8_t *u2k_mem = kmalloc(ukcmd->u2k_len, GFP_KERNEL);
    if (u2k_mem == NULL) {
        ret = YNIC_ERR;
        goto kfree_ret;
    }

    if (copy_from_user(u2k_mem, ukcmd->u2k_mem, ukcmd->u2k_len)) {
        ret = YNIC_ERR;
        goto kfree_ret;
    }
    stream_id = ((ynic_tx_stream_t *)u2k_mem)->stream_id;
    KDBG("zc-clear-tx-stream id=%d\n", stream_id);

    #ifdef FPGA_CONTROL_TX_STREAM
    func_id = ynic_get_net_bdf(STREAM_TX, stream_id, &info);
    if(func_id >= 0) {
        if(info.type == ALTERA_400G) {
            offset = func_id * FPGA_TX_OFFSET + FPGA_TX_BASE_ALTERA;
        } else {
            offset = func_id * FPGA_TX_OFFSET + FPGA_TX_BASE_XILINX;
        }
    } else {
        printk(KERN_ERR "%s get func_id %d Invalid\n",__func__, func_id);
        ret = YNIC_ERR;
        goto kfree_ret;
    }
    //todo:
    ynic_write_fpga_byte(STREAM_TX, stream_id, (0 | 0x10000), (FPGA_TX_STATUS_ADDR + offset));
    //ynic_write_fpga_byte(STREAM_TX, stream_id, (stream_id | 0x10000), (FPGA_TX_STATUS_ADDR + offset));
    #endif

    //if (copy_to_user(ukcmd->k2u_mem, u2k_mem, ukcmd->u2k_len)) {
    //    ret = YNIC_ERR;
    //    goto kfree_ret;
    //}

kfree_ret:
    if (u2k_mem) {
        kfree(u2k_mem);
    }
    return ret;
}

static int
yuannic_netdev_open_rx_stream(ynic_ukcmd_t *ukcmd)
{
    int ret = YNIC_SUC;
    uint32_t kstm_id;
    uint8_t *u2k_mem = NULL;
    ynic_rx_stream_t *krx_stream = NULL;
    uint8_t port_id;

    krx_stream = kmalloc(sizeof(ynic_rx_stream_t), GFP_KERNEL);
    if (krx_stream == NULL) {
        ret = YNIC_ERR;
        goto kfree_ret;
    }
    memset(krx_stream, 0 ,sizeof(ynic_rx_stream_t));

    u2k_mem = kmalloc(ukcmd->u2k_len, GFP_KERNEL);
    if (u2k_mem == NULL) {
        ret = YNIC_ERR;
        goto kfree_ret;
    }

    if (copy_from_user(u2k_mem, ukcmd->u2k_mem, ukcmd->u2k_len)) {
        ret = YNIC_ERR;
        goto kfree_ret;
    }

    port_id = ((ynic_rx_stream_t *)u2k_mem)->fpga_portid;

    spin_lock(&krx_spinlock);

    /* Lazy allocation of bitmap for this port */
    if(!krx_bitmap[port_id]) {
        uint16_t capacity = ynic_get_stream_capacity(kptnm[port_id].speed);
        krx_bitmap[port_id] = kmalloc(BITS_TO_LONGS(capacity) * sizeof(unsigned long), GFP_ATOMIC);
        if(!krx_bitmap[port_id]) {
            spin_unlock(&krx_spinlock);
            ret = YNIC_ERR;
            goto kfree_ret;
        }
        krx_bitmap_size[port_id] = capacity;
        bitmap_zero(krx_bitmap[port_id], capacity);
    }

    kstm_id = find_next_zero_bit(krx_bitmap[port_id], krx_bitmap_size[port_id], 0);
    if(kstm_id < krx_bitmap_size[port_id]) {
        set_bit(kstm_id, krx_bitmap[port_id]);
        krx_stream->stream_id = port_id * MAX_STREAM_PER_PORT_400G + kstm_id + 1;

        KDBG(KERN_INFO "alloc rx stream id: %d\n", krx_stream->stream_id);
    } else {
        spin_unlock(&krx_spinlock);
        printk("open-rx-port_id=%d,kstm_id=%d,capacity=%d\n",
                port_id, kstm_id, krx_bitmap_size[port_id]);
        return YNIC_ERR;
        goto kfree_ret;
    }
    spin_unlock(&krx_spinlock);

    if (copy_to_user(ukcmd->k2u_mem, (uint8_t *)&(krx_stream->stream_id), sizeof(krx_stream->stream_id))) {
        ret = YNIC_ERR;
        goto kfree_ret;
    }

    KDBG("zc-40-open rx stream,stream_id=%d,port_id=%d,stream_name=%s\n",krx_stream->stream_id, port_id, ((ynic_rx_stream_t *)u2k_mem)->stream_name);

kfree_ret:
    if (u2k_mem) {
        kfree(u2k_mem);
    }
    if(krx_stream) {
        kfree(krx_stream);
    }
    return ret;
}

static int
yuannic_netdev_set_rx_stream_cfg(ynic_ukcmd_t *ukcmd)
{
    int ret = YNIC_SUC;
    ynic_stream_cfg_t *kstream_cfg = NULL;   //stream配置信息
    uint8_t kmsg_mode = 0;                  //使用mdf还是五元组
    uint16_t knb_zones = 0;                 //过滤条件数量
    mdf_zone_var_t *kmdf_array = NULL;      //过滤条件数组
    uint8_t *kmdf = NULL;                   //过滤条件内容
    uint64_t kmdf_total_len = 0;            //过滤条件内容最大总长度
    uint64_t kmdf_actual_len = 0;           //过滤条件内容实际长度
    uint32_t *kmdf_fpga = NULL;             //过滤条件内容需要转换
    uint64_t kmdf_fpga_len = 0;             //过滤条件内容fpga发送长度
    uint8_t *kmdf_tmp = NULL;               //过滤条件临时指针
    void *kmdf_type_ptr = NULL;             //过滤条件类型指针
    int k,m = 0;
    uint16_t ktype = 0xFFFF;
    // uint16_t kmode = 0xFFFF;
    uint32_t stream_id;
    port_info info = {0};
    int func_id = -1;

    uint32_t offset = 0;
    uint16_t kpos = 0;
    uint32_t kflt_valid = 0;
    uint16_t fpga_id = 0;

    int8_t kflt_id = 0;                     //过滤器ID
    int8_t prev_kflt_id = -1;               //过滤器ID
    uint8_t kflt_num = 0;                   //过滤器数量
    uint8_t kaction = 0;                    //过滤动作
    uint8_t krelation = 0;                  //过滤规则关系
    uint8_t kflt_type = 0;                  //类型
    uint8_t kflt_rule = 0;                  //规则,==/!=

    uint32_t tmp_vals = 0; //value short
    uint128_t tmp_vall = 0; //value long
    uint32_t tmp_msks = 0;
    uint128_t tmp_mskl = 0;
    uint32_t tmp_val[4] = {0};
    uint32_t tmp_msk[4] = {0};
    //int i = 0;


    uint8_t *u2k_mem = kmalloc(ukcmd->u2k_len, GFP_KERNEL);
    if (u2k_mem == NULL) {
        ret = YNIC_ERR;
        goto kfree_ret;
    }

    if (copy_from_user(u2k_mem, ukcmd->u2k_mem, ukcmd->u2k_len)) {
        ret = YNIC_ERR;
        goto kfree_ret;
    }

    kstream_cfg = kmalloc(sizeof(ynic_stream_cfg_t), GFP_KERNEL);
    if(kstream_cfg == NULL) {
        ret = YNIC_ERR;
        goto kfree_ret;
    }

    if (copy_from_user(kstream_cfg, ((ynic_tx_stream_t *)u2k_mem)->stream_cfg, sizeof(ynic_stream_cfg_t))) {
        ret = YNIC_ERR;
        goto kfree_ret;
    }
    stream_id = ((ynic_tx_stream_t *)u2k_mem)->stream_id;

    //过滤处理
    //kaction = kstream_cfg->action;
    //krelation = kstream_cfg->relation;
    knb_zones = kstream_cfg->nb_mdf_zones;  //过滤条件个数
    kmsg_mode = kstream_cfg->msg_mode;
    KDBG("zc-49-stream_id=%d,knb_txd=%d,knb_zones=%d,knb_streams=%d,kmsg_mode=%d,kaction(1drop)=%d,krelation=%d\n",
            stream_id,kstream_cfg->nb_txd, kstream_cfg->nb_mdf_zones,kstream_cfg->nb_streams,kmsg_mode,kaction,krelation);
#if 0
    if(knb_zones < 1) {
        printk(KERN_ERR "Invalid nb_mdf_zones value,line: %d\n",__LINE__);
        ret = YNIC_ERR;
        goto kfree_ret;
    }
#endif
    //fpga发送
    #ifdef FPGA_CONTROL_RX_STREAM
    func_id = ynic_get_net_bdf(STREAM_RX, stream_id, &info);
    if(func_id >= 0) {
        if(info.type == ALTERA_400G) {
            offset = func_id * FPGA_RX_OFFSET + FPGA_RX_BASE_ALTERA;
        } else {
            offset = func_id * FPGA_RX_OFFSET + FPGA_RX_BASE_XILINX;
        }
    } else {
        printk(KERN_ERR "%s get func_id %d Invalid\n",__func__, func_id);
        ret = YNIC_ERR;
        goto kfree_ret;
    }
    fpga_id = stream_id - (info.port_id * MAX_STREAM_PER_PORT_400G) - 1;
    //1 divided into 4
    if(info.pf_num > 1) {
        ynic_write_fpga_byte(STREAM_RX, stream_id, ((uint8_t)0x1 << (info.adapter_id - func_id * 4)), (FPGA_RX_1to4 + offset));
        KDBG("zc-71-set-rx-stream_id=%d,adapter_id=%d,bdf=%s,func_id=%d,port_id=%d,hw_id=0x%02x\n",
                stream_id,info.adapter_id,info.port_bdf,func_id,info.port_id,((uint8_t)0x1 << (info.adapter_id - func_id * 4)));
    }
    ynic_write_fpga_byte(STREAM_RX, stream_id, 1, (FPGA_RX_FLT_ENB + offset));
    //ynic_write_fpga_byte(STREAM_RX, stream_id, kaction, (FPGA_RX_FLT_ACT + offset));
    //ynic_write_fpga_byte(STREAM_RX, stream_id, krelation, (FPGA_RX_FLT_REL + offset));
    #endif

    if(knb_zones > 0) {
        kmdf_array = kmalloc(sizeof(mdf_zone_var_t) * knb_zones, GFP_KERNEL);
        if(!kmdf_array) {
            ret = YNIC_ERR;
            goto kfree_ret;
        }
        KDBG("zc-50-knb_zones=%d, kaction=%d, krelation=%d, kmdf_array=%p\n", knb_zones, kaction, krelation, kstream_cfg->nsnic_mdf_zone_array);


        //kmdf_array = kmalloc(sizeof(mdf_zone_var_t) * knb_zones, GFP_KERNEL);
        //if(!kmdf_array) {
        //    ret = YNIC_ERR;
        //    goto kfree_ret;
        //}

        if(copy_from_user(kmdf_array, kstream_cfg->nsnic_mdf_zone_array, sizeof(mdf_zone_var_t) * knb_zones)) {
            ret = YNIC_ERR;
            goto kfree_ret;
        }

        for(k=0; k < knb_zones; k++) {

            ktype = be16_to_cpu(kmdf_array[k].value_type);
            if(MDF_ZONE_UINT8_TYPE == ktype) {
                kmdf_total_len += sizeof(mdf_uint8_zone_t) / sizeof(uint8_t);
            } else if(MDF_ZONE_UINT16_TYPE == ktype) {
                kmdf_total_len += sizeof(mdf_uint16_zone_t) / sizeof(uint8_t);
            } else if(MDF_ZONE_UINT32_TYPE == ktype) {
                kmdf_total_len += sizeof(mdf_uint32_zone_t) / sizeof(uint8_t);
            } else if(MDF_ZONE_IP4_ADR_TYPE == ktype) {
                kmdf_total_len += sizeof(mdf_ipaddr_zone_t) / sizeof(uint8_t);
            } else if(MDF_ZONE_IP6_ADR_TYPE == ktype) {
                kmdf_total_len += sizeof(mdf_ipaddr_zone_t) / sizeof(uint8_t);
            } else if(MDF_ZONE_MAC_ADR_TYPE == ktype) {
                kmdf_total_len += sizeof(mdf_macaddr_zone_t) / sizeof(uint8_t);
            } else {
                printk(KERN_ERR "[%s] Invalid mdf type: %d", __func__, ktype);
                ret = YNIC_ERR;
                goto kfree_ret;
            }

        }
        kmdf_total_len += knb_zones * YNIC_RX_STREAM_MDF_LENGTH;
        KDBG("zc-51-mdf,k=%d,ktype=%d,knb_zones=%d, kmdf_total_len=%lld\n",k, ktype, knb_zones, kmdf_total_len);

        kmdf = kmalloc(sizeof(uint8_t) * kmdf_total_len, GFP_KERNEL);
        if(!kmdf) {
            printk(KERN_ERR "kmdf kmalloc error,line=%d\n", __LINE__);
            ret = YNIC_ERR;
            goto kfree_ret;
        }

        kmdf_tmp = kmdf;
        for(m=0; m < knb_zones; m++) {
            ktype = be16_to_cpu(kmdf_array[m].value_type);
            // kmode = kmdf_array[m].value_mode;

            memcpy(kmdf_tmp, &(kmdf_array[m].filter_id), sizeof(uint8_t));
            kmdf_tmp += sizeof(uint8_t);
            kmdf_actual_len += sizeof(uint8_t);
            kflt_id = kmdf_array[m].filter_id;

            memcpy(kmdf_tmp, &(kmdf_array[m].action), sizeof(uint8_t));
            kmdf_tmp += sizeof(uint8_t);
            kmdf_actual_len += sizeof(uint8_t);
            kaction = kmdf_array[m].action;

            memcpy(kmdf_tmp, &(kmdf_array[m].relation), sizeof(uint8_t));
            kmdf_tmp += sizeof(uint8_t);
            kmdf_actual_len += sizeof(uint8_t);
            krelation = kmdf_array[m].relation;

            memcpy(kmdf_tmp, &(kmdf_array[m].filter_type), sizeof(uint8_t));
            kmdf_tmp += sizeof(uint8_t);
            kmdf_actual_len += sizeof(uint8_t);
            kflt_type = kmdf_array[m].filter_type;

            memcpy(kmdf_tmp, &(kmdf_array[m].filter_ruler), sizeof(uint8_t));
            kmdf_tmp += sizeof(uint8_t);
            kmdf_actual_len += sizeof(uint8_t);
            kflt_rule = kmdf_array[m].filter_ruler;

            memcpy(kmdf_tmp, &(kmdf_array[m].value_type), sizeof(uint16_t));
            kmdf_tmp += sizeof(uint16_t);
            kmdf_actual_len += sizeof(uint16_t);

            memcpy(kmdf_tmp, &(kmdf_array[m].buf_pos), sizeof(uint16_t));
            kmdf_tmp += sizeof(uint16_t);
            kmdf_actual_len += sizeof(uint16_t);
            kpos = be16_to_cpu(kmdf_array[m].buf_pos);

            memcpy(kmdf_tmp, &(kmdf_array[m].buf_size), sizeof(uint32_t));
            kmdf_tmp += sizeof(uint32_t);
            kmdf_actual_len += sizeof(uint32_t);
            KDBG("zc-51-kflt_id=%d,kaction=%d,krelation=%d,kflt_type=%d\n",kflt_id,kaction,krelation,kflt_type);

            if(MDF_ZONE_UINT8_TYPE == ktype) {
                kmdf_type_ptr = kmalloc(sizeof(mdf_uint8_zone_t), GFP_KERNEL);
                if(!kmdf_type_ptr) {
                    printk(KERN_ERR "mdf_zone_type_t kmalloc error,line:%d\n",__LINE__);
                    ret = YNIC_ERR;
                    goto kfree_ret;
                }
                if(copy_from_user(kmdf_type_ptr, kmdf_array[m].mdf_uint8_zone, sizeof(mdf_uint8_zone_t))) {
                    ret = YNIC_ERR;
                    goto kfree_ret;
                }

                memcpy(kmdf_tmp, &((mdf_uint8_zone_t *)kmdf_type_ptr)->value_next, sizeof(uint8_t)); //filter value
                kmdf_tmp += sizeof(uint8_t);
                kmdf_actual_len += sizeof(uint8_t);

                memcpy(kmdf_tmp, &((mdf_uint8_zone_t *)kmdf_type_ptr)->value_mask, sizeof(uint8_t));
                kmdf_tmp += sizeof(uint8_t);
                kmdf_actual_len += sizeof(uint8_t);
                tmp_msks = ((mdf_uint8_zone_t *)kmdf_type_ptr)->value_mask;

                memcpy(kmdf_tmp, &((mdf_uint8_zone_t *)kmdf_type_ptr)->value_start, sizeof(uint8_t));
                kmdf_tmp += sizeof(uint8_t);
                kmdf_actual_len += sizeof(uint8_t);
                tmp_vals = ((mdf_uint8_zone_t *)kmdf_type_ptr)->value_start;

                memcpy(kmdf_tmp, &((mdf_uint8_zone_t *)kmdf_type_ptr)->value_end, sizeof(uint8_t));
                kmdf_tmp += sizeof(uint8_t);
                kmdf_actual_len += sizeof(uint8_t);

                KDBG("zc-52-uint8\n");
                KDBG("zc-53-ktype=0x%08x,kpos=%d,mask=0x%02x,start=0x%02x\n", ktype, kpos, tmp_msks,tmp_vals);

            } else if(MDF_ZONE_UINT16_TYPE == ktype) {
                kmdf_type_ptr = kmalloc(sizeof(mdf_uint16_zone_t), GFP_KERNEL);
                if(!kmdf_type_ptr) {
                    printk(KERN_ERR "mdf_zone_type_t kmalloc error,line:%d\n",__LINE__);
                    ret = YNIC_ERR;
                    goto kfree_ret;
                }
                if(copy_from_user(kmdf_type_ptr, kmdf_array[m].mdf_uint16_zone, sizeof(mdf_uint16_zone_t))) {
                    ret = YNIC_ERR;
                    goto kfree_ret;
                }

                memcpy(kmdf_tmp, &((mdf_uint16_zone_t *)kmdf_type_ptr)->value_next, sizeof(uint16_t));
                kmdf_tmp += sizeof(uint16_t);
                kmdf_actual_len += sizeof(uint16_t);

                memcpy(kmdf_tmp, &((mdf_uint16_zone_t *)kmdf_type_ptr)->value_mask, sizeof(uint16_t));
                kmdf_tmp += sizeof(uint16_t);
                kmdf_actual_len += sizeof(uint16_t);
                tmp_msks = ((mdf_uint16_zone_t *)kmdf_type_ptr)->value_mask;

                memcpy(kmdf_tmp, &((mdf_uint16_zone_t *)kmdf_type_ptr)->value_start, sizeof(uint16_t));
                kmdf_tmp += sizeof(uint16_t);
                kmdf_actual_len += sizeof(uint16_t);
                tmp_vals = ((mdf_uint16_zone_t *)kmdf_type_ptr)->value_start;


                memcpy(kmdf_tmp, &((mdf_uint16_zone_t *)kmdf_type_ptr)->value_end, sizeof(uint16_t));
                kmdf_tmp += sizeof(uint16_t);
                kmdf_actual_len += sizeof(uint16_t);

                KDBG("zc-52-uint16\n");
                KDBG("zc-53-ktype=0x%08x,kpos=%d,value_mask=0x%02x,start=0x%02x\n", ktype, kpos, tmp_msks,tmp_vals);

            } else if(MDF_ZONE_UINT32_TYPE == ktype) {

                kmdf_type_ptr = kmalloc(sizeof(mdf_uint32_zone_t), GFP_KERNEL);
                if(!kmdf_type_ptr) {
                    printk(KERN_ERR "mdf_zone_type_t kmalloc error,line:%d\n",__LINE__);
                    ret = YNIC_ERR;
                    goto kfree_ret;
                }
                if(copy_from_user(kmdf_type_ptr, kmdf_array[m].mdf_uint32_zone, sizeof(mdf_uint32_zone_t))) {
                    ret = YNIC_ERR;
                    goto kfree_ret;
                }

                memcpy(kmdf_tmp, &((mdf_uint32_zone_t *)kmdf_type_ptr)->value_next, sizeof(uint32_t));
                kmdf_tmp += sizeof(uint32_t);
                kmdf_actual_len += sizeof(uint32_t);

                memcpy(kmdf_tmp, &((mdf_uint32_zone_t *)kmdf_type_ptr)->value_mask, sizeof(uint32_t));
                kmdf_tmp += sizeof(uint32_t);
                kmdf_actual_len += sizeof(uint32_t);
                tmp_msks = ((mdf_uint32_zone_t *)kmdf_type_ptr)->value_mask;

                memcpy(kmdf_tmp, &((mdf_uint32_zone_t *)kmdf_type_ptr)->value_start, sizeof(uint32_t));
                kmdf_tmp += sizeof(uint32_t);
                kmdf_actual_len += sizeof(uint32_t);
                tmp_vals = ((mdf_uint32_zone_t *)kmdf_type_ptr)->value_start;

                memcpy(kmdf_tmp, &((mdf_uint32_zone_t *)kmdf_type_ptr)->value_end, sizeof(uint32_t));
                kmdf_tmp += sizeof(uint32_t);
                kmdf_actual_len += sizeof(uint32_t);

                KDBG("zc-52-uint32\n");
                KDBG("zc-53-ktype=0x%08x,kpos=%d,value_mask=0x%08x,start=0x%08x\n", ktype, kpos, tmp_msks,tmp_vals);

            } else if(MDF_ZONE_IP4_ADR_TYPE ==ktype) {
                kmdf_type_ptr = kmalloc(sizeof(mdf_ipaddr_zone_t), GFP_KERNEL);
                if(!kmdf_type_ptr) {
                    printk(KERN_ERR "mdf_zone_type_t kmalloc error,line:%d\n",__LINE__);
                    ret = YNIC_ERR;
                    goto kfree_ret;
                }
                if(copy_from_user(kmdf_type_ptr, kmdf_array[m].mdf_ip4adr_zone, sizeof(mdf_ipaddr_zone_t))) {
                    ret = YNIC_ERR;
                    goto kfree_ret;
                }

                memcpy(kmdf_tmp, &((mdf_ipaddr_zone_t *)kmdf_type_ptr)->value_next.net_ipv4_addr, sizeof(in_addr_t));
                kmdf_tmp += sizeof(in_addr_t);
                kmdf_actual_len += sizeof(in_addr_t);

                memcpy(kmdf_tmp, &((mdf_ipaddr_zone_t *)kmdf_type_ptr)->value_mask, sizeof(ip_addr_t));
                kmdf_tmp += sizeof(ip_addr_t);
                kmdf_actual_len += sizeof(ip_addr_t);
                tmp_mskl = (uint128_t)(((mdf_ipaddr_zone_t *)kmdf_type_ptr)->value_mask.net_ipv4_addr);

                memcpy(kmdf_tmp, &((mdf_ipaddr_zone_t *)kmdf_type_ptr)->value_start, sizeof(ip_addr_t));
                kmdf_tmp += sizeof(ip_addr_t);
                kmdf_actual_len += sizeof(ip_addr_t);
                tmp_vall = ((uint128_t)(((mdf_ipaddr_zone_t *)kmdf_type_ptr)->value_start.net_ipv4_addr));

                memcpy(kmdf_tmp, &((mdf_ipaddr_zone_t *)kmdf_type_ptr)->value_end, sizeof(ip_addr_t));
                kmdf_tmp += sizeof(ip_addr_t);
                kmdf_actual_len += sizeof(ip_addr_t);

                KDBG("zc-52-ip4,ip_addr_t=%ld\n",sizeof(ip_addr_t));
                KDBG("zc-53-ktype=0x%08x,kpos=%d,value_mask=0x%08x,start=0x%08x\n",
                        ktype, kpos, (uint32_t)(tmp_mskl),(uint32_t)(tmp_vall));

            } else if(MDF_ZONE_IP6_ADR_TYPE == ktype) {
                kmdf_type_ptr = kmalloc(sizeof(mdf_ipaddr_zone_t), GFP_KERNEL);
                if(!kmdf_type_ptr) {
                    printk(KERN_ERR "mdf_zone_type_t kmalloc error,line:%d\n",__LINE__);
                    ret = YNIC_ERR;
                    goto kfree_ret;
                }
                if(copy_from_user(kmdf_type_ptr, kmdf_array[m].mdf_ip6adr_zone, sizeof(mdf_ipaddr_zone_t))) {
                    ret = YNIC_ERR;
                    goto kfree_ret;
                }

                memcpy(kmdf_tmp, &((mdf_ipaddr_zone_t *)kmdf_type_ptr)->value_next.net_ipv6_addr, sizeof(in6_addr_t));
                kmdf_tmp += sizeof(in6_addr_t);
                kmdf_actual_len += sizeof(in6_addr_t);

                memcpy(kmdf_tmp, &((mdf_ipaddr_zone_t *)kmdf_type_ptr)->value_mask, sizeof(ip_addr_t));
                kmdf_tmp += sizeof(ip_addr_t); kmdf_actual_len += sizeof(ip_addr_t);
                tmp_mskl = (((mdf_ipaddr_zone_t *)kmdf_type_ptr)->value_mask.ipv6_uint128);

                memcpy(kmdf_tmp, &((mdf_ipaddr_zone_t *)kmdf_type_ptr)->value_start, sizeof(ip_addr_t));
                kmdf_tmp += sizeof(ip_addr_t);
                kmdf_actual_len += sizeof(ip_addr_t);
                tmp_vall = (((mdf_ipaddr_zone_t *)kmdf_type_ptr)->value_start.ipv6_uint128);

                memcpy(kmdf_tmp, &((mdf_ipaddr_zone_t *)kmdf_type_ptr)->value_end, sizeof(ip_addr_t));
                kmdf_tmp += sizeof(ip_addr_t);
                kmdf_actual_len += sizeof(ip_addr_t);


                KDBG("zc-52-ip6\n");
                KDBG("zc-53-ktype=0x%08x,kpos=%d,value_mask_low=0x%llx,high=0x%llx,start_low=0x%llx,high=0x%llx\n",
                        ktype, kpos,(uint64_t)tmp_mskl,(uint64_t)(tmp_mskl>>64),(uint64_t)tmp_vall,(uint64_t)(tmp_vall>>64));

            } else if(MDF_ZONE_MAC_ADR_TYPE == ktype) {
                kmdf_type_ptr = kmalloc(sizeof(mdf_macaddr_zone_t), GFP_KERNEL);
                if(!kmdf_type_ptr) {
                    printk(KERN_ERR "mdf_zone_type_t kmalloc error,line:%d\n",__LINE__);
                    ret = YNIC_ERR;
                    goto kfree_ret;
                }
                if(copy_from_user(kmdf_type_ptr, kmdf_array[m].mdf_macaddr_zone, sizeof(mdf_macaddr_zone_t))) {
                    ret = YNIC_ERR;
                    goto kfree_ret;
                }

                memcpy(kmdf_tmp, &((mdf_macaddr_zone_t *)kmdf_type_ptr)->value_next, sizeof(eth_adr_t));
                kmdf_tmp += sizeof(eth_adr_t);
                kmdf_actual_len += sizeof(eth_adr_t);

                memcpy(kmdf_tmp, &((mdf_macaddr_zone_t *)kmdf_type_ptr)->value_mask, sizeof(eth_adr_t));
                kmdf_tmp += sizeof(eth_adr_t);
                kmdf_actual_len += sizeof(eth_adr_t);
                memcpy(&tmp_mskl, &((mdf_macaddr_zone_t *)kmdf_type_ptr)->value_mask, sizeof(eth_adr_t));

                memcpy(kmdf_tmp, &((mdf_macaddr_zone_t *)kmdf_type_ptr)->value_start, sizeof(eth_adr_t));
                kmdf_tmp += sizeof(eth_adr_t);
                kmdf_actual_len += sizeof(eth_adr_t);
                memcpy(&tmp_vall, &((mdf_macaddr_zone_t *)kmdf_type_ptr)->value_start, sizeof(eth_adr_t));

                memcpy(kmdf_tmp, &((mdf_macaddr_zone_t *)kmdf_type_ptr)->value_end, sizeof(eth_adr_t));
                kmdf_tmp += sizeof(eth_adr_t);
                kmdf_actual_len += sizeof(eth_adr_t);

                KDBG("zc-52-mac\n");
                KDBG("zc-53-ktype=0x%08x,kpos=%d,mask=0x%016llx,start=0x%016llx\n", ktype,
                        kpos, (uint64_t)tmp_mskl,(uint64_t)tmp_vall);

            } else {
                printk(KERN_ERR "mdf_zone_type_t union error,line:%d\n",__LINE__);
                ret = YNIC_ERR;
                goto kfree_ret;
            }

            KDBG("zc-54-total_len:%lld,actual_len:%lld\n",kmdf_total_len,kmdf_actual_len);


            if(prev_kflt_id != kflt_id) {
                prev_kflt_id = kflt_id;
                kflt_num ++;
                kflt_valid = GENMASK((kflt_num-1), 0);
            }
            ynic_write_fpga_byte(STREAM_RX, stream_id, (kflt_id-1), (FPGA_RX_FLT_BASE + offset));
            ynic_write_fpga_byte(STREAM_RX, stream_id, kflt_valid, (FPGA_RX_FLT_ENB_BIT + offset));
            ynic_write_fpga_byte(STREAM_RX, stream_id, !kaction, (FPGA_RX_FLT_ACTION + offset));
            ynic_write_fpga_byte(STREAM_RX, stream_id, krelation, (FPGA_RX_FLT_RELATION + offset));
            KDBG("zc-55-kflt_id=%d,valid=0x%02x,!action(1drop)=%d,relation(0and)=%d,kflt_rule(0==)=%d,kflt_type=%d\n",
                    kflt_id,kflt_valid,(!kaction),krelation,kflt_rule,kflt_type);
            switch(kflt_type) {
                case FILTER_SRC_MAC:
                    tmp_val[0] = (cpu_to_be64(tmp_vall & 0xffffffffffffffff) >> 16) & 0xffffffff;
                    tmp_val[1] = (cpu_to_be64(tmp_vall & 0xffffffffffffffff) >> 48) & 0xffff;
                    tmp_msk[0] = (cpu_to_be64(tmp_mskl & 0xffffffffffffffff) >> 16) & 0xffffffff;
                    tmp_msk[1] = (cpu_to_be64(tmp_mskl & 0xffffffffffffffff) >> 48) & 0xffff;
                    ynic_write_fpga_byte(STREAM_RX, stream_id, 1, (FPGA_RX_FLT_SMAC_EN + offset));
                    ynic_write_fpga_byte(STREAM_RX, stream_id, kflt_rule, (FPGA_RX_FLT_SMAC_MODE + offset));
                    ynic_write_fpga_byte(STREAM_RX, stream_id, tmp_msk[0], (FPGA_RX_FLT_SMAC_MSK0 + offset));
                    ynic_write_fpga_byte(STREAM_RX, stream_id, tmp_msk[1], (FPGA_RX_FLT_SMAC_MSK1 + offset));
                    ynic_write_fpga_byte(STREAM_RX, stream_id, tmp_val[0], (FPGA_RX_FLT_SMAC_VAL0 + offset));
                    ynic_write_fpga_byte(STREAM_RX, stream_id, tmp_val[1], (FPGA_RX_FLT_SMAC_VAL1 + offset));
                    break;
                case FILTER_DST_MAC:
                    tmp_val[0] = (cpu_to_be64(tmp_vall & 0xffffffffffffffff) >> 16) & 0xffffffff;
                    tmp_val[1] = (cpu_to_be64(tmp_vall & 0xffffffffffffffff) >> 48) & 0xffff;
                    tmp_msk[0] = (cpu_to_be64(tmp_mskl & 0xffffffffffffffff) >> 16) & 0xffffffff;
                    tmp_msk[1] = (cpu_to_be64(tmp_mskl & 0xffffffffffffffff) >> 48) & 0xffff;
                    ynic_write_fpga_byte(STREAM_RX, stream_id, 1, (FPGA_RX_FLT_DMAC_EN + offset));
                    ynic_write_fpga_byte(STREAM_RX, stream_id, kflt_rule, (FPGA_RX_FLT_DMAC_MODE + offset));
                    ynic_write_fpga_byte(STREAM_RX, stream_id, tmp_msk[0], (FPGA_RX_FLT_DMAC_MSK0 + offset));
                    ynic_write_fpga_byte(STREAM_RX, stream_id, tmp_msk[1], (FPGA_RX_FLT_DMAC_MSK1 + offset));
                    ynic_write_fpga_byte(STREAM_RX, stream_id, tmp_val[0], (FPGA_RX_FLT_DMAC_VAL0 + offset));
                    ynic_write_fpga_byte(STREAM_RX, stream_id, tmp_val[1], (FPGA_RX_FLT_DMAC_VAL1 + offset));
                    break;
                case FILTER_SRC_IPV6:
                    tmp_val[0] = tmp_vall & 0xffffffff;
                    tmp_val[1] = (tmp_vall >> 32) & 0xffffffff;
                    tmp_val[2] = (tmp_vall >> 64) & 0xffffffff;
                    tmp_val[3] = (tmp_vall >> 96) & 0xffffffff;
                    tmp_msk[0] = tmp_mskl & 0xffffffff;
                    tmp_msk[1] = (tmp_mskl >> 32) & 0xffffffff;
                    tmp_msk[2] = (tmp_mskl >> 64) & 0xffffffff;
                    tmp_msk[3] = (tmp_mskl >> 96) & 0xffffffff;
                    ynic_write_fpga_byte(STREAM_RX, stream_id, 1, (FPGA_RX_FLT_SIPV6_EN + offset));
                    ynic_write_fpga_byte(STREAM_RX, stream_id, kflt_rule, (FPGA_RX_FLT_SIPV6_MODE + offset));
                    ynic_write_fpga_byte(STREAM_RX, stream_id, tmp_msk[0], (FPGA_RX_FLT_SIPV6_MSK0 + offset));
                    ynic_write_fpga_byte(STREAM_RX, stream_id, tmp_msk[1], (FPGA_RX_FLT_SIPV6_MSK1 + offset));
                    ynic_write_fpga_byte(STREAM_RX, stream_id, tmp_msk[2], (FPGA_RX_FLT_SIPV6_MSK2 + offset));
                    ynic_write_fpga_byte(STREAM_RX, stream_id, tmp_msk[3], (FPGA_RX_FLT_SIPV6_MSK3 + offset));
                    ynic_write_fpga_byte(STREAM_RX, stream_id, tmp_val[0], (FPGA_RX_FLT_SIPV6_VAL0 + offset));
                    ynic_write_fpga_byte(STREAM_RX, stream_id, tmp_val[1], (FPGA_RX_FLT_SIPV6_VAL1 + offset));
                    ynic_write_fpga_byte(STREAM_RX, stream_id, tmp_val[2], (FPGA_RX_FLT_SIPV6_VAL2 + offset));
                    ynic_write_fpga_byte(STREAM_RX, stream_id, tmp_val[3], (FPGA_RX_FLT_SIPV6_VAL3 + offset));
                    break;
                case FILTER_DST_IPV6:
                    tmp_val[0] = tmp_vall & 0xffffffff;
                    tmp_val[1] = (tmp_vall >> 32) & 0xffffffff;
                    tmp_val[2] = (tmp_vall >> 64) & 0xffffffff;
                    tmp_val[3] = (tmp_vall >> 96) & 0xffffffff;
                    tmp_msk[0] = tmp_mskl & 0xffffffff;
                    tmp_msk[1] = (tmp_mskl >> 32) & 0xffffffff;
                    tmp_msk[2] = (tmp_mskl >> 64) & 0xffffffff;
                    tmp_msk[3] = (tmp_mskl >> 96) & 0xffffffff;
                    ynic_write_fpga_byte(STREAM_RX, stream_id, 1, (FPGA_RX_FLT_DIPV6_EN + offset));
                    ynic_write_fpga_byte(STREAM_RX, stream_id, kflt_rule, (FPGA_RX_FLT_DIPV6_MODE + offset));
                    ynic_write_fpga_byte(STREAM_RX, stream_id, tmp_msk[0], (FPGA_RX_FLT_DIPV6_MSK0 + offset));
                    ynic_write_fpga_byte(STREAM_RX, stream_id, tmp_msk[1], (FPGA_RX_FLT_DIPV6_MSK1 + offset));
                    ynic_write_fpga_byte(STREAM_RX, stream_id, tmp_msk[2], (FPGA_RX_FLT_DIPV6_MSK2 + offset));
                    ynic_write_fpga_byte(STREAM_RX, stream_id, tmp_msk[3], (FPGA_RX_FLT_DIPV6_MSK3 + offset));
                    ynic_write_fpga_byte(STREAM_RX, stream_id, tmp_val[0], (FPGA_RX_FLT_DIPV6_VAL0 + offset));
                    ynic_write_fpga_byte(STREAM_RX, stream_id, tmp_val[1], (FPGA_RX_FLT_DIPV6_VAL1 + offset));
                    ynic_write_fpga_byte(STREAM_RX, stream_id, tmp_val[2], (FPGA_RX_FLT_DIPV6_VAL2 + offset));
                    ynic_write_fpga_byte(STREAM_RX, stream_id, tmp_val[3], (FPGA_RX_FLT_DIPV6_VAL3 + offset));
                    break;
                case FILTER_VLAN:
                    tmp_val[0] = cpu_to_be16(tmp_vals & 0xffffffff);
                    tmp_msk[0] = cpu_to_be16(tmp_msks & 0xffffffff);
                    ynic_write_fpga_byte(STREAM_RX, stream_id, 1, (FPGA_RX_FLT_VLAN_EN + offset));
                    ynic_write_fpga_byte(STREAM_RX, stream_id, kflt_rule, (FPGA_RX_FLT_VLAN_MODE + offset));
                    ynic_write_fpga_byte(STREAM_RX, stream_id, tmp_msk[0], (FPGA_RX_FLT_VLAN_MSK + offset));
                    ynic_write_fpga_byte(STREAM_RX, stream_id, tmp_val[0], (FPGA_RX_FLT_VLAN_VAL + offset));
                    break;
                case FILTER_SRC_IPV4:
                    tmp_val[0] = cpu_to_be32(tmp_vall & 0xffffffff);
                    tmp_msk[0] = cpu_to_be32(tmp_mskl & 0xffffffff);
                    ynic_write_fpga_byte(STREAM_RX, stream_id, 1, (FPGA_RX_FLT_SIPV4_EN + offset));
                    ynic_write_fpga_byte(STREAM_RX, stream_id, kflt_rule, (FPGA_RX_FLT_SIPV4_MODE + offset));
                    ynic_write_fpga_byte(STREAM_RX, stream_id, tmp_msk[0], (FPGA_RX_FLT_SIPV4_MSK + offset));
                    ynic_write_fpga_byte(STREAM_RX, stream_id, tmp_val[0], (FPGA_RX_FLT_SIPV4_VAL + offset));
                    break;
                case FILTER_DST_IPV4:
                    tmp_val[0] = cpu_to_be32(tmp_vall & 0xffffffff);
                    tmp_msk[0] = cpu_to_be32(tmp_mskl & 0xffffffff);
                    ynic_write_fpga_byte(STREAM_RX, stream_id, 1, (FPGA_RX_FLT_DIPV4_EN + offset));
                    ynic_write_fpga_byte(STREAM_RX, stream_id, kflt_rule, (FPGA_RX_FLT_DIPV4_MODE + offset));
                    ynic_write_fpga_byte(STREAM_RX, stream_id, tmp_msk[0], (FPGA_RX_FLT_DIPV4_MSK + offset));
                    ynic_write_fpga_byte(STREAM_RX, stream_id, tmp_val[0], (FPGA_RX_FLT_DIPV4_VAL + offset));
                    break;
                case FILTER_PROTOCOL_TYPE:
                    tmp_val[0] = tmp_vals & 0xffffffff;
                    tmp_msk[0] = tmp_msks & 0xffffffff;
                    ynic_write_fpga_byte(STREAM_RX, stream_id, 1, (FPGA_RX_FLT_PROTO_EN + offset));
                    ynic_write_fpga_byte(STREAM_RX, stream_id, kflt_rule, (FPGA_RX_FLT_PROTO_MODE + offset));
                    ynic_write_fpga_byte(STREAM_RX, stream_id, tmp_msk[0], (FPGA_RX_FLT_PROTO_MSK + offset));
                    ynic_write_fpga_byte(STREAM_RX, stream_id, tmp_val[0], (FPGA_RX_FLT_PROTO_VAL + offset));
                    break;
                case FILTER_SRC_PORT:
                    tmp_val[0] = cpu_to_be16(tmp_vals & 0xffffffff);
                    tmp_msk[0] = cpu_to_be16(tmp_msks & 0xffffffff);
                    ynic_write_fpga_byte(STREAM_RX, stream_id, 1, (FPGA_RX_FLT_SPORT_EN + offset));
                    ynic_write_fpga_byte(STREAM_RX, stream_id, kflt_rule, (FPGA_RX_FLT_SPORT_MODE + offset));
                    ynic_write_fpga_byte(STREAM_RX, stream_id, tmp_msk[0], (FPGA_RX_FLT_SPORT_MSK + offset));
                    ynic_write_fpga_byte(STREAM_RX, stream_id, tmp_val[0], (FPGA_RX_FLT_SPORT_VAL + offset));
                    break;
                case FILTER_DST_PORT:
                    tmp_val[0] = cpu_to_be16(tmp_vals & 0xffffffff);
                    tmp_msk[0] = cpu_to_be16(tmp_msks & 0xffffffff);
                    ynic_write_fpga_byte(STREAM_RX, stream_id, 1, (FPGA_RX_FLT_DPORT_EN + offset));
                    ynic_write_fpga_byte(STREAM_RX, stream_id, kflt_rule, (FPGA_RX_FLT_DPORT_MODE + offset));
                    ynic_write_fpga_byte(STREAM_RX, stream_id, tmp_msk[0], (FPGA_RX_FLT_DPORT_MSK + offset));
                    ynic_write_fpga_byte(STREAM_RX, stream_id, tmp_val[0], (FPGA_RX_FLT_DPORT_VAL + offset));
                    break;
                case FILTER_FRAM_SIZE:
                    tmp_val[0] = cpu_to_be32(tmp_vals & 0xffffffff);
                    tmp_msk[0] = cpu_to_be32(tmp_msks & 0xffffffff);
                    ynic_write_fpga_byte(STREAM_RX, stream_id, 1, (FPGA_RX_FLT_LEN_EN + offset));
                    ynic_write_fpga_byte(STREAM_RX, stream_id, kflt_rule, (FPGA_RX_FLT_LEN_MODE + offset));
                    ynic_write_fpga_byte(STREAM_RX, stream_id, tmp_msk[0], (FPGA_RX_FLT_LEN_MSK + offset));
                    ynic_write_fpga_byte(STREAM_RX, stream_id, tmp_val[0], (FPGA_RX_FLT_LEN_VAL + offset));
                    break;
                default:
                    break;
            }
            KDBG("zc-56-val[0]=0x%08x,val[1]=0x%08x,val[2]=0x%08x,val[3]=0x%08x,"
                    "mask[0]=0x%08x,mask[1]=0x%08x,mask[2]=0x%08x,mask[3]=0x%08x\n",
                    tmp_val[0],tmp_val[1],tmp_val[2],tmp_val[3],
                    tmp_msk[0],tmp_msk[1],tmp_msk[2],tmp_msk[3]);

            //释放kmd_type_ptr;
            if(kmdf_type_ptr)
                kfree(kmdf_type_ptr);
        }

        #if 0   //todo过滤条件序列化内容打印
        uint8_t *kptr_tmp = kmdf;
        pr_cont("val:");
        for(i=0;i<kmdf_actual_len;i++) {

            pr_cont("0x%02x,",*kptr_tmp);
            kptr_tmp++;
        }
        #endif

        kmdf_fpga_len  = (kmdf_actual_len % 4) ? (kmdf_actual_len / 4) + 1 : (kmdf_actual_len / 4);
        KDBG("zc-57,kmdf_fpga_len=%lld\n", kmdf_fpga_len);
        kmdf_fpga = kmalloc(sizeof(uint32_t) * kmdf_fpga_len, GFP_KERNEL);
        if(!kmdf_fpga) {
            printk(KERN_ERR "kmdf fpga kmalloc error,line=%d\n", __LINE__);
            ret = YNIC_ERR;
            goto kfree_ret;
        }
        KDBG("zc-58-mdf_type=%d,mdf_pos=%d,mdf_size=%d\n",kmdf_array->value_type, kmdf_array->buf_pos, kmdf_array->buf_size);

        //过滤规则发送
        #if 0
        ynic_write_fpga_byte(STREAM_RX, stream_id, 1, FPGA_TX_PKT_CTRL_ITEEM0);
        ynic_convert_to_uint32(kmdf, kmdf_fpga, kmdf_actual_len);
        ynic_write_fpga_data(STREAM_RX, stream_id, kmdf_fpga, kmdf_fpga_len, FPGA_TX_PKT_CTRL_WRITE0);
        ynic_write_fpga_byte(STREAM_RX, stream_id, 1, FPGA_TX_PKT_CTRL_WDONE0);
        #endif
    } else {

        ynic_write_fpga_byte(STREAM_RX, stream_id, (1<<8), (FPGA_RX_FLT_ENB_BIT + offset));
#if 0
        ynic_write_fpga_byte(STREAM_RX, stream_id, 0, (FPGA_RX_FLT_BASE + offset));
        ynic_write_fpga_byte(STREAM_RX, stream_id, 1, (FPGA_RX_FLT_ENB_BIT + offset));
        ynic_write_fpga_byte(STREAM_RX, stream_id, 0, (FPGA_RX_FLT_ACTION + offset)); //queue/drop
        ynic_write_fpga_byte(STREAM_RX, stream_id, 0, (FPGA_RX_FLT_RELATION + offset));//and/or
        ynic_write_fpga_byte(STREAM_RX, stream_id, 1, (FPGA_RX_FLT_SIPV4_EN + offset));
        ynic_write_fpga_byte(STREAM_RX, stream_id, 0, (FPGA_RX_FLT_SIPV4_MODE + offset)); //==/!=
        ynic_write_fpga_byte(STREAM_RX, stream_id, 0xffffffff, (FPGA_RX_FLT_SIPV4_MSK + offset));
        ynic_write_fpga_byte(STREAM_RX, stream_id, 0, (FPGA_RX_FLT_SIPV4_VAL + offset));

        ynic_write_fpga_byte(STREAM_RX, stream_id, 0, (FPGA_RX_FLT_BASE + offset));
        ynic_write_fpga_byte(STREAM_RX, stream_id, 1, (FPGA_RX_FLT_ENB_BIT + offset));
        ynic_write_fpga_byte(STREAM_RX, stream_id, 0, (FPGA_RX_FLT_ACTION + offset));
        ynic_write_fpga_byte(STREAM_RX, stream_id, 0, (FPGA_RX_FLT_RELATION + offset));
        ynic_write_fpga_byte(STREAM_RX, stream_id, 1, (FPGA_RX_FLT_DIPV4_EN + offset));
        ynic_write_fpga_byte(STREAM_RX, stream_id, 0, (FPGA_RX_FLT_DIPV4_MODE + offset));
        ynic_write_fpga_byte(STREAM_RX, stream_id, 0xffffffff, (FPGA_RX_FLT_DIPV4_MSK + offset));
        ynic_write_fpga_byte(STREAM_RX, stream_id, 0, (FPGA_RX_FLT_DIPV4_VAL + offset));

        ynic_write_fpga_byte(STREAM_RX, stream_id, 0, (FPGA_RX_FLT_BASE + offset));
        ynic_write_fpga_byte(STREAM_RX, stream_id, 1, (FPGA_RX_FLT_ENB_BIT + offset));
        ynic_write_fpga_byte(STREAM_RX, stream_id, 0, (FPGA_RX_FLT_ACTION + offset));
        ynic_write_fpga_byte(STREAM_RX, stream_id, 0, (FPGA_RX_FLT_RELATION + offset));
        ynic_write_fpga_byte(STREAM_RX, stream_id, 1, (FPGA_RX_FLT_SPORT_EN + offset));
        ynic_write_fpga_byte(STREAM_RX, stream_id, 0, (FPGA_RX_FLT_SPORT_MODE + offset));
        ynic_write_fpga_byte(STREAM_RX, stream_id, 0xffff, (FPGA_RX_FLT_SPORT_MSK + offset));
        ynic_write_fpga_byte(STREAM_RX, stream_id, 0, (FPGA_RX_FLT_SPORT_VAL + offset));

        ynic_write_fpga_byte(STREAM_RX, stream_id, 0, (FPGA_RX_FLT_BASE + offset));
        ynic_write_fpga_byte(STREAM_RX, stream_id, 1, (FPGA_RX_FLT_ENB_BIT + offset));
        ynic_write_fpga_byte(STREAM_RX, stream_id, 0, (FPGA_RX_FLT_ACTION + offset));
        ynic_write_fpga_byte(STREAM_RX, stream_id, 0, (FPGA_RX_FLT_RELATION + offset));
        ynic_write_fpga_byte(STREAM_RX, stream_id, 1, (FPGA_RX_FLT_DPORT_EN + offset));
        ynic_write_fpga_byte(STREAM_RX, stream_id, 0, (FPGA_RX_FLT_DPORT_MODE + offset));
        ynic_write_fpga_byte(STREAM_RX, stream_id, 0xffff, (FPGA_RX_FLT_DPORT_MSK + offset));
        ynic_write_fpga_byte(STREAM_RX, stream_id, 0, (FPGA_RX_FLT_DPORT_VAL + offset));
#endif
    }

    // if (copy_to_user(ukcmd->k2u_mem, u2k_mem, ukcmd->u2k_len)) {
    //     ret = YNIC_ERR;
    //     goto kfree_ret;
    // }

kfree_ret:
    if (u2k_mem) {
        kfree(u2k_mem);
    }
    if(kstream_cfg) {
        kfree(kstream_cfg);
    }
    if(kmdf_array) {
        kfree(kmdf_array);
    }
    if(kmdf) {
        kfree(kmdf);
    }
    if(kmdf_fpga) {
        kfree(kmdf_fpga);
    }
    return ret;
}

static int
yuannic_netdev_close_rx_stream(ynic_ukcmd_t *ukcmd)
{
    int ret = YNIC_SUC;
    uint32_t kstm_id;

    uint8_t *u2k_mem = kmalloc(ukcmd->u2k_len, GFP_KERNEL);
    if (u2k_mem == NULL) {
        ret = YNIC_ERR;
        goto kfree_ret;
    }

    if (copy_from_user(u2k_mem, ukcmd->u2k_mem, ukcmd->u2k_len)) {
        ret = YNIC_ERR;
        goto kfree_ret;
    }
    kstm_id = ((uint32_t)u2k_mem[3] << 24) |
                ((uint32_t)u2k_mem[2] << 16) |
                ((uint32_t)u2k_mem[1] << 8)  |
                ((uint32_t)u2k_mem[0]);
    KDBG("zc-close-rx stream id=%d\n", kstm_id);

    if (kstm_id > 0 && kstm_id <= YNIC_TOTAL_STREAM_NUM_400G) {
        uint8_t port_id = (kstm_id - 1) / MAX_STREAM_PER_PORT_400G;
        uint32_t local_id = (kstm_id - 1) % MAX_STREAM_PER_PORT_400G;
        spin_lock(&krx_spinlock);
        if(krx_bitmap[port_id]) {
            clear_bit(local_id, krx_bitmap[port_id]);
        }
        spin_unlock(&krx_spinlock);
        KDBG(KERN_INFO "release rx stream id: %d\n", kstm_id);
    } else {
        printk(KERN_ERR "invalid rx stream id: %d\n", kstm_id);
        ret = YNIC_ERR;
        goto kfree_ret;
    }

    // if (copy_to_user(ukcmd->k2u_mem, u2k_mem, ukcmd->u2k_len)) {
    //     ret = YNIC_ERR;
    //     goto kfree_ret;
    // }

kfree_ret:
    if (u2k_mem) {
        kfree(u2k_mem);
    }
    return ret;
}
#if 1
static int
yuannic_netdev_start_rx_stream(ynic_ukcmd_t *ukcmd)
{
    int ret = YNIC_SUC;
    uint32_t stream_id;
    port_info info = {0};
    int func_id = -1;
    uint32_t offset = 0;

    uint8_t *u2k_mem = kmalloc(ukcmd->u2k_len, GFP_KERNEL);
    if (u2k_mem == NULL) {
        ret = YNIC_ERR;
        goto kfree_ret;
    }

    if (copy_from_user(u2k_mem, ukcmd->u2k_mem, ukcmd->u2k_len)) {
        ret = YNIC_ERR;
        goto kfree_ret;
    }

    stream_id = ((uint32_t)u2k_mem[3] << 24) |
                ((uint32_t)u2k_mem[2] << 16) |
                ((uint32_t)u2k_mem[1] << 8)  |
                ((uint32_t)u2k_mem[0]);
    KDBG("zc-rx_stream_start:%d\n", stream_id);

    //发给fpga哪个流开始了
    #ifdef FPGA_CONTROL_RX_STREAM
    func_id = ynic_get_net_bdf(STREAM_RX, stream_id, &info);
    if(func_id >= 0) {
        if(info.type == ALTERA_400G) {
            offset = func_id * FPGA_RX_OFFSET + FPGA_RX_BASE_ALTERA;
        } else {
            offset = func_id * FPGA_RX_OFFSET + FPGA_RX_BASE_XILINX;
        }
    } else {
        printk(KERN_ERR "%s get func_id %d Invalid\n",__func__, func_id);
        ret = YNIC_ERR;
        goto kfree_ret;
    }
    //1 divided into 4
    if(info.pf_num > 1) {
        ynic_write_fpga_byte(STREAM_RX, stream_id, ((uint8_t)0x1 << (info.adapter_id - func_id * 4)), (FPGA_RX_1to4 + offset));
        KDBG("zc-68-start-rx-stream_id=%d,adapter_id=%d,bdf=%s,func_id=%d,port_id=%d,hw_id=0x%02x\n",
            stream_id,info.adapter_id,info.port_bdf,func_id,info.port_id,((uint8_t)0x1 << (info.adapter_id - func_id * 4)));
    }
    ynic_write_fpga_byte(STREAM_RX, stream_id, 1, (FPGA_RX_ENB + offset));
    #endif

    // if (copy_to_user(ukcmd->k2u_mem, u2k_mem, ukcmd->u2k_len)) {
    //     ret = YNIC_ERR;
    //     goto kfree_ret;
    // }

kfree_ret:
    if (u2k_mem) {
        kfree(u2k_mem);
    }
    return ret;
}

static int
yuannic_netdev_stop_rx_stream(ynic_ukcmd_t *ukcmd)
{
    int ret = YNIC_SUC;
    uint32_t stream_id;
    port_info info = {0};
    int func_id = -1;
    uint32_t offset = 0;

    uint8_t *u2k_mem = kmalloc(ukcmd->u2k_len, GFP_KERNEL);
    if (u2k_mem == NULL) {
        ret = YNIC_ERR;
        goto kfree_ret;
    }

    if (copy_from_user(u2k_mem, ukcmd->u2k_mem, ukcmd->u2k_len)) {
        ret = YNIC_ERR;
        goto kfree_ret;
    }

    stream_id = ((uint32_t)u2k_mem[3] << 24) |
                ((uint32_t)u2k_mem[2] << 16) |
                ((uint32_t)u2k_mem[1] << 8)  |
                ((uint32_t)u2k_mem[0]);
    KDBG("zc-rx_stream_stop:%d\n", stream_id);
    #ifdef FPGA_CONTROL_RX_STREAM
    func_id = ynic_get_net_bdf(STREAM_RX, stream_id, &info);
    if(func_id >= 0) {
        if(info.type == ALTERA_400G) {
            offset = func_id * FPGA_RX_OFFSET + FPGA_RX_BASE_ALTERA;
        } else {
            offset = func_id * FPGA_RX_OFFSET + FPGA_RX_BASE_XILINX;
        }
    } else {
        printk(KERN_ERR "%s get func_id %d Invalid\n",__func__, func_id);
        ret = YNIC_ERR;
        goto kfree_ret;
    }
    //1 divided into 4
    if(info.pf_num > 1) {
        ynic_write_fpga_byte(STREAM_RX, stream_id, ((uint8_t)0x1 << (info.adapter_id - func_id * 4)), (FPGA_RX_1to4 + offset));
        KDBG("zc-69-stop-rx-stream_id=%d,adapter_id=%d,bdf=%s,func_id=%d,port_id=%d,hw_id=0x%02x\n",
            stream_id,info.adapter_id,info.port_bdf,func_id,info.port_id,((uint8_t)0x1 << (info.adapter_id - func_id * 4)));
    }
    ynic_write_fpga_byte(STREAM_RX, stream_id, 0, (FPGA_RX_FLT_ENB + offset));
    ynic_write_fpga_byte(STREAM_RX, stream_id, 0, (FPGA_RX_ENB + offset));
    #endif

    // if (copy_to_user(ukcmd->k2u_mem, u2k_mem, ukcmd->u2k_len)) {
    //     ret = YNIC_ERR;
    //     goto kfree_ret;
    // }

kfree_ret:
    if (u2k_mem) {
        kfree(u2k_mem);
    }
    return ret;
}
#endif

static int
yuannic_netdev_monitor_rx_stream(ynic_ukcmd_t *ukcmd)
{
    int ret = YNIC_SUC;
    uint32_t stream_id;
    ynic_txrx_stats_t *kstats = NULL;
#ifdef FPGA_CONTROL_RX_STREAM
    uint32_t val_low;
    uint32_t val_high;
#endif
    port_info info = {0};
    int func_id = -1;
    uint32_t offset = 0;

    uint8_t *u2k_mem = kmalloc(ukcmd->u2k_len, GFP_KERNEL);
    if (u2k_mem == NULL) {
        ret = YNIC_ERR;
        goto kfree_ret;
    }

    if (copy_from_user(u2k_mem, ukcmd->u2k_mem, ukcmd->u2k_len)) {
        ret = YNIC_ERR;
        goto kfree_ret;
    }

    stream_id = ((uint32_t)u2k_mem[3] << 24) |
                ((uint32_t)u2k_mem[2] << 16) |
                ((uint32_t)u2k_mem[1] << 8)  |
                ((uint32_t)u2k_mem[0]);
    KDBG("zc-monitor_rx_stream:%d\n", stream_id);

    kstats = kmalloc(sizeof(ynic_txrx_stats_t), GFP_KERNEL);
    if (!kstats) {
        ret = YNIC_ERR;
        goto kfree_ret;
    }
    memset(kstats, 0, sizeof(ynic_txrx_stats_t));

    #ifdef FPGA_CONTROL_RX_STREAM
    func_id = ynic_get_net_bdf(STREAM_RX, stream_id, &info);
    if(func_id >= 0) {
        if(info.type == ALTERA_400G) {
            offset = func_id * FPGA_RX_OFFSET + FPGA_RX_BASE_ALTERA;
        } else {
            offset = func_id * FPGA_RX_OFFSET + FPGA_RX_BASE_XILINX;
        }
    } else {
        printk(KERN_ERR "%s get func_id %d Invalid\n",__func__, func_id);
        ret = YNIC_ERR;
        goto kfree_ret;
    }

    //1 divided into 4
    if(info.pf_num > 1) {
        ynic_write_fpga_byte(STREAM_RX, stream_id, ((uint8_t)0x1 << (info.adapter_id - func_id * 4)), (FPGA_RX_1to4_READ + offset));
        KDBG("zc-monitor_rx_stream:%d,bdf=%s,adapter_id=%d,func_id=%d\n", stream_id,info.port_bdf,info.adapter_id,func_id);
    }
    //ynic_write_fpga_byte(STREAM_RX, stream_id, (1 & ~(0x10000)), (FPGA_RX_STA_CLEAR + offset));
    ynic_read_fpga_byte(STREAM_RX, stream_id, &val_low,(FPGA_PKTS_LOW_ADDR + offset));
    ynic_read_fpga_byte(STREAM_RX, stream_id, &val_high,(FPGA_RX_PKTS_HIGH_ADDR + offset));
    kstats->recv_packets = ((uint64_t)val_high << 32) | val_low;
    KDBG("zc-140-bdf=%s,adapter_id=%d,stream=%d,low=0x%08x,high=0x%08x,packet=%llu",
            info.port_bdf,info.adapter_id,stream_id, val_low, val_high, kstats->recv_packets);
    ynic_read_fpga_byte(STREAM_RX, stream_id, &val_low,(FPGA_RX_BYTES_LOW_ADDR + offset));
    ynic_read_fpga_byte(STREAM_RX, stream_id, &val_high,(FPGA_RX_BYTES_HIGH_ADDR + offset));
    kstats->recv_bytes = ((uint64_t)val_high << 32) | val_low;
    KDBG("zc-141-bdf=%s,adapter_id=%d,stream=%d,low=0x%08x,high=0x%08x,bytes=%llu",
            info.port_bdf,info.adapter_id,stream_id, val_low, val_high, kstats->recv_bytes);
    ynic_read_fpga_byte(STREAM_RX, stream_id, &val_low,(FPGA_RX_PKTS_DROP_LOW_ADDR + offset));
    ynic_read_fpga_byte(STREAM_RX, stream_id, &val_high,(FPGA_RX_PKTS_DROP_HIGH_ADDR + offset));
    kstats->drop_packets = ((uint64_t)val_high << 32) | val_low;
    KDBG("zc-142-bdf=%s,adapter_id=%d,stream=%d,low=0x%08x,high=0x%08x,drop_packet=%llu",
            info.port_bdf,info.adapter_id,stream_id, val_low, val_high, kstats->drop_packets);
    ynic_read_fpga_byte(STREAM_RX, stream_id, &val_low,(FPGA_RX_TS_SUM_LOW_ADDR + offset));
    ynic_read_fpga_byte(STREAM_RX, stream_id, &val_high,(FPGA_RX_TS_SUM_HIGH_ADDR + offset));
    kstats->rx_ts_sum_delay = ((uint64_t)val_high << 32) | val_low;
    KDBG("zc-145-bdf=%s,adapter_id=%d,stream=%d,low=0x%08x,high=0x%08x,sum_delay=%llu",
            info.port_bdf,info.adapter_id,stream_id, val_low, val_high, kstats->rx_ts_sum_delay);
    ynic_read_fpga_byte(STREAM_RX, stream_id, &val_low,(FPGA_RX_JT_SUM_LOW_ADDR + offset));
    ynic_read_fpga_byte(STREAM_RX, stream_id, &val_high,(FPGA_RX_JT_SUM_HIGH_ADDR + offset));
    kstats->rx_ts_sum_jitter = ((uint64_t)val_high << 32) | val_low;
    KDBG("zc-148-bdf=%s,stream=%d,adapter_id=%d,low=0x%08x,high=0x%08x,sum_jitter=%llu",
            info.port_bdf,stream_id,info.adapter_id, val_low, val_high, kstats->rx_ts_sum_jitter);
    ynic_read_fpga_byte(STREAM_RX, stream_id, &val_low,(FPGA_RX_BYTES_DROP_LOW_ADDR + offset));
    ynic_read_fpga_byte(STREAM_RX, stream_id, &val_high,(FPGA_RX_BYTES_DROP_HIGH_ADDR + offset));
    kstats->rx_drop_bytes = ((uint64_t)val_high << 32) | val_low;
    KDBG("zc-143-bdf=%s,adapter_id=%d,stream=%d,low=0x%08x,high=0x%08x,drop_bytes=%llu",
            info.port_bdf,info.adapter_id,stream_id, val_low, val_high, kstats->rx_drop_bytes);
    ynic_read_fpga_byte(STREAM_RX, stream_id, &val_low,(FPGA_RX_IP_CKSUM_ERR_LOW_ADDR + offset));
    ynic_read_fpga_byte(STREAM_RX, stream_id, &val_high,(FPGA_RX_IP_CKSUM_ERR_HIGH_ADDR + offset));
    kstats->rx_ip_cksum_err = ((uint64_t)val_high << 32) | val_low;
    KDBG("zc-144-bdf=%s,adapter_id=%d,stream=%d,low=0x%08x,high=0x%08x,ip_cksum_err=%llu",
            info.port_bdf,info.adapter_id,stream_id, val_low, val_high, kstats->rx_ip_cksum_err);
    ynic_read_fpga_byte(STREAM_RX, stream_id, &val_low,(FPGA_RX_TS_MAX_LOW_ADDR + offset));
    ynic_read_fpga_byte(STREAM_RX, stream_id, &val_high,(FPGA_RX_TS_MAX_HIGH_ADDR + offset));
    kstats->rx_ts_max_delay = ((uint64_t)val_high << 32) | val_low;
    KDBG("zc-146-bdf=%s,adapter_id=%d,stream=%d,low=0x%08x,high=0x%08x,max_delay=%llu",
            info.port_bdf,info.adapter_id,stream_id, val_low, val_high, kstats->rx_ts_max_delay);
    ynic_read_fpga_byte(STREAM_RX, stream_id, &val_low,(FPGA_RX_TS_MIN_LOW_ADDR + offset));
    ynic_read_fpga_byte(STREAM_RX, stream_id, &val_high,(FPGA_RX_TS_MIN_HIGH_ADDR + offset));
    kstats->rx_ts_min_delay = ((uint64_t)val_high << 32) | val_low;
    KDBG("zc-147-bdf=%s,adapter_id=%d,stream=%d,delay~sum=%llu~min=%llu~max=%llu",
            info.port_bdf,info.adapter_id,stream_id,kstats->rx_ts_sum_delay,kstats->rx_ts_min_delay,kstats->rx_ts_max_delay);
    ynic_read_fpga_byte(STREAM_RX, stream_id, &val_low,(FPGA_RX_JT_MAX_LOW_ADDR + offset));
    ynic_read_fpga_byte(STREAM_RX, stream_id, &val_high,(FPGA_RX_JT_MAX_HIGH_ADDR + offset));
    kstats->rx_ts_max_jitter = ((uint64_t)val_high << 32) | val_low;
    KDBG("zc-149-bdf=%s,adapter_id=%d,stream=%d,low=0x%08x,high=0x%08x,max_jitter=%llu",
            info.port_bdf,info.adapter_id, stream_id, val_low,val_high,kstats->rx_ts_max_jitter);
    ynic_read_fpga_byte(STREAM_RX, stream_id, &val_low,(FPGA_RX_JT_MIN_LOW_ADDR + offset));
    ynic_read_fpga_byte(STREAM_RX, stream_id, &val_high,(FPGA_RX_JT_MIN_HIGH_ADDR + offset));
    kstats->rx_ts_min_jitter = ((uint64_t)val_high << 32) | val_low;
    KDBG("zc-150-bdf=%s,adapter_id=%d,stream=%d,jitter~sum=%llu~min=%llu~max=%llu",
            info.port_bdf,info.adapter_id, stream_id,kstats->rx_ts_sum_jitter,kstats->rx_ts_min_jitter,kstats->rx_ts_max_jitter);
    ynic_read_fpga_byte(STREAM_RX, stream_id, &val_low,(FPGA_RX_BYTES_SPEED_LOW_ADDR + offset));
    ynic_read_fpga_byte(STREAM_RX, stream_id, &val_high,(FPGA_RX_BYTES_SPEED_HIGH_ADDR + offset));
    kstats->rx_bytes_speed = ((uint64_t)val_high << 32) | val_low;
    KDBG("zc-151-bdf=%s,adapter_id=%d,stream=%d,low=0x%08x,high=0x%08x,bps=%llu",
            info.port_bdf,info.adapter_id,stream_id, val_low, val_high, kstats->rx_bytes_speed);
    ynic_read_fpga_byte(STREAM_RX, stream_id, &val_low,(FPGA_RX_PKTS_SPEED_LOW_ADDR + offset));
    ynic_read_fpga_byte(STREAM_RX, stream_id, &val_high,(FPGA_RX_PKTS_SPEED_HIGH_ADDR + offset));
    kstats->rx_pkts_speed = ((uint64_t)val_high << 32) | val_low;
    KDBG("zc-152-bdf=%s,adapter_id=%d,stream=%d,low=0x%08x,high=0x%08x,pkts_speed=%llu",
            info.port_bdf,info.adapter_id,stream_id, val_low, val_high, kstats->rx_pkts_speed);
    ynic_read_fpga_byte(STREAM_RX, stream_id, &val_low,(FPGA_RX_TIME_START_LOW_ADDR + offset));
    ynic_read_fpga_byte(STREAM_RX, stream_id, &val_high,(FPGA_RX_TIME_START_HIGH_ADDR + offset));
    kstats->rx_time_start = ((uint64_t)val_high << 32) | val_low;
    KDBG("zc-153-bdf=%s,adapter_id=%d,stream=%d,low=0x%08x,high=0x%08x,rx_time_start=%llu",
            info.port_bdf,info.adapter_id,stream_id, val_low, val_high, kstats->rx_time_start);
    ynic_read_fpga_byte(STREAM_RX, stream_id, &val_low,(FPGA_RX_TIME_STOP_LOW_ADDR + offset));
    ynic_read_fpga_byte(STREAM_RX, stream_id, &val_high,(FPGA_RX_TIME_STOP_HIGH_ADDR + offset));
    kstats->rx_time_stop = ((uint64_t)val_high << 32) | val_low;
    KDBG("zc-154-bdf=%s,adapter_id=%d,stream=%d,low=0x%08x,high=0x%08x,rx_time_stop=%llu,stop-start=0x%llx~~%llu",
            info.port_bdf,info.adapter_id, stream_id, val_low, val_high, kstats->rx_time_stop,
            (kstats->rx_time_stop-kstats->rx_time_start),(kstats->rx_time_stop-kstats->rx_time_start));
    #endif

    if (copy_to_user(ukcmd->k2u_mem, (uint8_t *)kstats, ukcmd->k2u_len)) {
        ret = YNIC_ERR;
        goto kfree_ret;
    }

kfree_ret:
    if (u2k_mem) {
        kfree(u2k_mem);
    }
    if(kstats) {
        kfree(kstats);
    }
    return ret;
}

static int
yuannic_netdev_monitor_rx_mul_streams(ynic_ukcmd_t *ukcmd)
{
    int ret = YNIC_SUC;
    uint32_t stream_id;
    ynic_encap_rx_stats_t *kstats = NULL;
    uint32_t min_id = 0, max_id = 0, nb_stream = 0;
#ifdef FPGA_CONTROL_RX_STREAM
    uint32_t val_low;
    uint32_t val_high;
#endif
    port_info info = {0};
    int func_id = -1;
    uint32_t offset = 0;
    uint16_t fpga_id = 0;
    int i;

    uint8_t *u2k_mem = kmalloc(ukcmd->u2k_len, GFP_KERNEL);
    if (u2k_mem == NULL) {
        ret = YNIC_ERR;
        goto kfree_ret;
    }

    if (copy_from_user(u2k_mem, ukcmd->u2k_mem, ukcmd->u2k_len)) {
        ret = YNIC_ERR;
        goto kfree_ret;
    }

    stream_id = ((uint32_t)u2k_mem[3] << 24) |
                ((uint32_t)u2k_mem[2] << 16) |
                ((uint32_t)u2k_mem[1] << 8)  |
                ((uint32_t)u2k_mem[0]);
    min_id = stream_id;
    max_id = ((uint32_t)u2k_mem[7] << 24) |
             ((uint32_t)u2k_mem[6] << 16) |
             ((uint32_t)u2k_mem[5] << 8)  |
             ((uint32_t)u2k_mem[4]);
    if(min_id > max_id) {
        ret = YNIC_ERR;
        printk(KERN_ERR "%s stream id err,min:%d-max:%d\n",__func__, min_id, max_id);
        goto kfree_ret;
    }
    nb_stream = max_id - min_id + 1;

    kstats = kcalloc(nb_stream, sizeof(ynic_encap_rx_stats_t), GFP_KERNEL);
    if (!kstats) {
        ret = YNIC_ERR;
        goto kfree_ret;
    }

    #ifdef FPGA_CONTROL_RX_STREAM
    func_id = ynic_get_net_bdf(STREAM_RX, stream_id, &info);
    if(func_id >= 0) {
        if(info.type == ALTERA_400G) {
            offset = func_id * FPGA_RX_OFFSET + FPGA_RX_BASE_ALTERA;
        } else {
            offset = func_id * FPGA_RX_OFFSET + FPGA_RX_BASE_XILINX;
        }
    } else {
        printk(KERN_ERR "%s get func_id %d Invalid\n",__func__, func_id);
        ret = YNIC_ERR;
        goto kfree_ret;
    }
    fpga_id = stream_id - (info.port_id * MAX_STREAM_PER_PORT_400G) - 1;
    KDBG("zc-monitor_rx_mul_streams,id=%d,fpga_id=%d\n", stream_id, fpga_id);
    //1 divided into 4
    if(info.pf_num > 1) {
        ynic_write_fpga_byte(STREAM_RX, stream_id, ((uint8_t)0x1 << (info.adapter_id - func_id * 4)), (FPGA_RX_1to4_READ + offset));
    }

    for(i=0;i<nb_stream;i++) {
        ynic_write_fpga_byte(STREAM_RX, stream_id, ((fpga_id+i) & ~(0x10000)), (FPGA_RX_STA_CLEAR + offset));

        ynic_read_fpga_byte(STREAM_RX, stream_id, &val_low,(FPGA_RX_PKTS_MUL_LOW_ADDR + offset));
        ynic_read_fpga_byte(STREAM_RX, stream_id, &val_high,(FPGA_RX_PKTS_MUL_HIGH_ADDR + offset));
        kstats[i].rx_mul_pkts = ((uint64_t)val_high << 32) | val_low;
        KDBG("zc-160-bdf=%s,adapter_id=%d,stream=%d,i=%d,low=0x%08x,high=0x%08x,rx_pkts_mul=%llu",
                info.port_bdf,info.adapter_id, stream_id, i, val_low, val_high, kstats[i].rx_mul_pkts);
        ynic_read_fpga_byte(STREAM_RX, stream_id, &val_low,(FPGA_RX_TS_SUM_MUL_LOW_ADDR + offset));
        ynic_read_fpga_byte(STREAM_RX, stream_id, &val_high,(FPGA_RX_TS_SUM_MUL_HIGH_ADDR + offset));
        kstats[i].rmul_ts_sum_delay = ((uint64_t)val_high << 32) | val_low;
        ynic_read_fpga_byte(STREAM_RX, stream_id, &val_low,(FPGA_RX_JT_SUM_MUL_LOW_ADDR + offset));
        ynic_read_fpga_byte(STREAM_RX, stream_id, &val_high,(FPGA_RX_JT_SUM_MUL_HIGH_ADDR + offset));
        kstats[i].rmul_ts_sum_jitter = ((uint64_t)val_high << 32) | val_low;

        ynic_read_fpga_byte(STREAM_RX, stream_id, &val_low,(FPGA_RX_BYTES_MUL_LOW_ADDR + offset));
        ynic_read_fpga_byte(STREAM_RX, stream_id, &val_high,(FPGA_RX_BYTES_MUL_HIGH_ADDR + offset));
        kstats[i].rx_mul_bytes = ((uint64_t)val_high << 32) | val_low;
        KDBG("zc-161-bdf=%s,adapter_id=%d,stream=%d,i=%d, low=0x%08x,high=0x%08x,rx_bytes_mul=%llu",
                info.port_bdf,info.adapter_id, stream_id, i, val_low, val_high, kstats[i].rx_mul_bytes);

        ynic_read_fpga_byte(STREAM_RX, stream_id, &val_low,(FPGA_RX_TS_MAX_MUL_LOW_ADDR + offset));
        ynic_read_fpga_byte(STREAM_RX, stream_id, &val_high,(FPGA_RX_TS_MAX_MUL_HIGH_ADDR + offset));
        kstats[i].rmul_ts_max_delay = ((uint64_t)val_high << 32) | val_low;
        ynic_read_fpga_byte(STREAM_RX, stream_id, &val_low,(FPGA_RX_TS_MIN_MUL_LOW_ADDR + offset));
        ynic_read_fpga_byte(STREAM_RX, stream_id, &val_high,(FPGA_RX_TS_MIN_MUL_HIGH_ADDR + offset));
        kstats[i].rmul_ts_min_delay = ((uint64_t)val_high << 32) | val_low;
        KDBG("zc-162-bdf=%s,adapter_id=%d,stream=%d,delay~sum=%llu~min=%llu~max=%llu",
                info.port_bdf, info.adapter_id,stream_id, kstats[i].rmul_ts_sum_delay,
                kstats[i].rmul_ts_min_delay,kstats[i].rmul_ts_max_delay);
        ynic_read_fpga_byte(STREAM_RX, stream_id, &val_low,(FPGA_RX_JT_MAX_MUL_LOW_ADDR + offset));
        ynic_read_fpga_byte(STREAM_RX, stream_id, &val_high,(FPGA_RX_JT_MAX_MUL_HIGH_ADDR + offset));
        kstats[i].rmul_ts_max_jitter = ((uint64_t)val_high << 32) | val_low;
        ynic_read_fpga_byte(STREAM_RX, stream_id, &val_low,(FPGA_RX_JT_MIN_MUL_LOW_ADDR + offset));
        ynic_read_fpga_byte(STREAM_RX, stream_id, &val_high,(FPGA_RX_JT_MIN_MUL_HIGH_ADDR + offset));
        kstats[i].rmul_ts_min_jitter = ((uint64_t)val_high << 32) | val_low;
        KDBG("zc-163-bdf=%s,adapter_id=%d,stream=%d,jitter~sum=%llu~min=%llu~max=%llu",
                info.port_bdf, info.adapter_id,stream_id, kstats[i].rmul_ts_sum_jitter,
                kstats[i].rmul_ts_min_jitter,kstats[i].rmul_ts_max_jitter);
        ynic_read_fpga_byte(STREAM_RX, stream_id, &val_low,(FPGA_RX_DROP_MUL_LOW_ADDR + offset));
        kstats[i].rx_drop_rate = val_low;
        KDBG("zc-164-bdf=%s,adapter_id=%d,stream=%d,rx_drop=%llu",
                info.port_bdf, info.adapter_id,stream_id, kstats[i].rx_drop_rate);
        ynic_read_fpga_byte(STREAM_RX, stream_id, &val_low,(FPGA_RX_PKTS_SPEED_MUL_LOW_ADDR + offset));
        kstats[i].rx_pkts_speed = val_low;
        KDBG("zc-165-bdf=%s,adapter_id=%d,stream=%d,rx_pkts_speed=%llu",
                info.port_bdf, info.adapter_id,stream_id, kstats[i].rx_pkts_speed);
        ynic_read_fpga_byte(STREAM_RX, stream_id, &val_low,(FPGA_RX_BYTES_SPEED_MUL_LOW_ADDR + offset));
        ynic_read_fpga_byte(STREAM_RX, stream_id, &val_high,(FPGA_RX_BYTES_SPEED_MUL_HIGH_ADDR + offset));
        kstats[i].rx_bytes_speed = ((uint64_t)val_high << 32) | val_low;
        KDBG("zc-166-bdf=%s,adapter_id=%d,stream=%d,rx_bytes_speed=%llu",
                info.port_bdf, info.adapter_id,stream_id, kstats[i].rx_bytes_speed);

        if(i <= 8) {
            ynic_read_fpga_byte(STREAM_RX, stream_id, &val_low,(FPGA_RX_FLT0_PKT_LOW + offset + i*4));
            ynic_read_fpga_byte(STREAM_RX, stream_id, &val_high,(FPGA_RX_FLT0_PKT_HIGH + offset + i*4));
            kstats[i].rx_flt_pkts = ((uint64_t)val_high << 32) | val_low;
            ynic_read_fpga_byte(STREAM_RX, stream_id, &val_low,(FPGA_RX_FLT0_BYTE_LOW + offset + i*4));
            ynic_read_fpga_byte(STREAM_RX, stream_id, &val_high,(FPGA_RX_FLT0_BYTE_HIGH + offset + i*4));
            kstats[i].rx_flt_bytes = ((uint64_t)val_high << 32) | val_low;
            KDBG("zc-164-%d-bdf=%s,adapter_id=%d,stream=%d,flt_pkts=%llu\n",
                    i,info.port_bdf,info.adapter_id,stream_id, kstats[i].rx_flt_pkts);
        }
        #endif
    }

    if (copy_to_user(ukcmd->k2u_mem, (uint8_t *)kstats, ukcmd->k2u_len)) {
        ret = YNIC_ERR;
        goto kfree_ret;
    }

kfree_ret:
    if (u2k_mem) {
        kfree(u2k_mem);
    }
    if(kstats) {
        kfree(kstats);
    }
    return ret;
}

static int
yuannic_netdev_clear_rx_stream(ynic_ukcmd_t *ukcmd)
{
    int ret = YNIC_SUC;
    uint32_t stream_id;
    port_info info = {0};
    int func_id = -1;
    uint32_t offset = 0;

    uint8_t *u2k_mem = kmalloc(ukcmd->u2k_len, GFP_KERNEL);
    if (u2k_mem == NULL) {
        ret = YNIC_ERR;
        goto kfree_ret;
    }

    if (copy_from_user(u2k_mem, ukcmd->u2k_mem, ukcmd->u2k_len)) {
        ret = YNIC_ERR;
        goto kfree_ret;
    }
    stream_id = ((uint32_t)u2k_mem[3] << 24) |
                ((uint32_t)u2k_mem[2] << 16) |
                ((uint32_t)u2k_mem[1] << 8)  |
                ((uint32_t)u2k_mem[0]);
    KDBG("zc-rx-clear-stream id=%d\n", stream_id);

    #ifdef FPGA_CONTROL_RX_STREAM
    func_id = ynic_get_net_bdf(STREAM_RX, stream_id, &info);
    if(func_id >= 0) {
        if(info.type == ALTERA_400G) {
            offset = func_id * FPGA_RX_OFFSET + FPGA_RX_BASE_ALTERA;
        } else {
            offset = func_id * FPGA_RX_OFFSET + FPGA_RX_BASE_XILINX;
        }
    } else {
        printk(KERN_ERR "%s get func_id %d Invalid\n",__func__, func_id);
        ret = YNIC_ERR;
        goto kfree_ret;
    }
    //1 divided into 4
    if(info.pf_num > 1) {
        ynic_write_fpga_byte(STREAM_RX, stream_id, ((uint8_t)0x1 << (info.adapter_id - func_id * 4)), (FPGA_RX_1to4 + offset));
    }
    ynic_write_fpga_byte(STREAM_RX, stream_id, (0 | 0x10000), (FPGA_RX_STA_CLEAR + offset));
    #endif

    // if (copy_to_user(ukcmd->k2u_mem, u2k_mem, ukcmd->u2k_len)) {
    //     ret = YNIC_ERR;
    //     goto kfree_ret;
    // }

kfree_ret:
    if (u2k_mem) {
        kfree(u2k_mem);
    }
    return ret;
}

static int
yuannic_netdev_promisc_rx_stream(ynic_ukcmd_t *ukcmd)
{
    int ret = YNIC_SUC;
    ynic_uk_cfg_t *kukcfg = NULL;

    uint8_t *u2k_mem = kmalloc(ukcmd->u2k_len, GFP_KERNEL);
    if (u2k_mem == NULL) {
        ret = YNIC_ERR;
        goto kfree_ret;
    }

    if (copy_from_user(u2k_mem, ukcmd->u2k_mem, ukcmd->u2k_len)) {
        ret = YNIC_ERR;
        goto kfree_ret;
    }

    kukcfg = kmalloc(sizeof(ynic_uk_cfg_t), GFP_KERNEL);
    if(!kukcfg) {
        ret = YNIC_ERR;
        goto kfree_ret;
    }
    strscpy(kukcfg->port_pciid, ((ynic_uk_cfg_t *)u2k_mem)->port_pciid, sizeof(kukcfg->port_pciid));
    kukcfg->promisc  = ((ynic_uk_cfg_t *)u2k_mem)->promisc;
    KDBG("zc-rx-stream promisc=%d\n", kukcfg->promisc);

    #ifdef FPGA_CONTROL_RX_STREAM
    ynic_write_byte_by_pciid(kukcfg->port_pciid, kukcfg->promisc, FPGA_RX_PROMISC_ENB, FPGA_RX_OFFSET);
    #endif

    // if (copy_to_user(ukcmd->k2u_mem, u2k_mem, ukcmd->u2k_len)) {
    //     ret = YNIC_ERR;
    //     goto kfree_ret;
    // }

kfree_ret:
    if (u2k_mem) {
        kfree(u2k_mem);
    }
    if(kukcfg) {
        kfree(kukcfg);
    }
    return ret;
}


static int yuannic_netdev_monitor_txrx_stats(ynic_ukcmd_t *ukcmd)
{
    int ret = YNIC_SUC;
    ynic_txrx_debug_t *kdebug = NULL;
    char pci_bdf[16];
    uint32_t val_high=0, val_low=0;

    uint8_t *u2k_mem = kmalloc(ukcmd->u2k_len, GFP_KERNEL);
    if (u2k_mem == NULL) {
        ret = YNIC_ERR;
        goto kfree_ret;
    }

    if (copy_from_user(u2k_mem, ukcmd->u2k_mem, ukcmd->u2k_len)) {
        ret = YNIC_ERR;
        goto kfree_ret;
    }

    kdebug = kmalloc(sizeof(ynic_txrx_debug_t), GFP_KERNEL);
    if (!kdebug) {
        ret = YNIC_ERR;
        goto kfree_ret;
    }
    memset(kdebug, 0, sizeof(ynic_txrx_debug_t));

    strscpy(pci_bdf,((char *)u2k_mem), sizeof(pci_bdf));

    ynic_read_byte_by_pciid(pci_bdf, &val_low, DEBUG_H2C_TREADY_LOW_SUM_CNT, 0);
    ynic_read_byte_by_pciid(pci_bdf, &val_high, DEBUG_H2C_TREADY_HIGH_SUM_CNT, 0);
    kdebug->h2c_tready_sum = ((uint64_t)val_high << 32) | val_low;
    ynic_read_byte_by_pciid(pci_bdf, &val_low, DEBUG_C2H_TREADY_LOW_SUM_CNT, 0);
    ynic_read_byte_by_pciid(pci_bdf, &val_high, DEBUG_C2H_TREADY_HIGH_SUM_CNT, 0);
    kdebug->c2h_tready_sum = ((uint64_t)val_high << 32) | val_low;

    ynic_read_byte_by_pciid(pci_bdf, &val_low, DEBUG_H2C_TREADY_SEC_CNT, 0);
    kdebug->h2c_tready_sec = val_low;

    ynic_read_byte_by_pciid(pci_bdf, &val_low, DEBUG_C2H_TREADY_SEC_CNT, 0);
    kdebug->c2h_tready_sec = val_low;

    ynic_read_byte_by_pciid(pci_bdf, &val_low, DEBUG_QDMA0_LOW_TX_CNT, 0);
    ynic_read_byte_by_pciid(pci_bdf, &val_high, DEBUG_QDMA0_HIGH_TX_CNT, 0);
    kdebug->qdma0_tx_cnt = ((uint64_t)val_high << 32) | val_low;
    ynic_read_byte_by_pciid(pci_bdf, &val_low, DEBUG_QDMA1_LOW_TX_CNT, 0);
    ynic_read_byte_by_pciid(pci_bdf, &val_high, DEBUG_QDMA1_HIGH_TX_CNT, 0);
    kdebug->qdma1_tx_cnt = ((uint64_t)val_high << 32) | val_low;
    ynic_read_byte_by_pciid(pci_bdf, &val_low, DEBUG_QDMA2_LOW_TX_CNT, 0);
    ynic_read_byte_by_pciid(pci_bdf, &val_high, DEBUG_QDMA2_HIGH_TX_CNT, 0);
    kdebug->qdma2_tx_cnt = ((uint64_t)val_high << 32) | val_low;
    ynic_read_byte_by_pciid(pci_bdf, &val_low, DEBUG_QDMA3_LOW_TX_CNT, 0);
    ynic_read_byte_by_pciid(pci_bdf, &val_high, DEBUG_QDMA3_HIGH_TX_CNT, 0);
    kdebug->qdma3_tx_cnt = ((uint64_t)val_high << 32) | val_low;

    ynic_read_byte_by_pciid(pci_bdf, &val_low, DEBUG_QDMA0_LOW_RX_CNT, 0);
    ynic_read_byte_by_pciid(pci_bdf, &val_high, DEBUG_QDMA0_HIGH_RX_CNT, 0);
    kdebug->qdma0_rx_cnt = ((uint64_t)val_high << 32) | val_low;
    ynic_read_byte_by_pciid(pci_bdf, &val_low, DEBUG_QDMA1_LOW_RX_CNT, 0);
    ynic_read_byte_by_pciid(pci_bdf, &val_high, DEBUG_QDMA1_HIGH_RX_CNT, 0);
    kdebug->qdma1_rx_cnt = ((uint64_t)val_high << 32) | val_low;
    ynic_read_byte_by_pciid(pci_bdf, &val_low, DEBUG_QDMA2_LOW_RX_CNT, 0);
    ynic_read_byte_by_pciid(pci_bdf, &val_high, DEBUG_QDMA2_HIGH_RX_CNT, 0);
    kdebug->qdma2_rx_cnt = ((uint64_t)val_high << 32) | val_low;
    ynic_read_byte_by_pciid(pci_bdf, &val_low, DEBUG_QDMA3_LOW_RX_CNT, 0);
    ynic_read_byte_by_pciid(pci_bdf, &val_high, DEBUG_QDMA3_HIGH_RX_CNT, 0);
    kdebug->qdma3_rx_cnt = ((uint64_t)val_high << 32) | val_low;

    ynic_read_byte_by_pciid(pci_bdf, &val_low, DEBUG_MAC0_LOW_TX_CNT, 0);
    ynic_read_byte_by_pciid(pci_bdf, &val_high, DEBUG_MAC0_HIGH_TX_CNT, 0);
    kdebug->mac0_tx_cnt = ((uint64_t)val_high << 32) | val_low;
    ynic_read_byte_by_pciid(pci_bdf, &val_low, DEBUG_MAC1_LOW_TX_CNT, 0);
    ynic_read_byte_by_pciid(pci_bdf, &val_high, DEBUG_MAC1_HIGH_TX_CNT, 0);
    kdebug->mac1_tx_cnt = ((uint64_t)val_high << 32) | val_low;
    ynic_read_byte_by_pciid(pci_bdf, &val_low, DEBUG_MAC2_LOW_TX_CNT, 0);
    ynic_read_byte_by_pciid(pci_bdf, &val_high, DEBUG_MAC2_HIGH_TX_CNT, 0);
    kdebug->mac2_tx_cnt = ((uint64_t)val_high << 32) | val_low;
    ynic_read_byte_by_pciid(pci_bdf, &val_low, DEBUG_MAC3_LOW_TX_CNT, 0);
    ynic_read_byte_by_pciid(pci_bdf, &val_high, DEBUG_MAC3_HIGH_TX_CNT, 0);
    kdebug->mac3_tx_cnt = ((uint64_t)val_high << 32) | val_low;

    ynic_read_byte_by_pciid(pci_bdf, &val_low, DEBUG_MAC0_LOW_RX_CNT, 0);
    ynic_read_byte_by_pciid(pci_bdf, &val_high, DEBUG_MAC0_HIGH_RX_CNT, 0);
    kdebug->mac0_rx_cnt = ((uint64_t)val_high << 32) | val_low;
    ynic_read_byte_by_pciid(pci_bdf, &val_low, DEBUG_MAC1_LOW_RX_CNT, 0);
    ynic_read_byte_by_pciid(pci_bdf, &val_high, DEBUG_MAC1_HIGH_RX_CNT, 0);
    kdebug->mac1_rx_cnt = ((uint64_t)val_high << 32) | val_low;
    ynic_read_byte_by_pciid(pci_bdf, &val_low, DEBUG_MAC2_LOW_RX_CNT, 0);
    ynic_read_byte_by_pciid(pci_bdf, &val_high, DEBUG_MAC2_HIGH_RX_CNT, 0);
    kdebug->mac2_rx_cnt = ((uint64_t)val_high << 32) | val_low;
    ynic_read_byte_by_pciid(pci_bdf, &val_low, DEBUG_MAC3_LOW_RX_CNT, 0);
    ynic_read_byte_by_pciid(pci_bdf, &val_high, DEBUG_MAC3_HIGH_RX_CNT, 0);
    kdebug->mac3_rx_cnt = ((uint64_t)val_high << 32) | val_low;

    ynic_read_byte_by_pciid(pci_bdf, &val_low, DEBUG_ADAPTER0_LOW_RX_CNT, 0);
    ynic_read_byte_by_pciid(pci_bdf, &val_high, DEBUG_ADAPTER0_HIGH_RX_CNT, 0);
    kdebug->adapter0_rx_cnt = ((uint64_t)val_high << 32) | val_low;
    ynic_read_byte_by_pciid(pci_bdf, &val_low, DEBUG_ADAPTER1_LOW_RX_CNT, 0);
    ynic_read_byte_by_pciid(pci_bdf, &val_high, DEBUG_ADAPTER1_HIGH_RX_CNT, 0);
    kdebug->adapter1_rx_cnt = ((uint64_t)val_high << 32) | val_low;
    ynic_read_byte_by_pciid(pci_bdf, &val_low, DEBUG_ADAPTER2_LOW_RX_CNT, 0);
    ynic_read_byte_by_pciid(pci_bdf, &val_high, DEBUG_ADAPTER2_HIGH_RX_CNT, 0);
    kdebug->adapter2_rx_cnt = ((uint64_t)val_high << 32) | val_low;
    ynic_read_byte_by_pciid(pci_bdf, &val_low, DEBUG_ADAPTER3_LOW_RX_CNT, 0);
    ynic_read_byte_by_pciid(pci_bdf, &val_high, DEBUG_ADAPTER3_HIGH_RX_CNT, 0);
    kdebug->adapter3_rx_cnt = ((uint64_t)val_high << 32) | val_low;

    ynic_read_byte_by_pciid(pci_bdf, &val_low, FPGA_TEMPERATURE_REG, 0);
    kdebug->fpga_temp = val_low;

    if (copy_to_user(ukcmd->k2u_mem, (uint8_t *)kdebug, ukcmd->k2u_len)) {
        ret = YNIC_ERR;
        goto kfree_ret;
    }

kfree_ret:
    if (u2k_mem) {
        kfree(u2k_mem);
    }
    if(kdebug) {
        kfree(kdebug);
    }
    return ret;
}


static int yuannic_netdev_clear_txrx_stats(ynic_ukcmd_t *ukcmd)
{
    int ret = YNIC_SUC;
    char pci_bdf[16];

    uint8_t *u2k_mem = kmalloc(ukcmd->u2k_len, GFP_KERNEL);
    if (u2k_mem == NULL) {
        ret = YNIC_ERR;
        goto kfree_ret;
    }

    if (copy_from_user(u2k_mem, ukcmd->u2k_mem, ukcmd->u2k_len)) {
        ret = YNIC_ERR;
        goto kfree_ret;
    }

    strscpy(pci_bdf, ((char *)u2k_mem), sizeof(pci_bdf));

    ynic_write_byte_by_pciid(pci_bdf, 1, FPGA_CLEAR_STATIS_REG, 0);
    ynic_write_byte_by_pciid(pci_bdf, 0, FPGA_CLEAR_STATIS_REG, 0);

    //if (copy_to_user(ukcmd->k2u_mem, u2k_mem, ukcmd->u2k_len)) {
    //    ret = YNIC_ERR;
    //    goto kfree_ret;
    //}

kfree_ret:
    if (u2k_mem) {
        kfree(u2k_mem);
    }
    return ret;
}

static inline int yuannic_netdev_set_rx_qid(ynic_ukcmd_t *ukcmd)
{
    int ret = YNIC_SUC;
    ynic_uk_cfg_t *kukcfg = NULL;

    uint8_t *u2k_mem = kmalloc(ukcmd->u2k_len, GFP_KERNEL);
    if (u2k_mem == NULL) {
        ret = YNIC_ERR;
        goto kfree_ret;
    }

    if (copy_from_user(u2k_mem, ukcmd->u2k_mem, ukcmd->u2k_len)) {
        ret = YNIC_ERR;
        goto kfree_ret;
    }

    kukcfg = kmalloc(sizeof(ynic_uk_cfg_t), GFP_KERNEL);
    if(!kukcfg) {
        ret = YNIC_ERR;
        goto kfree_ret;
    }
    strscpy(kukcfg->port_pciid, ((ynic_uk_cfg_t *)u2k_mem)->port_pciid, sizeof(kukcfg->port_pciid));
    kukcfg->rxque_id  = ((ynic_uk_cfg_t *)u2k_mem)->rxque_id;

    KDBG("zc-111-qid=%d,reg=0x%08x\n",kukcfg->rxque_id,FPGA_RX_QUEUE_ID);
    ynic_write_byte_by_pciid(kukcfg->port_pciid, kukcfg->rxque_id, FPGA_RX_QUEUE_ID , FPGA_RX_OFFSET);


    //if (copy_to_user(ukcmd->k2u_mem, u2k_mem, ukcmd->u2k_len)) {
    //    ret = YNIC_ERR;
    //    goto kfree_ret;
    //}

kfree_ret:
    if (u2k_mem) {
        kfree(u2k_mem);
    }
    if(kukcfg) {
        kfree(kukcfg);
    }
    return ret;
}


static inline int yuannic_netdev_set_work_mode(ynic_ukcmd_t *ukcmd)
{
    int ret = YNIC_SUC;
    ynic_uk_cfg_t *kukcfg = NULL;
    uint8_t wk_mode = 0,tt_mode = 0;


    uint8_t *u2k_mem = kmalloc(ukcmd->u2k_len, GFP_KERNEL);
    if (u2k_mem == NULL) {
        ret = YNIC_ERR;
        goto kfree_ret;
    }

    if (copy_from_user(u2k_mem, ukcmd->u2k_mem, ukcmd->u2k_len)) {
        ret = YNIC_ERR;
        goto kfree_ret;
    }

    kukcfg = kmalloc(sizeof(ynic_uk_cfg_t), GFP_KERNEL);
    if(!kukcfg) {
        ret = YNIC_ERR;
        goto kfree_ret;
    }
    strscpy(kukcfg->port_pciid, ((ynic_uk_cfg_t *)u2k_mem)->port_pciid, sizeof(kukcfg->port_pciid));
    kukcfg->work_mode  = ((ynic_uk_cfg_t *)u2k_mem)->work_mode;
    tt_mode = (kukcfg->work_mode >> 4) & 0xf;
    wk_mode = kukcfg->work_mode & 0xf;


    KDBG("zc-130-pciid=%s,work_mode=%d,test_mode=%d,reg=0x%08x\n",kukcfg->port_pciid,wk_mode,tt_mode,FPGA_RX_WORK_MODE);
    ynic_write_byte_by_pciid(kukcfg->port_pciid, wk_mode, FPGA_RX_WORK_MODE , FPGA_RX_OFFSET);
    ynic_write_byte_by_pciid(kukcfg->port_pciid, tt_mode, FPGA_RX_TEST_MODE , FPGA_RX_OFFSET);


    //if (copy_to_user(ukcmd->k2u_mem, u2k_mem, ukcmd->u2k_len)) {
    //    ret = YNIC_ERR;
    //    goto kfree_ret;
    //}

kfree_ret:
    if (u2k_mem) {
        kfree(u2k_mem);
    }
    if(kukcfg) {
        kfree(kukcfg);
    }
    return ret;
}

static int yuannic_netdev_get_send_status(ynic_ukcmd_t *ukcmd)
{
    int ret = YNIC_SUC;
    ynic_uk_cfg_t *kukcfg = NULL;
    u8 adapter_id;
    u8 pf_num;
    uint32_t domain,bus,dev,func;
    uint32_t ktxsta;

    uint8_t *u2k_mem = kmalloc(ukcmd->u2k_len, GFP_KERNEL);
    if (u2k_mem == NULL) {
        ret = YNIC_ERR;
        goto kfree_ret;
    }

    if (copy_from_user(u2k_mem, ukcmd->u2k_mem, ukcmd->u2k_len)) {
        ret = YNIC_ERR;
        goto kfree_ret;
    }

    kukcfg = kmalloc(sizeof(ynic_uk_cfg_t), GFP_KERNEL);
    if(!kukcfg) {
        ret = YNIC_ERR;
        goto kfree_ret;
    }
    strscpy(kukcfg->port_pciid, ((ynic_uk_cfg_t *)u2k_mem)->port_pciid, sizeof(kukcfg->port_pciid));
    kukcfg->system_portid  = ((ynic_uk_cfg_t *)u2k_mem)->system_portid;

    pf_num = kptnm[kukcfg->system_portid].pf_num;
    adapter_id = kptnm[kukcfg->system_portid].adapter_id;

    if (sscanf(kukcfg->port_pciid, "%04x:%02x:%02x.%01x", &domain, &bus, &dev, &func) != 4) {
        printk(KERN_ERR "pci device %s Invalid.\n", kukcfg->port_pciid);
        return -EINVAL;
    }

    if(pf_num > 1) {
        ynic_write_byte_by_pciid(kukcfg->port_pciid, (adapter_id - func * 4), FPGA_TX_1to4_SEL_ADDR , FPGA_TX_OFFSET);
    }
    ynic_read_byte_by_pciid(kukcfg->port_pciid, &ktxsta, FPGA_TX_START_ADDR , FPGA_TX_OFFSET);
    KDBG("zc-136-pciid=%s,adapter_id=%d,func_id=%d,pf_num=%d,sta=0x%08x\n",kukcfg->port_pciid,adapter_id,func,pf_num,ktxsta);

    if (copy_to_user(ukcmd->k2u_mem, (uint8_t *)&ktxsta, ukcmd->k2u_len)) {
        ret = YNIC_ERR;
        goto kfree_ret;
    }

kfree_ret:
    if (u2k_mem) {
        kfree(u2k_mem);
    }
    return ret;
}

/*
 *
 * LIFO:0
 * LILO:1
 * FIFO:2
 * FILO:3
 */
static int yuannic_netdev_set_td_type(ynic_ukcmd_t *ukcmd)
{
    int ret = YNIC_SUC;
    ynic_uk_cfg_t *kukcfg = NULL;

    uint8_t *u2k_mem = kmalloc(ukcmd->u2k_len, GFP_KERNEL);
    if (u2k_mem == NULL) {
        ret = YNIC_ERR;
        goto kfree_ret;
    }

    if (copy_from_user(u2k_mem, ukcmd->u2k_mem, ukcmd->u2k_len)) {
        ret = YNIC_ERR;
        goto kfree_ret;
    }

    kukcfg = kmalloc(sizeof(ynic_uk_cfg_t), GFP_KERNEL);
    if(!kukcfg) {
        ret = YNIC_ERR;
        goto kfree_ret;
    }
    strscpy(kukcfg->port_pciid, ((ynic_uk_cfg_t *)u2k_mem)->port_pciid, sizeof(kukcfg->port_pciid));
    kukcfg->delay_type  = ((ynic_uk_cfg_t *)u2k_mem)->delay_type;

    KDBG("zc-131-pciid=%s,delay_type=%d\n",kukcfg->port_pciid,kukcfg->delay_type);
    switch (kukcfg->delay_type) {
        case 0:
        case 2:
            ynic_write_byte_by_pciid(kukcfg->port_pciid, 0, FPGA_RX_TD_TYPE , FPGA_RX_OFFSET);
            break;
        case 1:
        case 3:
            ynic_write_byte_by_pciid(kukcfg->port_pciid, 1, FPGA_RX_TD_TYPE , FPGA_RX_OFFSET);
            break;
        default:
            break;
    }


    //if (copy_to_user(ukcmd->k2u_mem, u2k_mem, ukcmd->u2k_len)) {
    //    ret = YNIC_ERR;
    //    goto kfree_ret;
    //}

kfree_ret:
    if (u2k_mem) {
        kfree(u2k_mem);
    }
    if(kukcfg) {
        kfree(kukcfg);
    }
    return ret;
}

/*
 *
 * LIFO:0
 * LILO:1
 * FIFO:2
 * FILO:3
 */
static int yuannic_netdev_set_tx_td_type(ynic_ukcmd_t *ukcmd)
{
    int ret = YNIC_SUC;
    ynic_uk_cfg_t *kukcfg = NULL;

    uint8_t *u2k_mem = kmalloc(ukcmd->u2k_len, GFP_KERNEL);
    if (u2k_mem == NULL) {
        ret = YNIC_ERR;
        goto kfree_ret;
    }

    if (copy_from_user(u2k_mem, ukcmd->u2k_mem, ukcmd->u2k_len)) {
        ret = YNIC_ERR;
        goto kfree_ret;
    }

    kukcfg = kmalloc(sizeof(ynic_uk_cfg_t), GFP_KERNEL);
    if(!kukcfg) {
        ret = YNIC_ERR;
        goto kfree_ret;
    }
    strscpy(kukcfg->port_pciid, ((ynic_uk_cfg_t *)u2k_mem)->port_pciid, sizeof(kukcfg->port_pciid));
    kukcfg->delay_type  = ((ynic_uk_cfg_t *)u2k_mem)->delay_type;

    KDBG("zc-137-pciid=%s,delay_type=%d\n",kukcfg->port_pciid,kukcfg->delay_type);
    switch (kukcfg->delay_type) {
        case 0:
        case 1:
            ynic_write_byte_by_pciid(kukcfg->port_pciid, 1, FPGA_TX_TD_TYPE, FPGA_TX_OFFSET);
            break;
        case 2:
        case 3:
            ynic_write_byte_by_pciid(kukcfg->port_pciid, 0, FPGA_TX_TD_TYPE, FPGA_TX_OFFSET);
            break;
        default:
            break;
    }


    //if (copy_to_user(ukcmd->k2u_mem, u2k_mem, ukcmd->u2k_len)) {
    //    ret = YNIC_ERR;
    //    goto kfree_ret;
    //}

kfree_ret:
    if (u2k_mem) {
        kfree(u2k_mem);
    }
    if(kukcfg) {
        kfree(kukcfg);
    }
    return ret;
}

static int yuannic_netdev_set_port_direct(ynic_ukcmd_t *ukcmd)
{
    int ret = YNIC_SUC;
    ynic_uk_cfg_t *kukcfg = NULL;
    u8 adapter_id;
    u8 pf_num;
    uint32_t domain,bus,dev,func;
    int i,j;

    uint8_t *u2k_mem = kmalloc(ukcmd->u2k_len, GFP_KERNEL);
    if (u2k_mem == NULL) {
        ret = YNIC_ERR;
        goto kfree_ret;
    }

    if (copy_from_user(u2k_mem, ukcmd->u2k_mem, ukcmd->u2k_len)) {
        ret = YNIC_ERR;
        goto kfree_ret;
    }

    kukcfg = kmalloc(sizeof(ynic_uk_cfg_t), GFP_KERNEL);
    if(!kukcfg) {
        ret = YNIC_ERR;
        goto kfree_ret;
    }
    strscpy(kukcfg->port_pciid, ((ynic_uk_cfg_t *)u2k_mem)->port_pciid, sizeof(kukcfg->port_pciid));
    kukcfg->direct  = ((ynic_uk_cfg_t *)u2k_mem)->direct;
    kukcfg->system_portid  = ((ynic_uk_cfg_t *)u2k_mem)->system_portid;

    pf_num = kptnm[kukcfg->system_portid].pf_num;
    adapter_id = kptnm[kukcfg->system_portid].adapter_id;

    if (sscanf(kukcfg->port_pciid, "%04x:%02x:%02x.%01x", &domain, &bus, &dev, &func) != 4) {
        printk(KERN_ERR "pci device %s Invalid.\n", kukcfg->port_pciid);
        return -EINVAL;
    }

    if(pf_num > 1) {
        ynic_write_byte_by_pciid(kukcfg->port_pciid, (adapter_id - func * 4), FPGA_TX_1to4_SEL_ADDR , FPGA_TX_OFFSET);
    }
    KDBG("zc-132-pciid=%s,adapter_id=%d,fun_id=%d,pf_num=%d,direct=%d\n",kukcfg->port_pciid, adapter_id, func, pf_num, kukcfg->direct);
    ynic_write_byte_by_pciid(kukcfg->port_pciid, kukcfg->direct, FPGA_TX_DIRECT_ADDR , FPGA_TX_OFFSET);

    //init ram
    for(i=0;i<4;i++) {
        ynic_write_byte_by_pciid(kukcfg->port_pciid, i, FPGA_TX_PKT_JUMP_INDEX, FPGA_TX_OFFSET);
        ynic_write_byte_by_pciid(kukcfg->port_pciid, 0, FPGA_TX_PKT_JUMP_ITEEM0, FPGA_TX_OFFSET);
        for(j=0;j<2048;j++) {
            ynic_write_byte_by_pciid(kukcfg->port_pciid, 0, FPGA_TX_PKT_JUMP_WRITE0, FPGA_TX_OFFSET);
        }
    }


    //if (copy_to_user(ukcmd->k2u_mem, u2k_mem, ukcmd->u2k_len)) {
    //    ret = YNIC_ERR;
    //    goto kfree_ret;
    //}

kfree_ret:
    if (u2k_mem) {
        kfree(u2k_mem);
    }
    if(kukcfg) {
        kfree(kukcfg);
    }
    return ret;
}


static int ynic_altera_400g_pfc_speed_offset(uint32_t speed, uint32_t *offset)
{
    switch (speed) {
    case MD_LINK_SPEED_50G:
        *offset = ALTERA_400G_PFC_SPEED_50G_OFFSET;
        break;
    case MD_LINK_SPEED_100G:
        *offset = ALTERA_400G_PFC_SPEED_100G_OFFSET;
        break;
    case MD_LINK_SPEED_200G:
        *offset = ALTERA_400G_PFC_SPEED_200G_OFFSET;
        break;
    case MD_LINK_SPEED_400G:
        *offset = ALTERA_400G_PFC_SPEED_400G_OFFSET;
        break;
    default:
        return -EINVAL;
    }

    return YNIC_SUC;
}

static void ynic_altera_400g_pfc_write(uint8_t port_id, uint32_t addr, uint32_t data)
{
    void __iomem *bar = kptnm[port_id].bar;
    u8 pcie_mode = kptnm[port_id].pcie_mode;

    ynic_hw_write32_mode(bar, pcie_mode, addr, ALTERA_400G_PFC_MB_ADDR_REG);
    ynic_hw_write32_mode(bar, pcie_mode, data, ALTERA_400G_PFC_MB_DATA_REG);
    ynic_hw_write32_mode(bar, pcie_mode, ALTERA_400G_PFC_MB_WRITE_REQ, ALTERA_400G_PFC_MB_CTL_REG);
}

static int ynic_altera_400g_config_pfc(uint8_t port_id, uint8_t pfc_enable, uint16_t pfc_priority)
{
    uint32_t offset = 0;
    uint32_t tx_pause_en = 0;
    uint32_t rx_pause_enable = 0;
    uint32_t txsfc_ehip_cfg = 0;
    uint32_t rx_pause_fwd = 0;
    uint32_t rxsfc_ehip_cfg = 0;
    int ret;

    if (pfc_enable) {
        tx_pause_en = (pfc_priority == 0) ? 0x000001FF : (pfc_priority & 0xFF);
        rx_pause_enable = (pfc_priority == 0) ? 0x000000FF : (pfc_priority & 0xFF);
        txsfc_ehip_cfg = 0x00000003;
        rx_pause_fwd = 0x00000001;
        rxsfc_ehip_cfg = 0x00000003;
    }

    if (port_id >= YNIC_TOTAL_PORT_NUM || !kptnm || !kptnm[port_id].bar)
        return -EINVAL;

    ret = ynic_altera_400g_pfc_speed_offset(kptnm[port_id].speed, &offset);
    if (ret)
        return ret;
    KDBG("zc-139-port_id=%d,speed=0x%08x,offset=0x%08x\n",port_id,kptnm[port_id].speed,offset);

    ynic_altera_400g_pfc_write(port_id, ALTERA_400G_PFC_RX_PAUSE_ENABLE + offset, rx_pause_enable);
    usleep_range(1000,1500);
    ynic_altera_400g_pfc_write(port_id, ALTERA_400G_PFC_TX_PAUSE_EN + offset, tx_pause_en);
    usleep_range(1000,1500);
    ynic_altera_400g_pfc_write(port_id, ALTERA_400G_PFC_TXSFC_EHIP_CFG + offset, txsfc_ehip_cfg);
    usleep_range(1000,1500);
    ynic_altera_400g_pfc_write(port_id, ALTERA_400G_PFC_RX_PAUSE_ENABLE + offset, rx_pause_enable);
    usleep_range(1000,1500);
    ynic_altera_400g_pfc_write(port_id, ALTERA_400G_PFC_RX_PAUSE_FWD + offset, rx_pause_fwd);
    usleep_range(1000,1500);
    ynic_altera_400g_pfc_write(port_id, ALTERA_400G_PFC_RXSFC_EHIP_CFG + offset, rxsfc_ehip_cfg);

    return YNIC_SUC;
}

static int ynic_xilinx_100g_config_pfc(uint8_t port_id, uint8_t cmac_port, uint8_t pfc_enable,
                                     uint16_t pfc_priority)
{
    void __iomem *bar;
    uint32_t tx_pause_enable = 0;
    uint32_t rx_pause_enable = XILINX_100G_PFC_RX_GCP_PCP_GPP_PPP;

    if (port_id >= YNIC_TOTAL_PORT_NUM || !kptnm || !kptnm[port_id].bar)
        return -EINVAL;

    if (pfc_enable) {
        if (pfc_priority == 0) {
            tx_pause_enable = XILINX_100G_PFC_PAUSE_ENABLE;
            rx_pause_enable |= XILINX_100G_PFC_PAUSE_ENABLE;
        } else {
            tx_pause_enable = pfc_priority & 0xff;
            rx_pause_enable |= pfc_priority & 0xff;
        }
    }

    bar = kptnm[port_id].bar;
    ynic_hw_write32_mode(bar, kptnm[port_id].pcie_mode, tx_pause_enable,
                        CMAC_SUBSYSTEM_OFFSET(cmac_port) + XILINX_100G_PFC_TX_CTRL);
    ynic_hw_write32_mode(bar, kptnm[port_id].pcie_mode, rx_pause_enable,
                        CMAC_SUBSYSTEM_OFFSET(cmac_port) + XILINX_100G_PFC_RX_CTRL);

    return YNIC_SUC;
}

/* Configure the legacy FPGA PFC register used by non-CMAC rates. */
static int ynic_xilinx_legacy_config_pfc(char *pciid, uint8_t pfc_enable,
                                        uint16_t pfc_priority, bool one_g_switch_only)
{
    uint32_t value;

    if (!pciid)
        return -EINVAL;
    if (!pfc_enable)
        value = 0;
    else if (one_g_switch_only)
        value = 1;
    else if (pfc_priority == 0)
        value = BIT(8);
    else
        value = pfc_priority & 0xff;
    ynic_write_byte_by_pciid(pciid, value, FPGA_PFC_STATS_REG0, 4);
    return YNIC_SUC;
}

static int yuannic_netdev_set_pfc_stats(ynic_ukcmd_t *ukcmd)
{
    int ret = YNIC_SUC;
    ynic_uk_cfg_t *kukcfg = NULL;
    uint8_t i;
    uint8_t port_id = 0;
    uint32_t domain, bus, dev, func_id;

    uint8_t *u2k_mem = kmalloc(ukcmd->u2k_len, GFP_KERNEL);
    if (u2k_mem == NULL) {
        ret = YNIC_ERR;
        goto kfree_ret;
    }

    if (copy_from_user(u2k_mem, ukcmd->u2k_mem, ukcmd->u2k_len)) {
        ret = YNIC_ERR;
        goto kfree_ret;
    }

    kukcfg = kmalloc(sizeof(ynic_uk_cfg_t), GFP_KERNEL);
    if(!kukcfg) {
        ret = YNIC_ERR;
        goto kfree_ret;
    }
    strscpy(kukcfg->port_pciid, ((ynic_uk_cfg_t *)u2k_mem)->port_pciid, sizeof(kukcfg->port_pciid));
    kukcfg->pfc_enable  = ((ynic_uk_cfg_t *)u2k_mem)->pfc_enable;
    kukcfg->pfc_priority = ((ynic_uk_cfg_t *)u2k_mem)->pfc_priority;
    if (sscanf(kukcfg->port_pciid, "%04x:%02x:%02x.%01x",
               &domain, &bus, &dev, &func_id) != 4) {
        ret = -EINVAL;
        goto kfree_ret;
    }
    (void)domain;
    (void)bus;
    (void)dev;
    printk("zc-138-pciid=%s,pfc_enable=%d,pfc_priority=0x%x,reg=0x%08x\n",kukcfg->port_pciid,kukcfg->pfc_enable,kukcfg->pfc_priority,FPGA_PFC_STATS_REG0);
    for(i=0;i<YNIC_TOTAL_PORT_NUM;i++) {
        if(strncmp(kukcfg->port_pciid, kptnm[i].port_bdf, strlen(kukcfg->port_pciid)) == 0) {
            port_id = i;
            break;
        }
    }
    if((kptnm[port_id].type >= XILINX_10G) && (kptnm[port_id].type <= ALTERA_400G)) {
        if(kptnm[port_id].type == ALTERA_400G) {
            ret = ynic_altera_400g_config_pfc(port_id, kukcfg->pfc_enable, kukcfg->pfc_priority);
            if (ret)
                goto kfree_ret;
        } else if(kptnm[port_id].type == XILINX_100G) {
            if (kptnm[port_id].speed == MD_LINK_SPEED_100G) {
                ret = ynic_xilinx_100g_config_pfc(port_id, func_id, kukcfg->pfc_enable,
                                                 kukcfg->pfc_priority);
                if (ret)
                    goto kfree_ret;
            } else {
                ret = ynic_xilinx_legacy_config_pfc(kukcfg->port_pciid,
                                                   kukcfg->pfc_enable,
                                                   kukcfg->pfc_priority, false);
                if (ret)
                    goto kfree_ret;
            }
        } else if(kptnm[port_id].type == XILINX_25G) {
            ret = ynic_xilinx_legacy_config_pfc(kukcfg->port_pciid,
                                               kukcfg->pfc_enable,
                                               kukcfg->pfc_priority,
                                               kptnm[port_id].speed == MD_LINK_SPEED_1G);
            if (ret)
                goto kfree_ret;
        } else {
            ret = ynic_xilinx_legacy_config_pfc(kukcfg->port_pciid,
                                               kukcfg->pfc_enable,
                                               kukcfg->pfc_priority, false);
            if (ret)
                goto kfree_ret;
        }
    }




    //if (copy_to_user(ukcmd->k2u_mem, u2k_mem, ukcmd->u2k_len)) {
    //    ret = YNIC_ERR;
    //    goto kfree_ret;
    //}

kfree_ret:
    if (u2k_mem) {
        kfree(u2k_mem);
    }
    if(kukcfg) {
        kfree(kukcfg);
    }
    return ret;
}

static int yuannic_netdev_reset_txrx_status(ynic_ukcmd_t *ukcmd)
{
    int ret = YNIC_SUC;
    ynic_uk_cfg_t *kukcfg = NULL;

    uint8_t *u2k_mem = kmalloc(ukcmd->u2k_len, GFP_KERNEL);
    if (u2k_mem == NULL) {
        ret = YNIC_ERR;
        goto kfree_ret;
    }

    if (copy_from_user(u2k_mem, ukcmd->u2k_mem, ukcmd->u2k_len)) {
        ret = YNIC_ERR;
        goto kfree_ret;
    }

    kukcfg = kmalloc(sizeof(ynic_uk_cfg_t), GFP_KERNEL);
    if(!kukcfg) {
        ret = YNIC_ERR;
        goto kfree_ret;
    }
    strscpy(kukcfg->port_pciid, ((ynic_uk_cfg_t *)u2k_mem)->port_pciid, sizeof(kukcfg->port_pciid));

    KDBG("zc-133-pciid=%s",kukcfg->port_pciid);
    //ynic_write_byte_by_pciid(kukcfg->port_pciid, 0, FPGA_RX_FLT_ENB , FPGA_RX_OFFSET);
    //ynic_write_byte_by_pciid(kukcfg->port_pciid, 0, FPGA_RX_WORK_MODE , FPGA_RX_OFFSET);
    //ynic_write_byte_by_pciid(kukcfg->port_pciid, 0, FPGA_RX_ENABLE_REG , FPGA_RX_OFFSET);
    //ynic_write_byte_by_pciid(kukcfg->port_pciid, 1, FPGA_RX_ENABLE_REG , FPGA_RX_OFFSET);
    //ynic_write_byte_by_pciid(kukcfg->port_pciid, 0, FPGA_RX_STREAM_ENB , FPGA_RX_OFFSET);
    //ynic_write_byte_by_pciid(kukcfg->port_pciid, 0, FPGA_RX_TEST_MODE , FPGA_RX_OFFSET);
    //ynic_write_byte_by_pciid(kukcfg->port_pciid, 0, FPGA_TX_1to4_EN_ADDR , FPGA_TX_OFFSET);


    //if (copy_to_user(ukcmd->k2u_mem, u2k_mem, ukcmd->u2k_len)) {
    //    ret = YNIC_ERR;
    //    goto kfree_ret;
    //}

kfree_ret:
    if (u2k_mem) {
        kfree(u2k_mem);
    }
    if(kukcfg) {
        kfree(kukcfg);
    }
    return ret;
}

static int yuannic_netdev_set_1g_type(ynic_ukcmd_t *ukcmd)
{
    int ret = YNIC_SUC;
    ynic_uk_cfg_t *kukcfg = NULL;
    uint8_t type = 0,speed = 0;

    uint8_t *u2k_mem = kmalloc(ukcmd->u2k_len, GFP_KERNEL);
    if (u2k_mem == NULL) {
        ret = YNIC_ERR;
        goto kfree_ret;
    }

    if (copy_from_user(u2k_mem, ukcmd->u2k_mem, ukcmd->u2k_len)) {
        ret = YNIC_ERR;
        goto kfree_ret;
    }

    kukcfg = kmalloc(sizeof(ynic_uk_cfg_t), GFP_KERNEL);
    if(!kukcfg) {
        ret = YNIC_ERR;
        goto kfree_ret;
    }
    strscpy(kukcfg->port_pciid, ((ynic_uk_cfg_t *)u2k_mem)->port_pciid, sizeof(kukcfg->port_pciid));
    kukcfg->modle_type = ((ynic_uk_cfg_t *)u2k_mem)->modle_type;
    type = (kukcfg->modle_type >> 4) & 0xf;
    speed = kukcfg->modle_type & 0xf;

    KDBG("zc-133-pciid=%s,1g-type=%d,speed=%d\n",kukcfg->port_pciid,type,speed);
    ynic_write_byte_by_pciid(kukcfg->port_pciid, type, FPGA_RX_1G_TYPE, FPGA_RX_OFFSET);
    ynic_write_byte_by_pciid(kukcfg->port_pciid, speed, FPGA_RX_1G_SPEED, FPGA_RX_OFFSET);


    //if (copy_to_user(ukcmd->k2u_mem, u2k_mem, ukcmd->u2k_len)) {
    //    ret = YNIC_ERR;
    //    goto kfree_ret;
    //}

kfree_ret:
    if (u2k_mem) {
        kfree(u2k_mem);
    }
    if(kukcfg) {
        kfree(kukcfg);
    }
    return ret;
}

static int yuannic_netdev_set_ts_base(ynic_ukcmd_t *ukcmd)
{
    int ret = YNIC_SUC;
    ynic_uk_cfg_t *kukcfg = NULL;

    uint8_t *u2k_mem = kmalloc(ukcmd->u2k_len, GFP_KERNEL);
    if (u2k_mem == NULL) {
        ret = YNIC_ERR;
        goto kfree_ret;
    }

    if (copy_from_user(u2k_mem, ukcmd->u2k_mem, ukcmd->u2k_len)) {
        ret = YNIC_ERR;
        goto kfree_ret;
    }

    kukcfg = kmalloc(sizeof(ynic_uk_cfg_t), GFP_KERNEL);
    if(!kukcfg) {
        ret = YNIC_ERR;
        goto kfree_ret;
    }
    strscpy(kukcfg->port_pciid, ((ynic_uk_cfg_t *)u2k_mem)->port_pciid, sizeof(kukcfg->port_pciid));
    kukcfg->ts_base[0] = ((ynic_uk_cfg_t *)u2k_mem)->ts_base[0];
    kukcfg->ts_base[1] = ((ynic_uk_cfg_t *)u2k_mem)->ts_base[1];
    kukcfg->ts_base[2] = ((ynic_uk_cfg_t *)u2k_mem)->ts_base[2];

    //printk("zc-134-pciid=%s,set-val[0]=%u,val[1]=%u,val[2]=%u\n",kukcfg->port_pciid, kukcfg->ts_base[0],kukcfg->ts_base[1],kukcfg->ts_base[2]);
    KDBG("zc-134-pciid=%s,set_value=%u\n",kukcfg->port_pciid, kukcfg->ts_base[0]);
    ynic_write_byte_by_pciid(kukcfg->port_pciid, kukcfg->ts_base[0], FPGA_RX_TS_BASE, FPGA_RX_OFFSET);



    //if (copy_to_user(ukcmd->k2u_mem, u2k_mem, ukcmd->u2k_len)) {
    //    ret = YNIC_ERR;
    //    goto kfree_ret;
    //}

kfree_ret:
    if (u2k_mem) {
        kfree(u2k_mem);
    }
    if(kukcfg) {
        kfree(kukcfg);
    }
    return ret;
}

static int yuannic_netdev_set_roce_ts(ynic_ukcmd_t *ukcmd)
{
    int ret = YNIC_SUC;
    char pciid[40] = {0};
    ynic_timestamps_pkt_cfg_t *ktscfg = NULL;
    //uint8_t koplen = 0;
    //uint16_t kopoff = 0,kpyloff = 0,kpylen = 0, kudplen = 0;

    uint8_t *u2k_mem = kmalloc(ukcmd->u2k_len, GFP_KERNEL);
    if (u2k_mem == NULL) {
        ret = YNIC_ERR;
        goto kfree_ret;
    }

    if (copy_from_user(u2k_mem, ukcmd->u2k_mem, ukcmd->u2k_len)) {
        ret = YNIC_ERR;
        goto kfree_ret;
    }

    ktscfg = kmalloc(sizeof(ynic_timestamps_pkt_cfg_t), GFP_KERNEL);
    if(!ktscfg) {
        ret = YNIC_ERR;
        goto kfree_ret;
    }
    strscpy(pciid, ((ynic_uk_cfg_t *)u2k_mem)->port_pciid, sizeof(pciid));
    memcpy(ktscfg, &(((ynic_uk_cfg_t *)u2k_mem)->ynic_timestamps_pkt_cfg), sizeof(ynic_timestamps_pkt_cfg_t));

    KDBG("zc-135-pciid=%s,en=0x%02x,op_len=0x%02x\n",pciid,ktscfg->timestp_en,ktscfg->opcode_len);
    ynic_write_byte_by_pciid(pciid, ktscfg->timestp_en, FPGA_TX_ROCE_EN, 4);


    //if (copy_to_user(ukcmd->k2u_mem, u2k_mem, ukcmd->u2k_len)) {
    //    ret = YNIC_ERR;
    //    goto kfree_ret;
    //}

kfree_ret:
    if (u2k_mem) {
        kfree(u2k_mem);
    }
    if(ktscfg) {
        kfree(ktscfg);
    }
    return ret;
}

static int yuannic_netdev_monitor_roce_stats(ynic_ukcmd_t *ukcmd)
{
    int ret = YNIC_SUC;
    ynic_txrx_stats_t *kstats = NULL;
    char pci_bdf[16];
    uint32_t val_high=0, val_low=0;

    uint8_t *u2k_mem = kmalloc(ukcmd->u2k_len, GFP_KERNEL);
    if (u2k_mem == NULL) {
        ret = YNIC_ERR;
        goto kfree_ret;
    }

    if (copy_from_user(u2k_mem, ukcmd->u2k_mem, ukcmd->u2k_len)) {
        ret = YNIC_ERR;
        goto kfree_ret;
    }

    kstats = kmalloc(sizeof(ynic_txrx_stats_t), GFP_KERNEL);
    if (!kstats) {
        ret = YNIC_ERR;
        goto kfree_ret;
    }
    memset(kstats, 0, sizeof(ynic_txrx_stats_t));

    strscpy(pci_bdf,((char *)u2k_mem), sizeof(pci_bdf));

    ynic_read_byte_by_pciid(pci_bdf, &val_low, FPGA_ROCE_TS_SUM_LOW_ADDR, FPGA_RX_OFFSET);
    ynic_read_byte_by_pciid(pci_bdf, &val_high, FPGA_ROCE_TS_SUM_HIGH_ADDR, FPGA_RX_OFFSET);
    kstats->roce_sum_delay = ((uint64_t)val_high << 32) | val_low;
    ynic_read_byte_by_pciid(pci_bdf, &val_low, FPGA_ROCE_TS_MAX_LOW_ADDR, FPGA_RX_OFFSET);
    ynic_read_byte_by_pciid(pci_bdf, &val_high, FPGA_ROCE_TS_MAX_HIGH_ADDR, FPGA_RX_OFFSET);
    kstats->roce_max_delay = ((uint64_t)val_high << 32) | val_low;
    ynic_read_byte_by_pciid(pci_bdf, &val_low, FPGA_ROCE_TS_MIN_LOW_ADDR, FPGA_RX_OFFSET);
    ynic_read_byte_by_pciid(pci_bdf, &val_high, FPGA_ROCE_TS_MIN_HIGH_ADDR, FPGA_RX_OFFSET);
    kstats->roce_min_delay = ((uint64_t)val_high << 32) | val_low;
    KDBG("zc-180-bdf=%s,ts~sum=%llu~min=%llu~max=%llu",
            pci_bdf,kstats->roce_sum_delay,kstats->roce_min_delay,kstats->roce_max_delay);

    ynic_read_byte_by_pciid(pci_bdf, &val_low, FPGA_ROCE_JT_SUM_LOW_ADDR, FPGA_RX_OFFSET);
    ynic_read_byte_by_pciid(pci_bdf, &val_high, FPGA_ROCE_JT_SUM_HIGH_ADDR, FPGA_RX_OFFSET);
    kstats->roce_sum_jitter = ((uint64_t)val_high << 32) | val_low;
    ynic_read_byte_by_pciid(pci_bdf, &val_low, FPGA_ROCE_JT_MAX_LOW_ADDR, FPGA_RX_OFFSET);
    ynic_read_byte_by_pciid(pci_bdf, &val_high, FPGA_ROCE_JT_MAX_HIGH_ADDR, FPGA_RX_OFFSET);
    kstats->roce_max_jitter = ((uint64_t)val_high << 32) | val_low;
    ynic_read_byte_by_pciid(pci_bdf, &val_low, FPGA_ROCE_JT_MIN_LOW_ADDR, FPGA_RX_OFFSET);
    ynic_read_byte_by_pciid(pci_bdf, &val_high, FPGA_ROCE_JT_MIN_HIGH_ADDR, FPGA_RX_OFFSET);
    kstats->roce_min_jitter = ((uint64_t)val_high << 32) | val_low;
    KDBG("zc-181-bdf=%s,jt~sum=%llu~min=%llu~max=%llu",
            pci_bdf,kstats->roce_sum_jitter,kstats->roce_min_jitter,kstats->roce_max_jitter);

    ynic_read_byte_by_pciid(pci_bdf, &val_low, FPGA_ROCE_TS_REAL_LOW_ADDR, FPGA_RX_OFFSET);
    ynic_read_byte_by_pciid(pci_bdf, &val_high, FPGA_ROCE_TS_REAL_HIGH_ADDR, FPGA_RX_OFFSET);
    kstats->roce_real_delay = ((uint64_t)val_high << 32) | val_low;
    ynic_read_byte_by_pciid(pci_bdf, &val_low, FPGA_ROCE_JT_REAL_LOW_ADDR, FPGA_RX_OFFSET);
    ynic_read_byte_by_pciid(pci_bdf, &val_high, FPGA_ROCE_JT_REAL_HIGH_ADDR, FPGA_RX_OFFSET);
    kstats->roce_real_jitter = ((uint64_t)val_high << 32) | val_low;
    ynic_read_byte_by_pciid(pci_bdf, &val_low, FPGA_ROCE_PKT_LOW_ADDR, FPGA_RX_OFFSET);
    ynic_read_byte_by_pciid(pci_bdf, &val_high, FPGA_ROCE_PKT_HIGH_ADDR, FPGA_RX_OFFSET);
    kstats->roce_pkts = ((uint64_t)val_high << 32) | val_low;
    KDBG("zc-182-bdf=%s,real_delay=%llu,real_jitter=%llu~pkts=%llu",
            pci_bdf,kstats->roce_real_delay,kstats->roce_real_jitter,kstats->roce_pkts);

    if (copy_to_user(ukcmd->k2u_mem, (uint8_t *)kstats, ukcmd->k2u_len)) {
        ret = YNIC_ERR;
        goto kfree_ret;
    }

kfree_ret:
    if (u2k_mem) {
        kfree(u2k_mem);
    }
    if(kstats) {
        kfree(kstats);
    }
    return ret;
}


static int yuannic_netdev_monitor_pfc_stats(ynic_ukcmd_t *ukcmd)
{
    int ret = YNIC_SUC;
    int priority;
    ynic_txrx_stats_t *kstats = NULL;
    char pci_bdf[16];
    uint32_t value = 0;
    uint8_t *u2k_mem = NULL;

    if (!ukcmd->u2k_len || ukcmd->k2u_len > sizeof(*kstats))
        return -EINVAL;

    u2k_mem = kmalloc(ukcmd->u2k_len, GFP_KERNEL);
    if (!u2k_mem)
        return YNIC_ERR;

    if (copy_from_user(u2k_mem, ukcmd->u2k_mem, ukcmd->u2k_len)) {
        ret = YNIC_ERR;
        goto kfree_ret;
    }

    kstats = kzalloc(sizeof(*kstats), GFP_KERNEL);
    if (!kstats) {
        ret = YNIC_ERR;
        goto kfree_ret;
    }

    strscpy(pci_bdf, (char *)u2k_mem, sizeof(pci_bdf));
    ynic_read_byte_by_pciid(pci_bdf, &value, FPGA_RX_PAUSE_START_ADDR, FPGA_RX_OFFSET);
    kstats->rx_pause_start = value;
    KDBG("zc-183-bdf=%s,pause_start=%llu", pci_bdf,kstats->rx_pause_start);
    for (priority = 0; priority < 8; priority++) {
        ynic_read_byte_by_pciid(pci_bdf, &value, FPGA_RX_PFC_START_ADDR(priority), FPGA_RX_OFFSET);
        kstats->rx_pfc_start[priority] = value;
        KDBG("zc-184-bdf=%s,pfc_start[%d]=%llu", pci_bdf, priority,kstats->rx_pfc_start[priority]);
    }
    ynic_read_byte_by_pciid(pci_bdf, &value, FPGA_RX_PAUSE_STOP_ADDR, FPGA_RX_OFFSET);
    kstats->rx_pause_stop = value;
    KDBG("zc-185-bdf=%s,pause_stop=%llu", pci_bdf,kstats->rx_pause_stop);
    for (priority = 0; priority < 8; priority++) {
        ynic_read_byte_by_pciid(pci_bdf, &value, FPGA_RX_PFC_STOP_ADDR(priority), FPGA_RX_OFFSET);
        kstats->rx_pfc_stop[priority] = value;
        KDBG("zc-186-bdf=%s,pfc_stop[%d]=%llu", pci_bdf, priority,kstats->rx_pfc_stop[priority]);
    }
    if (copy_to_user(ukcmd->k2u_mem, kstats, ukcmd->k2u_len))
        ret = YNIC_ERR;

kfree_ret:
    kfree(kstats);
    kfree(u2k_mem);
    return ret;
}

static int yuannic_netdev_clear_roce_stats(ynic_ukcmd_t *ukcmd)
{
    int ret = YNIC_SUC;
    char pci_bdf[16];

    uint8_t *u2k_mem = kmalloc(ukcmd->u2k_len, GFP_KERNEL);
    if (u2k_mem == NULL) {
        ret = YNIC_ERR;
        goto kfree_ret;
    }

    if (copy_from_user(u2k_mem, ukcmd->u2k_mem, ukcmd->u2k_len)) {
        ret = YNIC_ERR;
        goto kfree_ret;
    }

    strscpy(pci_bdf, ((char *)u2k_mem), sizeof(pci_bdf));

    ynic_write_byte_by_pciid(pci_bdf, (0 | 0x10000), FPGA_RX_STA_CLEAR, FPGA_RX_OFFSET);

    //if (copy_to_user(ukcmd->k2u_mem, u2k_mem, ukcmd->u2k_len)) {
    //    ret = YNIC_ERR;
    //    goto kfree_ret;
    //}

kfree_ret:
    if (u2k_mem) {
        kfree(u2k_mem);
    }
    return ret;
}

static int
yuannic_netdev_set_rx_filter(ynic_ukcmd_t *ukcmd)
{
    int ret = YNIC_SUC;
    int fi, ci;
    md_filter_info_t *kfilter_info = NULL;
    md_filter_cfg_t *f = NULL;
    md_match_condition_t *c = NULL;
    char port_pciid[40];

    uint8_t kflt_id = 0;
    uint8_t kflt_num = 0;
    uint32_t kflt_valid = 0;
    uint8_t kaction = 0;
    uint8_t krelation = 0;
    uint8_t kflt_type = 0;
    uint8_t kflt_rule = 0;

    uint32_t tmp_vals = 0;
    uint128_t tmp_vall = 0;
    uint32_t tmp_msks = 0;
    uint128_t tmp_mskl = 0;
    uint32_t tmp_val[4] = {0};
    uint32_t tmp_msk[4] = {0};

    uint8_t *u2k_mem = kmalloc(ukcmd->u2k_len, GFP_KERNEL);
    if (u2k_mem == NULL) {
        ret = YNIC_ERR;
        goto kfree_ret;
    }

    if (copy_from_user(u2k_mem, ukcmd->u2k_mem, ukcmd->u2k_len)) {
        ret = YNIC_ERR;
        goto kfree_ret;
    }

    kfilter_info = kmalloc(sizeof(md_filter_info_t), GFP_KERNEL);
    if (!kfilter_info) {
        ret = YNIC_ERR;
        goto kfree_ret;
    }
    memcpy(kfilter_info, u2k_mem, sizeof(md_filter_info_t));
    strscpy(port_pciid, kfilter_info->port_pciid, sizeof(port_pciid));

    printk(KERN_INFO "set_rx_filter: pciid=%s, filter_count=%d\n", port_pciid, kfilter_info->filter_count);

    #ifdef FPGA_CONTROL_RX_STREAM
    ynic_write_byte_by_pciid(port_pciid, 1, FPGA_RX_FLT_ENB, FPGA_RX_OFFSET);
    #endif

    for (fi = 0; fi < kfilter_info->filter_count && fi < MAX_FILTERS; fi++) {
        f = &kfilter_info->filters[fi];
        kflt_id  = (uint8_t)f->filter_id;
        kaction  = f->action;
        krelation = f->relation;
        kflt_num++;
        kflt_valid = GENMASK((kflt_num - 1), 0);

        printk(KERN_INFO "  filter[%d]: id=%d name=%s action=%d relation=%d framsize=%u cond_count=%d\n",
               fi, f->filter_id, f->filter_name, f->action, f->relation, f->framsize, f->condition_count);

        for (ci = 0; ci < f->condition_count && ci < MAX_CONDITIONS; ci++) {
            c = &f->conditions[ci];
            if (!c->filed_enable)
                continue;

            kflt_type = c->field_type;
            kflt_rule = c->rule;

            tmp_vals = 0; tmp_vall = 0;
            tmp_msks = 0; tmp_mskl = 0;
            memset(tmp_val, 0, sizeof(tmp_val));
            memset(tmp_msk, 0, sizeof(tmp_msk));

            switch (kflt_type) {
            case FILTER_SRC_MAC:
                memcpy(&tmp_vall, c->s_mac, 6);
                tmp_mskl = 0xffffffffffff;
                printk(KERN_INFO "    cond[%d]: SrcMac rule=%d mac=%02x:%02x:%02x:%02x:%02x:%02x\n",
                       ci, kflt_rule,
                       c->s_mac[0], c->s_mac[1], c->s_mac[2],
                       c->s_mac[3], c->s_mac[4], c->s_mac[5]);
                break;
            case FILTER_DST_MAC:
                memcpy(&tmp_vall, c->d_mac, 6);
                tmp_mskl = 0xffffffffffff;
                printk(KERN_INFO "    cond[%d]: DstMac rule=%d mac=%02x:%02x:%02x:%02x:%02x:%02x\n",
                       ci, kflt_rule,
                       c->d_mac[0], c->d_mac[1], c->d_mac[2],
                       c->d_mac[3], c->d_mac[4], c->d_mac[5]);
                break;
            case FILTER_VLAN:
                tmp_vals = c->vlan_id;
                tmp_msks = 0xffff;
                printk(KERN_INFO "    cond[%d]: VLAN rule=%d vlan_id=%u\n",
                       ci, kflt_rule, c->vlan_id);
                break;
            case FILTER_SRC_IPV4:
                tmp_vall = c->src_ip4;
                tmp_mskl = 0xffffffff;
                printk(KERN_INFO "    cond[%d]: SrcIpv4 rule=%d ip=0x%08x\n",
                       ci, kflt_rule, c->src_ip4);
                break;
            case FILTER_DST_IPV4:
                tmp_vall = c->dst_ip4;
                tmp_mskl = 0xffffffff;
                printk(KERN_INFO "    cond[%d]: DstIpv4 rule=%d ip=0x%08x\n",
                       ci, kflt_rule, c->dst_ip4);
                break;
            case FILTER_SRC_IPV6:
                memcpy(&tmp_vall, c->src_ip6, 16);
                memset(&tmp_mskl, 0xff, sizeof(tmp_mskl));
                printk(KERN_INFO "    cond[%d]: SrcIpv6 rule=%d ip=%02x%02x:%02x%02x:%02x%02x:%02x%02x:"
                       "%02x%02x:%02x%02x:%02x%02x:%02x%02x\n",
                       ci, kflt_rule,
                       c->src_ip6[0],  c->src_ip6[1],  c->src_ip6[2],  c->src_ip6[3],
                       c->src_ip6[4],  c->src_ip6[5],  c->src_ip6[6],  c->src_ip6[7],
                       c->src_ip6[8],  c->src_ip6[9],  c->src_ip6[10], c->src_ip6[11],
                       c->src_ip6[12], c->src_ip6[13], c->src_ip6[14], c->src_ip6[15]);
                break;
            case FILTER_DST_IPV6:
                memcpy(&tmp_vall, c->dst_ip6, 16);
                memset(&tmp_mskl, 0xff, sizeof(tmp_mskl));
                printk(KERN_INFO "    cond[%d]: DstIpv6 rule=%d ip=%02x%02x:%02x%02x:%02x%02x:%02x%02x:"
                       "%02x%02x:%02x%02x:%02x%02x:%02x%02x\n",
                       ci, kflt_rule,
                       c->dst_ip6[0],  c->dst_ip6[1],  c->dst_ip6[2],  c->dst_ip6[3],
                       c->dst_ip6[4],  c->dst_ip6[5],  c->dst_ip6[6],  c->dst_ip6[7],
                       c->dst_ip6[8],  c->dst_ip6[9],  c->dst_ip6[10], c->dst_ip6[11],
                       c->dst_ip6[12], c->dst_ip6[13], c->dst_ip6[14], c->dst_ip6[15]);
                break;
            case FILTER_PROTOCOL_TYPE:
                tmp_vals = c->protocol;
                tmp_msks = 0xff;
                printk(KERN_INFO "    cond[%d]: Protocol rule=%d proto=%u\n",
                       ci, kflt_rule, c->protocol);
                break;
            case FILTER_SRC_PORT:
                tmp_vals = c->src_port;
                tmp_msks = 0xffff;
                printk(KERN_INFO "    cond[%d]: SrcPort rule=%d port=%u\n",
                       ci, kflt_rule, c->src_port);
                break;
            case FILTER_DST_PORT:
                tmp_vals = c->dst_port;
                tmp_msks = 0xffff;
                printk(KERN_INFO "    cond[%d]: DstPort rule=%d port=%u\n",
                       ci, kflt_rule, c->dst_port);
                break;
            case FILTER_FRAM_SIZE:
                tmp_vals = c->frame_size_min;
                tmp_msks = 0xffff;
                printk(KERN_INFO "    cond[%d]: FrameSize rule=%d min=%u max=%u\n",
                       ci, kflt_rule, c->frame_size_min, c->frame_size_max);
                break;
            default:
                continue;
            }

            #ifdef FPGA_CONTROL_RX_STREAM
            ynic_write_byte_by_pciid(port_pciid, (kflt_id - 1), FPGA_RX_FLT_BASE, FPGA_RX_OFFSET);
            ynic_write_byte_by_pciid(port_pciid, kflt_valid, FPGA_RX_FLT_ENB_BIT, FPGA_RX_OFFSET);
            ynic_write_byte_by_pciid(port_pciid, !kaction, FPGA_RX_FLT_ACTION, FPGA_RX_OFFSET);
            ynic_write_byte_by_pciid(port_pciid, krelation, FPGA_RX_FLT_RELATION, FPGA_RX_OFFSET);

            switch (kflt_type) {
            case FILTER_SRC_MAC:
                tmp_val[0] = (cpu_to_be64(tmp_vall & 0xffffffffffffffff) >> 16) & 0xffffffff;
                tmp_val[1] = (cpu_to_be64(tmp_vall & 0xffffffffffffffff) >> 48) & 0xffff;
                tmp_msk[0] = (cpu_to_be64(tmp_mskl & 0xffffffffffffffff) >> 16) & 0xffffffff;
                tmp_msk[1] = (cpu_to_be64(tmp_mskl & 0xffffffffffffffff) >> 48) & 0xffff;
                ynic_write_byte_by_pciid(port_pciid, 1,          FPGA_RX_FLT_SMAC_EN,   FPGA_RX_OFFSET);
                ynic_write_byte_by_pciid(port_pciid, kflt_rule,  FPGA_RX_FLT_SMAC_MODE, FPGA_RX_OFFSET);
                ynic_write_byte_by_pciid(port_pciid, tmp_msk[0], FPGA_RX_FLT_SMAC_MSK0, FPGA_RX_OFFSET);
                ynic_write_byte_by_pciid(port_pciid, tmp_msk[1], FPGA_RX_FLT_SMAC_MSK1, FPGA_RX_OFFSET);
                ynic_write_byte_by_pciid(port_pciid, tmp_val[0], FPGA_RX_FLT_SMAC_VAL0, FPGA_RX_OFFSET);
                ynic_write_byte_by_pciid(port_pciid, tmp_val[1], FPGA_RX_FLT_SMAC_VAL1, FPGA_RX_OFFSET);
                break;
            case FILTER_DST_MAC:
                tmp_val[0] = (cpu_to_be64(tmp_vall & 0xffffffffffffffff) >> 16) & 0xffffffff;
                tmp_val[1] = (cpu_to_be64(tmp_vall & 0xffffffffffffffff) >> 48) & 0xffff;
                tmp_msk[0] = (cpu_to_be64(tmp_mskl & 0xffffffffffffffff) >> 16) & 0xffffffff;
                tmp_msk[1] = (cpu_to_be64(tmp_mskl & 0xffffffffffffffff) >> 48) & 0xffff;
                ynic_write_byte_by_pciid(port_pciid, 1,          FPGA_RX_FLT_DMAC_EN,   FPGA_RX_OFFSET);
                ynic_write_byte_by_pciid(port_pciid, kflt_rule,  FPGA_RX_FLT_DMAC_MODE, FPGA_RX_OFFSET);
                ynic_write_byte_by_pciid(port_pciid, tmp_msk[0], FPGA_RX_FLT_DMAC_MSK0, FPGA_RX_OFFSET);
                ynic_write_byte_by_pciid(port_pciid, tmp_msk[1], FPGA_RX_FLT_DMAC_MSK1, FPGA_RX_OFFSET);
                ynic_write_byte_by_pciid(port_pciid, tmp_val[0], FPGA_RX_FLT_DMAC_VAL0, FPGA_RX_OFFSET);
                ynic_write_byte_by_pciid(port_pciid, tmp_val[1], FPGA_RX_FLT_DMAC_VAL1, FPGA_RX_OFFSET);
                break;
            case FILTER_SRC_IPV6:
                tmp_val[0] = tmp_vall & 0xffffffff;
                tmp_val[1] = (tmp_vall >> 32) & 0xffffffff;
                tmp_val[2] = (tmp_vall >> 64) & 0xffffffff;
                tmp_val[3] = (tmp_vall >> 96) & 0xffffffff;
                tmp_msk[0] = tmp_mskl & 0xffffffff;
                tmp_msk[1] = (tmp_mskl >> 32) & 0xffffffff;
                tmp_msk[2] = (tmp_mskl >> 64) & 0xffffffff;
                tmp_msk[3] = (tmp_mskl >> 96) & 0xffffffff;
                ynic_write_byte_by_pciid(port_pciid, 1,          FPGA_RX_FLT_SIPV6_EN,   FPGA_RX_OFFSET);
                ynic_write_byte_by_pciid(port_pciid, kflt_rule,  FPGA_RX_FLT_SIPV6_MODE, FPGA_RX_OFFSET);
                ynic_write_byte_by_pciid(port_pciid, tmp_msk[0], FPGA_RX_FLT_SIPV6_MSK0, FPGA_RX_OFFSET);
                ynic_write_byte_by_pciid(port_pciid, tmp_msk[1], FPGA_RX_FLT_SIPV6_MSK1, FPGA_RX_OFFSET);
                ynic_write_byte_by_pciid(port_pciid, tmp_msk[2], FPGA_RX_FLT_SIPV6_MSK2, FPGA_RX_OFFSET);
                ynic_write_byte_by_pciid(port_pciid, tmp_msk[3], FPGA_RX_FLT_SIPV6_MSK3, FPGA_RX_OFFSET);
                ynic_write_byte_by_pciid(port_pciid, tmp_val[0], FPGA_RX_FLT_SIPV6_VAL0, FPGA_RX_OFFSET);
                ynic_write_byte_by_pciid(port_pciid, tmp_val[1], FPGA_RX_FLT_SIPV6_VAL1, FPGA_RX_OFFSET);
                ynic_write_byte_by_pciid(port_pciid, tmp_val[2], FPGA_RX_FLT_SIPV6_VAL2, FPGA_RX_OFFSET);
                ynic_write_byte_by_pciid(port_pciid, tmp_val[3], FPGA_RX_FLT_SIPV6_VAL3, FPGA_RX_OFFSET);
                break;
            case FILTER_DST_IPV6:
                tmp_val[0] = tmp_vall & 0xffffffff;
                tmp_val[1] = (tmp_vall >> 32) & 0xffffffff;
                tmp_val[2] = (tmp_vall >> 64) & 0xffffffff;
                tmp_val[3] = (tmp_vall >> 96) & 0xffffffff;
                tmp_msk[0] = tmp_mskl & 0xffffffff;
                tmp_msk[1] = (tmp_mskl >> 32) & 0xffffffff;
                tmp_msk[2] = (tmp_mskl >> 64) & 0xffffffff;
                tmp_msk[3] = (tmp_mskl >> 96) & 0xffffffff;
                ynic_write_byte_by_pciid(port_pciid, 1,          FPGA_RX_FLT_DIPV6_EN,   FPGA_RX_OFFSET);
                ynic_write_byte_by_pciid(port_pciid, kflt_rule,  FPGA_RX_FLT_DIPV6_MODE, FPGA_RX_OFFSET);
                ynic_write_byte_by_pciid(port_pciid, tmp_msk[0], FPGA_RX_FLT_DIPV6_MSK0, FPGA_RX_OFFSET);
                ynic_write_byte_by_pciid(port_pciid, tmp_msk[1], FPGA_RX_FLT_DIPV6_MSK1, FPGA_RX_OFFSET);
                ynic_write_byte_by_pciid(port_pciid, tmp_msk[2], FPGA_RX_FLT_DIPV6_MSK2, FPGA_RX_OFFSET);
                ynic_write_byte_by_pciid(port_pciid, tmp_msk[3], FPGA_RX_FLT_DIPV6_MSK3, FPGA_RX_OFFSET);
                ynic_write_byte_by_pciid(port_pciid, tmp_val[0], FPGA_RX_FLT_DIPV6_VAL0, FPGA_RX_OFFSET);
                ynic_write_byte_by_pciid(port_pciid, tmp_val[1], FPGA_RX_FLT_DIPV6_VAL1, FPGA_RX_OFFSET);
                ynic_write_byte_by_pciid(port_pciid, tmp_val[2], FPGA_RX_FLT_DIPV6_VAL2, FPGA_RX_OFFSET);
                ynic_write_byte_by_pciid(port_pciid, tmp_val[3], FPGA_RX_FLT_DIPV6_VAL3, FPGA_RX_OFFSET);
                break;
            case FILTER_VLAN:
                tmp_val[0] = cpu_to_be32(tmp_vals & 0xffffffff);
                tmp_msk[0] = cpu_to_be32(tmp_msks & 0xffffffff);
                ynic_write_byte_by_pciid(port_pciid, 1,          FPGA_RX_FLT_VLAN_EN,   FPGA_RX_OFFSET);
                ynic_write_byte_by_pciid(port_pciid, kflt_rule,  FPGA_RX_FLT_VLAN_MODE, FPGA_RX_OFFSET);
                ynic_write_byte_by_pciid(port_pciid, tmp_msk[0], FPGA_RX_FLT_VLAN_MSK,  FPGA_RX_OFFSET);
                ynic_write_byte_by_pciid(port_pciid, tmp_val[0], FPGA_RX_FLT_VLAN_VAL,  FPGA_RX_OFFSET);
                break;
            case FILTER_SRC_IPV4:
                tmp_val[0] = cpu_to_be32(tmp_vall & 0xffffffff);
                tmp_msk[0] = cpu_to_be32(tmp_mskl & 0xffffffff);
                ynic_write_byte_by_pciid(port_pciid, 1,          FPGA_RX_FLT_SIPV4_EN,   FPGA_RX_OFFSET);
                ynic_write_byte_by_pciid(port_pciid, kflt_rule,  FPGA_RX_FLT_SIPV4_MODE, FPGA_RX_OFFSET);
                ynic_write_byte_by_pciid(port_pciid, tmp_msk[0], FPGA_RX_FLT_SIPV4_MSK,  FPGA_RX_OFFSET);
                ynic_write_byte_by_pciid(port_pciid, tmp_val[0], FPGA_RX_FLT_SIPV4_VAL,  FPGA_RX_OFFSET);
                break;
            case FILTER_DST_IPV4:
                tmp_val[0] = cpu_to_be32(tmp_vall & 0xffffffff);
                tmp_msk[0] = cpu_to_be32(tmp_mskl & 0xffffffff);
                ynic_write_byte_by_pciid(port_pciid, 1,          FPGA_RX_FLT_DIPV4_EN,   FPGA_RX_OFFSET);
                ynic_write_byte_by_pciid(port_pciid, kflt_rule,  FPGA_RX_FLT_DIPV4_MODE, FPGA_RX_OFFSET);
                ynic_write_byte_by_pciid(port_pciid, tmp_msk[0], FPGA_RX_FLT_DIPV4_MSK,  FPGA_RX_OFFSET);
                ynic_write_byte_by_pciid(port_pciid, tmp_val[0], FPGA_RX_FLT_DIPV4_VAL,  FPGA_RX_OFFSET);
                break;
            case FILTER_PROTOCOL_TYPE:
                tmp_val[0] = tmp_vals & 0xffffffff;
                tmp_msk[0] = tmp_msks & 0xffffffff;
                ynic_write_byte_by_pciid(port_pciid, 1,          FPGA_RX_FLT_PROTO_EN,   FPGA_RX_OFFSET);
                ynic_write_byte_by_pciid(port_pciid, kflt_rule,  FPGA_RX_FLT_PROTO_MODE, FPGA_RX_OFFSET);
                ynic_write_byte_by_pciid(port_pciid, tmp_msk[0], FPGA_RX_FLT_PROTO_MSK,  FPGA_RX_OFFSET);
                ynic_write_byte_by_pciid(port_pciid, tmp_val[0], FPGA_RX_FLT_PROTO_VAL,  FPGA_RX_OFFSET);
                break;
            case FILTER_SRC_PORT:
                tmp_val[0] = cpu_to_be16(tmp_vals & 0xffff);
                tmp_msk[0] = cpu_to_be16(tmp_msks & 0xffff);
                ynic_write_byte_by_pciid(port_pciid, 1,          FPGA_RX_FLT_SPORT_EN,   FPGA_RX_OFFSET);
                ynic_write_byte_by_pciid(port_pciid, kflt_rule,  FPGA_RX_FLT_SPORT_MODE, FPGA_RX_OFFSET);
                ynic_write_byte_by_pciid(port_pciid, tmp_msk[0], FPGA_RX_FLT_SPORT_MSK,  FPGA_RX_OFFSET);
                ynic_write_byte_by_pciid(port_pciid, tmp_val[0], FPGA_RX_FLT_SPORT_VAL,  FPGA_RX_OFFSET);
                break;
            case FILTER_DST_PORT:
                tmp_val[0] = cpu_to_be16(tmp_vals & 0xffff);
                tmp_msk[0] = cpu_to_be16(tmp_msks & 0xffff);
                ynic_write_byte_by_pciid(port_pciid, 1,          FPGA_RX_FLT_DPORT_EN,   FPGA_RX_OFFSET);
                ynic_write_byte_by_pciid(port_pciid, kflt_rule,  FPGA_RX_FLT_DPORT_MODE, FPGA_RX_OFFSET);
                ynic_write_byte_by_pciid(port_pciid, tmp_msk[0], FPGA_RX_FLT_DPORT_MSK,  FPGA_RX_OFFSET);
                ynic_write_byte_by_pciid(port_pciid, tmp_val[0], FPGA_RX_FLT_DPORT_VAL,  FPGA_RX_OFFSET);
                break;
            case FILTER_FRAM_SIZE:
                tmp_val[0] = cpu_to_be32(tmp_vals & 0xffffffff);
                tmp_msk[0] = cpu_to_be32(tmp_msks & 0xffffffff);
                ynic_write_byte_by_pciid(port_pciid, 1,          FPGA_RX_FLT_LEN_EN,   FPGA_RX_OFFSET);
                ynic_write_byte_by_pciid(port_pciid, kflt_rule,  FPGA_RX_FLT_LEN_MODE, FPGA_RX_OFFSET);
                ynic_write_byte_by_pciid(port_pciid, tmp_msk[0], FPGA_RX_FLT_LEN_MSK,  FPGA_RX_OFFSET);
                ynic_write_byte_by_pciid(port_pciid, tmp_val[0], FPGA_RX_FLT_LEN_VAL,  FPGA_RX_OFFSET);
                break;
            default:
                break;
            }
            #endif
        }
    }

kfree_ret:
    if (u2k_mem)
        kfree(u2k_mem);
    if (kfilter_info)
        kfree(kfilter_info);
    return ret;
}

static int
yuannic_netdev_clear_rx_filter(ynic_ukcmd_t *ukcmd)
{
    int ret = YNIC_SUC;
    int filter_id;
    md_filter_info_t *kfilter_info = NULL;
    char port_pciid[40];

    uint8_t *u2k_mem = kmalloc(ukcmd->u2k_len, GFP_KERNEL);
    if (u2k_mem == NULL) {
        ret = YNIC_ERR;
        goto kfree_ret;
    }

    if (copy_from_user(u2k_mem, ukcmd->u2k_mem, ukcmd->u2k_len)) {
        ret = YNIC_ERR;
        goto kfree_ret;
    }

    kfilter_info = kmalloc(sizeof(md_filter_info_t), GFP_KERNEL);
    if (!kfilter_info) {
        ret = YNIC_ERR;
        goto kfree_ret;
    }
    memcpy(kfilter_info, u2k_mem, sizeof(md_filter_info_t));
    strscpy(port_pciid, kfilter_info->port_pciid, sizeof(port_pciid));

    printk(KERN_INFO "clear_rx_filter: pciid=%s\n", port_pciid);

    #ifdef FPGA_CONTROL_RX_STREAM
    for (filter_id = 0; filter_id < FPGA_RX_FILTER_COUNT; filter_id++) {
        ynic_write_byte_by_pciid(port_pciid, filter_id, FPGA_RX_FLT_BASE, FPGA_RX_OFFSET);
        ynic_write_byte_by_pciid(port_pciid, 0, FPGA_RX_FLT_ACTION, FPGA_RX_OFFSET);
        ynic_write_byte_by_pciid(port_pciid, 0, FPGA_RX_FLT_RELATION, FPGA_RX_OFFSET);
        ynic_write_byte_by_pciid(port_pciid, 0, FPGA_RX_FLT_DMAC_EN, FPGA_RX_OFFSET);
        ynic_write_byte_by_pciid(port_pciid, 0, FPGA_RX_FLT_DMAC_MODE, FPGA_RX_OFFSET);
        ynic_write_byte_by_pciid(port_pciid, 0, FPGA_RX_FLT_DMAC_MSK0, FPGA_RX_OFFSET);
        ynic_write_byte_by_pciid(port_pciid, 0, FPGA_RX_FLT_DMAC_MSK1, FPGA_RX_OFFSET);
        ynic_write_byte_by_pciid(port_pciid, 0, FPGA_RX_FLT_DMAC_VAL0, FPGA_RX_OFFSET);
        ynic_write_byte_by_pciid(port_pciid, 0, FPGA_RX_FLT_DMAC_VAL1, FPGA_RX_OFFSET);
        ynic_write_byte_by_pciid(port_pciid, 0, FPGA_RX_FLT_SMAC_EN, FPGA_RX_OFFSET);
        ynic_write_byte_by_pciid(port_pciid, 0, FPGA_RX_FLT_SMAC_MODE, FPGA_RX_OFFSET);
        ynic_write_byte_by_pciid(port_pciid, 0, FPGA_RX_FLT_SMAC_MSK0, FPGA_RX_OFFSET);
        ynic_write_byte_by_pciid(port_pciid, 0, FPGA_RX_FLT_SMAC_MSK1, FPGA_RX_OFFSET);
        ynic_write_byte_by_pciid(port_pciid, 0, FPGA_RX_FLT_SMAC_VAL0, FPGA_RX_OFFSET);
        ynic_write_byte_by_pciid(port_pciid, 0, FPGA_RX_FLT_SMAC_VAL1, FPGA_RX_OFFSET);
        ynic_write_byte_by_pciid(port_pciid, 0, FPGA_RX_FLT_VLAN_EN, FPGA_RX_OFFSET);
        ynic_write_byte_by_pciid(port_pciid, 0, FPGA_RX_FLT_VLAN_MODE, FPGA_RX_OFFSET);
        ynic_write_byte_by_pciid(port_pciid, 0, FPGA_RX_FLT_VLAN_MSK, FPGA_RX_OFFSET);
        ynic_write_byte_by_pciid(port_pciid, 0, FPGA_RX_FLT_VLAN_VAL, FPGA_RX_OFFSET);
        ynic_write_byte_by_pciid(port_pciid, 0, FPGA_RX_FLT_PROTO_EN, FPGA_RX_OFFSET);
        ynic_write_byte_by_pciid(port_pciid, 0, FPGA_RX_FLT_PROTO_MODE, FPGA_RX_OFFSET);
        ynic_write_byte_by_pciid(port_pciid, 0, FPGA_RX_FLT_PROTO_MSK, FPGA_RX_OFFSET);
        ynic_write_byte_by_pciid(port_pciid, 0, FPGA_RX_FLT_PROTO_VAL, FPGA_RX_OFFSET);
        ynic_write_byte_by_pciid(port_pciid, 0, FPGA_RX_FLT_SIPV4_EN, FPGA_RX_OFFSET);
        ynic_write_byte_by_pciid(port_pciid, 0, FPGA_RX_FLT_SIPV4_MODE, FPGA_RX_OFFSET);
        ynic_write_byte_by_pciid(port_pciid, 0, FPGA_RX_FLT_SIPV4_MSK, FPGA_RX_OFFSET);
        ynic_write_byte_by_pciid(port_pciid, 0, FPGA_RX_FLT_SIPV4_VAL, FPGA_RX_OFFSET);
        ynic_write_byte_by_pciid(port_pciid, 0, FPGA_RX_FLT_DIPV4_EN, FPGA_RX_OFFSET);
        ynic_write_byte_by_pciid(port_pciid, 0, FPGA_RX_FLT_DIPV4_MODE, FPGA_RX_OFFSET);
        ynic_write_byte_by_pciid(port_pciid, 0, FPGA_RX_FLT_DIPV4_MSK, FPGA_RX_OFFSET);
        ynic_write_byte_by_pciid(port_pciid, 0, FPGA_RX_FLT_DIPV4_VAL, FPGA_RX_OFFSET);
        ynic_write_byte_by_pciid(port_pciid, 0, FPGA_RX_FLT_SIPV6_EN, FPGA_RX_OFFSET);
        ynic_write_byte_by_pciid(port_pciid, 0, FPGA_RX_FLT_SIPV6_MODE, FPGA_RX_OFFSET);
        ynic_write_byte_by_pciid(port_pciid, 0, FPGA_RX_FLT_SIPV6_MSK0, FPGA_RX_OFFSET);
        ynic_write_byte_by_pciid(port_pciid, 0, FPGA_RX_FLT_SIPV6_MSK1, FPGA_RX_OFFSET);
        ynic_write_byte_by_pciid(port_pciid, 0, FPGA_RX_FLT_SIPV6_MSK2, FPGA_RX_OFFSET);
        ynic_write_byte_by_pciid(port_pciid, 0, FPGA_RX_FLT_SIPV6_MSK3, FPGA_RX_OFFSET);
        ynic_write_byte_by_pciid(port_pciid, 0, FPGA_RX_FLT_SIPV6_VAL0, FPGA_RX_OFFSET);
        ynic_write_byte_by_pciid(port_pciid, 0, FPGA_RX_FLT_SIPV6_VAL1, FPGA_RX_OFFSET);
        ynic_write_byte_by_pciid(port_pciid, 0, FPGA_RX_FLT_SIPV6_VAL2, FPGA_RX_OFFSET);
        ynic_write_byte_by_pciid(port_pciid, 0, FPGA_RX_FLT_SIPV6_VAL3, FPGA_RX_OFFSET);
        ynic_write_byte_by_pciid(port_pciid, 0, FPGA_RX_FLT_DIPV6_EN, FPGA_RX_OFFSET);
        ynic_write_byte_by_pciid(port_pciid, 0, FPGA_RX_FLT_DIPV6_MODE, FPGA_RX_OFFSET);
        ynic_write_byte_by_pciid(port_pciid, 0, FPGA_RX_FLT_DIPV6_MSK0, FPGA_RX_OFFSET);
        ynic_write_byte_by_pciid(port_pciid, 0, FPGA_RX_FLT_DIPV6_MSK1, FPGA_RX_OFFSET);
        ynic_write_byte_by_pciid(port_pciid, 0, FPGA_RX_FLT_DIPV6_MSK2, FPGA_RX_OFFSET);
        ynic_write_byte_by_pciid(port_pciid, 0, FPGA_RX_FLT_DIPV6_MSK3, FPGA_RX_OFFSET);
        ynic_write_byte_by_pciid(port_pciid, 0, FPGA_RX_FLT_DIPV6_VAL0, FPGA_RX_OFFSET);
        ynic_write_byte_by_pciid(port_pciid, 0, FPGA_RX_FLT_DIPV6_VAL1, FPGA_RX_OFFSET);
        ynic_write_byte_by_pciid(port_pciid, 0, FPGA_RX_FLT_DIPV6_VAL2, FPGA_RX_OFFSET);
        ynic_write_byte_by_pciid(port_pciid, 0, FPGA_RX_FLT_DIPV6_VAL3, FPGA_RX_OFFSET);
        ynic_write_byte_by_pciid(port_pciid, 0, FPGA_RX_FLT_SPORT_EN, FPGA_RX_OFFSET);
        ynic_write_byte_by_pciid(port_pciid, 0, FPGA_RX_FLT_SPORT_MODE, FPGA_RX_OFFSET);
        ynic_write_byte_by_pciid(port_pciid, 0, FPGA_RX_FLT_SPORT_MSK, FPGA_RX_OFFSET);
        ynic_write_byte_by_pciid(port_pciid, 0, FPGA_RX_FLT_SPORT_VAL, FPGA_RX_OFFSET);
        ynic_write_byte_by_pciid(port_pciid, 0, FPGA_RX_FLT_DPORT_EN, FPGA_RX_OFFSET);
        ynic_write_byte_by_pciid(port_pciid, 0, FPGA_RX_FLT_DPORT_MODE, FPGA_RX_OFFSET);
        ynic_write_byte_by_pciid(port_pciid, 0, FPGA_RX_FLT_DPORT_MSK, FPGA_RX_OFFSET);
        ynic_write_byte_by_pciid(port_pciid, 0, FPGA_RX_FLT_DPORT_VAL, FPGA_RX_OFFSET);
        ynic_write_byte_by_pciid(port_pciid, 0, FPGA_RX_FLT_LEN_EN, FPGA_RX_OFFSET);
        ynic_write_byte_by_pciid(port_pciid, 0, FPGA_RX_FLT_LEN_MODE, FPGA_RX_OFFSET);
        ynic_write_byte_by_pciid(port_pciid, 0, FPGA_RX_FLT_LEN_MSK, FPGA_RX_OFFSET);
        ynic_write_byte_by_pciid(port_pciid, 0, FPGA_RX_FLT_LEN_VAL, FPGA_RX_OFFSET);
    }
    ynic_write_byte_by_pciid(port_pciid, 0, FPGA_RX_FLT_BASE, FPGA_RX_OFFSET);
    ynic_write_byte_by_pciid(port_pciid, 0, FPGA_RX_FLT_ENB_BIT, FPGA_RX_OFFSET);
    #endif

kfree_ret:
    if (u2k_mem)
        kfree(u2k_mem);
    if (kfilter_info)
        kfree(kfilter_info);
    return ret;
}

static inline int yuannic_netdev_clear_ukrx_filter(ynic_ukcmd_t *ukcmd)
{
    int ret = YNIC_SUC;
    int filter_id;
    ynic_uk_cfg_t *kukcfg = NULL;

    uint8_t *u2k_mem = kmalloc(ukcmd->u2k_len, GFP_KERNEL);
    if (u2k_mem == NULL) {
        ret = YNIC_ERR;
        goto kfree_ret;
    }

    if (copy_from_user(u2k_mem, ukcmd->u2k_mem, ukcmd->u2k_len)) {
        ret = YNIC_ERR;
        goto kfree_ret;
    }

    kukcfg = kmalloc(sizeof(ynic_uk_cfg_t), GFP_KERNEL);
    if (!kukcfg) {
        ret = YNIC_ERR;
        goto kfree_ret;
    }
    strscpy(kukcfg->port_pciid, ((ynic_uk_cfg_t *)u2k_mem)->port_pciid, sizeof(kukcfg->port_pciid));

    printk(KERN_INFO "clear_ukrx_filter: pciid=%s\n", kukcfg->port_pciid);

    #ifdef FPGA_CONTROL_RX_STREAM
    for (filter_id = 0; filter_id < FPGA_RX_FILTER_COUNT; filter_id++) {
        ynic_write_byte_by_pciid(kukcfg->port_pciid, filter_id, FPGA_RX_FLT_BASE, FPGA_RX_OFFSET);
        ynic_write_byte_by_pciid(kukcfg->port_pciid, 0, FPGA_RX_FLT_ACTION, FPGA_RX_OFFSET);
        ynic_write_byte_by_pciid(kukcfg->port_pciid, 0, FPGA_RX_FLT_RELATION, FPGA_RX_OFFSET);
        ynic_write_byte_by_pciid(kukcfg->port_pciid, 0, FPGA_RX_FLT_DMAC_EN, FPGA_RX_OFFSET);
        ynic_write_byte_by_pciid(kukcfg->port_pciid, 0, FPGA_RX_FLT_DMAC_MODE, FPGA_RX_OFFSET);
        ynic_write_byte_by_pciid(kukcfg->port_pciid, 0, FPGA_RX_FLT_DMAC_MSK0, FPGA_RX_OFFSET);
        ynic_write_byte_by_pciid(kukcfg->port_pciid, 0, FPGA_RX_FLT_DMAC_MSK1, FPGA_RX_OFFSET);
        ynic_write_byte_by_pciid(kukcfg->port_pciid, 0, FPGA_RX_FLT_DMAC_VAL0, FPGA_RX_OFFSET);
        ynic_write_byte_by_pciid(kukcfg->port_pciid, 0, FPGA_RX_FLT_DMAC_VAL1, FPGA_RX_OFFSET);
        ynic_write_byte_by_pciid(kukcfg->port_pciid, 0, FPGA_RX_FLT_SMAC_EN, FPGA_RX_OFFSET);
        ynic_write_byte_by_pciid(kukcfg->port_pciid, 0, FPGA_RX_FLT_SMAC_MODE, FPGA_RX_OFFSET);
        ynic_write_byte_by_pciid(kukcfg->port_pciid, 0, FPGA_RX_FLT_SMAC_MSK0, FPGA_RX_OFFSET);
        ynic_write_byte_by_pciid(kukcfg->port_pciid, 0, FPGA_RX_FLT_SMAC_MSK1, FPGA_RX_OFFSET);
        ynic_write_byte_by_pciid(kukcfg->port_pciid, 0, FPGA_RX_FLT_SMAC_VAL0, FPGA_RX_OFFSET);
        ynic_write_byte_by_pciid(kukcfg->port_pciid, 0, FPGA_RX_FLT_SMAC_VAL1, FPGA_RX_OFFSET);
        ynic_write_byte_by_pciid(kukcfg->port_pciid, 0, FPGA_RX_FLT_VLAN_EN, FPGA_RX_OFFSET);
        ynic_write_byte_by_pciid(kukcfg->port_pciid, 0, FPGA_RX_FLT_VLAN_MODE, FPGA_RX_OFFSET);
        ynic_write_byte_by_pciid(kukcfg->port_pciid, 0, FPGA_RX_FLT_VLAN_MSK, FPGA_RX_OFFSET);
        ynic_write_byte_by_pciid(kukcfg->port_pciid, 0, FPGA_RX_FLT_VLAN_VAL, FPGA_RX_OFFSET);
        ynic_write_byte_by_pciid(kukcfg->port_pciid, 0, FPGA_RX_FLT_PROTO_EN, FPGA_RX_OFFSET);
        ynic_write_byte_by_pciid(kukcfg->port_pciid, 0, FPGA_RX_FLT_PROTO_MODE, FPGA_RX_OFFSET);
        ynic_write_byte_by_pciid(kukcfg->port_pciid, 0, FPGA_RX_FLT_PROTO_MSK, FPGA_RX_OFFSET);
        ynic_write_byte_by_pciid(kukcfg->port_pciid, 0, FPGA_RX_FLT_PROTO_VAL, FPGA_RX_OFFSET);
        ynic_write_byte_by_pciid(kukcfg->port_pciid, 0, FPGA_RX_FLT_SIPV4_EN, FPGA_RX_OFFSET);
        ynic_write_byte_by_pciid(kukcfg->port_pciid, 0, FPGA_RX_FLT_SIPV4_MODE, FPGA_RX_OFFSET);
        ynic_write_byte_by_pciid(kukcfg->port_pciid, 0, FPGA_RX_FLT_SIPV4_MSK, FPGA_RX_OFFSET);
        ynic_write_byte_by_pciid(kukcfg->port_pciid, 0, FPGA_RX_FLT_SIPV4_VAL, FPGA_RX_OFFSET);
        ynic_write_byte_by_pciid(kukcfg->port_pciid, 0, FPGA_RX_FLT_DIPV4_EN, FPGA_RX_OFFSET);
        ynic_write_byte_by_pciid(kukcfg->port_pciid, 0, FPGA_RX_FLT_DIPV4_MODE, FPGA_RX_OFFSET);
        ynic_write_byte_by_pciid(kukcfg->port_pciid, 0, FPGA_RX_FLT_DIPV4_MSK, FPGA_RX_OFFSET);
        ynic_write_byte_by_pciid(kukcfg->port_pciid, 0, FPGA_RX_FLT_DIPV4_VAL, FPGA_RX_OFFSET);
        ynic_write_byte_by_pciid(kukcfg->port_pciid, 0, FPGA_RX_FLT_SIPV6_EN, FPGA_RX_OFFSET);
        ynic_write_byte_by_pciid(kukcfg->port_pciid, 0, FPGA_RX_FLT_SIPV6_MODE, FPGA_RX_OFFSET);
        ynic_write_byte_by_pciid(kukcfg->port_pciid, 0, FPGA_RX_FLT_SIPV6_MSK0, FPGA_RX_OFFSET);
        ynic_write_byte_by_pciid(kukcfg->port_pciid, 0, FPGA_RX_FLT_SIPV6_MSK1, FPGA_RX_OFFSET);
        ynic_write_byte_by_pciid(kukcfg->port_pciid, 0, FPGA_RX_FLT_SIPV6_MSK2, FPGA_RX_OFFSET);
        ynic_write_byte_by_pciid(kukcfg->port_pciid, 0, FPGA_RX_FLT_SIPV6_MSK3, FPGA_RX_OFFSET);
        ynic_write_byte_by_pciid(kukcfg->port_pciid, 0, FPGA_RX_FLT_SIPV6_VAL0, FPGA_RX_OFFSET);
        ynic_write_byte_by_pciid(kukcfg->port_pciid, 0, FPGA_RX_FLT_SIPV6_VAL1, FPGA_RX_OFFSET);
        ynic_write_byte_by_pciid(kukcfg->port_pciid, 0, FPGA_RX_FLT_SIPV6_VAL2, FPGA_RX_OFFSET);
        ynic_write_byte_by_pciid(kukcfg->port_pciid, 0, FPGA_RX_FLT_SIPV6_VAL3, FPGA_RX_OFFSET);
        ynic_write_byte_by_pciid(kukcfg->port_pciid, 0, FPGA_RX_FLT_DIPV6_EN, FPGA_RX_OFFSET);
        ynic_write_byte_by_pciid(kukcfg->port_pciid, 0, FPGA_RX_FLT_DIPV6_MODE, FPGA_RX_OFFSET);
        ynic_write_byte_by_pciid(kukcfg->port_pciid, 0, FPGA_RX_FLT_DIPV6_MSK0, FPGA_RX_OFFSET);
        ynic_write_byte_by_pciid(kukcfg->port_pciid, 0, FPGA_RX_FLT_DIPV6_MSK1, FPGA_RX_OFFSET);
        ynic_write_byte_by_pciid(kukcfg->port_pciid, 0, FPGA_RX_FLT_DIPV6_MSK2, FPGA_RX_OFFSET);
        ynic_write_byte_by_pciid(kukcfg->port_pciid, 0, FPGA_RX_FLT_DIPV6_MSK3, FPGA_RX_OFFSET);
        ynic_write_byte_by_pciid(kukcfg->port_pciid, 0, FPGA_RX_FLT_DIPV6_VAL0, FPGA_RX_OFFSET);
        ynic_write_byte_by_pciid(kukcfg->port_pciid, 0, FPGA_RX_FLT_DIPV6_VAL1, FPGA_RX_OFFSET);
        ynic_write_byte_by_pciid(kukcfg->port_pciid, 0, FPGA_RX_FLT_DIPV6_VAL2, FPGA_RX_OFFSET);
        ynic_write_byte_by_pciid(kukcfg->port_pciid, 0, FPGA_RX_FLT_DIPV6_VAL3, FPGA_RX_OFFSET);
        ynic_write_byte_by_pciid(kukcfg->port_pciid, 0, FPGA_RX_FLT_SPORT_EN, FPGA_RX_OFFSET);
        ynic_write_byte_by_pciid(kukcfg->port_pciid, 0, FPGA_RX_FLT_SPORT_MODE, FPGA_RX_OFFSET);
        ynic_write_byte_by_pciid(kukcfg->port_pciid, 0, FPGA_RX_FLT_SPORT_MSK, FPGA_RX_OFFSET);
        ynic_write_byte_by_pciid(kukcfg->port_pciid, 0, FPGA_RX_FLT_SPORT_VAL, FPGA_RX_OFFSET);
        ynic_write_byte_by_pciid(kukcfg->port_pciid, 0, FPGA_RX_FLT_DPORT_EN, FPGA_RX_OFFSET);
        ynic_write_byte_by_pciid(kukcfg->port_pciid, 0, FPGA_RX_FLT_DPORT_MODE, FPGA_RX_OFFSET);
        ynic_write_byte_by_pciid(kukcfg->port_pciid, 0, FPGA_RX_FLT_DPORT_MSK, FPGA_RX_OFFSET);
        ynic_write_byte_by_pciid(kukcfg->port_pciid, 0, FPGA_RX_FLT_DPORT_VAL, FPGA_RX_OFFSET);
        ynic_write_byte_by_pciid(kukcfg->port_pciid, 0, FPGA_RX_FLT_LEN_EN, FPGA_RX_OFFSET);
        ynic_write_byte_by_pciid(kukcfg->port_pciid, 0, FPGA_RX_FLT_LEN_MODE, FPGA_RX_OFFSET);
        ynic_write_byte_by_pciid(kukcfg->port_pciid, 0, FPGA_RX_FLT_LEN_MSK, FPGA_RX_OFFSET);
        ynic_write_byte_by_pciid(kukcfg->port_pciid, 0, FPGA_RX_FLT_LEN_VAL, FPGA_RX_OFFSET);
    }
    ynic_write_byte_by_pciid(kukcfg->port_pciid, 0, FPGA_RX_FLT_BASE, FPGA_RX_OFFSET);
    ynic_write_byte_by_pciid(kukcfg->port_pciid, 0, FPGA_RX_FLT_ENB_BIT, FPGA_RX_OFFSET);
    #endif

kfree_ret:
    if (u2k_mem) {
        kfree(u2k_mem);
    }
    if (kukcfg) {
        kfree(kukcfg);
    }
    return ret;
}

static int ynic_ioctl_handler(struct file *file, unsigned int cmd, void __user *argp)
{
    int ret = 0;
    ynic_ukcmd_t ukcmd;
    uint32_t kpdf;
    uint32_t kfec;
    uint32_t kflag;

    memset(&ukcmd, 0, sizeof(ynic_ukcmd_t));

    YNIC_LOG(YNIC_DBG_IOCTL, "ioctl cmd=0x%x arg=%px\n", cmd, argp);

    if (cmd == YNIC_DEV_IOCTL_REQ) {
        if (copy_from_user(&ukcmd, argp, sizeof(ynic_ukcmd_t))) {
            printk("Copy ukcmd by ioctl from user space failed\n");
            return -EFAULT;
        }
        YNIC_LOG(YNIC_DBG_IOCTL, "  ukcmd.cmd=%u u2k_len=%u k2u_len=%u\n",
                ukcmd.cmd, ukcmd.u2k_len, ukcmd.k2u_len);
    } else if(cmd == IOCTL_SET_NET_ID) {
        if (copy_from_user(&kpdf, argp, sizeof(uint32_t))) {
            printk("Copy net by ioctl from user space failed\n");
            return -EFAULT;
        }
        KDBG("net pdf=%x\n",kpdf);
        ret = nfc_get_sys_pcidev(kpdf);
        if(ret) {
            return -EFAULT;
        }
        goto suc_exit;
    } else if(cmd == IOCTL_SET_NET_INFO) {

        ret = nfc_get_sys_hw_info(NET_VENDOR_ID, argp);
        if(ret) {
            return -EFAULT;
        }
        goto suc_exit;
    } else if(cmd == IOCTL_SET_CLOCK) {

        ret = nfc_card_sync_clocks();
        if(ret) {
            return -EFAULT;
        }
        goto suc_exit;
    } else if(cmd == IOCTL_SET_FEC) {

        if (copy_from_user(&kfec, argp, sizeof(uint32_t))) {
            printk("Copy net by ioctl from user space failed\n");
            return -EFAULT;
        }
        ret = nfc_card_set_fec(kfec);
        if(ret) {
            return -EFAULT;
        }
        goto suc_exit;
    } else if(cmd == IOCTL_SET_UP) {

        if (copy_from_user(&kflag, argp, sizeof(uint32_t))) {
            printk("Copy net by ioctl from user space failed\n");
            return -EFAULT;
        }
        ret = nfc_card_set_up(kflag);
        if(ret) {
            return -EFAULT;
        }
        goto suc_exit;
    } else {
        printk("%s get a invalid command %d, should be %d\n",
            YNIC_SYS_NET_NAME, cmd, YNIC_DEV_IOCTL_REQ);
        return -EINVAL;
    }

    switch (ukcmd.cmd) {

        /**< 初始化 YuanGrid FPGA 网卡 */
        case U2K_INIT_NET_DEV:
            KDBG("cmd: U2K_INIT_NET_DEV\n");
            break;

        /**< 用户态->内核态，获取系统中的网卡和网口信息 */
        case U2K_GET_DEV_INFO:
            KDBG("cmd: U2K_GET_DEV_INFO\n");
            if (ynic_get_net_dev_info(&ukcmd)) {
                return -EFAULT;
            }
            break;

        case U2K_OPEN_TX_STREAM:
            KDBG("cmd: U2K_OPEN_TX_STREAM\n");
            if (yuannic_netdev_open_tx_stream(&ukcmd)) {
                return -EFAULT;
            }
            break;

        /**< 设置或更新发送流的配置信息 */
        case U2K_SET_TX_STREAM_CFG:
            KDBG("cmd: U2K_SET_TX_STREAM_CFG\n");
            if (yuannic_netdev_set_tx_stream_cfg(&ukcmd)) {
                return -EFAULT;
            }
            break;

        case U2K_START_TX_STREAM:
            KDBG("cmd: U2K_START_TX_STREAM\n");
            if (yuannic_netdev_start_tx_stream(&ukcmd)) {
                return -EFAULT;
            }
            break;

        case U2K_STOP_TX_STREAM:
            KDBG("cmd: U2K_STOP_TX_STREAM\n");
            if (yuannic_netdev_stop_tx_stream(&ukcmd)) {
                return -EFAULT;
            }
            break;

        case U2K_CLOSE_TX_STREAM:
            KDBG("cmd: U2K_CLOSE_TX_STREAM\n");
            if (yuannic_netdev_close_tx_stream(&ukcmd)) {
                return -EFAULT;
            }
            break;

        case U2K_GET_TX_STREAM_STATS:
            KDBG("cmd: U2K_GET_TX_STREAM_STATS\n");
            if (yuannic_netdev_monitor_tx_stream(&ukcmd)) {
                return -EFAULT;
            }
            break;

        case U2K_OPEN_RX_STREAM:
            KDBG("cmd: U2K_OPEN_RX_STREAM\n");
            if (yuannic_netdev_open_rx_stream(&ukcmd)) {
                return -EFAULT;
            }
            break;

        case U2K_SET_RX_STREAM_CFG:
            KDBG("cmd: U2K_SET_RX_STREAM_CFG\n");
            if (yuannic_netdev_set_rx_stream_cfg(&ukcmd)) {
                return -EFAULT;
            }
            break;

        case U2K_CLOSE_RX_STREAM:
            KDBG("cmd: U2K_CLOSE_RX_STREAM\n");
            if (yuannic_netdev_close_rx_stream(&ukcmd)) {
                return -EFAULT;
            }
            break;

        case U2K_START_RX_STREAM:
            KDBG("cmd: U2K_START_RX_STREAM\n");
            if (yuannic_netdev_start_rx_stream(&ukcmd)) {
                return -EFAULT;
            }
            break;

        case U2K_STOP_RX_STREAM:
            KDBG("cmd: U2K_STOP_RX_STREAM\n");
            if (yuannic_netdev_stop_rx_stream(&ukcmd)) {
                return -EFAULT;
            }
            break;

        case U2K_GET_RX_STREAM_STATS:
            KDBG("cmd: U2K_GET_RX_STREAM_STATS\n");
            if (yuannic_netdev_monitor_rx_stream(&ukcmd)) {
                return -EFAULT;
            }
            break;

        case U2K_CLEAR_TX_STREAM: //tx统计信息清0
            KDBG("cmd: U2K_CLEAR_TX_STREAM\n");
            if (yuannic_netdev_clear_tx_stream(&ukcmd)) {
                return -EFAULT;
            }
            break;

        case U2K_CLEAR_RX_STREAM: //rx统计信息清0
            KDBG("cmd: U2K_CLEAR_RX_STREAM\n");
            if (yuannic_netdev_clear_rx_stream(&ukcmd)) {
                return -EFAULT;
            }
            break;

        case U2K_ENABLE_PROMISC_DEV: //enable 混杂模式
            KDBG("cmd: U2K_PORMISC_MODE_ENB\n");
            if (yuannic_netdev_promisc_rx_stream(&ukcmd)) {
                return -EFAULT;
            }
            break;

        case U2K_GET_TXRX_DEBUG_STATS:
            KDBG("cmd: U2K_GET_TXRX_DEBUG_STATS\n");
            if (yuannic_netdev_monitor_txrx_stats(&ukcmd)) {
                return -EFAULT;
            }
            break;

        case U2K_CLEAR_TXRX_DEBUG_STATS:
            KDBG("cmd: U2K_CLEAR_TXRX_DEBUG_STATS\n");
            if (yuannic_netdev_clear_txrx_stats(&ukcmd)) {
                return -EFAULT;
            }
            break;

        case U2K_SET_RX_QUEUE_ID:
            KDBG("cmd: U2K_SET_RX_QUEUE_ID\n");
            #if 0
            if (yuannic_netdev_set_rx_qid(&ukcmd)) {
                return -EFAULT;
            }
            #endif
            break;

        case U2K_SET_RX_WORK_MODE:
            KDBG("cmd: U2K_SET_RX_WORK_MODE\n");
            #if 0
            if (yuannic_netdev_set_work_mode(&ukcmd)) {
                return -EFAULT;
            }
            #endif
            break;

        case U2K_GET_TX_SEND_STATUS:
            KDBG("cmd: U2K_GET_TX_SEND_STATUS\n");
            if (yuannic_netdev_get_send_status(&ukcmd)) {
                return -EFAULT;
            }
            break;

        case U2K_SET_RX_TD_TYPE:
            KDBG("cmd: U2K_SET_RX_TD_TYPE\n");
            if (yuannic_netdev_set_td_type(&ukcmd)) {
                return -EFAULT;
            }
            break;

        case U2K_SET_TX_TD_TYPE:
            KDBG("cmd: U2K_SET_TX_TD_TYPE\n");
            if (yuannic_netdev_set_tx_td_type(&ukcmd)) {
                return -EFAULT;
            }
            break;

        case U2K_SET_PORT_DIRECT:
            KDBG("cmd: U2K_SET_PORT_DIRECT\n");
            if (yuannic_netdev_set_port_direct(&ukcmd)) {
                return -EFAULT;
            }
            break;

        case U2K_SET_PFC_STATS:
            KDBG("cmd: U2K_SET_PFC_STATS\n");
            if (yuannic_netdev_set_pfc_stats(&ukcmd)) {
                return -EFAULT;
            }
            break;

        case U2K_RESET_TXRX_STATUS:
            KDBG("cmd: U2K_RESET_TXRX_STATUS\n");
            if (yuannic_netdev_reset_txrx_status(&ukcmd)) {
                return -EFAULT;
            }
            break;

        case U2K_SET_1G_IFTYPE:
            KDBG("cmd: U2K_SET_1G_IFTYPE\n");
            if (yuannic_netdev_set_1g_type(&ukcmd)) {
                return -EFAULT;
            }
            break;

        case U2K_SET_RX_TS_BASE:
            KDBG("cmd: U2K_SET_RX_TS_BASE\n");
            if (yuannic_netdev_set_ts_base(&ukcmd)) {
                return -EFAULT;
            }
            break;

        case U2K_GET_TX_MULSTREAMS_STATS:
            KDBG("cmd: U2K_GET_TX_MULSTREAMS_STATS\n");
            if (yuannic_netdev_monitor_tx_mul_streams(&ukcmd)) {
                return -EFAULT;
            }
            break;

        case U2K_GET_RX_MULSTREAMS_STATS:
            KDBG("cmd: U2K_GET_RX_MULSTREAMS_STATS\n");
            if (yuannic_netdev_monitor_rx_mul_streams(&ukcmd)) {
                return -EFAULT;
            }
            break;

        case U2K_SET_TX_PKT_TIMESTAMP:
            KDBG("cmd: U2K_SET_TX_PKT_TIMESTAMP\n");
            if (yuannic_netdev_set_roce_ts(&ukcmd)) {
                return -EFAULT;
            }
            break;

        case U2K_GET_RX_ROCE_STATS:
            KDBG("cmd: U2K_GET_RX_ROCE_STATS\n");
            if (yuannic_netdev_monitor_roce_stats(&ukcmd)) {
                return -EFAULT;
            }
            break;

        case U2K_GET_RX_PFC_STATS:
            KDBG("cmd: U2K_GET_RX_PFC_STATS\n");
            if (yuannic_netdev_monitor_pfc_stats(&ukcmd)) {
                return -EFAULT;
            }
            break;

        case U2K_CLEAR_RX_ROCE_STATS:
            KDBG("cmd: U2K_CLEAR_RX_ROCE_STATS\n");
            if (yuannic_netdev_clear_roce_stats(&ukcmd)) {
                return -EFAULT;
            }
            break;

        case U2K_SET_RX_FILTER:
            KDBG("cmd: U2K_SET_RX_FILTER\n");
            if (yuannic_netdev_set_rx_filter(&ukcmd)) {
                return -EFAULT;
            }
            break;

        case U2K_CLEAR_RX_FILTER:
            KDBG("cmd: U2K_CLEAR_RX_FILTER\n");
            if (yuannic_netdev_clear_rx_filter(&ukcmd)) {
                return -EFAULT;
            }
            break;

#if 0
        case U2K_CLEAR_UKRX_FILTER:
            KDBG("cmd: U2K_CLEAR_UKRX_FILTER\n");
            if (yuannic_netdev_clear_ukrx_filter(&ukcmd)) {
                return -EFAULT;
            }
            break;
#endif

        default:
            KDBG("cmd para error!\n");
            break;


    }
suc_exit:

    YNIC_LOG(YNIC_DBG_IOCTL, "ioctl done cmd=0x%x ret=%d\n", cmd, ret);
    return ret;
}

#if LINUX_VERSION_CODE >= KERNEL_VERSION(2, 6, 36)
static long ynic_ioctl(struct file *file, unsigned int cmd, unsigned long arg)
#else
static int ynic_ioctl(struct inode *inode, struct file *file, unsigned int cmd, unsigned long arg)
#endif
{
    return ynic_ioctl_handler(file, cmd, (void __user *)arg);
}

#ifdef CONFIG_COMPAT
#if (LINUX_VERSION_CODE < KERNEL_VERSION(2, 6, 11))
static int ynic_compat_ioctl(unsigned int fd, unsigned int cmd,
                                                     unsigned long arg, struct file *file)
#else
static long ynic_compat_ioctl(struct file *file,
                                                        unsigned int cmd, unsigned long arg)
#endif
{
    return ynic_ioctl_handler(file, cmd, compat_ptr(arg));
}
#endif

static unsigned int ynic_poll(struct file *file, poll_table *wait)
{
    struct nt_net_struct *ntnet = (struct nt_net_struct *)file->private_data;
    unsigned int mask = 0;

    if (!ntnet)
    {
        return -EBADFD;
    }

    rtnl_lock();
    poll_wait(file, &ntnet->read_wait, wait);
    if (ntnet->rx_data)
    {
        mask = POLLIN | POLLRDNORM;
        ntnet->rx_data = 0;
    }
    rtnl_unlock();

    return mask;
}

/* maps the PCIe BAR into user space for memory-like access using mmap() */
static int ynic_bridge_mmap(struct file *file, struct vm_area_struct *vma)
{
    struct pci_dev *dev = NULL;
    unsigned long off;
    unsigned long phys;
    unsigned long vsize;
    unsigned long psize;
    int rv;


    //dev = pci_get_device(0x1172, 0x0000, NULL);
    if(net_pci_dev) {
        dev = net_pci_dev;
    } else {
        printk(KERN_ERR "Network Card not exist!!!\n");
        return -ENODEV;
    }

    off = vma->vm_pgoff << PAGE_SHIFT;
    /* BAR physical address */
    phys = pci_resource_start(dev, 2) + off;
    vsize = vma->vm_end - vma->vm_start;
    /* complete resource */
    psize = pci_resource_end(dev, 2) - pci_resource_start(dev, 2) + 1 - off;

    // printk("mmap(): priv = 0x%08lx\n", (unsigned long)priv);
    // printk("mmap(): cdev->bar = %d\n", 2);
    // printk("mmap(): pci_dev = 0x%08lx\n", (unsigned long)dev);

    // printk("off = 0x%lx\n", off);
    // printk("start = 0x%llx\n", (unsigned long long)pci_resource_start(dev, 2));
    // printk("phys = 0x%lx\n", phys);

    YNIC_LOG(YNIC_DBG_LIFE, "mmap BAR2 off=0x%lx phys=0x%lx vsize=0x%lx\n", off, phys, vsize);

    if (vsize > psize)
        return -EINVAL;
    /*
     * pages must not be cached as this would result in cache line sized
     * accesses to the end point
     */
    vma->vm_page_prot = pgprot_noncached(vma->vm_page_prot);
    /*
     * prevent touching the pages (byte access) for swap-in,
     * and prevent the pages from being swapped out
     */
    //vma->vm_flags |= VMEM_FLAGS;
    /* make MMIO accessible to user space */
    rv = io_remap_pfn_range(vma, vma->vm_start, phys >> PAGE_SHIFT,
            vsize, vma->vm_page_prot);
    // printk("vma=0x%p, vma->vm_start=0x%lx, phys=0x%lx, size=%lu = %d\n", vma, vma->vm_start, phys >> PAGE_SHIFT, vsize, rv);

    if (rv)
        return -EAGAIN;
    return 0;
}

static struct file_operations nt_fops =
{
    .owner = THIS_MODULE,
    .open = ynic_open,
    .release = ynic_close,
    .poll = ynic_poll,
#if LINUX_VERSION_CODE >= KERNEL_VERSION(2, 6, 36)
    .unlocked_ioctl = ynic_ioctl,
#else
    .ioctl = ynic_ioctl,
#endif
#ifdef CONFIG_COMPAT
    .compat_ioctl = ynic_compat_ioctl,
#endif
    .mmap = ynic_bridge_mmap,
};

static int ynic_init_hardware(void)
{
    int ret = YNIC_SUC;
    struct pci_dev *dev = NULL;
    int domain = 0;
    int num = 0;
    int prev_domain = -1;
    int prev_num = -1;
    int port = 0;   //每个网卡的网口号
    int sysid = 0; //系统id号,不重复
    void __iomem *bar = NULL;
    u8 pcie_mode = YNIC_PCIE4_MODE;
    int func_id;
    uint16_t kmulpt = 0;
    uint32_t kspd = 0;
    uint32_t kmodel = 0;
    uint32_t mspeed = 0;
    const struct pci_device_id *id;

    for(id = md_card_id_table; id->vendor != 0; id++) {
        // 使用 pci_get_device 遍历所有设备
        dev = pci_get_device(id->vendor, PCI_ANY_ID, NULL);
        while (dev) {
            domain = pci_domain_nr(dev->bus);
            num = dev->bus->number; //设备总线号
            if(prev_domain != domain || prev_num != num) {
                prev_domain = domain;
                prev_num = num;
                port = 0; //每个网卡port从0开始
            }

            {
                u16 cmd = 0xffff, psts = 0xffff;
                pci_read_config_word(dev, PCI_COMMAND, &cmd);
                pci_read_config_word(dev, PCI_STATUS, &psts);
                YNIC_LOG(YNIC_DBG_LIFE,
                        "HWINIT probing %04x:%02x:%02x.%x vendor=%04x device=%04x rev=%02x "
                        "bar2 phys=0x%llx len=0x%llx cmd=0x%04x status=0x%04x\n",
                        pci_domain_nr(dev->bus), dev->bus->number,
                        PCI_SLOT(dev->devfn), PCI_FUNC(dev->devfn),
                        dev->vendor, dev->device, dev->revision,
                        (unsigned long long)pci_resource_start(dev, 2),
                        (unsigned long long)pci_resource_len(dev, 2),
                        cmd, psts);
            }

            /*
             * 在 ioremap 之前先确认端点配置空间可读。
             * 卡在冷断电后的某个不固定时刻会自行掉链路（UESta SDES+），
             * 此时 pci_read_config_dword 返回全 1；若此时继续 ioremap 然后
             * 读 BAR，ioread32 会返回 0xffffffff，kmulpt 读成 65535，
             * 导致 -EINVAL 被 init_ntmodule 包成 -EFAULT（insmod: Bad address）。
             * 在这里提前判断，给出可读的错误信息。
             */
            {
                u32 cfg_check = 0xffffffffU;
                pci_read_config_dword(dev, PCI_VENDOR_ID, &cfg_check);
                if (cfg_check == 0xffffffffU) {
                    YNIC_ERRL(YNIC_DBG_LIFE,
                             "HWINIT ABORT %04x:%02x:%02x.%x: config space reads 0xffffffff "
                             "— device is off-bus (Surprise Down?). Skipping BAR map.\n",
                             pci_domain_nr(dev->bus), dev->bus->number,
                             PCI_SLOT(dev->devfn), PCI_FUNC(dev->devfn));
                    pr_err("yuannic: %04x:%02x:%02x.%x is off-bus (cfg=0xffffffff), insmod aborted\n",
                           pci_domain_nr(dev->bus), dev->bus->number,
                           PCI_SLOT(dev->devfn), PCI_FUNC(dev->devfn));
                    return -ENODEV;
                }
            }

            bar = pci_ioremap_bar(dev, 2);
            if (!bar) {
                YNIC_ERRL(YNIC_DBG_LIFE, "Failed to map BAR2 for %04x:%02x:%02x.%x\n",
                         pci_domain_nr(dev->bus), dev->bus->number,
                         PCI_SLOT(dev->devfn), PCI_FUNC(dev->devfn));
                pr_err("Failed to map BAR\n");
                return -ENOMEM;
            }
            YNIC_LOG(YNIC_DBG_LIFE, "BAR2 mapped at %px\n", bar);
            pcie_mode = ynic_detect_pcie_mode(bar);
            ynic_watch_add(dev, bar);

            //网卡的网口处理
            func_id = PCI_FUNC(dev->devfn);
            if(id->vendor == ALTERA_VENDOR_ID) {
                kmulpt = ynic_hw_read32_mode(bar, pcie_mode, FPGA_PORT_PF0_NUM_REG + (func_id * 4) + FPGA_SYS_BASE_ALTERA); //每个pf分出几个port
                kspd = ynic_hw_read32_mode(bar, pcie_mode, FPGA_PORT_SPEED_REG + FPGA_SYS_BASE_ALTERA);
                kmodel = ynic_hw_read32_mode(bar, pcie_mode, FPGA_MODEL_REG + FPGA_SYS_BASE_ALTERA);
            } else {
                kmulpt = ynic_hw_read32_mode(bar, pcie_mode, FPGA_PORT_PF0_NUM_REG + (func_id * 4)); //每个pf分出几个port
                kspd = ynic_hw_read32_mode(bar, pcie_mode, FPGA_PORT_SPEED_REG);
                kmodel = ynic_hw_read32_mode(bar, pcie_mode, FPGA_MODEL_REG);
            }

            if (kmulpt == 0 || kmulpt > MAX_PORT_PER_ADP) {
                pr_err("Invalid kmulpt=%u for %04x:%02x:%02x.%01x\n",
                       kmulpt, pci_domain_nr(dev->bus), dev->bus->number,
                       PCI_SLOT(dev->devfn), PCI_FUNC(dev->devfn));
                iounmap(bar);
                return -EINVAL;
            }

            if (sysid >= YNIC_TOTAL_PORT_NUM) {
                pr_err("System port index overflow before PF init: sysid=%d max=%d for %04x:%02x:%02x.%01x\n",
                       sysid, YNIC_TOTAL_PORT_NUM, pci_domain_nr(dev->bus), dev->bus->number,
                       PCI_SLOT(dev->devfn), PCI_FUNC(dev->devfn));
                iounmap(bar);
                return -EINVAL;
            }

            mspeed = (kmodel >> 12) & 0xf;
            snprintf(kptnm[sysid].port_bdf, sizeof(kptnm[sysid].port_bdf),
                    "%04x:%02x:%02x.%01x", pci_domain_nr(dev->bus), dev->bus->number, PCI_SLOT(dev->devfn), PCI_FUNC(dev->devfn));
            kptnm[sysid].adapter_id = port;
            kptnm[sysid].pf_num = kmulpt;
            kptnm[sysid].pcie_mode = pcie_mode;
            kptnm[sysid].port_id = sysid;
            kptnm[sysid].bar = bar;
            kptnm[sysid].speed = kspd;
            if(mspeed == 0) {
                kptnm[sysid].type = XILINX_10G;
            } else if(mspeed == 1) {
                kptnm[sysid].type = XILINX_25G;
            } else if(mspeed == 3) {
                kptnm[sysid].type = XILINX_100G;
            } else if(mspeed == 4) {
                kptnm[sysid].type = ALTERA_400G;
            }

            port++;
            sysid++;

            if(kmulpt > 1) {
                for(int i=1;i<kmulpt;i++) {
                    if (sysid >= YNIC_TOTAL_PORT_NUM) {
                        pr_err("System port index overflow during PF expansion: sysid=%d max=%d for %04x:%02x:%02x.%01x\n",
                               sysid, YNIC_TOTAL_PORT_NUM, pci_domain_nr(dev->bus), dev->bus->number,
                               PCI_SLOT(dev->devfn), PCI_FUNC(dev->devfn));
                        iounmap(bar);
                        return -EINVAL;
                    }
                    snprintf(kptnm[sysid].port_bdf, sizeof(kptnm[sysid].port_bdf),
                            "%04x:%02x:%02x.%01x", pci_domain_nr(dev->bus), dev->bus->number, PCI_SLOT(dev->devfn), PCI_FUNC(dev->devfn));
                    kptnm[sysid].adapter_id = port;
                    kptnm[sysid].pf_num = kmulpt;
                    kptnm[sysid].port_id = sysid;
                    kptnm[sysid].bar = bar;
                    kptnm[sysid].speed = kspd;
                    if(mspeed == 0) {
                        kptnm[sysid].type = XILINX_10G;
                    } else if(mspeed == 1) {
                        kptnm[sysid].type = XILINX_25G;
                    } else if(mspeed == 3) {
                        kptnm[sysid].type = XILINX_100G;
                    } else if(mspeed == 4) {
                        kptnm[sysid].type = ALTERA_400G;
                    }

                    port++;
                    sysid++;
                }
            }
            dev = pci_get_device(id->vendor, PCI_ANY_ID, dev); // 获取下一个同厂商的设备
        }

        dev = NULL;
    }

    return ret;
}

static void ynic_watch_sample(struct ynic_watch_dev *w, u32 *cfg, u32 *sts,
                             u16 *lnksta, u16 *lnkcap,
                             u32 *ue_sta, u32 *ce_sta, u16 *sec_sts)
{
    *cfg     = 0xffffffffU;
    *sts     = 0xffffffffU;
    *lnksta  = 0xffff;
    *lnkcap  = 0xffff;
    *ue_sta  = 0;
    *ce_sta  = 0;
    *sec_sts = 0;

    /* 设备已从总线消失时这两次读取返回全 1，不会阻塞 */
    pci_read_config_dword(w->dev, PCI_VENDOR_ID, cfg);
    pci_read_config_dword(w->dev, PCI_COMMAND, sts);

    if (w->bridge) {
        pcie_capability_read_word(w->bridge, PCI_EXP_LNKSTA, lnksta);
        pcie_capability_read_word(w->bridge, PCI_EXP_LNKCAP, lnkcap);
        /* Bridge Secondary Status: bit 13 = Received Master Abort */
        pci_read_config_word(w->bridge, PCI_SEC_STATUS, sec_sts);
        /* AER Uncorrectable/Correctable Error Status（SDES 在 UESta bit 5） */
        if (w->aer_pos) {
            pci_read_config_dword(w->bridge, w->aer_pos + PCI_ERR_UNCOR_STATUS, ue_sta);
            pci_read_config_dword(w->bridge, w->aer_pos + PCI_ERR_COR_STATUS,   ce_sta);
        }
    }
}

static void ynic_watch_tick(struct work_struct *work)
{
    int i;

    for (i = 0; i < ynic_watch_n; i++) {
        struct ynic_watch_dev *w = &ynic_watch[i];
        u32 cfg, sts, beat = 0, ue_sta, ce_sta;
        u16 lnksta, lnkcap, sec_sts;
        bool present;

        ynic_watch_sample(w, &cfg, &sts, &lnksta, &lnkcap, &ue_sta, &ce_sta, &sec_sts);
        present = (cfg != 0xffffffffU);

        if (!w->primed) {
            w->primed = true;
            w->last_cfg = cfg;
            w->last_sts = sts;
            w->last_lnksta = lnksta;
            w->last_lnkcap = lnkcap;
            w->last_ue_sta = ue_sta;
            w->last_ce_sta = ce_sta;
            w->last_sec_sts = sec_sts;
            w->last_present = present;
            YNIC_LOG(YNIC_DBG_WATCH,
                    "WATCH %04x:%02x:%02x.%x start: cfg=0x%08x sts=0x%08x lnksta=0x%04x lnkcap=0x%04x "
                    "ue=0x%08x ce=0x%08x sec=0x%04x present=%d\n",
                    pci_domain_nr(w->dev->bus), w->dev->bus->number,
                    PCI_SLOT(w->dev->devfn), PCI_FUNC(w->dev->devfn),
                    cfg, sts, lnksta, lnkcap, ue_sta, ce_sta, sec_sts, present);
        } else if (present != w->last_present) {
            if (!present) {
                /*
                 * 掉线这一拍的 ue_sta / ce_sta / lnksta 是刚从根端口读到的实时值，
                 * 而 last_* 是上一拍（还活着时）的值。SDES(UESta bit5) 只会在
                 * 掉线瞬间被置位，所以两组值必须同时打印，否则正好丢掉现场。
                 */
                YNIC_ERRL(YNIC_DBG_WATCH,
                         "WATCH %04x:%02x:%02x.%x GONE: config space reads 0xffffffff | "
                         "now cfg=0x%08x lnksta=0x%04x ue=0x%08x ce=0x%08x sec=0x%04x | "
                         "prev cfg=0x%08x lnksta=0x%04x ue=0x%08x ce=0x%08x sec=0x%04x\n",
                         pci_domain_nr(w->dev->bus), w->dev->bus->number,
                         PCI_SLOT(w->dev->devfn), PCI_FUNC(w->dev->devfn),
                         cfg, lnksta, ue_sta, ce_sta, sec_sts,
                         w->last_cfg, w->last_lnksta,
                         w->last_ue_sta, w->last_ce_sta, w->last_sec_sts);
            } else {
                YNIC_LOG(YNIC_DBG_WATCH,
                        "WATCH %04x:%02x:%02x.%x BACK: cfg=0x%08x sts=0x%08x lnksta=0x%04x "
                        "ue=0x%08x ce=0x%08x sec=0x%04x\n",
                        pci_domain_nr(w->dev->bus), w->dev->bus->number,
                        PCI_SLOT(w->dev->devfn), PCI_FUNC(w->dev->devfn),
                        cfg, sts, lnksta, ue_sta, ce_sta, sec_sts);
            }
            w->last_present = present;
        } else if (present &&
                   (cfg != w->last_cfg || sts != w->last_sts ||
                    lnksta != w->last_lnksta || lnkcap != w->last_lnkcap ||
                    ue_sta != w->last_ue_sta || ce_sta != w->last_ce_sta ||
                    sec_sts != w->last_sec_sts)) {
            YNIC_LOG(YNIC_DBG_WATCH,
                    "WATCH %04x:%02x:%02x.%x CHANGE: cfg=0x%08x sts=0x%08x lnksta=0x%04x lnkcap=0x%04x "
                    "ue=0x%08x(0x%08x) ce=0x%08x(0x%08x) sec=0x%04x(0x%04x)\n",
                    pci_domain_nr(w->dev->bus), w->dev->bus->number,
                    PCI_SLOT(w->dev->devfn), PCI_FUNC(w->dev->devfn),
                    cfg, sts, lnksta, lnkcap,
                    ue_sta, w->last_ue_sta, ce_sta, w->last_ce_sta,
                    sec_sts, w->last_sec_sts);
        }

        /* 每次 tick 都刷新 last_*，避免同一变化反复打印 */
        if (present) {
            w->last_cfg = cfg;
            w->last_sts = sts;
            w->last_lnksta = lnksta;
            w->last_lnkcap = lnkcap;
            w->last_ue_sta = ue_sta;
            w->last_ce_sta = ce_sta;
            w->last_sec_sts = sec_sts;
        }

        /* 可选 MMIO 心跳：能区分"配置空间还活着但 BAR 已死"与整卡消失 */
        if ((dbg & YNIC_DBG_MMIO_HEART) && w->bar) {
            u32 now = ioread32(w->bar);

            if (unlikely(now == 0xffffffffU)) {
                YNIC_ERRL(YNIC_DBG_MMIO_HEART, "HEARTBEAT %04x:%02x:%02x.%x bar[0]=0xffffffff (dead)\n",
                         pci_domain_nr(w->dev->bus), w->dev->bus->number,
                         PCI_SLOT(w->dev->devfn), PCI_FUNC(w->dev->devfn));
                w->bar = NULL; /* 只报一次，避免刷屏 */
            } else if (now != w->last_beat) {
                YNIC_LOG(YNIC_DBG_MMIO_HEART, "HEARTBEAT bar[0]=0x%08x\n", now);
                w->last_beat = now;
            }
            beat = now;
        }
        (void)beat;
    }

    if (watch_ms > 0)
        schedule_delayed_work(&ynic_watch_work, msecs_to_jiffies(watch_ms));
}

static void ynic_watch_add(struct pci_dev *dev, void __iomem *bar)
{
    struct ynic_watch_dev *w;
    struct pci_dev *bridge;

    if (ynic_watch_n >= YNIC_WATCH_MAX_DEVS)
        return;

    w = &ynic_watch[ynic_watch_n];
    memset(w, 0, sizeof(*w));

    w->dev = pci_dev_get(dev);
    bridge = pci_upstream_bridge(dev);
    w->bridge = bridge ? pci_dev_get(bridge) : NULL;
    w->bar = bar;

    /* 找根端口 AER 扩展能力偏移，用于后续读 UESta/CESta */
    if (w->bridge)
        w->aer_pos = pci_find_ext_capability(w->bridge, PCI_EXT_CAP_ID_ERR);

    ynic_watch_n++;

    YNIC_LOG(YNIC_DBG_WATCH, "WATCH add %04x:%02x:%02x.%x (bridge=%s aer_pos=0x%x)\n",
            pci_domain_nr(dev->bus), dev->bus->number,
            PCI_SLOT(dev->devfn), PCI_FUNC(dev->devfn),
            w->bridge ? "yes" : "none", w->aer_pos);
}

static void ynic_watch_start(void)
{
    if (!(dbg & (YNIC_DBG_WATCH | YNIC_DBG_MMIO_HEART)) || watch_ms <= 0)
        return;
    if (watch_ms < 50)
        watch_ms = 50;

    INIT_DELAYED_WORK(&ynic_watch_work, ynic_watch_tick);
    ynic_watch_started = 1;
    schedule_delayed_work(&ynic_watch_work, msecs_to_jiffies(watch_ms));
    YNIC_LOG(YNIC_DBG_WATCH, "WATCH started, period=%dms devs=%d\n", watch_ms, ynic_watch_n);
}

static void ynic_watch_stop(void)
{
    int i;

    /* 没启动过（dbg 未开 watch，或 init 在 start 之前就失败）就不要碰 work 结构体 */
    if (ynic_watch_started) {
        cancel_delayed_work_sync(&ynic_watch_work);
        ynic_watch_started = 0;
    }

    for (i = 0; i < ynic_watch_n; i++) {
        if (ynic_watch[i].bridge)
            pci_dev_put(ynic_watch[i].bridge);
        if (ynic_watch[i].dev)
            pci_dev_put(ynic_watch[i].dev);
        memset(&ynic_watch[i], 0, sizeof(ynic_watch[i]));
    }
    ynic_watch_n = 0;
}

static void ynic_clear_hardware(void)
{
    int i;
    void __iomem *bar = NULL;

    /* 半初始化失败时会走到这里：kptnm 分配失败则整段跳过 */
    if (kptnm) {
        for(i=0;i<YNIC_TOTAL_PORT_NUM;i++) {
            if(kptnm[i].bar) {
                if(kptnm[i].bar != bar) {
                    iounmap(kptnm[i].bar);
                    bar = kptnm[i].bar;
                    kptnm[i].bar = NULL;
                }
            }
        }
    }

    // 释放每个port的位图
    for(i=0;i<YNIC_TOTAL_PORT_NUM;i++) {
        if(ktx_bitmap[i]) {
            kfree(ktx_bitmap[i]);
            ktx_bitmap[i] = NULL;
        }
        if(krx_bitmap[i]) {
            kfree(krx_bitmap[i]);
            krx_bitmap[i] = NULL;
        }
    }
    if(kptnm) {
        kfree(kptnm);
        kptnm = NULL;
    }
}

static int __init init_ntmodule(void)
{
    dev_t dev;
    int ret = YNIC_SUC;
    ynic_dbg_t0 = ktime_get();
    printk("yuannic_netdev init\n");

    YNIC_LOG(YNIC_DBG_LIFE, "loading: dbg=0x%x watch_ms=%d mmio_max=%d\n",
            dbg, watch_ms, dbg_mmio_max);

    if (alloc_chrdev_region(&dev, 0, 1, YNIC_SYS_NET_NAME))
    {
        return -EFAULT;
    }
    cdev_init(&cdev, &nt_fops);
    if (cdev_add(&cdev, dev, 1))
    {
        unregister_chrdev_region(dev, 1);
        return -EFAULT;
    }

    majorNumber = MAJOR(dev);
#if LINUX_VERSION_CODE >= KERNEL_VERSION(6, 4, 0)
     myClass = class_create(YNIC_CLASS_NAME);
#else
    myClass = class_create(THIS_MODULE, YNIC_CLASS_NAME);
#endif
    if (IS_ERR(myClass)) {
        ret = PTR_ERR(myClass);
        myClass = NULL;
        KDBG("Failed to register yuannic_netdev class\n");
        goto err_cdev;
    }
    //KDBG("The yuannic_netdev class registered correctly\n");

    myDevice = device_create(myClass, NULL, MKDEV(MAJOR(dev), MINOR(dev)), NULL, YNIC_SYS_NET_NAME);
    if (IS_ERR(myDevice)) {
         ret = PTR_ERR(myDevice);
         myDevice = NULL;
         KDBG("Failed to create the yuannic_netdev device\n");
         goto err_class;
    }

    // write_fpga_data();
    //KDBG("The yuannic_netdev class created correctly\n");


    spin_lock_init(&ktx_spinlock);
    spin_lock_init(&krx_spinlock);


    memset(ktx_bitmap, 0, sizeof(ktx_bitmap));
    memset(krx_bitmap, 0, sizeof(krx_bitmap));
    memset(ktx_bitmap_size, 0, sizeof(ktx_bitmap_size));
    memset(krx_bitmap_size, 0, sizeof(krx_bitmap_size));

    kptnm = kcalloc(YNIC_TOTAL_PORT_NUM, sizeof(struct port_name), GFP_KERNEL);
    if(!kptnm) {
        printk("Failed to allocate memory for kptnm\n");
        ret = -ENOMEM;
        goto err_device;
    }

    ret = ynic_init_hardware();
    if(ret) {
        printk(KERN_ERR "hardware init failed: %d\n", ret);
        goto err_hardware;
    }

    /* 定时器在所有 BAR 映射、kptnm 填好之后再启动，避免 tick 撞上半初始化状态 */
    ynic_watch_start();

    YNIC_LOG(YNIC_DBG_LIFE, "module init done, dbg=0x%x watch_ms=%d ports=%d\n",
            dbg, watch_ms, ynic_watch_n);

    return 0;

/*
 * 失败回滚。这里必须把字符设备注销干净：insmod 失败时内核会立刻释放模块内存，
 * 而 cdev_map 里仍持有指向本模块 .data 的 cdev 指针；残留的 /dev/yuannic_netdev
 * 一旦被 open()，chrdev_open -> kobj_lookup -> exact_lock 就会解引用已释放内存。
 * 2026-10-23 就是这样在 `ynictrl -q` 时踩到 use-after-free。
 */
err_hardware:
    /* ynic_init_hardware() 可能已映射 BAR2 并登记 watch，先撤掉 */
    ynic_watch_stop();
    ynic_clear_hardware();   /* 内部释放 kptnm 并置 NULL */
err_device:
    device_destroy(myClass, MKDEV(majorNumber, 0));
    myDevice = NULL;
err_class:
    class_destroy(myClass);
    myClass = NULL;
err_cdev:
    cdev_del(&cdev);
    unregister_chrdev_region(cdev.dev, 1);
    return ret;
}

static void __exit cleanup_ntmodule(void)
{
    printk("yuannic_netdev exit\n");
    device_destroy(myClass, MKDEV(majorNumber, 0));
    class_destroy(myClass);

    cdev_del(&cdev);
    unregister_chrdev_region(cdev.dev, 1);

    pci_dev_put(net_pci_dev);
    net_pci_dev =  NULL;
    ynic_watch_stop();
    ynic_clear_hardware();
    //return;
}

module_init(init_ntmodule);
module_exit(cleanup_ntmodule);

MODULE_AUTHOR("YuanGrid");
MODULE_LICENSE("GPL");
MODULE_DESCRIPTION("Suzhou YuanGrid Technology Co., Ltd.");
// MODULE_VERSION(DRIVER_RELEASE_VERSION);
