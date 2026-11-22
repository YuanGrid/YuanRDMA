/******************************************************************************
 * Copyright (C) 2020 Xilinx, Inc.  All rights reserved.
 * SPDX-License-Identifier: MIT
 ******************************************************************************/

/*****************************************************************************/
/**
 *
 * @file xqspipsu_hw.c
 * @addtogroup qspipsu_v1_12
 * @{
 *
 * This file contains functions to reads RXFifo, writes TXFifo and setup
 * RX DMA operation, used by xqspipsu_control.c and xqspipsu_lowlevel.c files.
 *
 * <pre>
 * MODIFICATION HISTORY:
 *
 * Ver   Who Date     Changes
 * ----- --- -------- -----------------------------------------------
 * 1.11   akm  03/09/20 First release
 *         mn  03/30/20 Add xil_smc.h include for Xil_Smc calls
 *
 ******************************************************************************/

/***************************** Include Files *********************************/

#include "xqspipsu_driver.h"
#if defined(__aarch64__)
#include "xil_smc.h"
#endif

#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <string.h>
#include <errno.h>
#include <signal.h>
#include <fcntl.h>
#include <ctype.h>
#include <termios.h>
#include <sys/types.h>
#include <sys/mman.h>
#include <assert.h>
#define FATAL                                                    \
	do                                                           \
	{                                                            \
		fprintf(stderr, "Error at line %d, file %s (%d) [%s]\n", \
				__LINE__, __FILE__, errno, strerror(errno));     \
		exit(1);                                                 \
	} while (0)

#define MAP_SIZE 4096UL
#define MAP_MASK (MAP_SIZE - 1)

/************************** Constant Definitions *****************************/

/**************************** Type Definitions *******************************/

/***************** Macros (Inline Functions) Definitions *********************/

/************************** Function Prototypes ******************************/

/************************** Variable Definitions *****************************/

/*****************************************************************************/

void *map_base;
extern int fd_user;
void Init(void)
{
	char name[128];
	// strcpy(name, "/dev/qspi_cdev");
    strcpy(name, "/dev/ynic_netdev");

	// open device file
	fd_user = open(name, O_RDWR | O_SYNC);
	if (fd_user < 0)
	{
		printf("Can't open %s.\n", name);
		// return;
	}
	else
	{
		// printf("device %s opened, fd = %d.\n", name, fd_user);
	}
}
void End()
{
#if 0
	if(munmap(map_base, MAP_SIZE) == -1) FATAL;
    close(fd);
#endif
	close(fd_user);
	return;
}

/*****************************************************************************/
/**
 *
 * @brief    Perform a 32-bit endian conversion.
 *
 * @param Data: 32 bit value to be converted
 *
 * @return    32 bit data with converted endianness
 *
 ******************************************************************************/
#if 0
static u32 endianSwap32(u32 Data)
{
	u16 LoWord;
	u16 HiWord;

	/* get each of the half words from the 32 bit word */

	LoWord = (u16)(Data & 0x0000FFFFU);
	HiWord = (u16)((Data & 0xFFFF0000U) >> 16U);

	/* byte swap each of the 16 bit half words */

	LoWord = (u16)(((LoWord & 0xFF00U) >> 8U) | ((LoWord & 0x00FFU) << 8U));
	HiWord = (u16)(((HiWord & 0xFF00U) >> 8U) | ((HiWord & 0x00FFU) << 8U));

	/* swap the half words before returning the value */

	return ((((u32)LoWord) << (u32)16U) | (u32)HiWord);
}
#endif

unsigned int XQspiPsu_ReadReg(unsigned long long BaseAddress, unsigned int RegOffset)
{
	unsigned int PAGE_SIZE = sysconf(_SC_PAGESIZE); //page_size = 4k
	unsigned long long Addr = BaseAddress + RegOffset + 0x100;

	unsigned int page_addr = (Addr & ~(PAGE_SIZE - 1));
	unsigned int page_offset = Addr - page_addr;
	unsigned int read_result = 0;

	void *mm_base = mmap(NULL, PAGE_SIZE, PROT_READ, MAP_SHARED, fd_user, page_addr);
	if (mm_base == (void *)-1)
	{
		printf("Can't map the memory to user space.\n");
		return -1;
	}

	read_result = *((unsigned int *)((u8 *)mm_base + page_offset));
    // printf("Addr=0x%llx,Baseaddr=0x%llx,Regoffset=0x%08x,PAGE_SIZE=0x%08x\n",Addr,BaseAddress,RegOffset,PAGE_SIZE);
    // printf("page_addr=0x%08x,page_offset=0x%08x,mm_base=0x%llx,read=0x%08x\n",page_addr, page_offset, mm_base,read_result);

	if (munmap(mm_base, PAGE_SIZE) == -1)
	{
		printf("Can't unmap memory from user space.\n");
		return -1;
	}

#ifdef DEBUG
	printf("RD register 0x%lX : 0x%08X \r\n", (BaseAddress + RegOffset), read_result);
	fflush(stdout);
#endif

	return read_result;
}

