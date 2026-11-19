/******************************************************************************
* Copyright (C) 2008 - 2020 Xilinx, Inc.  All rights reserved.
* SPDX-License-Identifier: MIT
******************************************************************************/

/*****************************************************************************/
/**
* @file xspi_polled_example.c
*
*
* This file contains a design example using the Spi driver (XSpi) and the Spi
* device using the polled mode.
*
* To put the driver in polled mode the Global Interrupt must be disabled after
* the Spi is Initialized and Spi driver is started.
*
* This example works with a PPC/MicroBlaze processor.
*
* @note
*
* None.
*
*<pre>
* MODIFICATION HISTORY:
*
* Ver   Who  Date     Changes
* ----- ---- -------- ---------------------------------------------------------
* 1.00a sdm  03/03/08 First Release
* 3.00a ktn  10/28/09 Converted all register accesses to 32 bit access.
*		      Updated to use the HAL APIs/macros. Replaced call to
*		      XSpi_Initialize API with XSpi_LookupConfig and
*		      XSpi_CfgInitialize.
* 3.02a sdm  05/04/11 Updated to run the loopback test only in standard spi
*		      mode.
* 4.2   ms   01/23/17 Added xil_printf statement in main function to
*                     ensure that "Successfully ran" and "Failed" strings
*                     are available in all examples. This is a fix for
*                     CR-965028.
*</pre>
******************************************************************************/

#include "xspi_polled.h"
#include "main.h"

/************************** Variable Definitions *****************************/

/*
 * The instances to support the device drivers are global such that the
 * are initialized to zero each time the program runs.
 */
XSpi  SpiInstance;	 /* The instance of the SPI device */

/*
 * The following variables are used to read and write to the  Spi device, they
 * are global to avoid having large buffers on the stack.
 */
static u8 ReadBuffer[BUFFER_SIZE + READ_WRITE_EXTRA_BYTES + 5];
static u8 WriteBuffer[BUFFER_SIZE + READ_WRITE_EXTRA_BYTES + 1];


volatile static int TransferInProgress;

static int ErrorCount;

extern uint8_t verbose;

/*****************************************************************************/
/**
*
* This function enables 4-Byte Addressing mode to the SPI Flash memory.
*
* @param	SpiPtr is a pointer to the instance of the SPI device.
*
* @return	XST_SUCCESS if successful else XST_FAILURE.
*
* @note		None
*
******************************************************************************/
int SpiFlash4bytemodeEnable(XSpi *SpiPtr)
{
	int Status;

	Status = SpiFlashWriteEnable(SpiPtr);
	if(Status != XST_SUCCESS) {
		return XST_FAILURE;
	}
	/*
	 * Wait while the Flash is busy.
	 */
	Status = SpiFlashWaitForFlashReady();
	if(Status != XST_SUCCESS) {
		return XST_FAILURE;
	}

	/*
	 * Prepare the COMMNAD_ENTER_4BYTE_ADDRESS_MODE.
	 */
	WriteBuffer[BYTE1] = COMMAND_ENTER_4BYTE_ADDRESS_MODE;

	/*
	 * Initiate the Transfer.
	 */
	//TransferInProgress = TRUE;
	Status = XSpi_Transfer(SpiPtr, WriteBuffer, NULL,
				WRITE_ENABLE_BYTES);
	if(Status != XST_SUCCESS) {
		return XST_FAILURE;
	}

	/*
	 * Wait till the Transfer is complete and check if there are any errors
	 * in the transaction..
	 */
	//while(TransferInProgress);
	if(ErrorCount != 0) {
		ErrorCount = 0;
		return XST_FAILURE;
	}

	return XST_SUCCESS;
}

/*****************************************************************************/
/**
*
* This function sets the QuadEnable bit in Micron flash.
*
* @param	None
*
* @return	XST_SUCCESS if successful else XST_FAILURE.
*
* @note		None.
*
******************************************************************************/
int SpiFlash4byteexit(XSpi *SpiPtr)
{
	int Status;

	Status = SpiFlashWriteEnable(SpiPtr);
	if(Status != XST_SUCCESS) {
		return XST_FAILURE;
	}
		/*
	 * Wait while the Flash is busy.
	 */
	Status = SpiFlashWaitForFlashReady();
	if(Status != XST_SUCCESS) {
		return XST_FAILURE;
	}

	/*
	 * Prepare the WriteBuffer.
	 */
	WriteBuffer[BYTE1] = COMMAND_EXIT_4BYTE_ADDRESS_MODE;

	/*
	 * Initiate the Transfer.
	 */
	//TransferInProgress = TRUE;
	Status = XSpi_Transfer(SpiPtr, WriteBuffer, NULL,
				WRITE_ENABLE_BYTES);
	if(Status != XST_SUCCESS) {
		return XST_FAILURE;
	}

	/*
	 * Wait till the Transfer is complete and check if there are any errors
	 * in the transaction..
	 */
	//while(TransferInProgress);
	if(ErrorCount != 0) {
		ErrorCount = 0;
		return XST_FAILURE;
	}
	return XST_SUCCESS;
}


/*****************************************************************************/
/**
*
* This function Extended Address Register Bit Definitions the Numonyx Serial Flash memory.
*
* @param	SpiPtr is a pointer to the instance of the Spi device.
*
* @return	XST_SUCCESS if successful else XST_FAILURE.
*
* @note		None
*
******************************************************************************/
int SpiReadExtendedAddressRegister(XSpi *SpiPtr)
{
	int 	Status;
	Status = SpiFlashWriteEnable(SpiPtr);
	if(Status != XST_SUCCESS) {
		return XST_FAILURE;
	}

	Status = SpiFlashWaitForFlashReady();
	if(Status != XST_SUCCESS) {
		return XST_FAILURE;
	}

	WriteBuffer[BYTE1] = COMMAND_READ_EXTENDED_ADDRESS;
	//TransferInProgress = TRUE;
	Status = XSpi_Transfer(SpiPtr, WriteBuffer, ReadBuffer,
			READ_WRITE_EXTRA_BYTES);
	if(Status != XST_SUCCESS) {
		return XST_FAILURE;
	}
	//while(TransferInProgress);
	if(ErrorCount != 0) {
		ErrorCount = 0;
		return XST_FAILURE;
		}
		//print ("\n\rCOMMAND_READ_EXTENDED_ADDRESS"); putnum(ReadBuffer[1]);
	return XST_SUCCESS;
}




