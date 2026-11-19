#ifndef _XFAST_H_
#define _XFAST_H_

#ifdef __cplusplus
extern "C" {
#endif


/***************************** Include Files *********************************/
#include <stdio.h>
#include <fcntl.h>
#include <ctype.h>
#include <sys/stat.h>
#include <stdlib.h>
#include <unistd.h>
#include <sys/ioctl.h>
#include <sys/mman.h>
#include <net/if.h>
#include <stdint.h>
#include <arpa/inet.h>
#include <string.h>
#include "xil_types.h"



/************************** Constant Definitions *****************************/

/*
 * The following constant defines the slave select signal that is used to
 * to select the Flash device on the SPI bus, this signal is typically
 * connected to the chip select of the device.
 */

/**************************** Type Definitions *******************************/


/***************** Macros (Inline Functions) Definitions *********************/

#define XFAST_TEST_LOG_LEN 512

#define XFAST_HW_BASE_ADDR					0x00000000U  //0MB
#define XFAST_HW_JUMPTABLE_ADDR				0x00C70000U
#define XFAST_HW_RELEASE1_ADDR				0x00C80000U  //12.5MB,12.5M*2bytes
#define XFAST_HW_RELEASE2_ADDR				0x01900000U
#define XFAST_HW_RELEASE3_ADDR				0x02580000U
#define XFAST_HW_RELEASE4_ADDR				0x03200000U
#define XFAST_IMG_SECTOR_ADDR				0x03FF0000U  //high 128KB


#define XFAST_TEST_ADDRESS1					0x00000000U
#define XFAST_MASTER_ADDRESS1				0x01000000U
/*
 * flash size 1024Mb
 */
#define XFAST_FLASH_ADDR_LEN				1
#define XFAST_FLASH_DATA_LEN				2
#define XFAST_FLASH_SECTOR_64K				0x10000
#define XFAST_FLASH_SECTOR_64K_MASK			(~(0x10000 - 1))
#define XFAST_FLASH_SECTOR_NUM				512
#define XFAST_FLASH_SECTOR_SIZE				0x10000
#define XFAST_FLASH_SECTOR_MASK				(0x10000 - 1)
#define XFAST_FLASH_BUFFER_SIZE				256U

#define XFAST_STATUS_BUSY					1
#define XFAST_STATUS_IDLE					0
#define XFAST_BASE_ADDR						0xF000
#define XFAST_BPI_STATUS_REG				0x0100
#define XFAST_BPI_READ_CMD_REG				0x0104
#define XFAST_BPI_READ_DATA_REG				0x0108
#define XFAST_BPI_WRITE_CMD_REG				0x010C
#define XFAST_BPI_WRITE_DATA_REG			0x0110
#define XFAST_BPI_ERASE_CMD_REG				0x0114

#define XFAST_BPI_RDBUF_CMD_REG				0x0124
#define XFAST_BPI_RDBUF_DATA_REG			0x0128
#define XFAST_RDBUF_ALIGN					(8)
#define XFAST_RDBUF_DATA_SIZE				(8 * 4)
#define XFAST_RDBUF_ADDR_SIZE				(XFAST_RDBUF_DATA_SIZE / 2)
#define XFAST_BPI_WRBUF_OFFSET_REG			0x0118
#define XFAST_BPI_WRBUF_CMD_REG				0x0120
#define XFAST_BPI_WRBUF_DATA_REG			0x011C
#define XFAST_WRBUF_ALIGN					(256)
#define XFAST_WRBUF_DATA_SIZE				(256 * 4) //1kbyte
#define XFAST_WRBUF_ADDR_SIZE				(XFAST_WRBUF_DATA_SIZE / 2)

#define XFAST_BPI_UPDATE_REG				0x0300
#define XFAST_BPI_CONTROL_REG				0x030C

/************************** Function Prototypes ******************************/

void xfast_demo(void);
void xfast_demo1(void);
int xfast_flash_erase(u32 address, u32 len);
int xfast_flash_write(u32 address, u32 len, u8 *wbuf);
int xfast_flash_write_high(u32 address, u32 len, u8 *wbuf);
int xfast_flash_read(u32 address, u32 len, u8 *res);
int xfast_flash_read_high(u32 address, u32 len, u8 *res);
int xfast_flash_verify(u32 address, u32 len, u8 *src);
int xfast_flash_verify_high(u32 address, u32 len, u8 *src);
int xfast_flash_update(void);
int test_xfast_highaddr(void);
int Xfast_FlashInit(void);
int xfast_update_act(void);
int xfast_update_mac(void);

/************************** Variable Definitions *****************************/



#ifdef __cplusplus
}
#endif


#endif