void XQspiPsu_WriteReg(unsigned long long BaseAddress, unsigned int RegOffset, unsigned int RegisterValue)
{
	unsigned int PAGE_SIZE = sysconf(_SC_PAGESIZE);
	unsigned long long Addr = BaseAddress + RegOffset + 0x100;

	u32 page_addr = (Addr & ~(PAGE_SIZE - 1));
	u32 page_offset = Addr - page_addr;

	void *mm_base = mmap(NULL, PAGE_SIZE, PROT_READ | PROT_WRITE, MAP_SHARED, fd_user, page_addr);
	if (mm_base == (void *)-1)
	{
		printf("Can't map the memory to user space.\n");
		return;
	}

	*((u32 *)((u8 *)mm_base + page_offset)) = RegisterValue;
	if (munmap(mm_base, PAGE_SIZE) == -1)
	{
		printf("Can't unmap memory from user space.\n");
		return ;
	}
#ifdef DEBUG
	printf("WR register 0x%lX : 0x%08X \r\n", (BaseAddress + RegOffset), RegisterValue);
	fflush(stdout);
#endif

	return;
}

/*****************************************************************************/
/**
 *
 * Fills the TX FIFO as long as there is room in the FIFO or the bytes required
 * to be transmitted.
 *
 * @param	InstancePtr is a pointer to the XQspiPsu instance.
 * @param	Msg is a pointer to the structure containing transfer data.
 * @param	Size is the number of bytes to be transmitted.
 *
 * @return	None
 *
 * @note	None.
 *
 ******************************************************************************/
void XQspiPsu_FillTxFifo(XQspiPsu *InstancePtr, XQspiPsu_Msg *Msg, u32 Size)
{
	u32 Count = 0;
	u32 Data = 0U;

	Xil_AssertVoid(InstancePtr != NULL);
	Xil_AssertVoid(Msg != NULL);
	Xil_AssertVoid(Size != 0);
	Xil_AssertVoid(InstancePtr->IsReady == XIL_COMPONENT_IS_READY);
#ifdef DEBUG
	xil_printf("\nXQspiPsu_FillTxFifo\r\n");
#endif
	while ((InstancePtr->TxBytes > 0) && (Count < Size))
	{
		if (InstancePtr->TxBytes >= 4)
		{
			(void)memcpy((u8 *)&Data, Msg->TxBfrPtr, 4);
			Msg->TxBfrPtr += 4;
			InstancePtr->TxBytes -= 4;
			Count += 4;
		}
		else
		{
			(void)memcpy((u8 *)&Data, Msg->TxBfrPtr,
						 (u32)InstancePtr->TxBytes);
			Msg->TxBfrPtr += InstancePtr->TxBytes;
			Count += InstancePtr->TxBytes;
			InstancePtr->TxBytes = 0;
		}
		XQspiPsu_WriteReg(InstancePtr->Config.BaseAddress,
						  XQSPIPSU_TXD_OFFSET, Data);
#ifdef DEBUG
		xil_printf("\nData is %08x\r\n", Data);
#endif
	}
	if (InstancePtr->TxBytes < 0)
		InstancePtr->TxBytes = 0;
}

/*****************************************************************************/
/**
 *
 * This function checks the TX buffer in the message and setup the
 * TX FIFO as required.
 *
 * @param	InstancePtr is a pointer to the XQspiPsu instance.
 * @param	Msg is a pointer to the structure containing transfer data.
 *
 * @return	None
 *
 * @note	None.
 *
 ******************************************************************************/
void XQspiPsu_TXSetup(XQspiPsu *InstancePtr, XQspiPsu_Msg *Msg)
{
	Xil_AssertVoid(InstancePtr != NULL);
	Xil_AssertVoid(Msg != NULL);
	Xil_AssertVoid(InstancePtr->IsReady == XIL_COMPONENT_IS_READY);
#ifdef DEBUG
	xil_printf("\nXQspiPsu_TXSetup\r\n");
#endif
	InstancePtr->TxBytes = (s32)Msg->ByteCount;
	InstancePtr->SendBufferPtr = Msg->TxBfrPtr;

	XQspiPsu_FillTxFifo(InstancePtr, Msg, (u32)XQSPIPSU_TXD_DEPTH);
}

/*****************************************************************************/
/**
 *
 * This function sets up the RX DMA operation.
 *
 * @param	InstancePtr is a pointer to the XQspiPsu instance.
 * @param	Msg is a pointer to the structure containing transfer data.
 *
 * @return	None
 *
 * @note	None.
 *
 ******************************************************************************/