/*****************************************************************************/
/**
*
* This function erases the entire contents of the Numonyx Serial Flash device.
*
* @param	SpiPtr is a pointer to the instance of the Spi device.
*
* @return	XST_SUCCESS if successful else XST_FAILURE.
*
* @note		The erased bytes will read as 0xFF.
*
******************************************************************************/
int SpiFlashBulkErase(XSpi *SpiPtr)
{
	int Status;

	/*
	 * Wait while the Flash is busy.
	 */
	Status = SpiFlashWaitForFlashReady();
	if(Status != XST_SUCCESS) {
		return XST_FAILURE;
	}

	/*
	 * Prepare the WriteBuffer.
	 */
	WriteBuffer[BYTE1] = COMMAND_BULK_ERASE;

	/*
	 * Initiate the Transfer.
	 */
	//TransferInProgress = TRUE;
	Status = XSpi_Transfer(SpiPtr, WriteBuffer, NULL,
						BULK_ERASE_BYTES);
	if(Status != XST_SUCCESS) {
		return XST_FAILURE;
	}

	/*
	 * Wait till the Transfer is complete and check if there are any errors
	 * in the transaction..
	 */
	//while(TransferInProgress);
	if(ErrorCount != 0) {
		ErrorCount = 0;
		return XST_FAILURE;
	}

	return XST_SUCCESS;
}

/*****************************************************************************/
/**
*
* This function erases the contents of the specified Sector in the Numonyx
* Serial Flash device.
*
* @param	SpiPtr is a pointer to the instance of the Spi device.
* @param	Addr is the address within a sector of the Buffer, which is to
*		be erased.
*
* @return	XST_SUCCESS if successful else XST_FAILURE.
*
* @note		The erased bytes will be read back as 0xFF.
*
******************************************************************************/
int SpiFlashSectorErase(XSpi *SpiPtr, u32 Addr)
{
	int Status;

	Status = SpiFlash4bytemodeEnable(SpiPtr);
	if (Status != XST_SUCCESS) {
		return XST_FAILURE;
	}
	Status = SpiReadExtendedAddressRegister(SpiPtr);
	if(Status != XST_SUCCESS) {
		return XST_FAILURE;
	}
	Status = SpiFlashWriteEnable(SpiPtr);
	if(Status != XST_SUCCESS) {
		return XST_FAILURE;
	}

	/*
	 * Wait while the Flash is busy.
	 */
	Status = SpiFlashWaitForFlashReady();
	if(Status != XST_SUCCESS) {
		return XST_FAILURE;
	}

	/*
	 * Prepare the WriteBuffer.
	 */
	//WriteBuffer[BYTE1] = COMMAND_WRITE_EXTENDED_ADDRESS;
	//WriteBuffer[BYTE2] = (u8) (0xFF);
	WriteBuffer[BYTE1] = COMMAND_SECTOR_ERASE;		//COMMAND_SECTOR_ERASE;
	WriteBuffer[BYTE2] = (u8) (Addr >> 24);
	WriteBuffer[BYTE3] = (u8) (Addr >> 16);
	WriteBuffer[BYTE4] = (u8) (Addr >> 8);
	WriteBuffer[BYTE5] = (u8) (Addr);


	/*
	 * Initiate the Transfer.
	 */
	//TransferInProgress = TRUE;
	Status = XSpi_Transfer(SpiPtr, WriteBuffer, NULL,
					SECTOR_ERASE_BYTES+1);
	if(Status != XST_SUCCESS) {
		return XST_FAILURE;
	}

	/*
	 * Wait till the Transfer is complete and check if there are any errors
	 * in the transaction..
	 */
	//while(TransferInProgress);
	//if(ErrorCount != 0) {
	//	ErrorCount = 0;
	//	return XST_FAILURE;
	//}

	//Status = SpiFlash4byteexit(SpiPtr);
	//if (Status != XST_SUCCESS) {
	//	return XST_FAILURE;
	//}

	return XST_SUCCESS;
}


/*****************************************************************************/
/**
*
* This function enables writes to the Numonyx Serial Flash memory.
*
* @param	SpiPtr is a pointer to the instance of the Spi device.
*
* @return	XST_SUCCESS if successful else XST_FAILURE.
*
* @note		None
*
******************************************************************************/
/*
 * Page Program,Sector Erase,Block Erase,Chip Erase,Write Status Register之前调用该函数
 */
int SpiFlashWriteEnable(XSpi *SpiPtr)
{
	int Status;

	/*
	 * Wait while the Flash is busy.
	 */
	Status = SpiFlashWaitForFlashReady();
	if(Status != XST_SUCCESS) {
		return XST_FAILURE;
	}

	/*
	 * Prepare the WriteBuffer.
	 */
	WriteBuffer[BYTE1] = COMMAND_WRITE_ENABLE;

	/*
	 * Initiate the Transfer.
	 */
	//TransferInProgress = TRUE;
	Status = XSpi_Transfer(SpiPtr, WriteBuffer, NULL,
				WRITE_ENABLE_BYTES);
	if(Status != XST_SUCCESS) {
		return XST_FAILURE;
	}

	/*
	 * Wait till the Transfer is complete and check if there are any errors
	 * in the transaction..
	 */
	//while(TransferInProgress);
	if(ErrorCount != 0) {
		ErrorCount = 0;
		return XST_FAILURE;
	}

	return XST_SUCCESS;
}

