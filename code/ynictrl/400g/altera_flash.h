#ifndef _ALTERA_H_
#define _ALTERA_H_

#ifdef __cplusplus
extern "C" {
#endif


/***************************** Include Files *********************************/
#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <string.h>
#include <unistd.h>
#include <fcntl.h>
#include <sys/mman.h>
#include <sys/time.h>
#include <arpa/inet.h>
#include "xil_types.h"



/************************** Constant Definitions *****************************/

/*
 * The following constant defines the slave select signal that is used to
 * to select the Flash device on the SPI bus, this signal is typically
 * connected to the chip select of the device.
 */

/**************************** Type Definitions *******************************/


/***************** Macros (Inline Functions) Definitions *********************/

// Mailbox AVMM Memory Map
#define BASE_ADDRESS 0x200000
//#define BASE_ADDRESS (0x4000000000 + 0x200000) //1.160
//#define BASE_ADDRESS (0x8c000000 + 0x200000) //1.160
//#define BASE_ADDRESS (0x60200000) //1.156

// 寄存器偏移量
#define REG_CMD          0x00       //+0
#define REG_CMD_LAST     0x10       //+1
#define REG_CMD_FIFO     0x20       //+2
#define REG_URGENT_CMD   0x30       //+3
#define REG_URGENT_FIFO  0x40       //+4
#define REG_RESP_DATA    0x50       //+5
#define REG_RESP_FIFO    0x60       //+6
#define REG_IER          0x70       //+7
#define REG_ISR          0x80       //+8

// 命令定义
#define CMD_GET_IDCODE   0x10
#define CMD_GET_CHIPID   0x12
#define CMD_GET_USERCODE 0x13
#define CMD_GET_VOLTAGE  0x18
#define CMD_GET_TEMP     0x19
#define CMD_QSPI_OPEN    0x32
#define CMD_QSPI_CLOSE   0x33
#define CMD_QSPI_SET_CS  0x34
#define CMD_QSPI_READ_SR 0x35
#define CMD_QSPI_ERASE   0x38
#define CMD_QSPI_WRITE   0x39
#define CMD_QSPI_READ    0x3A
#define CMD_RSU_STATUS   0x5B
#define CMD_RSU_UPDATE   0x5C

#define ALTERA_HW_IMAGE_NUM					4
#define ALTERA_HW_BASE_ADDR					0x00210000U  //0MB
#define ALTERA_HW_JUMPTABLE_ADDR			0x00C70000U
#define ALTERA_HW_RELEASE1_ADDR				0x01630000U
#define ALTERA_HW_RELEASE2_ADDR				0x01630000U
#define ALTERA_HW_RELEASE3_ADDR				0x01630000U
#define ALTERA_HW_RELEASE4_ADDR				0x01630000U
//#define ALTERA_IMG_SECTOR_ADDR				0x0FFFF000U //4k
#define ALTERA_IMG_SECTOR_ADDR				0x07FF0000U //64k


#define ALTERA_TEST_ADDRESS1				0x00000000U
#define ALTERA_MASTER_ADDRESS1				0x01000000U
/*
 * flash size 2Gb
 */
#define ALTERA_FLASH_ADDR_LEN				1
#define ALTERA_FLASH_DATA_LEN				2
#define ALTERA_FLASH_SECTOR_64K				0x10000
#define ALTERA_FLASH_SECTOR_64K_MASK		(~(0x10000 - 1))


#define ALTERA_RDBUF_ALIGN					(8)
//#define ALTERA_WRBUF_ALIGN				(256)
#define ALTERA_BUF_DATA_LEN					(1024) //1k word = 4k byte
#define ALTERA_BUF_DATA_SIZE				(ALTERA_BUF_DATA_LEN * 4) //1k word = 4k byte
#define ALTERA_BUF_ADDR_SIZE				(ALTERA_BUF_DATA_LEN * 4)

#define ALTERA_PCIE5_BAR2_MAGIC				0x4e540000U

/************************** Function Prototypes ******************************/

int init_hardware(void);
void cleanup_hardware(void);
uint32_t read_register(uint32_t offset);
void write_register(uint32_t offset, uint32_t value);
int read_command_fifo_empty_space(void);
int read_resp_fill_level(void);
int exec_command(uint32_t command, uint32_t *args, int num_args);
int read_response(uint32_t *response, int max_response);
int rsu_image_update(uint32_t addr);
int rsu_status(void);
int read_idcode(void);
int read_chipid(void);
int read_vol(uint32_t bmask);
int read_temp(uint32_t bmask);
int qspi_open(void);
int qspi_close(void);
int qspi_set_cs(void);
int qspi_read(uint32_t addr, uint32_t word_count, uint32_t *data);
int qspi_write_one_word(uint32_t addr, uint32_t data);
int qspi_erase(uint32_t addr, uint32_t num_sectors);
int qspi_read_status_register(void);
int qspi_read_flag_status_register(void);
int qspi_read_device_id(void);
int altera_flash_erase(u32 address, u32 len);
int altera_flash_write(u32 address, u32 len, u8 *wbuf);
int altera_flash_read(u32 address, u32 len, u8 *res);
int altera_flash_verify(u32 address, u32 len, u8 *src);
int altera_update_act(void);
int test_altera_highaddr(void);
int altera_is_pcie5(void);
void altera_set_current_adapter(int adapter_index, uint32_t pdf);

/************************** Variable Definitions *****************************/



#ifdef __cplusplus
}
#endif


#endif