void XQspiPsu_SetupRxDma(const XQspiPsu *InstancePtr,
						 XQspiPsu_Msg *Msg)
{
	s32 Remainder;
	s32 DmaRxBytes;
	UINTPTR AddrTemp;

	Xil_AssertVoid(InstancePtr != NULL);
	Xil_AssertVoid(Msg != NULL);
	Xil_AssertVoid(InstancePtr->IsReady == XIL_COMPONENT_IS_READY);
#ifdef DEBUG
	xil_printf("\nXQspiPsu_SetupRxDma\r\n");
#endif

	AddrTemp = ((UINTPTR)(Msg->RxBfrPtr) & XQSPIPSU_QSPIDMA_DST_ADDR_MASK);
	/* Check for RXBfrPtr to be word aligned */
	XQspiPsu_WriteReg(InstancePtr->Config.BaseAddress,
					  XQSPIPSU_QSPIDMA_DST_ADDR_OFFSET, (u32)AddrTemp);

	// #if defined(__aarch64__) || defined(__arch64__)
	AddrTemp = ((UINTPTR)(Msg->RxBfrPtr) >> 32U);
	XQspiPsu_WriteReg(InstancePtr->Config.BaseAddress,
					  XQSPIPSU_QSPIDMA_DST_ADDR_MSB_OFFSET, (u32)AddrTemp & XQSPIPSU_QSPIDMA_DST_ADDR_MSB_MASK);
	// #else
	//	XQspiPsu_WriteReg(InstancePtr->Config.BaseAddress,
	//			XQSPIPSU_QSPIDMA_DST_ADDR_MSB_OFFSET, 0U);
	// #endif

	Remainder = InstancePtr->RxBytes % 4;
	DmaRxBytes = InstancePtr->RxBytes;
	if (Remainder != 0)
	{
		/* This is done to make Dma bytes aligned */
		DmaRxBytes = InstancePtr->RxBytes - Remainder;
		Msg->ByteCount = (u32)DmaRxBytes;
	}
	if (InstancePtr->Config.IsCacheCoherent == 0U)
		// Xil_DCacheInvalidateRange((INTPTR)Msg->RxBfrPtr, Msg->ByteCount);

		/* Write no. of words to DMA DST SIZE */
		XQspiPsu_WriteReg(InstancePtr->Config.BaseAddress,
						  XQSPIPSU_QSPIDMA_DST_SIZE_OFFSET, (u32)DmaRxBytes);
}

/*****************************************************************************/
/**
 *
 * This function sets up the RX DMA operation on a 32bit Machine
 * For 64bit Dma transfers..
 *
 * @param	InstancePtr is a pointer to the XQspiPsu instance.
 * @param	Msg is a pointer to the structure containing transfer data.
 *
 * @return	None
 *
 * @note	None.
 *
 ******************************************************************************/
void XQspiPsu_Setup64BRxDma(const XQspiPsu *InstancePtr,
							XQspiPsu_Msg *Msg)
{
	s32 Remainder;
	s32 DmaRxBytes;
	u64 AddrTemp;

	Xil_AssertVoid(InstancePtr != NULL);
	Xil_AssertVoid(Msg != NULL);
	Xil_AssertVoid(InstancePtr->IsReady == XIL_COMPONENT_IS_READY);
#ifdef DEBUG
	xil_printf("\nXQspiPsu_Setup64BRxDma\r\n");
#endif
	AddrTemp = Msg->RxAddr64bit & XQSPIPSU_QSPIDMA_DST_ADDR_MASK;

	XQspiPsu_WriteReg(InstancePtr->Config.BaseAddress,
					  XQSPIPSU_QSPIDMA_DST_ADDR_OFFSET, (u32)AddrTemp);

	AddrTemp = (Msg->RxAddr64bit >> 32);
	XQspiPsu_WriteReg(InstancePtr->Config.BaseAddress,
					  XQSPIPSU_QSPIDMA_DST_ADDR_MSB_OFFSET, (u32)AddrTemp & XQSPIPSU_QSPIDMA_DST_ADDR_MSB_MASK);

	Remainder = InstancePtr->RxBytes % 4;
	DmaRxBytes = InstancePtr->RxBytes;
	if (Remainder != 0)
	{
		/* This is done to make Dma bytes aligned */
		DmaRxBytes = InstancePtr->RxBytes - Remainder;
		Msg->ByteCount = (u32)DmaRxBytes;
	}

	/* Write no. of words to DMA DST SIZE */
	XQspiPsu_WriteReg(InstancePtr->Config.BaseAddress,
					  XQSPIPSU_QSPIDMA_DST_SIZE_OFFSET, (u32)DmaRxBytes);
}