/*****************************************************************************/
/**
*
* This function writes the data to the specified locations in the Numonyx Serial
* Flash memory.
*
* @param	SpiPtr is a pointer to the instance of the Spi device.
* @param	Addr is the address in the Buffer, where to write the data.
* @param	ByteCount is the number of bytes to be written.
*
* @return	XST_SUCCESS if successful else XST_FAILURE.
*
* @note		None
*
******************************************************************************/
#if 1
int SpiFlashWrite(XSpi *SpiPtr, u32 Addr, u32 ByteCount, u8 WriteCmd)
{
	//u32 Index;
	int Status;

	Status = SpiFlash4bytemodeEnable(SpiPtr);
	if (Status != XST_SUCCESS) {
		return XST_FAILURE;
	}
	Status = SpiFlashWriteEnable(SpiPtr);
	if(Status != XST_SUCCESS) {
		return XST_FAILURE;
	}

	/*
	 * Wait while the Flash is busy.
	 */
	Status = SpiFlashWaitForFlashReady();
	if(Status != XST_SUCCESS) {
		return XST_FAILURE;
	}

	/*
	 * Prepare the WriteBuffer.
	 */
	WriteBuffer[BYTE1] = WriteCmd;
	WriteBuffer[BYTE2] = (u8) (Addr >> 24);
	WriteBuffer[BYTE3] = (u8) (Addr >> 16);
	WriteBuffer[BYTE4] = (u8) (Addr >> 8);
	WriteBuffer[BYTE5] = (u8) Addr;


	/*
	 * Fill in the TEST data that is to be written into the Numonyx Serial
	 * Flash device.
	 */
	//for(Index = 4; Index < ByteCount + READ_WRITE_EXTRA_BYTES; Index++) {
	//	WriteBuffer[Index] = (u8)((Index - 4) + TestByte);
	//}

	/*
	 * Initiate the Transfer.
	 */
	//TransferInProgress = TRUE;
	Status = XSpi_Transfer(SpiPtr, WriteBuffer, NULL,
				(ByteCount + READ_WRITE_EXTRA_BYTES+1));
	if(Status != XST_SUCCESS) {
		return XST_FAILURE;
	}

	/*
	 * Wait till the Transfer is complete and check if there are any errors
	 * in the transaction.
	 */
	//while(TransferInProgress);
	if(ErrorCount != 0) {
		ErrorCount = 0;
		return XST_FAILURE;
	}

	Status = SpiFlash4byteexit(SpiPtr);
	if (Status != XST_SUCCESS) {
		return XST_FAILURE;
	}

	return XST_SUCCESS;
}
#endif

/*****************************************************************************/
/**
*
* This function reads the data from the Numonyx Serial Flash Memory
*
* @param	SpiPtr is a pointer to the instance of the Spi device.
* @param	Addr is the starting address in the Flash Memory from which the
*		data is to be read.
* @param	ByteCount is the number of bytes to be read.
*
* @return	XST_SUCCESS if successful else XST_FAILURE.
*
* @note		None
*
******************************************************************************/
int SpiFlashRead(XSpi *SpiPtr, u32 Addr, u32 ByteCount, u8 ReadCmd)
{
	int Status;

	Status = SpiFlash4bytemodeEnable(SpiPtr);
	if (Status != XST_SUCCESS) {
		return XST_FAILURE;
	}
	Status = SpiFlashWriteEnable(SpiPtr);
	if(Status != XST_SUCCESS) {
			return XST_FAILURE;
	}

	/*
	 * Wait while the Flash is busy.
	 */
	Status = SpiFlashWaitForFlashReady();
	if(Status != XST_SUCCESS) {
		return XST_FAILURE;
	}

	/*
	 * Prepare the WriteBuffer.
	 */
	WriteBuffer[BYTE1] = ReadCmd;
	WriteBuffer[BYTE2] = (u8) (Addr >> 24);
	WriteBuffer[BYTE3] = (u8) (Addr >> 16);
	WriteBuffer[BYTE4] = (u8) (Addr >> 8);
	WriteBuffer[BYTE5] = (u8) Addr;

	if (ReadCmd == COMMAND_DUAL_READ) {
		ByteCount += DUAL_READ_DUMMY_BYTES;
	} else if (ReadCmd == COMMAND_DUAL_IO_READ) {
		ByteCount += DUAL_READ_DUMMY_BYTES;
	} else if (ReadCmd == COMMAND_QUAD_IO_READ) {
		ByteCount += QUAD_IO_READ_DUMMY_BYTES;
	} else if (ReadCmd==COMMAND_QUAD_READ) {
		ByteCount += QUAD_READ_DUMMY_BYTES;
	}else if (ReadCmd==COMMAND_4BYTE_QUAD_OUTPUT_FAST_READ) {
		ByteCount += QUAD_IO_READ_DUMMY_BYTES;
	}

	/*
	 * Initiate the Transfer.
	 */
	//TransferInProgress = TRUE;
	Status = XSpi_Transfer( SpiPtr, WriteBuffer, ReadBuffer,
				(ByteCount + READ_WRITE_EXTRA_BYTES));
	if(Status != XST_SUCCESS) {
		return XST_FAILURE;
	}

	/*
	 * Wait till the Transfer is complete and check if there are any errors
	 * in the transaction.
	 */
	//while(TransferInProgress);
	if(ErrorCount != 0) {
		ErrorCount = 0;
		return XST_FAILURE;
	}

	Status = SpiFlash4byteexit(SpiPtr);
	if (Status != XST_SUCCESS) {
		return XST_FAILURE;
	}

	return XST_SUCCESS;
}



