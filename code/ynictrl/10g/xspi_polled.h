#ifndef _XSPI_POLLED_H_
#define _XSPI_POLLED_H_

#ifdef __cplusplus
extern "C" {
#endif


/***************************** Include Files *********************************/

#include "xparameters_10g.h"	/* XPAR parameters */
#include "xspi.h"		/* SPI device driver */
#include "xspi_l.h"
//#include "xil_printf.h"

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


/************************** Constant Definitions *****************************/

/*
 * The following constant defines the slave select signal that is used to
 * to select the Flash device on the SPI bus, this signal is typically
 * connected to the chip select of the device.
 */
#define SPI_SELECT 			0x01
/*
 *  This is the size of the buffer to be transmitted/received in this example.
 */
#define BUFFER_SIZE		256U

#define FLASH_SR_IS_READY_MASK		0x01 /* Ready mask */

#define PAGE_SIZE		256

#define TEST_ADDRESS_10G	0x00000000U
#define MASTER_ADDRESS	    0x01000000U
#define SLAVE_ADDRESS	    0x00000000U
#define IMG_SECTOR_10G      0x01FFF000      //4k space


#define TEST_ADDRESS1	0x00000000U
#define MASTER_ADDRESS1	0x01000000U
/*
 * flash size 256Mb
 */
#define FLASH_SECTOR_NUM		512
#define FLASH_SECTOR_SIZE		0x10000
#define FLASH_SECTOR_MASK		(0x10000 - 1)
#define FLASH_BUFFER_SIZE		256U

#define READ_WRITE_EXTRA_BYTES		4 /* Read/Write extra bytes */
#define	WRITE_ENABLE_BYTES		1 /* Write Enable bytes */
#define SECTOR_ERASE_BYTES		4 /* Sector erase extra bytes */
#define BULK_ERASE_BYTES		1 /* Bulk erase extra bytes */
#define STATUS_READ_BYTES		2 /* Status read bytes count */
#define STATUS_WRITE_BYTES		2 /* Status write bytes count */
/*
 * Byte Positions.
 */
#define BYTE1				0 /* Byte 1 position */
#define BYTE2				1 /* Byte 2 position */
#define BYTE3				2 /* Byte 3 position */
#define BYTE4				3 /* Byte 4 position */
#define BYTE5				4 /* Byte 5 position */
#define BYTE6				5 /* Byte 6 position */
#define BYTE7				6 /* Byte 7 position */
#define BYTE8				7 /* Byte 8 position */


#define DUAL_READ_DUMMY_BYTES		2
#define QUAD_READ_DUMMY_BYTES		4

#define DUAL_IO_READ_DUMMY_BYTES	2
#define QUAD_IO_READ_DUMMY_BYTES	5

/*
 * Definitions of the commands shown in this example.
 */
#define COMMAND_PAGE_PROGRAM		0x02 /* Page Program command */
#define COMMAND_QUAD_WRITE		    0x32 /* Quad Input Fast Program */
#define COMMAND_RANDOM_READ		    0x03 /* Random read command */
#define COMMAND_DUAL_READ		    0x3B /* Dual Output Fast Read */
#define COMMAND_QUAD_READ		    0x6B /* Quad Output Fast Read */
#define	COMMAND_WRITE_ENABLE		0x06 /* Write Enable command */
#define COMMAND_SECTOR_ERASE		0xD8 /* Sector Erase command */
#define COMMAND_BULK_ERASE		    0xC7 /* Bulk Erase command */
#define COMMAND_STATUSREG_READ		0x05 /* Status read command */
#define COMMAND_READ_ID		        0x9F /* read id command */
#define COMMAND_DUAL_IO_READ		0xBB /* Dual IO Fast Read */
#define COMMAND_QUAD_IO_READ		0xEB /* Quad IO Fast Read */
#define COMMAND_ENTER_4BYTE_ADDRESS_MODE			0xB7 /* ENTER 4-BYTE ADDRESS MODE B7 */
#define COMMAND_EXIT_4BYTE_ADDRESS_MODE				0xE9 /* EXIT 4-BYTE ADDRESS MODE E9h */
#define COMMAND_READ_EXTENDED_ADDRESS				0xC8
#define COMMAND_WRITE_EXTENDED_ADDRESS				0xC5
#define COMMAND_4BYTE_QUAD_OUTPUT_FAST_READ			0x6C /* 4-BYTE QUAD OUTPUT FAST READ */
//zc-todo:
#define COMMAND_4BYTE_QUAD_OUTPUT_FAST_WRITE		0x34 /* 4-BYTE QUAD OUTPUT FAST WRITE */
#define COMMAND_4BYTE_SECTOR_ERASE		 		 	0xDC /* Sector Erase command */




/*
 * The following constants map to the XPAR parameters created in the
 * xparameters.h file. They are defined here such that a user can easily
 * change all the needed parameters in one place.
 */
#define SPI_DEVICE_ID		XPAR_SPI_0_DEVICE_ID

/**************************** Type Definitions *******************************/

extern XSpi  SpiInstance;

/***************** Macros (Inline Functions) Definitions *********************/


/************************** Function Prototypes ******************************/

int SpiFlashInit(XSpi *SpiInstancePtr, u16 SpiDeviceId);
int SpiFlashWrite(XSpi *SpiPtr, u32 Addr, u32 ByteCount, u8 WriteCmd);
int SpiFlashRead(XSpi *SpiPtr, u32 Addr, u32 ByteCount, u8 ReadCmd);
int SpiFlashWaitForFlashReady(void);
int SpiFlashReadID(XSpi *SpiPtr);
int SpiFlashWriteEnable(XSpi *SpiPtr);

/* my own defined func */
int Spi_Flash_ReadId(void);
int Spi_Flash_erase(XSpi *SpiPtr, u32 address, u32 len);
int Spi_Flash_write(XSpi *SpiPtr, u32 address, u32 len, u8 *wbuf);
int Spi_Flash_read(XSpi *SpiPtr, u32 address, u32 len, u8 *res);
int Spi_Flash_verify(XSpi *SpiPtr, u32 address, u32 len, u8 *src);
int test_10g_highaddr(void);

/************************** Variable Definitions *****************************/



#ifdef __cplusplus
}
#endif


#endif