/*****************************************************************************/
/**
 *
 * This function reads remaining bytes, after the completion of a DMA transfer,
 * using IO mode
 *
 * @param	InstancePtr is a pointer to the XQspiPsu instance.
 * @param	Msg is a pointer to the structure containing transfer data.
 *
 * @return
 *		- XST_SUCCESS if successful.
 *		- XST_FAILURE if transfer fails.
 *		- XST_DEVICE_BUSY if a transfer is already in progress.
 *
 * @note	None.
 *
 ******************************************************************************/
u32 XQspiPsu_SetIOMode(XQspiPsu *InstancePtr, XQspiPsu_Msg *Msg)
{
	Xil_AssertNonvoid(InstancePtr != NULL);
	Xil_AssertNonvoid(Msg != NULL);
	Xil_AssertNonvoid(InstancePtr->IsReady == XIL_COMPONENT_IS_READY);
#ifdef DEBUG
	xil_printf("\nXQspiPsu_DMARXComplete\r\n");
#endif

	/* Read remaining bytes using IO mode */
	if ((InstancePtr->RxBytes % 4) != 0)
	{
		XQspiPsu_WriteReg(InstancePtr->Config.BaseAddress, XQSPIPSU_CFG_OFFSET,
						  (XQspiPsu_ReadReg(InstancePtr->Config.BaseAddress, XQSPIPSU_CFG_OFFSET) &
						   ~XQSPIPSU_CFG_MODE_EN_MASK));
		InstancePtr->ReadMode = XQSPIPSU_READMODE_IO;
		Msg->ByteCount = (InstancePtr->RxBytes % 4);
		Msg->RxBfrPtr += (InstancePtr->RxBytes - (InstancePtr->RxBytes % 4));
		InstancePtr->IsUnaligned = 1;
		return (u32)TRUE;
	}
	return (u32)FALSE;
}

/*****************************************************************************/
/**
 *
 * This function checks the RX buffers in the message and setup the
 * RX DMA as required.
 *
 * @param	InstancePtr is a pointer to the XQspiPsu instance.
 * @param	Msg is a pointer to the structure containing transfer data.
 *
 * @return	None
 *
 * @note	None.
 *
 ******************************************************************************/
void XQspiPsu_RXSetup(XQspiPsu *InstancePtr, XQspiPsu_Msg *Msg)
{
	Xil_AssertVoid(InstancePtr != NULL);
	Xil_AssertVoid(Msg != NULL);
	Xil_AssertVoid(InstancePtr->IsReady == XIL_COMPONENT_IS_READY);
#ifdef DEBUG
	xil_printf("\nXQspiPsu_RXSetup\r\n");
#endif
	InstancePtr->RxBytes = (s32)Msg->ByteCount;

	if (((Msg->RxAddr64bit >= XQSPIPSU_RXADDR_OVER_32BIT) ||
		 (Msg->Xfer64bit != (u8)0U)) &&
		(InstancePtr->ReadMode == XQSPIPSU_READMODE_DMA))
		XQspiPsu_Setup64BRxDma(InstancePtr, Msg);
	else if (InstancePtr->ReadMode == XQSPIPSU_READMODE_DMA)
		XQspiPsu_SetupRxDma(InstancePtr, Msg);
}

/*****************************************************************************/
/**
 *
 * This function checks the TX/RX buffers in the message and setups up the
 * GENFIFO entries, TX FIFO or RX DMA as required.
 *
 * @param	InstancePtr is a pointer to the XQspiPsu instance.
 * @param	Msg is a pointer to the structure containing transfer data.
 * @param	GenFifoEntry is pointer to the variable in which GENFIFO mask
 *		is returned to calling function
 *
 * @return	None
 *
 * @note	None.
 *
 ******************************************************************************/