/*****************************************************************************/
/**
*
* This function reads the Status register of the Numonyx Flash.
*
* @param	SpiPtr is a pointer to the instance of the Spi device.
*
* @return	XST_SUCCESS if successful else XST_FAILURE.
*
* @note		The status register content is stored at the second byte
*		pointed by the ReadBuffer.
*
******************************************************************************/
int SpiFlashGetStatus(XSpi *SpiPtr)
{
	int Status;

	/*
	 * Prepare the Write Buffer.
	 */
	WriteBuffer[BYTE1] = COMMAND_STATUSREG_READ;

	/*
	 * Initiate the Transfer.
	 */
	//TransferInProgress = TRUE;
	Status = XSpi_Transfer(SpiPtr, WriteBuffer, ReadBuffer,
						STATUS_READ_BYTES);
	if(Status != XST_SUCCESS) {
		return XST_FAILURE;
	}

	/*
	 * Wait till the Transfer is complete and check if there are any errors
	 * in the transaction..
	 */
	//while(TransferInProgress);
	if(ErrorCount != 0) {
		ErrorCount = 0;
		return XST_FAILURE;
	}

	return XST_SUCCESS;
}


/*****************************************************************************/
/**
*
* This function waits till the Numonyx serial Flash is ready to accept next
* command.
*
* @param	None
*
* @return	XST_SUCCESS if successful else XST_FAILURE.
*
* @note		This function reads the status register of the Buffer and waits
*.		till the WIP bit of the status register becomes 0.
*
******************************************************************************/
int SpiFlashWaitForFlashReady(void)
{
	int Status;
	u8 StatusReg;

	while(1) {

		/*
		 * Get the Status Register. The status register content is
		 * stored at the second byte pointed by the ReadBuffer.
		 */
		Status = SpiFlashGetStatus(&SpiInstance);
		if(Status != XST_SUCCESS) {
			return XST_FAILURE;
		}

		/*
		 * Check if the flash is ready to accept the next command.
		 * If so break.
		 */
		StatusReg = ReadBuffer[1];
		if((StatusReg & FLASH_SR_IS_READY_MASK) == 0) {
			break;
		}
	}

	return XST_SUCCESS;
}

int Spi_Flash_ReadId(void)
{
	int Status;

	Status = SpiFlashRead(&SpiInstance,0x9f,1,COMMAND_READ_ID);
	if(Status != XST_SUCCESS) {
		return XST_FAILURE;
	}
	printf("flash id: %02x%02x%02x\n",ReadBuffer[1],ReadBuffer[2],ReadBuffer[3]);
	return XST_SUCCESS;
}

/*
 * erase flash by length
 */
int Spi_Flash_erase(XSpi *SpiPtr, u32 address, u32 len)
{
	int Status;
	u32 NumSect;
	int Sector;
	u32 Addr = address;
	u16 prorate = 0;
	u16 prev_prorate = 0;

	if(len == (FLASH_SECTOR_SIZE * FLASH_SECTOR_NUM)) {
		Status = SpiFlashWriteEnable(SpiPtr);
		if(Status != XST_SUCCESS) {
			return XST_FAILURE;
		}

		Status = SpiFlashBulkErase(SpiPtr);
		if(Status != XST_SUCCESS) {
			return XST_FAILURE;
		}

		goto end;
	}

	NumSect = (len / FLASH_SECTOR_SIZE) + 1;

	if(((Addr + len) & FLASH_SECTOR_MASK) == ((Addr + (NumSect * FLASH_SECTOR_SIZE)) & FLASH_SECTOR_MASK)) {
		NumSect++;
	}

	printf("erase: ");
	printf("%3d%%", prorate);
	fflush(stdout);
	for (Sector = 0; Sector < NumSect; Sector++)
	{
		prorate = Sector * 100 / NumSect;
		if(prev_prorate != prorate) {
			printf("\033[4D");
			printf("%3d%%", prorate);
			fflush(stdout);
			prev_prorate = prorate;
		}

		Status = SpiFlashWriteEnable(SpiPtr);
		if(Status != XST_SUCCESS) {
			return XST_FAILURE;
		}

		Status = SpiFlashSectorErase(SpiPtr, Addr);
		if(Status != XST_SUCCESS) {
			return XST_FAILURE;
		}
		Addr  += FLASH_SECTOR_SIZE;

	}
	printf("\033[4D");
	printf("%3d%%", 100);
	printf("\033[2K");
	printf("\r");
	fflush(stdout);

end:
    if(verbose) {
        printf("erase success.\n");
    }
	return XST_SUCCESS;

}

/*
 * write flash by length
 */
int Spi_Flash_write(XSpi *SpiPtr, u32 address, u32 len, u8 *wbuf)
{
	int Status;
	int Page;
	u32 Addr = address;
	u8 *ptr = wbuf;
	int page_count,remain;
	u16 prorate = 0;
	u16 prev_prorate = 0;

	page_count = (len + FLASH_BUFFER_SIZE - 1) / FLASH_BUFFER_SIZE;
	remain = len % FLASH_BUFFER_SIZE;
	//printf("zc-page_count=%d,remain=%d, len=%d,page_size=%d\n", page_count, remain, len, FLASH_BUFFER_SIZE);

	printf("program: ");
	printf("%3d%%", prorate);
	fflush(stdout);
	for (Page = 0; Page < page_count; Page++)
	{
		prorate = Page * 100 / page_count;
		if(prev_prorate != prorate) {
			printf("\033[4D");
			printf("%3d%%", prorate);
			fflush(stdout);
			prev_prorate = prorate;
		}

		Status = SpiFlashWriteEnable(SpiPtr);
		if(Status != XST_SUCCESS) {
			return XST_FAILURE;
		}

		if (Page != page_count - 1)
		{
			//zc-todo:
			memcpy((WriteBuffer+READ_WRITE_EXTRA_BYTES+1), (ptr + (Page * FLASH_BUFFER_SIZE)), FLASH_BUFFER_SIZE);

			Status = SpiFlashWrite(SpiPtr, Addr + (Page * FLASH_BUFFER_SIZE), FLASH_BUFFER_SIZE, COMMAND_4BYTE_QUAD_OUTPUT_FAST_WRITE);
			if(Status != XST_SUCCESS) {
				return XST_FAILURE;
			}
		}
		else
		{
            if(remain != 0) {
                memcpy((WriteBuffer+READ_WRITE_EXTRA_BYTES+1), (ptr + (Page * FLASH_BUFFER_SIZE)), remain);
                Status = SpiFlashWrite(SpiPtr, Addr + (Page * FLASH_BUFFER_SIZE), remain, COMMAND_4BYTE_QUAD_OUTPUT_FAST_WRITE);
                if(Status != XST_SUCCESS) {
                    return XST_FAILURE;
                }
            } else {
                memcpy((WriteBuffer+READ_WRITE_EXTRA_BYTES+1), (ptr + (Page * FLASH_BUFFER_SIZE)), FLASH_BUFFER_SIZE);
                Status = SpiFlashWrite(SpiPtr, Addr + (Page * FLASH_BUFFER_SIZE), FLASH_BUFFER_SIZE, COMMAND_4BYTE_QUAD_OUTPUT_FAST_WRITE);
                if(Status != XST_SUCCESS) {
                    return XST_FAILURE;
                }
            }
		}
	}
	printf("\033[4D");
	printf("%3d%%", 100);
	printf("\033[2K");
	printf("\r");
	fflush(stdout);

	if(verbose)
		printf("write success.\n");
	return XST_SUCCESS;

}

