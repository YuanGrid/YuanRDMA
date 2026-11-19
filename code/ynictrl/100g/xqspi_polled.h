#ifndef _XQSPI_POLLED_H_
#define _XQSPI_POLLED_H_

#ifdef __cplusplus
extern "C" {
#endif

#include "xparameters.h" /* SDK generated parameters */
#include "xqspipsu.h"	 /* QSPIPSU device driver */
#include "xil_printf.h"
// #include "xil_cache.h"
#include "sleep.h"
#include <stdio.h>
#include <fcntl.h>
#include <ctype.h>
#include <sys/stat.h>
#include <stdlib.h>
#include <unistd.h>
#include <getopt.h>
#include <sys/ioctl.h>
#include <net/if.h>
#include <stdint.h>
#include <arpa/inet.h>
#include <string.h>
#include "ynic_net_base.h"




// 定义flash读写命令
#define WRITE_STATUS_CMD 0x01
#define WRITE_CMD 0x02
#define READ_CMD 0x03
#define WRITE_DISABLE_CMD 0x04
#define READ_STATUS_CMD 0x05
#define WRITE_ENABLE_CMD 0x06
#define VOLATILE_WRITE_ENABLE_CMD 0x50
#define QUAD_MODE_ENABLE_BIT 0x06
#define FAST_READ_CMD 0x0B
#define DUAL_READ_CMD 0x3B
#define QUAD_READ_CMD 0x6B
#define BULK_ERASE_CMD 0xC7
#define SEC_ERASE_CMD 0xD8
#define READ_ID 0x9F
#define READ_CONFIG_CMD 0x35
#define WRITE_CONFIG_CMD 0x01

#define READ_CMD_4B 0x13
#define FAST_READ_CMD_4B 0x0C
#define DUAL_READ_CMD_4B 0x3C
#define QUAD_READ_CMD_4B 0x6C

#define READ_FLAG_STATUS_CMD 0x70

#define COMMAND_OFFSET 0   /* Flash instruction */
#define ADDRESS_1_OFFSET 1 // 数据偏移地址的最高位
#define ADDRESS_2_OFFSET 2 // 数据偏移地址的中间位
#define ADDRESS_3_OFFSET 3 // 数据偏移地址的最低位
#define ADDRESS_4_OFFSET 4 // 数据偏移地址为四字节时 最低位

#define DATA_OFFSET 5  // Start of Data for Read/Write
#define DUMMY_OFFSET 4 // Dummy byte offset for fast, dual and quad reads

#define DUMMY_SIZE 1 // Number of dummy bytes for fast, dual and quad reads

#define DUMMY_CLOCKS 8 // Number of dummy bytes for fast, dual and quad reads

#define RD_ID_SIZE 4	  /* Read ID command + 3 bytes ID response */
#define BULK_ERASE_SIZE 1 /* Bulk Erase command size */
#define SEC_ERASE_SIZE 4  /* Sector Erase command + Sector address */
#define BANK_SEL_SIZE 2	  // BRWR or EARWR command + 1 byte bank value

#define RD_CFG_SIZE 2 // 1 byte Configuration register + RD CFG command

#define WR_CFG_SIZE 3 // WRR command + 1 byte each Status and Config Reg

#define DIE_ERASE_SIZE 4 /* Die Erase command + Die address */

#define OVERHEAD_SIZE 4

// flash基地址
#define FLASH1BASE 0x0000000

// 16MB
#define SIXTEENMB 0x1000000

// quad enable mask bit
#define FLASH_QUAD_EN_MASK 0x02

#define FLASH_SRWD_MASK 0x80

// Bank mask
#define BANKMASK 0xF000000

// Identification of Flash
// Micron:
// Byte 0 is Manufacturer ID;
// Byte 1 is first byte of Device ID - 0xBB or 0xBA
// Byte 2 is second byte of Device ID describes flash size:
// 128Mbit : 0x18; 256Mbit : 0x19; 512Mbit : 0x20
#define MICRON_ID_BYTE0 0x20
#define MICRON_ID_BYTE2_128 0x18
#define MICRON_ID_BYTE2_256 0x19
#define MICRON_ID_BYTE2_512 0x20
#define MICRON_ID_BYTE2_1G 0x21
#define MICRON_ID_BYTE2_2G 0x22

// Spansion:
// Byte 0 is Manufacturer ID;
// Byte 1 is Device ID - Memory Interface type - 0x20 or 0x02
// Byte 2 is second byte of Device ID describes flash size:
// 128Mbit : 0x18; 256Mbit : 0x19; 512Mbit : 0x20
#define SPANSION_ID_BYTE0 0x01
#define SPANSION_ID_BYTE2_64 0x17
#define SPANSION_ID_BYTE2_128 0x18
#define SPANSION_ID_BYTE2_256 0x19
#define SPANSION_ID_BYTE2_512 0x20

#define WINBOND_ID_BYTE0 0xEF
#define WINBOND_ID_BYTE2_128 0x18

#define ISSI_ID_BYTE0 0x9D
#define ISSI_ID_BYTE2_08 0x14
#define ISSI_ID_BYTE2_16 0x15
#define ISSI_ID_BYTE2_32 0x16
#define ISSI_ID_BYTE2_64 0x17
#define ISSI_ID_BYTE2_128 0x18
#define ISSI_ID_BYTE2_256 0x19
#define ISSI_ID_BYTE2_512 0x1a

#define QSPIPSU_DEVICE_ID XPAR_XQSPIPSU_0_DEVICE_ID

// flash页的数量
#define PAGE_COUNT 32

// 页大小的最大值
#define MAX_PAGE_SIZE 1024

#define TEST_ADDRESS 0x000000   //主，低地址
#define BACK_ADDRESS 0x2000000  //备，高地址，32M字节 32*1024*1024

#define UNIQUE_VALUE 0x06


#define IMG_SECTOR_START    0x00000000
#define IMG_SECTOR_END      0x04000000
#define IMG_SECTOR_100G     0x03FFF000
#define IMG_SECTOR_SIZE     4096

#define MAC_ADDR_LENGTH     6
#ifndef IFNAMSIZ
#define IFNAMSIZ IF_NAMESIZE
#endif


/**************************** Type Definitions *******************************/
typedef struct
{
	u32 SectSize;		 // 扇区大小
	u32 NumSect;		 // 扇区总个数
	u32 PageSize;		 // 页大小
	u32 NumPage;		 // 总页数
	u32 FlashDeviceSize; // 一个存储器件的大小
	u8 ManufacturerID;	 // 制造商ID
	u8 DeviceIDMemSize;	 // 指出存储容量的器件ID
	u32 SectMask;		 // 扇区开始地址掩码
	u8 NumDie;			 // No. of die forming a single flash
} FlashInfo;

extern int fd_user;

struct neti_card {
    char name[IFNAMSIZ];
    char mac[18];
};

extern XQspiPsu QspiPsuInstance;
extern u8 ReadCmd;
extern u8 WriteCmd;
extern u8 StatusCmd;
extern u8 SectorEraseCmd;
extern u8 FSRFlag;

/************************** Function Prototypes ******************************/

int QspiPsuPolledFlashExample(XQspiPsu *QspiPsuInstancePtr, u16 QspiPsuDeviceId);
int FlashReadID(XQspiPsu *QspiPsuPtr);
int FlashErase(XQspiPsu *QspiPsuPtr, u32 Address, u32 ByteCount, u8 *WriteBfrPtr);
int FlashWrite(XQspiPsu *QspiPsuPtr, u32 Address, u32 ByteCount, u8 Command,
			   u8 *WriteBfrPtr);
int FlashRead(XQspiPsu *QspiPsuPtr, u32 Address, u32 ByteCount, u8 Command,
			  u8 *WriteBfrPtr, u8 *ReadBfrPtr);
u32 GetRealAddr(XQspiPsu *QspiPsuPtr, u32 Address);
int BulkErase(XQspiPsu *QspiPsuPtr, u8 *WriteBfrPtr);
int FlashEnableQuadMode(XQspiPsu *QspiPsuPtr);
void Init(void);
int Qspi_Flash_init(XQspiPsu *QspiPsuInstancePtr, u16 QspiPsuDeviceId);
int Qspi_Flash_erase(XQspiPsu *QspiPsuInstancePtr, u32 addr, int len);
int Qspi_Flash_update(XQspiPsu *QspiPsuInstancePtr, u32 address, u8 *src, u32 len);
int Qspi_Flash_read(XQspiPsu *QspiPsuInstancePtr, u32 address, u8 *readbuf, u32 len);
int Qspi_Flash_verify(XQspiPsu *QspiPsuInstancePtr, u32 address, u8 *src, u32 len);

#ifdef __cplusplus
}
#endif


#endif