void XQspiPsu_TXRXSetup(XQspiPsu *InstancePtr, XQspiPsu_Msg *Msg,
						u32 *GenFifoEntry)
{
	Xil_AssertVoid(InstancePtr != NULL);
	Xil_AssertVoid(Msg != NULL);
	Xil_AssertVoid(GenFifoEntry != NULL);
	Xil_AssertVoid(InstancePtr->IsReady == XIL_COMPONENT_IS_READY);
#ifdef DEBUG
	xil_printf("\nXQspiPsu_TXRXSetup\r\n");
#endif
	/* Transmit */
	if (((Msg->Flags & XQSPIPSU_MSG_FLAG_TX) != FALSE) &&
		((Msg->Flags & XQSPIPSU_MSG_FLAG_RX) == FALSE))
	{

		*GenFifoEntry |= XQSPIPSU_GENFIFO_DATA_XFER;
		*GenFifoEntry |= XQSPIPSU_GENFIFO_TX;
		/* Discard RX data */
		*GenFifoEntry &= ~XQSPIPSU_GENFIFO_RX;

		/* Setup data to be TXed */
		XQspiPsu_TXSetup(InstancePtr, Msg);

		InstancePtr->RecvBufferPtr = NULL;
		InstancePtr->RxBytes = 0;
	}
	/*Receive*/
	if (((Msg->Flags & XQSPIPSU_MSG_FLAG_RX) != FALSE) &&
		((Msg->Flags & XQSPIPSU_MSG_FLAG_TX) == FALSE))
	{

		/* TX auto fill */
		*GenFifoEntry &= ~XQSPIPSU_GENFIFO_TX;
		/* Setup RX */
		*GenFifoEntry |= XQSPIPSU_GENFIFO_DATA_XFER;
		*GenFifoEntry |= XQSPIPSU_GENFIFO_RX;

		/* Setup DMA for data to be RXed */
		XQspiPsu_RXSetup(InstancePtr, Msg);

		InstancePtr->SendBufferPtr = NULL;
		InstancePtr->TxBytes = 0;
	}
	/* If only dummy is requested as a separate entry */
	if (((Msg->Flags & XQSPIPSU_MSG_FLAG_TX) == FALSE) &&
		((Msg->Flags & XQSPIPSU_MSG_FLAG_RX) == FALSE))
	{

		*GenFifoEntry |= XQSPIPSU_GENFIFO_DATA_XFER;
		*GenFifoEntry &= ~(XQSPIPSU_GENFIFO_TX | XQSPIPSU_GENFIFO_RX);
		InstancePtr->TxBytes = 0;
		InstancePtr->RxBytes = 0;
		InstancePtr->SendBufferPtr = NULL;
		InstancePtr->RecvBufferPtr = NULL;
	}
	/* Dummy and cmd sent by upper layer to received data */
	if (((Msg->Flags & XQSPIPSU_MSG_FLAG_TX) != FALSE) &&
		((Msg->Flags & XQSPIPSU_MSG_FLAG_RX) != FALSE))
	{
		*GenFifoEntry |= XQSPIPSU_GENFIFO_DATA_XFER;
		*GenFifoEntry |= (XQSPIPSU_GENFIFO_TX | XQSPIPSU_GENFIFO_RX);

		/* Setup data to be TXed */
		XQspiPsu_TXSetup(InstancePtr, Msg);
		/* Setup DMA for data to be RXed */
		XQspiPsu_RXSetup(InstancePtr, Msg);
	}
}
/*****************************************************************************/
/**
 *
 * This function writes the Data length to GENFIFO entries that need to be
 * transmitted or received.
 *
 * @param	InstancePtr is a pointer to the XQspiPsu instance.
 * @param	Msg is a pointer to the structure containing transfer data.
 * @param	Index of the current message to be handled.
 *
 * @return
 *		- XST_SUCCESS if successful.
 *		- XST_FAILURE if transfer fails.
 *		- XST_DEVICE_BUSY if a transfer is already in progress.
 *
 * @note	None.
 *
 ******************************************************************************/
void XQspiPsu_GenFifoEntryDataLen(XQspiPsu *InstancePtr, XQspiPsu_Msg *Msg,
								  u32 *GenFifoEntry)
{
	u32 TempCount;
	u32 ImmData;

	Xil_AssertVoid(InstancePtr != NULL);
	Xil_AssertVoid(Msg != NULL);
	Xil_AssertVoid(GenFifoEntry != NULL);
	Xil_AssertVoid(InstancePtr->IsReady == XIL_COMPONENT_IS_READY);
#ifdef DEBUG
	xil_printf("\nXQspiPsu_GenFifoEntryDataLen\r\n");
#endif

	if (Msg->ByteCount <= XQSPIPSU_GENFIFO_IMM_DATA_MASK)
	{
		*GenFifoEntry &= (u32)(~XQSPIPSU_GENFIFO_IMM_DATA_MASK);
		*GenFifoEntry |= Msg->ByteCount;
#ifdef DEBUG
		xil_printf("\nFifoEntry=%08x\r\n", GenFifoEntry);
#endif
		XQspiPsu_WriteReg(InstancePtr->Config.BaseAddress, XQSPIPSU_GEN_FIFO_OFFSET,
						  *GenFifoEntry);
	}
	else
	{
		TempCount = Msg->ByteCount;
		u32 Exponent = 8; /* 2^8 = 256 */
		ImmData = TempCount & 0xFFU;
		/* Exponent entries */
		*GenFifoEntry |= XQSPIPSU_GENFIFO_EXP;
		while (TempCount != 0U)
		{
			if ((TempCount & XQSPIPSU_GENFIFO_EXP_START) != FALSE)
			{
				*GenFifoEntry &= (u32)(~XQSPIPSU_GENFIFO_IMM_DATA_MASK);
				*GenFifoEntry |= Exponent;
#ifdef DEBUG
				xil_printf("\nFifoEntry=%08x\r\n",
						   *GenFifoEntry);
#endif
				XQspiPsu_WriteReg(InstancePtr->Config.BaseAddress, XQSPIPSU_GEN_FIFO_OFFSET,
								  *GenFifoEntry);
			}
			TempCount = TempCount >> 1;
			Exponent++;
		}
		/* Immediate entry */
		*GenFifoEntry &= (u32)(~XQSPIPSU_GENFIFO_EXP);
		if ((ImmData & 0xFFU) != FALSE)
		{
			*GenFifoEntry &= (u32)(~XQSPIPSU_GENFIFO_IMM_DATA_MASK);
			*GenFifoEntry |= ImmData & 0xFFU;
#ifdef DEBUG
			xil_printf("\nFifoEntry=%08x\r\n", GenFifoEntry);
#endif
			XQspiPsu_WriteReg(InstancePtr->Config.BaseAddress, XQSPIPSU_GEN_FIFO_OFFSET,
							  *GenFifoEntry);
		}
	}
}