/*
 * read flash by length
 */
int Spi_Flash_read(XSpi *SpiPtr, u32 address, u32 len, u8 *res)
{
	int Status;
	u32 Addr = address;
	u32 count,remain;
	u8 *ptr = res;
	int j;

	count = len / FLASH_BUFFER_SIZE;
	remain = len % FLASH_BUFFER_SIZE;
	for(j = 0; j < count; j++) {
		Status = SpiFlashRead(SpiPtr, (Addr + (j * FLASH_BUFFER_SIZE)), FLASH_BUFFER_SIZE, COMMAND_4BYTE_QUAD_OUTPUT_FAST_READ);
		if(Status != XST_SUCCESS) {
			return XST_FAILURE;
		}

		//zc-todo:
		memcpy(ptr, (ReadBuffer+READ_WRITE_EXTRA_BYTES+5), FLASH_BUFFER_SIZE);
		ptr += FLASH_BUFFER_SIZE;
	}

	if(remain) {
		Status = SpiFlashRead(SpiPtr, (Addr + (count * FLASH_BUFFER_SIZE)), remain, COMMAND_4BYTE_QUAD_OUTPUT_FAST_READ);
		if(Status != XST_SUCCESS) {
			return XST_FAILURE;
		}
		memcpy(ptr, (ReadBuffer+READ_WRITE_EXTRA_BYTES+5), remain);

	}
	if(verbose)
		printf("read success. \n");

	return XST_SUCCESS;
}

int Spi_Flash_verify(XSpi *SpiPtr, u32 address, u32 len, u8 *src)
{
	int Status;
	u32 Addr = address;
	u32 count,remain;
	u8 *ptr = src;
	int i,j;
	u16 prorate = 0;
	u16 prev_prorate = 0;

	count = len / FLASH_BUFFER_SIZE;
	remain = len % FLASH_BUFFER_SIZE;
	//printf("zc-count=%d,remain=%d,len=%d\n", count, remain, len);
	//count=14963,remain=164,len=3830692
	//zc-page_count=14964,remain=164, len=3830692,page_size=256
	printf("verify: ");
	printf("%3d%%", prorate);
	fflush(stdout);
	for(j = 0; j < count; j++) {
		Status = SpiFlashRead(SpiPtr, (Addr + (j * FLASH_BUFFER_SIZE)), FLASH_BUFFER_SIZE, COMMAND_4BYTE_QUAD_OUTPUT_FAST_READ);
		if(Status != XST_SUCCESS) {
			return XST_FAILURE;
		}


		for(i = 0; i < FLASH_BUFFER_SIZE; i++) {
			prorate = ((j * FLASH_BUFFER_SIZE) + i) * 100 / len;
			if(prev_prorate != prorate) {
				printf("\033[4D");
				printf("%3d%%", prorate);
				fflush(stdout);
				prev_prorate = prorate;
			}

			//zc-todo:
			if(ReadBuffer[i+READ_WRITE_EXTRA_BYTES+5] != *ptr++) {
				printf("verify error pos:%d\n",i);
				return XST_FAILURE;
			}
		}

	}

	// printf("run=%d%%\n", ((count * FLASH_BUFFER_SIZE) + i) * 100 / len);
	if(remain) {
		Status = SpiFlashRead(SpiPtr, (Addr + (count * FLASH_BUFFER_SIZE)), remain, COMMAND_4BYTE_QUAD_OUTPUT_FAST_READ);
		if(Status != XST_SUCCESS) {
			return XST_FAILURE;
		}

		for(i = 0; i < remain; i++) {
			prorate = ((count * FLASH_BUFFER_SIZE) + i) * 100 / len;
			if(prev_prorate != prorate) {
				printf("\033[4D");
				printf("%3d%%", prorate);
				fflush(stdout);
				prev_prorate = prorate;
			}

			//zc-todo:
			if(ReadBuffer[i+READ_WRITE_EXTRA_BYTES+5] != *ptr++) {
				printf("verify error pos:%d\n", i);
				return XST_FAILURE;
			}
		}
	}
	printf("\033[4D");
	printf("%3d%%", 100);
	printf("\033[2K");
	printf("\r");
	fflush(stdout);

	if(verbose)
		printf("verify success.\n");
	return XST_SUCCESS;
}


