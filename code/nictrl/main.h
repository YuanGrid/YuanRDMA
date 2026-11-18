#ifndef _XILINX_MAIN_H_
#define _XILINX_MAIN_H_

#ifdef __cplusplus
extern "C" {
#endif

#include "ynic_net_base.h"

#define IMG_DEV             "/dev/ynic_netdev"
#define VERSION             "2.0"

#define XFAST_HW_IMAGE_NUM					4
#define NF_ADAPTER_NUM      8
#define NF_PORT_SIZE        16
#define NF_PROGRAM_NAME     "nictrl"
#define NF_FIRMWARE_NUM     3
#define NF_BOOT_FW_ADDR     8
#define NF_WRITE_SIZE       ((NF_ADAPTER_NUM * NF_PORT_SIZE) + NF_SERNUM_LEN_RU + (NF_FIRMWARE_LEN * XFAST_HW_IMAGE_NUM))
#define NF_SERNUM_ADDR      (NF_ADAPTER_NUM * NF_PORT_SIZE)
#define NF_FIRMWARE_ADDR    (NF_ADAPTER_NUM * NF_PORT_SIZE + NF_SERNUM_LEN_RU)
#define NF_SERNUM_VALUE     MD010G250217001
//#define NF_SERNUM_LEN       strlen(NF_SERNUM_VALUE)


enum {
	BASE = 0,
	FIRMWARE_1,
	FIRMWARE_2,
	FIRMWARE_3,
};

#ifndef O_BINARY
#define O_BINARY 0
#endif


#ifdef __cplusplus
}
#endif


#endif