/*****************************************************************************/
/**
 *
 * This function creates Poll config register data to write
 *
 * @param	BusMask is mask to enable/disable upper/lower data bus masks.
 *
 * @param	DataBusMask is Data bus mask value during poll operation.
 *
 * @param	Data is the poll data value to write into config register.
 *
 * @return	None
 *
 * @note	None.
 *
 ******************************************************************************/
u32 XQspiPsu_CreatePollDataConfig(const XQspiPsu *InstancePtr,
								  const XQspiPsu_Msg *FlashMsg)
{
	u32 ConfigData = 0;

	Xil_AssertNonvoid(InstancePtr != NULL);
	Xil_AssertNonvoid(FlashMsg != NULL);
	Xil_AssertNonvoid(InstancePtr->IsReady == XIL_COMPONENT_IS_READY);
#ifdef DEBUG
	xil_printf("\nXQspiPsu_CreatePollDataConfig\r\n");
#endif

	if ((InstancePtr->GenFifoBus & XQSPIPSU_GENFIFO_BUS_UPPER) != FALSE)
		ConfigData = XQSPIPSU_SELECT_FLASH_BUS_LOWER << XQSPIPSU_POLL_CFG_EN_MASK_UPPER_SHIFT;
	if ((InstancePtr->GenFifoBus & XQSPIPSU_GENFIFO_BUS_LOWER) != FALSE)
		ConfigData |= XQSPIPSU_SELECT_FLASH_BUS_LOWER << XQSPIPSU_POLL_CFG_EN_MASK_LOWER_SHIFT;
	ConfigData |= (u32)(((u32)FlashMsg->PollBusMask << XQSPIPSU_POLL_CFG_MASK_EN_SHIFT) & XQSPIPSU_POLL_CFG_MASK_EN_MASK);
	ConfigData |= (u32)(((u32)FlashMsg->PollData << XQSPIPSU_POLL_CFG_DATA_VALUE_SHIFT) & XQSPIPSU_POLL_CFG_DATA_VALUE_MASK);
	return ConfigData;
}

/*****************************************************************************/
/**
 *
 * Selects SPI mode - x1 or x2 or x4.
 *
 * @param	SpiMode - spi or dual or quad.
 * @return	Mask to set desired SPI mode in GENFIFO entry.
 *
 * @note	None.
 *
 ******************************************************************************/
u32 XQspiPsu_SelectSpiMode(u8 SpiMode)
{
	u32 Mask;

	Xil_AssertNonvoid(SpiMode > 0);
#ifdef DEBUG
	xil_printf("\nXQspiPsu_SelectSpiMode\r\n");
#endif

	switch (SpiMode)
	{
	case XQSPIPSU_SELECT_MODE_DUALSPI:
		Mask = XQSPIPSU_GENFIFO_MODE_DUALSPI;
		break;
	case XQSPIPSU_SELECT_MODE_QUADSPI:
		Mask = XQSPIPSU_GENFIFO_MODE_QUADSPI;
		break;
	case XQSPIPSU_SELECT_MODE_SPI:
		Mask = XQSPIPSU_GENFIFO_MODE_SPI;
		break;
	default:
		Mask = XQSPIPSU_GENFIFO_MODE_SPI;
		break;
	}
#ifdef DEBUG
	xil_printf("\nSPIMode is %08x\r\n", SpiMode);
#endif
	return Mask;
}

/*****************************************************************************/
/**
 *
 * Enable and initialize DMA Mode, set little endain, disable poll timeout,
 * clear prescalar bits and reset thresholds
 *
 * @param	InstancePtr is a pointer to the XQspiPsu instance.
 *
 * @return	None.
 *
 * @note	None.
 *
 ******************************************************************************/