/*****************************************************************************/
/**
*
* Main function to call the Spi Polled example.
*
* @param	None
*
* @return	XST_SUCCESS if successful, otherwise XST_FAILURE.
*
* @note		None
*
******************************************************************************/
int XSpi_example(void)
{
	int Status;

	//u32 Index;
	//u32 Address;
	//XSpi_Config *ConfigPtr;	/* Pointer to Configuration data */
    u32 data;
	// u8 buffer[2048];
	// u8 readbuf[2048];
	
	size_t size;
	struct stat filestat;
	unsigned char *src;
	int ret = XST_SUCCESS;
	char name[30];

    Init_10g();
    //read register success.
    data = XSpi_ReadReg(0xf000,0x60);
    printf("data=0x%08x\n",data);

	Status = SpiFlashInit(&SpiInstance, SPI_DEVICE_ID);
	if (Status != XST_SUCCESS) {
		xil_printf("Spi init Failed\r\n");
		return XST_FAILURE;
	}

    //read id
    Status = SpiFlashRead(&SpiInstance,0x9f,1,COMMAND_READ_ID);
	if(Status != XST_SUCCESS) {
		return XST_FAILURE;
	}
    printf("flash id: %02x%02x%02x\n",ReadBuffer[1],ReadBuffer[2],ReadBuffer[3]);

	Status = SpiFlashWriteEnable(&SpiInstance);
	if(Status != XST_SUCCESS) {
		return XST_FAILURE;
	}

#if 0
    //erase
    Status = SpiFlashBulkErase(&SpiInstance);
	if(Status != XST_SUCCESS) {
		return XST_FAILURE;
	}

    //write data
    for(int i=4;i<BUFFER_SIZE+READ_WRITE_EXTRA_BYTES;i++) {
        WriteBuffer[i] = (u8)(100+(i-4));
        printf("0x%02x ",WriteBuffer[i]);
    }
    printf("\n");

	Status = SpiFlashWriteEnable(&SpiInstance);
	if(Status != XST_SUCCESS) {
		return XST_FAILURE;
	}

    Status = SpiFlashWrite(&SpiInstance, TEST_ADDRESS_10G, BUFFER_SIZE, COMMAND_QUAD_WRITE);
    //Status = SpiFlashWrite(&SpiInstance, TEST_ADDRESS_10G, BUFFER_SIZE, COMMAND_PAGE_PROGRAM);
	if(Status != XST_SUCCESS) {
		return XST_FAILURE;
	}

    for(int i=0;i<BUFFER_SIZE+READ_WRITE_EXTRA_BYTES;i++) {
        ReadBuffer[i] = 0x00;
    }
    printf("zc-read-data:\n");
    Status = SpiFlashRead(&SpiInstance, TEST_ADDRESS_10G, BUFFER_SIZE, COMMAND_QUAD_READ);
    //Status = SpiFlashRead(&SpiInstance, TEST_ADDRESS_10G, BUFFER_SIZE, COMMAND_RANDOM_READ);
	if(Status != XST_SUCCESS) {
		return XST_FAILURE;
	}

    for(int i=0;i<(BUFFER_SIZE + READ_WRITE_EXTRA_BYTES + 4);i++) {
        printf("0x%02x ",ReadBuffer[i]);
    }
    printf("\n");

    for(int i=0;i<BUFFER_SIZE;i++) {
        if(ReadBuffer[i+READ_WRITE_EXTRA_BYTES+4] != WriteBuffer[i+READ_WRITE_EXTRA_BYTES])
		    return XST_FAILURE;
    }
    printf("flash write success.\n");
#endif

    //read/write/verfiy test code.
#if 0
	for(int i=0;i<2048;i++) {
		buffer[i] = (u8)(i%256);
	}
	Spi_Flash_erase(&SpiInstance, TEST_ADDRESS_10G, sizeof(buffer));
#if 1
	Spi_Flash_read(&SpiInstance,TEST_ADDRESS_10G, sizeof(readbuf), readbuf);
	for(int i=0;i<sizeof(readbuf);i++) { 
		if(readbuf[i] != 0xff) {
			printf("flash erase error at %d\n",i);
			return XST_FAILURE;
		}
	}
#endif

	Spi_Flash_write(&SpiInstance, TEST_ADDRESS_10G, sizeof(buffer),buffer);

	Spi_Flash_read(&SpiInstance,TEST_ADDRESS_10G, sizeof(readbuf), readbuf);
	for(int i=0;i<sizeof(readbuf);i++) {
		if(readbuf[i] != buffer[i]) {
            printf("flash write error at %d, write=0x%02x, read=0x%02x\n",i,buffer[i],readbuf[i]);
            return XST_FAILURE;
        }
	}
	Spi_Flash_verify(&SpiInstance, TEST_ADDRESS_10G, sizeof(buffer), buffer);
#endif

	sprintf(name, "%s", "./led_test.bin");

	int file_fd = open(name, O_RDONLY | O_BINARY);
	if (file_fd < 0)
	{
		printf("Failed to open %s\n", name);
		ret = XST_FAILURE;
	}

	if (fstat(file_fd, &filestat) < 0)
	{
		printf("Failed to stat %s\n", name);
		ret = XST_FAILURE;
	}

	size = filestat.st_size;
	src = malloc(size);
	if (!src)
	{
		printf("Failed to allocated memory\n");
		ret = XST_FAILURE;
	}
	memset(src, 0, size);

	if (read(file_fd, src, size) < size)
	{
		printf("Read file failed\n");
		ret = XST_FAILURE;
	}

	Spi_Flash_erase(&SpiInstance, TEST_ADDRESS_10G, size);
	Spi_Flash_write(&SpiInstance, TEST_ADDRESS_10G, size, src);
	Spi_Flash_verify(&SpiInstance, TEST_ADDRESS_10G, size, src);


	return ret;
}


/*****************************************************************************/
/**
*
* This function init flash chip.
*
* @param	SpiInstancePtr is a pointer to the instance of Spi component.
* @param	SpiDeviceId is the Device ID of the Spi Device and is the
*		XPAR_<SPI_instance>_DEVICE_ID value from xparameters.h.
*
* @return	XST_SUCCESS if successful, otherwise XST_FAILURE.
*
* @note
*
******************************************************************************/
int SpiFlashInit(XSpi *SpiInstancePtr, u16 SpiDeviceId)
{
	int Status;
	// u32 Count;
	//u8 Test;
	XSpi_Config *ConfigPtr;	/* Pointer to Configuration data */

	/*
	 * Initialize the SPI driver so that it is  ready to use.
	 */
	ConfigPtr = XSpi_LookupConfig(SpiDeviceId);
	if (ConfigPtr == NULL) {
		return XST_DEVICE_NOT_FOUND;
	}

	XSpi_Abort(SpiInstancePtr);


	Status = XSpi_CfgInitialize(SpiInstancePtr, ConfigPtr,
				  ConfigPtr->BaseAddress);
	if (Status != XST_SUCCESS) {
		return XST_FAILURE;
	}

	/*
	 * Perform a self-test to ensure that the hardware was built correctly.
	 */
	//Status = XSpi_SelfTest(SpiInstancePtr);
	//if (Status != XST_SUCCESS) {
	//	return XST_FAILURE;
	//}

	/*
	 * Run loopback test only in case of standard SPI mode.
	 */
	//if (SpiInstancePtr->SpiMode != XSP_STANDARD_MODE) {
	//	return XST_SUCCESS;
	//}

	/*
	 * Set the Spi device as a master and in loopback mode.
	 */
	Status = XSpi_SetOptions(SpiInstancePtr, XSP_MASTER_OPTION |
 					XSP_MANUAL_SSELECT_OPTION);//zc-add-是否需要设置为手动选项
	if (Status != XST_SUCCESS) {
		return XST_FAILURE;
	}


	/*
	 * Select the quad flash device on the SPI bus, so that it can be
	 * read and written using the SPI bus.
	 */
	Status = XSpi_SetSlaveSelect(SpiInstancePtr, SPI_SELECT);
	if(Status != XST_SUCCESS) {
		return XST_FAILURE;
	}

	/*
	 * Start the SPI driver so that the device is enabled.
	 */
	XSpi_Start(SpiInstancePtr);

	/*
	 * Perform the Write Enable operation.
	 */
	//Status = SpiFlashWriteEnable(SpiInstancePtr);
	//if(Status != XST_SUCCESS) {
	//	return XST_FAILURE;
	//}

	/*
	 * Disable Global interrupt to use polled mode operation
	 */
	XSpi_IntrGlobalDisable(SpiInstancePtr);

	/*
	 * Initialize the write buffer with pattern to write, initialize the
	 * read buffer to zero so it can be verified after the read, the
	 * Test value that is added to the unique value allows the value to be
	 * changed in a debug environment.
	 */
#if 0
	Test = 0x10;
	for (Count = 0; Count < BUFFER_SIZE; Count++) {
		WriteBuffer[Count] = (u8)(Count + Test);
		ReadBuffer[Count] = 0;
	}


	/*
	 * Transmit the data.
	 */
	XSpi_Transfer(SpiInstancePtr, WriteBuffer, ReadBuffer, BUFFER_SIZE);

	/*
	 * Compare the data received with the data that was transmitted.
	 */
	for (Count = 0; Count < BUFFER_SIZE; Count++) {
		if (WriteBuffer[Count] != ReadBuffer[Count]) {
			return XST_FAILURE;
		}
	}
#endif
	Status = SpiFlashRead(&SpiInstance,0x9f,1,COMMAND_READ_ID);
	if(Status != XST_SUCCESS) {
		return XST_FAILURE;
	}
	if(verbose)
		printf("flash id: %02x%02x%02x\n",ReadBuffer[1],ReadBuffer[2],ReadBuffer[3]);

	return XST_SUCCESS;
}