void XQspiPsu_SetDefaultConfig(XQspiPsu *InstancePtr)
{
	u32 ConfigReg;

	Xil_AssertVoid(InstancePtr != NULL);
#ifdef DEBUG
	xil_printf("\nXQspiPsu_SetDefaultConfig\r\n");
#endif

	/* Default value to config register */
	ConfigReg = XQspiPsu_ReadReg(InstancePtr->Config.BaseAddress,
								 XQSPIPSU_CFG_OFFSET);

	/* DMA mode */
	ConfigReg &= ~XQSPIPSU_CFG_MODE_EN_MASK;
	ConfigReg |= XQSPIPSU_CFG_MODE_EN_DMA_MASK;
	/* Manual start */
	ConfigReg |= XQSPIPSU_CFG_GEN_FIFO_START_MODE_MASK;
	/* Little endain by default */
	ConfigReg &= ~XQSPIPSU_CFG_ENDIAN_MASK;
	/* Disable poll timeout */
	ConfigReg &= ~XQSPIPSU_CFG_EN_POLL_TO_MASK;
	/* Set hold bit */
	ConfigReg |= XQSPIPSU_CFG_WP_HOLD_MASK;
	/* Clear prescalar by default */
	ConfigReg &= (u32)(~XQSPIPSU_CFG_BAUD_RATE_DIV_MASK);
	/* CPOL CPHA 00 */
	ConfigReg &= (u32)(~XQSPIPSU_CFG_CLK_PHA_MASK);
	ConfigReg &= (u32)(~XQSPIPSU_CFG_CLK_POL_MASK);

	XQspiPsu_WriteReg(InstancePtr->Config.BaseAddress,
					  XQSPIPSU_CFG_OFFSET, ConfigReg);

	/* Set by default to allow for high frequencies */
	XQspiPsu_WriteReg(InstancePtr->Config.BaseAddress,
					  XQSPIPSU_LPBK_DLY_ADJ_OFFSET,
					  XQspiPsu_ReadReg(InstancePtr->Config.BaseAddress,
									   XQSPIPSU_LPBK_DLY_ADJ_OFFSET) |
						  XQSPIPSU_LPBK_DLY_ADJ_USE_LPBK_MASK);

	/* Reset thresholds */
	XQspiPsu_WriteReg(InstancePtr->Config.BaseAddress,
					  XQSPIPSU_TX_THRESHOLD_OFFSET, XQSPIPSU_TX_FIFO_THRESHOLD_RESET_VAL);
	XQspiPsu_WriteReg(InstancePtr->Config.BaseAddress,
					  XQSPIPSU_RX_THRESHOLD_OFFSET, XQSPIPSU_RX_FIFO_THRESHOLD_RESET_VAL);
	XQspiPsu_WriteReg(InstancePtr->Config.BaseAddress,
					  XQSPIPSU_GF_THRESHOLD_OFFSET, XQSPIPSU_GEN_FIFO_THRESHOLD_RESET_VAL);

	/* DMA init */
	XQspiPsu_WriteReg(InstancePtr->Config.BaseAddress,
					  XQSPIPSU_QSPIDMA_DST_CTRL_OFFSET,
					  XQSPIPSU_QSPIDMA_DST_CTRL_RESET_VAL);
}

/*****************************************************************************/
/**
 *
 * Read the specified number of bytes from RX FIFO
 *
 * @param	InstancePtr is a pointer to the XQspiPsu instance.
 * @param	Msg is a pointer to the structure containing transfer data.
 * @param	Size is the number of bytes to be read.
 *
 * @return	None
 *
 * @note	None.
 *
 ******************************************************************************/
void XQspiPsu_ReadRxFifo(XQspiPsu *InstancePtr, XQspiPsu_Msg *Msg, s32 Size)
{
	s32 Count = 0;
	u32 Data;

	Xil_AssertVoid(InstancePtr != NULL);
	Xil_AssertVoid(Msg != NULL);
	Xil_AssertVoid(Size > 0);
	Xil_AssertVoid(InstancePtr->IsReady == XIL_COMPONENT_IS_READY);
#ifdef DEBUG
	xil_printf("\nXQspiPsu_ReadRxFifo\r\n");
#endif
	while ((InstancePtr->RxBytes != 0) && (Count < Size))
	{
		Data = XQspiPsu_ReadReg(InstancePtr->Config.BaseAddress,
								XQSPIPSU_RXD_OFFSET);
#ifdef DEBUG
		xil_printf("\nData is %08x\r\n", Data);
#endif
		// printf("\nData is %08x\r\n", Data);
		if (InstancePtr->RxBytes >= 4)
		{
			(void)memcpy(Msg->RxBfrPtr, (u8 *)&Data, 4);
			InstancePtr->RxBytes -= 4;
			Msg->RxBfrPtr += 4;
			Count += 4;
		}
		else
		{
			/* Read unaligned bytes (< 4 bytes) */
			(void)memcpy(Msg->RxBfrPtr, (u8 *)&Data,
						 (u32)InstancePtr->RxBytes);
			Msg->RxBfrPtr += InstancePtr->RxBytes;
			Count += InstancePtr->RxBytes;
			InstancePtr->RxBytes = 0;
		}
	}
}