int test_10g_highaddr(void)
{

	int Status;

	//u32 Index;
	//u32 Address;
	//XSpi_Config *ConfigPtr;	/* Pointer to Configuration data */
    u32 data;
	//u8 buffer[2048];
	u8 readbuf[2048];

    Init_10g();
    //read register success.
    data = XSpi_ReadReg(0xf000,0x60);
    printf("data=0x%08x\n",data);

#if 0
	Status = SpiFlashInit(&SpiInstance, SPI_DEVICE_ID);
	if (Status != XST_SUCCESS) {
		xil_printf("Spi init Failed\r\n");
		return XST_FAILURE;
	}
#endif

    //read id
    Status = SpiFlashRead(&SpiInstance,0x9f,1,COMMAND_READ_ID);
	if(Status != XST_SUCCESS) {
		return XST_FAILURE;
	}
    printf("flash id: %02x%02x%02x\n",ReadBuffer[1],ReadBuffer[2],ReadBuffer[3]);

	//read high and low address.
	Spi_Flash_read(&SpiInstance,TEST_ADDRESS1, sizeof(readbuf), readbuf);
	printf("low address 0M:\n");
	for(int i=0;i<512;i++) {
		printf("0x%02x ",readbuf[i]);
		if((i+1) % 16 == 0)
			printf("\n");
	}
	printf("IS_BASE:");
	data = 0;
	for(int i=0;i<512;i++) {
		if((readbuf[i] == 0x30) && (readbuf[i+1] == 0x02) &&
			(readbuf[i+2] == 0x00) && (readbuf[i+3] == 0x01)) {
			if((i+7) < 512) {
				if((readbuf[i+4] == 0x01) && (readbuf[i+5] == 0x00) &&
					(readbuf[i+6] == 0x00) && (readbuf[i+7] == 0x00)) {
					data |= readbuf[i+7];
					data |= (u32)readbuf[i+6] << 8;
					data |= (u32)readbuf[i+5] << 16;
					data |= (u32)readbuf[i+4] << 24;
					printf("base(0x%08x)\n",data);
				} else {
					printf("not base\n");
				}
				break;
			}
		}
	}

	data = 0;
	for(int i=0;i<512;i++) {
		if((readbuf[i] == 0x30) && (readbuf[i+1] == 0x01) &&
			(readbuf[i+2] == 0xa0) && (readbuf[i+3] == 0x01)) {
			if((i+7) < 512) {
				data |= readbuf[i+7];
				data |= (u32)readbuf[i+6] << 8;
				data |= (u32)readbuf[i+5] << 16;
				data |= (u32)readbuf[i+4] << 24;
				break;
			}
		}
	}
	printf("data=0x%08x---",data);
	u32 year,month,day,hour,minute,second;
	second = data & 0x3f;
	minute = (data >> 6) & 0x3f;
	hour = (data >> 12) & 0x1f;
	year = (data >> 17) & 0x3f;
	month = (data >> 23) & 0x0f;
	day = (data >> 27) & 0x1f;
	printf("DATE:%02d/%02d/%02d,",year,month,day);
	printf("TIME:%02d:%02d:%02d\n",hour,minute,second);

    memset(readbuf, 0 , sizeof(readbuf));
	Spi_Flash_read(&SpiInstance,MASTER_ADDRESS1, sizeof(readbuf), readbuf);
	printf("high address 16M:\n");
	for(int i=0;i<512;i++) {
		printf("0x%02x ",readbuf[i]);
		if((i+1) % 16 == 0)
			printf("\n");
	}

	data = 0;
	for(int i=0;i<512;i++) {
		if((readbuf[i] == 0x30) && (readbuf[i+1] == 0x01) &&
			(readbuf[i+2] == 0xa0) && (readbuf[i+3] == 0x01)) {
			if((i+7) < 512) {
				data |= readbuf[i+7];
				data |= (u32)readbuf[i+6] << 8;
				data |= (u32)readbuf[i+5] << 16;
				data |= (u32)readbuf[i+4] << 24;
				break;
			}
		}
	}
	printf("data=0x%08x---",data);
	second = data & 0x3f;
	minute = (data >> 6) & 0x3f;
	hour = (data >> 12) & 0x1f;
	year = (data >> 17) & 0x3f;
	month = (data >> 23) & 0x0f;
	day = (data >> 27) & 0x1f;
	printf("DATE:%02d/%02d/%02d,",year,month,day);
	printf("TIME:%02d:%02d:%02d\n",hour,minute,second);

    memset(readbuf, 0 , sizeof(readbuf));
	Spi_Flash_read(&SpiInstance,IMG_SECTOR_10G, 192, readbuf);
	printf("mac sector:\n");
	for(int i=0;i<256;i++) {
		printf("0x%02x ",readbuf[i]);
		if((i+1) % 16 == 0)
			printf("\n");
	}
	printf("version:%.*s\n",64, &readbuf[144]);

#if 0
    //read/write/verfiy test code. low address
	for(int i=0;i<2048;i++) {
		buffer[i] = 0x16;
	}
	Spi_Flash_read(&SpiInstance,TEST_ADDRESS1, sizeof(buffer), readbuf);
	Spi_Flash_erase(&SpiInstance, TEST_ADDRESS1, sizeof(buffer));
	//Spi_Flash_erase(&SpiInstance, TEST_ADDRESS1, (32*1024*1024));
#if 1
	Spi_Flash_read(&SpiInstance,TEST_ADDRESS1, sizeof(buffer), readbuf);
	for(int i=0;i<sizeof(readbuf);i++) {
		if(readbuf[i] != 0xff) {
			printf("flash erase error at %d\n",i);
            printf("first 128 bytes\n");
            for(int j=0;j<128;j++) {
                printf("0x%02x ",readbuf[j]);
                if((j+1) % 16 == 0) {
                    printf("\n");
                }
            }
            printf("last 128 bytes\n");
            for(int j=sizeof(readbuf)-128;j<sizeof(readbuf);j++) {
                printf("0x%02x ",readbuf[j]);
                if((j+1) % 16 == 0) {
                    printf("\n");
                }
            }
			return XST_FAILURE;
		}
	}
    Spi_Flash_write(&SpiInstance,TEST_ADDRESS1, sizeof(buffer), buffer);
	Spi_Flash_read(&SpiInstance,TEST_ADDRESS1, sizeof(buffer), readbuf);
    Spi_Flash_verify(&SpiInstance,TEST_ADDRESS1,sizeof(buffer), buffer);
#endif
#endif

#if 0
    //read/write/verfiy test code. high address
	for(int i=0;i<2048;i++) {
		buffer[i] = 0x3b;
	}
	Spi_Flash_read(&SpiInstance,MASTER_ADDRESS1, sizeof(readbuf), readbuf);
	Spi_Flash_erase(&SpiInstance, MASTER_ADDRESS1, sizeof(buffer));
#if 1
	Spi_Flash_read(&SpiInstance,MASTER_ADDRESS1, sizeof(readbuf), readbuf);
    //Status = SpiFlashRead(&SpiInstance, TEST_ADDRESS1, BUFFER_SIZE, COMMAND_4BYTE_QUAD_OUTPUT_FAST_READ);
	for(int i=0;i<sizeof(readbuf);i++) {
		if(readbuf[i] != 0xff) {
			printf("flash erase error at %d\n",i);
			return XST_FAILURE;
		}
	}

	Spi_Flash_write(&SpiInstance, MASTER_ADDRESS1, sizeof(buffer), buffer);
	Spi_Flash_verify(&SpiInstance,MASTER_ADDRESS1, sizeof(buffer), buffer);

	Spi_Flash_read(&SpiInstance,MASTER_ADDRESS1, sizeof(readbuf), readbuf);
	for(int i=0;i<sizeof(readbuf);i++) {
		if(readbuf[i] != 0x3b) {
			printf("flash erase error at %d\n",i);
			return XST_FAILURE;
		}
	}
	printf("0x3b\n");

	Spi_Flash_read(&SpiInstance,TEST_ADDRESS1, sizeof(readbuf), readbuf);
	for(int i=0;i<sizeof(readbuf);i++) {
		if(readbuf[i] != 0x16) {
			printf("flash erase error at %d\n",i);
			return XST_FAILURE;
		}
	}
	printf("0x16\n");
#endif
#endif
    return XST_SUCCESS;
}