/*****************************************************************************/
/**
 *
 * This function reads data from RXFifo in IO mode.
 *
 * @param	InstancePtr is a pointer to the XQspiPsu instance.
 * @param	Msg is a pointer to the structure containing transfer data.
 * @param	StatusReg is the Interrupt status Register value.
 *
 * @return	None.
 *
 * @note	None.
 *
 ******************************************************************************/
void XQspiPsu_IORead(XQspiPsu *InstancePtr, XQspiPsu_Msg *Msg,
					 u32 StatusReg)
{
	s32 RxThr;

	Xil_AssertVoid(InstancePtr != NULL);
	Xil_AssertVoid(Msg != NULL);
	Xil_AssertVoid(InstancePtr->IsReady == XIL_COMPONENT_IS_READY);
#ifdef DEBUG
	xil_printf("\nXQspiPsu_IORXComplete\r\n");
#endif

	if ((StatusReg & XQSPIPSU_ISR_RXNEMPTY_MASK) != 0U)
	{
		/*
		 * Check if PIO RX is complete and
		 * update RxBytes
		 */
		RxThr = (s32)XQspiPsu_ReadReg(InstancePtr->Config.BaseAddress,
									  XQSPIPSU_RX_THRESHOLD_OFFSET);
		RxThr = RxThr * 4;
		XQspiPsu_ReadRxFifo(InstancePtr, Msg, RxThr);
	}
	else if ((StatusReg & XQSPIPSU_ISR_GENFIFOEMPTY_MASK) != 0U)
	{
		XQspiPsu_ReadRxFifo(InstancePtr, Msg, InstancePtr->RxBytes);
	}
}

#if defined(ARMR5) || (__aarch64__)
/*****************************************************************************/
/**
 *
 * This function sets the Tapdelay values for the QSPIPSU device driver.The device
 * must be idle rather than busy transferring data before setting Tapdelay.
 *
 * @param	InstancePtr is a pointer to the XQspiPsu instance.
 * @param	TapdelayBypss contains the IOU_TAPDLY_BYPASS register value.
 * @param	LPBKDelay contains the GQSPI_LPBK_DLY_ADJ register value.
 * @param	Datadelay contains the QSPI_DATA_DLY_ADJ register value.
 *
 * @return
 *		- XST_SUCCESS if options are successfully set.
 *		- XST_DEVICE_BUSY if the device is currently transferring data.
 *		The transfer must complete or be aborted before setting TapDelay.
 *
 * @note
 * This function is not thread-safe.
 *
 ******************************************************************************/
s32 XQspipsu_Set_TapDelay(const XQspiPsu *InstancePtr, u32 TapdelayBypass,
						  u32 LPBKDelay, u32 Datadelay)
{
	s32 Status;

	Xil_AssertNonvoid(InstancePtr != NULL);
	Xil_AssertNonvoid(InstancePtr->IsReady == XIL_COMPONENT_IS_READY);

	/*
	 * Do not allow to modify the Control Register while a transfer is in
	 * progress. Not thread-safe.
	 */
	if (InstancePtr->IsBusy == TRUE)
	{
		Status = XST_DEVICE_BUSY;
	}
	else
	{
#if EL1_NONSECURE && defined(__aarch64__) && !defined(versal)
		Xil_Smc(MMIO_WRITE_SMC_FID, (u64)(XPS_SYS_CTRL_BASEADDR + IOU_TAPDLY_BYPASS_OFFSET) | ((u64)(0x4) << 32),
				(u64)TapdelayBypass, 0, 0, 0, 0, 0);
#elif defined(versal)
		XQspiPsu_WriteReg(XQSPIPS_BASEADDR, IOU_TAPDLY_BYPASS_OFFSET,
						  TapdelayBypass);
#else
		XQspiPsu_WriteReg(XPS_SYS_CTRL_BASEADDR, IOU_TAPDLY_BYPASS_OFFSET,
						  TapdelayBypass);
#endif
		XQspiPsu_WriteReg(InstancePtr->Config.BaseAddress,
						  XQSPIPSU_LPBK_DLY_ADJ_OFFSET, LPBKDelay);
		XQspiPsu_WriteReg(InstancePtr->Config.BaseAddress,
						  XQSPIPSU_DATA_DLY_ADJ_OFFSET, Datadelay);

		Status = XST_SUCCESS;
	}
	return Status;
}
#endif
