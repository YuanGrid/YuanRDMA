#include "xqspi_polled.h"
#include "main.h"

u8 ReadCmd;
u8 WriteCmd;
u8 StatusCmd;
u8 SectorEraseCmd;
u8 FSRFlag;

/************************** Variable Definitions *****************************/
u8 TxBfrPtr;
u8 ReadBfrPtr[3];
FlashInfo Flash_Config_Table[] = {
	{SECTOR_SIZE_64K, NUM_OF_SECTORS128, BYTES256_PER_PAGE,
	 0x8000, 0x800000, SPANSION_ID_BYTE0,
	 SPANSION_ID_BYTE2_64, 0xFFFF0000, 1}};

u32 FlashMake;
u32 FCTIndex; // 闪存配置表的索引

// QSPI实例
XQspiPsu QspiPsuInstance;

static XQspiPsu_Msg FlashMsg[5];

// 测试变量 用于产生发送数据
int Test = 1;

// 用于存储读写数据的变量
//static u8 ReadBuffer[(PAGE_COUNT * MAX_PAGE_SIZE) + (DATA_OFFSET + DUMMY_SIZE) * 8] __attribute__((aligned(64)));
//static u8 WriteBuffer[(PAGE_COUNT * MAX_PAGE_SIZE) + DATA_OFFSET];
u8 CmdBfr[8];

u32 MaxData = PAGE_COUNT * 256;

XQspiPsu_Config *QspiPsuConfig;

int Qspi_Flash_init(XQspiPsu *QspiPsuInstancePtr, u16 QspiPsuDeviceId)
{
	//int ReadBfrSize;

	//ReadBfrSize = (PAGE_COUNT * MAX_PAGE_SIZE) +
	//			  (DATA_OFFSET + DUMMY_SIZE) * 8;

	// 根据ID查找Qspi配置信息
	QspiPsuConfig = XQspiPsu_LookupConfig(QspiPsuDeviceId);
	if (QspiPsuConfig == NULL)
	{
		return XST_FAILURE;
	}

	// 初始化Qspi
    //printf("BaseAddress=0x%08x\n",QspiPsuConfig->BaseAddress);
	XQspiPsu_CfgInitialize(QspiPsuInstancePtr, QspiPsuConfig,
						   QspiPsuConfig->BaseAddress);

	// 设置Options
	XQspiPsu_SetOptions(QspiPsuInstancePtr, XQSPIPSU_MANUAL_START_OPTION);

	// 为qspi时钟设置分频系数
	XQspiPsu_SetClkPrescaler(QspiPsuInstancePtr, XQSPIPSU_CLK_PRESCALE_8);

	XQspiPsu_SelectFlash(QspiPsuInstancePtr,
						 XQSPIPSU_SELECT_FLASH_CS_LOWER,
						 XQSPIPSU_SELECT_FLASH_BUS_LOWER);

	// 读Flash ID
	FlashReadID(QspiPsuInstancePtr);

	// 使能flash quad模式
	FlashEnableQuadMode(QspiPsuInstancePtr);

	return XST_SUCCESS;
}

int Qspi_Flash_erase(XQspiPsu *QspiPsuInstancePtr, u32 addr, int len)
{
	// Initialize MaxData according to page size.

	MaxData = ((len - 1) / Flash_Config_Table[FCTIndex].PageSize + 1) * Flash_Config_Table[FCTIndex].PageSize;

	// Address size and read command selection
	ReadCmd = QUAD_READ_CMD;
	WriteCmd = WRITE_CMD;
	SectorEraseCmd = SEC_ERASE_CMD;

	/* Status cmd - SR or FSR selection */
	if ((Flash_Config_Table[FCTIndex].NumDie > 1) &&
		(FlashMake == MICRON_ID_BYTE0))
	{
		StatusCmd = READ_FLAG_STATUS_CMD;
		FSRFlag = 1;
	}
	else
	{
		StatusCmd = READ_STATUS_CMD;
		FSRFlag = 0;
	}

	// 擦除flash
	// FlashErase(QspiPsuInstancePtr, addr, MaxData, CmdBfr);
	FlashErase(QspiPsuInstancePtr, addr, len, CmdBfr);

	return XST_SUCCESS;
}

// Flash
// 读写示例
int Qspi_Flash_update(XQspiPsu *QspiPsuInstancePtr, u32 address, u8 *src, u32 len)
{
	int page_count, remain;
	int Page;
	u8 *ptr = src;

	page_count = (len + Flash_Config_Table[FCTIndex].PageSize - 1) / Flash_Config_Table[FCTIndex].PageSize;
	remain = len % Flash_Config_Table[FCTIndex].PageSize;
    printf("zc-page_count=%d,remain=%d, len=%d,page_size=%d\n", page_count, remain, len, Flash_Config_Table[FCTIndex].PageSize);

	for (Page = 0; Page < page_count; Page++)
	{
		printf("program: %d%%\n", Page * 100 / page_count);
		printf("\033[A");
		printf("\033[K");
		if (Page != page_count - 1)
		{
			FlashWrite(QspiPsuInstancePtr,
					   (Page * Flash_Config_Table[FCTIndex].PageSize) + address,
					   Flash_Config_Table[FCTIndex].PageSize,
					   WriteCmd, ptr + (Page * Flash_Config_Table[FCTIndex].PageSize));
		}
		else
		{

			FlashWrite(QspiPsuInstancePtr,
					   (Page * Flash_Config_Table[FCTIndex].PageSize) + address,
					   remain,
					   WriteCmd, ptr + (Page * Flash_Config_Table[FCTIndex].PageSize));
		}
	}
	printf("program success.\n");
    return XST_SUCCESS;
}

int Qspi_Flash_read(XQspiPsu *QspiPsuInstancePtr, u32 address, u8 *readbuf, u32 len)
{
	u32 addr = address;
	u32 Count;

	// 读出的数据和写入的数据对比
	for (Count = 0; Count < len; Count++)
	{
		if (Count % 4 == 0)
		{
			FlashRead(QspiPsuInstancePtr, addr, 4, ReadCmd, CmdBfr, (readbuf+ Count));
			addr = addr + 4;
			// printf("%02x %02x %02x %02x\n", readbuf[Count], readbuf[Count+1], readbuf[Count+2], readbuf[Count+3]);
		}
	}

	return XST_SUCCESS;
}

int Qspi_Flash_verify(XQspiPsu *QspiPsuInstancePtr, u32 address, u8 *src, u32 len)
{
	u32 addr = address;
	u32 Count, i;
	u8 buf[1024];
	u8 *ptr = src;
    int remain_len = 0;

	// 读出的数据和写入的数据对比
	for (Count = 0; Count < len; Count++)
	{
		printf("verify: %d%%\n", Count * 100 / len);
		printf("\033[A");
		printf("\033[K");
		if (Count % 4 == 0)
		{
            remain_len = (len - Count >= 4) ? 4 : (len - Count);
			FlashRead(QspiPsuInstancePtr, addr, remain_len, ReadCmd, CmdBfr, buf);
			addr = addr + remain_len;
			for (i = 0; i < remain_len; i++)
			{
                // printf("ptr = 0x%02x,buf[%d]=0x%02x\n", *ptr, i, buf[i]);
				if (*ptr++ != buf[i])
				{
					printf(" verify error pos:%d\n", Count);
					return -1;
				}

			}
			// printf("%2x %2x %2x %2x\n", readbuf[0], readbuf[1], readbuf[2], readbuf[3]);
		}
	}

	printf("verify success.\n");
	return XST_SUCCESS;
}

// 读flash ID,并为flash配置表FCT分配序号
int FlashReadID(XQspiPsu *QspiPsuPtr)
{
	int Status;

	// 读flash ID
	TxBfrPtr = READ_ID;
	FlashMsg[0].TxBfrPtr = &TxBfrPtr;
	FlashMsg[0].RxBfrPtr = NULL;
	FlashMsg[0].ByteCount = 1;
	FlashMsg[0].BusWidth = XQSPIPSU_SELECT_MODE_SPI;
	FlashMsg[0].Flags = XQSPIPSU_MSG_FLAG_TX;

	FlashMsg[1].TxBfrPtr = NULL;
	FlashMsg[1].RxBfrPtr = ReadBfrPtr;
	FlashMsg[1].ByteCount = 3;
	FlashMsg[1].BusWidth = XQSPIPSU_SELECT_MODE_SPI;
	FlashMsg[1].Flags = XQSPIPSU_MSG_FLAG_RX;

	Status = XQspiPsu_PolledTransfer(QspiPsuPtr, FlashMsg, 2);
	if (Status != XST_SUCCESS)
	{
		return XST_FAILURE;
	}

	xil_printf("FlashID:%x%x%x\n\r", ReadBfrPtr[0], ReadBfrPtr[1],
			   ReadBfrPtr[2]);

	// 确定flash制造商
	if (ReadBfrPtr[0] == WINBOND_ID_BYTE0)
	{
		FlashMake = WINBOND_ID_BYTE0;
	}

	FCTIndex = 0;

	return XST_SUCCESS;
}

// flash 写函数
int FlashWrite(XQspiPsu *QspiPsuPtr, u32 Address, u32 ByteCount, u8 Command,
			   u8 *WriteBfrPtr)
{
	u8 WriteEnableCmd;
	u8 ReadStatusCmd;
	u8 FlashStatus[2];
	u8 WriteCmd[5];
	u32 RealAddr;
	u32 CmdByteCount;
	int Status;

	WriteEnableCmd = WRITE_ENABLE_CMD;
	/*
	 * Translate address based on type of connection
	 * If stacked assert the slave select based on address
	 */
	RealAddr = GetRealAddr(QspiPsuPtr, Address);

	/*
	 * Send the write enable command to the Flash so that it can be
	 * written to, this needs to be sent as a separate transfer before
	 * the write
	 */
	FlashMsg[0].TxBfrPtr = &WriteEnableCmd;
	FlashMsg[0].RxBfrPtr = NULL;
	FlashMsg[0].ByteCount = 1;
	FlashMsg[0].BusWidth = XQSPIPSU_SELECT_MODE_SPI;
	FlashMsg[0].Flags = XQSPIPSU_MSG_FLAG_TX;

	Status = XQspiPsu_PolledTransfer(QspiPsuPtr, FlashMsg, 1);
	if (Status != XST_SUCCESS)
	{
		return XST_FAILURE;
	}

	WriteCmd[COMMAND_OFFSET] = Command;

	/* To be used only if 4B address program cmd is supported by flash */
	if (Flash_Config_Table[FCTIndex].FlashDeviceSize > SIXTEENMB)
	{
		WriteCmd[ADDRESS_1_OFFSET] =
			(u8)((RealAddr & 0xFF000000) >> 24);
		WriteCmd[ADDRESS_2_OFFSET] =
			(u8)((RealAddr & 0xFF0000) >> 16);
		WriteCmd[ADDRESS_3_OFFSET] =
			(u8)((RealAddr & 0xFF00) >> 8);
		WriteCmd[ADDRESS_4_OFFSET] =
			(u8)(RealAddr & 0xFF);
		CmdByteCount = 5;
	}
	else
	{
		WriteCmd[ADDRESS_1_OFFSET] =
			(u8)((RealAddr & 0xFF0000) >> 16);
		WriteCmd[ADDRESS_2_OFFSET] =
			(u8)((RealAddr & 0xFF00) >> 8);
		WriteCmd[ADDRESS_3_OFFSET] =
			(u8)(RealAddr & 0xFF);
		CmdByteCount = 4;
	}

	FlashMsg[0].TxBfrPtr = WriteCmd;
	FlashMsg[0].RxBfrPtr = NULL;
	FlashMsg[0].ByteCount = CmdByteCount;
	FlashMsg[0].BusWidth = XQSPIPSU_SELECT_MODE_SPI;
	FlashMsg[0].Flags = XQSPIPSU_MSG_FLAG_TX;

	FlashMsg[1].TxBfrPtr = WriteBfrPtr;
	FlashMsg[1].RxBfrPtr = NULL;
	FlashMsg[1].ByteCount = ByteCount;
	FlashMsg[1].BusWidth = XQSPIPSU_SELECT_MODE_SPI;
	FlashMsg[1].Flags = XQSPIPSU_MSG_FLAG_TX;
	if (QspiPsuPtr->Config.ConnectionMode ==
		XQSPIPSU_CONNECTION_MODE_PARALLEL)
	{
		FlashMsg[1].Flags |= XQSPIPSU_MSG_FLAG_STRIPE;
	}

	Status = XQspiPsu_PolledTransfer(QspiPsuPtr, FlashMsg, 2);
	if (Status != XST_SUCCESS)
	{
		return XST_FAILURE;
	}

	/*
	 * Wait for the write command to the Flash to be completed, it takes
	 * some time for the data to be written
	 */
	while (1)
	{
		ReadStatusCmd = StatusCmd;
		FlashMsg[0].TxBfrPtr = &ReadStatusCmd;
		FlashMsg[0].RxBfrPtr = NULL;
		FlashMsg[0].ByteCount = 1;
		FlashMsg[0].BusWidth = XQSPIPSU_SELECT_MODE_SPI;
		FlashMsg[0].Flags = XQSPIPSU_MSG_FLAG_TX;

		FlashMsg[1].TxBfrPtr = NULL;
		FlashMsg[1].RxBfrPtr = FlashStatus;
		FlashMsg[1].ByteCount = 2;
		FlashMsg[1].BusWidth = XQSPIPSU_SELECT_MODE_SPI;
		FlashMsg[1].Flags = XQSPIPSU_MSG_FLAG_RX;
		if (QspiPsuPtr->Config.ConnectionMode ==
			XQSPIPSU_CONNECTION_MODE_PARALLEL)
		{
			FlashMsg[1].Flags |= XQSPIPSU_MSG_FLAG_STRIPE;
		}

		Status = XQspiPsu_PolledTransfer(QspiPsuPtr, FlashMsg, 2);
		if (Status != XST_SUCCESS)
		{
			return XST_FAILURE;
		}

		if (QspiPsuPtr->Config.ConnectionMode ==
			XQSPIPSU_CONNECTION_MODE_PARALLEL)
		{
			if (FSRFlag)
			{
				FlashStatus[1] &= FlashStatus[0];
			}
			else
			{
				FlashStatus[1] |= FlashStatus[0];
			}
		}

		if (FSRFlag)
		{
			if ((FlashStatus[1] & 0x80) != 0)
			{
				break;
			}
		}
		else
		{
			if ((FlashStatus[1] & 0x01) == 0)
			{
				break;
			}
		}
	}

	return 0;
}

/*****************************************************************************/
/**
 *
 * This function erases the sectors in the  serial Flash connected to the
 * QSPIPSU interface.
 *
 * @param	QspiPtr is a pointer to the QSPIPSU driver component to use.
 * @param	Address contains the address of the first sector which needs to
 *		be erased.
 * @param	ByteCount contains the total size to be erased.
 * @param	Pointer to the write buffer (which is to be transmitted)
 *
 * @return	XST_SUCCESS if successful, else XST_FAILURE.
 *
 * @note	None.
 *
 ******************************************************************************/
int FlashErase(XQspiPsu *QspiPsuPtr, u32 Address, u32 ByteCount,
			   u8 *WriteBfrPtr)
{
	u8 WriteEnableCmd;
	u8 ReadStatusCmd;
	u8 FlashStatus[2];
	int Sector;
	u32 RealAddr;
	u32 NumSect;
	int Status;

	WriteEnableCmd = WRITE_ENABLE_CMD;
	/*
	 * If erase size is same as the total size of the flash, use bulk erase
	 * command or die erase command multiple times as required
	 */
	if (ByteCount == ((Flash_Config_Table[FCTIndex]).NumSect *
					  (Flash_Config_Table[FCTIndex]).SectSize))
	{

		if (QspiPsuPtr->Config.ConnectionMode ==
			XQSPIPSU_CONNECTION_MODE_STACKED)
		{
			XQspiPsu_SelectFlash(QspiPsuPtr,
								 XQSPIPSU_SELECT_FLASH_CS_LOWER,
								 XQSPIPSU_SELECT_FLASH_BUS_LOWER);
		}

		if (Flash_Config_Table[FCTIndex].NumDie == 1)
		{
			/*
			 * Call Bulk erase
			 */
			BulkErase(QspiPsuPtr, WriteBfrPtr);
		}

		/*
		 * If stacked mode, bulk erase second flash
		 */
		if (QspiPsuPtr->Config.ConnectionMode ==
			XQSPIPSU_CONNECTION_MODE_STACKED)
		{

			XQspiPsu_SelectFlash(QspiPsuPtr,
								 XQSPIPSU_SELECT_FLASH_CS_UPPER,
								 XQSPIPSU_SELECT_FLASH_BUS_LOWER);

			if (Flash_Config_Table[FCTIndex].NumDie == 1)
			{
				/*
				 * Call Bulk erase
				 */
				BulkErase(QspiPsuPtr, WriteBfrPtr);
			}
		}

		return 0;
	}

	/*
	 * If the erase size is less than the total size of the flash, use
	 * sector erase command
	 */

	/*
	 * Calculate no. of sectors to erase based on byte count
	 */
	NumSect = ByteCount / (Flash_Config_Table[FCTIndex].SectSize) + 1;

	/*
	 * If ByteCount to k sectors,
	 * but the address range spans from N to N+k+1 sectors, then
	 * increment no. of sectors to be erased
	 */

	if (((Address + ByteCount) & Flash_Config_Table[FCTIndex].SectMask) ==
		((Address + (NumSect * Flash_Config_Table[FCTIndex].SectSize)) &
		 Flash_Config_Table[FCTIndex].SectMask))
	{
		NumSect++;
	}

	for (Sector = 0; Sector < NumSect; Sector++)
	{

		printf("erase: %d%%\n", Sector * 100 / NumSect);
		printf("\033[A");
		printf("\033[K");

		/*
		 * Translate address based on type of connection
		 * If stacked assert the slave select based on address
		 */
		RealAddr = GetRealAddr(QspiPsuPtr, Address);

		/*
		 * Send the write enable command to the Flash so that it can be
		 * written to, this needs to be sent as a separate
		 * transfer before the write
		 */
		FlashMsg[0].TxBfrPtr = &WriteEnableCmd;
		FlashMsg[0].RxBfrPtr = NULL;
		FlashMsg[0].ByteCount = 1;
		FlashMsg[0].BusWidth = XQSPIPSU_SELECT_MODE_SPI;
		FlashMsg[0].Flags = XQSPIPSU_MSG_FLAG_TX;

		Status = XQspiPsu_PolledTransfer(QspiPsuPtr, FlashMsg, 1);
		if (Status != XST_SUCCESS)
		{
			return XST_FAILURE;
		}

		WriteBfrPtr[COMMAND_OFFSET] = SectorEraseCmd;

		/*
		 * To be used only if 4B address sector erase cmd is
		 * supported by flash
		 */
		if (Flash_Config_Table[FCTIndex].FlashDeviceSize > SIXTEENMB)
		{
			WriteBfrPtr[ADDRESS_1_OFFSET] =
				(u8)((RealAddr & 0xFF000000) >> 24);
			WriteBfrPtr[ADDRESS_2_OFFSET] =
				(u8)((RealAddr & 0xFF0000) >> 16);
			WriteBfrPtr[ADDRESS_3_OFFSET] =
				(u8)((RealAddr & 0xFF00) >> 8);
			WriteBfrPtr[ADDRESS_4_OFFSET] =
				(u8)(RealAddr & 0xFF);
			FlashMsg[0].ByteCount = 5;
		}
		else
		{
			WriteBfrPtr[ADDRESS_1_OFFSET] =
				(u8)((RealAddr & 0xFF0000) >> 16);
			WriteBfrPtr[ADDRESS_2_OFFSET] =
				(u8)((RealAddr & 0xFF00) >> 8);
			WriteBfrPtr[ADDRESS_3_OFFSET] =
				(u8)(RealAddr & 0xFF);
			FlashMsg[0].ByteCount = 4;
		}

		FlashMsg[0].TxBfrPtr = WriteBfrPtr;
		FlashMsg[0].RxBfrPtr = NULL;
		FlashMsg[0].BusWidth = XQSPIPSU_SELECT_MODE_SPI;
		FlashMsg[0].Flags = XQSPIPSU_MSG_FLAG_TX;

		Status = XQspiPsu_PolledTransfer(QspiPsuPtr, FlashMsg, 1);
		if (Status != XST_SUCCESS)
		{
			return XST_FAILURE;
		}

		/*
		 * Wait for the erase command to be completed
		 */
		while (1)
		{
			ReadStatusCmd = StatusCmd;
			FlashMsg[0].TxBfrPtr = &ReadStatusCmd;
			FlashMsg[0].RxBfrPtr = NULL;
			FlashMsg[0].ByteCount = 1;
			FlashMsg[0].BusWidth = XQSPIPSU_SELECT_MODE_SPI;
			FlashMsg[0].Flags = XQSPIPSU_MSG_FLAG_TX;

			FlashMsg[1].TxBfrPtr = NULL;
			FlashMsg[1].RxBfrPtr = FlashStatus;
			FlashMsg[1].ByteCount = 2;
			FlashMsg[1].BusWidth = XQSPIPSU_SELECT_MODE_SPI;
			FlashMsg[1].Flags = XQSPIPSU_MSG_FLAG_RX;
			if (QspiPsuPtr->Config.ConnectionMode ==
				XQSPIPSU_CONNECTION_MODE_PARALLEL)
			{
				FlashMsg[1].Flags |= XQSPIPSU_MSG_FLAG_STRIPE;
			}

			Status = XQspiPsu_PolledTransfer(QspiPsuPtr,
											 FlashMsg, 2);
			if (Status != XST_SUCCESS)
			{
				return XST_FAILURE;
			}

			if (QspiPsuPtr->Config.ConnectionMode ==
				XQSPIPSU_CONNECTION_MODE_PARALLEL)
			{
				if (FSRFlag)
				{
					FlashStatus[1] &= FlashStatus[0];
				}
				else
				{
					FlashStatus[1] |= FlashStatus[0];
				}
			}

			if (FSRFlag)
			{
				if ((FlashStatus[1] & 0x80) != 0)
				{
					break;
				}
			}
			else
			{
				if ((FlashStatus[1] & 0x01) == 0)
				{
					break;
				}
			}
		}
		Address += Flash_Config_Table[FCTIndex].SectSize;
	}

	printf("erase success.\n");
	return 0;
}

// flash 读函数
int FlashRead(XQspiPsu *QspiPsuPtr, u32 Address, u32 ByteCount, u8 Command,
			  u8 *WriteBfrPtr, u8 *ReadBfrPtr)
{
	u32 RealAddr;
	u32 DiscardByteCnt;
	u32 FlashMsgCnt;
	int Status;
	// printf("address:0x%x count:%d\n", Address, ByteCount);

	if ((Flash_Config_Table[FCTIndex].NumDie = 1))
	{
		/* For Dual Stacked, split and read for boundary crossing */
		/*
		 * Translate address based on type of connection
		 * If stacked assert the slave select based on address
		 */
		RealAddr = GetRealAddr(QspiPsuPtr, Address);
		// printf("RealAddr:0x%x\n", RealAddr);

		WriteBfrPtr[COMMAND_OFFSET] = Command;
		if (Flash_Config_Table[FCTIndex].FlashDeviceSize > SIXTEENMB)
		{
			WriteBfrPtr[ADDRESS_1_OFFSET] =
				(u8)((RealAddr & 0xFF000000) >> 24);
			WriteBfrPtr[ADDRESS_2_OFFSET] =
				(u8)((RealAddr & 0xFF0000) >> 16);
			WriteBfrPtr[ADDRESS_3_OFFSET] =
				(u8)((RealAddr & 0xFF00) >> 8);
			WriteBfrPtr[ADDRESS_4_OFFSET] =
				(u8)(RealAddr & 0xFF);
			DiscardByteCnt = 5;
		}
		else
		{
			WriteBfrPtr[ADDRESS_1_OFFSET] =
				(u8)((RealAddr & 0xFF0000) >> 16);
			WriteBfrPtr[ADDRESS_2_OFFSET] =
				(u8)((RealAddr & 0xFF00) >> 8);
			WriteBfrPtr[ADDRESS_3_OFFSET] =
				(u8)(RealAddr & 0xFF);
			DiscardByteCnt = 4;
		}

		FlashMsg[0].TxBfrPtr = WriteBfrPtr;
		FlashMsg[0].RxBfrPtr = NULL;
		FlashMsg[0].ByteCount = DiscardByteCnt;
		FlashMsg[0].BusWidth = XQSPIPSU_SELECT_MODE_SPI;
		FlashMsg[0].Flags = XQSPIPSU_MSG_FLAG_TX;

		FlashMsgCnt = 1;

		/* It is recommended to have a separate entry for dummy */
		if (Command == FAST_READ_CMD || Command == DUAL_READ_CMD ||
			Command == QUAD_READ_CMD || Command == FAST_READ_CMD_4B ||
			Command == DUAL_READ_CMD_4B ||
			Command == QUAD_READ_CMD_4B)
		{
			/* Update Dummy cycles as per flash specs for QUAD IO */

			/*
			 * It is recommended that Bus width value during dummy
			 * phase should be same as data phase
			 */
			if (Command == FAST_READ_CMD ||
				Command == FAST_READ_CMD_4B)
				FlashMsg[1].BusWidth =
					XQSPIPSU_SELECT_MODE_SPI;

			if (Command == DUAL_READ_CMD ||
				Command == DUAL_READ_CMD_4B)
				FlashMsg[1].BusWidth =
					XQSPIPSU_SELECT_MODE_DUALSPI;

			if (Command == QUAD_READ_CMD ||
				Command == QUAD_READ_CMD_4B)
				FlashMsg[1].BusWidth =
					XQSPIPSU_SELECT_MODE_QUADSPI;

			FlashMsg[1].TxBfrPtr = NULL;
			FlashMsg[1].RxBfrPtr = NULL;
			FlashMsg[1].ByteCount = DUMMY_CLOCKS;
			FlashMsg[1].Flags = 0;

			FlashMsgCnt++;
		}

		if (Command == FAST_READ_CMD ||
			Command == FAST_READ_CMD_4B)
			FlashMsg[FlashMsgCnt].BusWidth =
				XQSPIPSU_SELECT_MODE_SPI;

		if (Command == DUAL_READ_CMD ||
			Command == DUAL_READ_CMD_4B)
			FlashMsg[FlashMsgCnt].BusWidth =
				XQSPIPSU_SELECT_MODE_DUALSPI;

		if (Command == QUAD_READ_CMD ||
			Command == QUAD_READ_CMD_4B)
			FlashMsg[FlashMsgCnt].BusWidth =
				XQSPIPSU_SELECT_MODE_QUADSPI;

		FlashMsg[FlashMsgCnt].TxBfrPtr = NULL;
		FlashMsg[FlashMsgCnt].RxBfrPtr = ReadBfrPtr;
		FlashMsg[FlashMsgCnt].ByteCount = ByteCount;
		FlashMsg[FlashMsgCnt].Flags = XQSPIPSU_MSG_FLAG_RX;

		if (QspiPsuPtr->Config.ConnectionMode ==
			XQSPIPSU_CONNECTION_MODE_PARALLEL)
			FlashMsg[FlashMsgCnt].Flags |=
				XQSPIPSU_MSG_FLAG_STRIPE;

		Status = XQspiPsu_PolledTransfer(QspiPsuPtr, FlashMsg,
										 FlashMsgCnt + 1);
		if (Status != XST_SUCCESS)
			return XST_FAILURE;
	}
	return 0;
}

// 当flash器件只有一个die时，执行批量擦除操作
int BulkErase(XQspiPsu *QspiPsuPtr, u8 *WriteBfrPtr)
{
	u8 WriteEnableCmd;
	u8 ReadStatusCmd;
	u8 FlashStatus[2];
	int Status;

	WriteEnableCmd = WRITE_ENABLE_CMD;
	/*
	 * Send the write enable command to the Flash so that it can be
	 * written to, this needs to be sent as a separate transfer before
	 * the write
	 */
	FlashMsg[0].TxBfrPtr = &WriteEnableCmd;
	FlashMsg[0].RxBfrPtr = NULL;
	FlashMsg[0].ByteCount = 1;
	FlashMsg[0].BusWidth = XQSPIPSU_SELECT_MODE_SPI;
	FlashMsg[0].Flags = XQSPIPSU_MSG_FLAG_TX;

	Status = XQspiPsu_PolledTransfer(QspiPsuPtr, FlashMsg, 1);
	if (Status != XST_SUCCESS)
	{
		return XST_FAILURE;
	}

	WriteBfrPtr[COMMAND_OFFSET] = BULK_ERASE_CMD;
	FlashMsg[0].TxBfrPtr = WriteBfrPtr;
	FlashMsg[0].RxBfrPtr = NULL;
	FlashMsg[0].ByteCount = 1;
	FlashMsg[0].BusWidth = XQSPIPSU_SELECT_MODE_SPI;
	FlashMsg[0].Flags = XQSPIPSU_MSG_FLAG_TX;

	Status = XQspiPsu_PolledTransfer(QspiPsuPtr, FlashMsg, 1);
	if (Status != XST_SUCCESS)
	{
		return XST_FAILURE;
	}

	/*
	 * Wait for the write command to the Flash to be completed, it takes
	 * some time for the data to be written
	 */
	while (1)
	{
		ReadStatusCmd = StatusCmd;
		FlashMsg[0].TxBfrPtr = &ReadStatusCmd;
		FlashMsg[0].RxBfrPtr = NULL;
		FlashMsg[0].ByteCount = 1;
		FlashMsg[0].BusWidth = XQSPIPSU_SELECT_MODE_SPI;
		FlashMsg[0].Flags = XQSPIPSU_MSG_FLAG_TX;

		FlashMsg[1].TxBfrPtr = NULL;
		FlashMsg[1].RxBfrPtr = FlashStatus;
		FlashMsg[1].ByteCount = 2;
		FlashMsg[1].BusWidth = XQSPIPSU_SELECT_MODE_SPI;
		FlashMsg[1].Flags = XQSPIPSU_MSG_FLAG_RX;
		if (QspiPsuPtr->Config.ConnectionMode ==
			XQSPIPSU_CONNECTION_MODE_PARALLEL)
		{
			FlashMsg[1].Flags |= XQSPIPSU_MSG_FLAG_STRIPE;
		}

		Status = XQspiPsu_PolledTransfer(QspiPsuPtr, FlashMsg, 2);
		if (Status != XST_SUCCESS)
		{
			return XST_FAILURE;
		}
		if (QspiPsuPtr->Config.ConnectionMode ==
			XQSPIPSU_CONNECTION_MODE_PARALLEL)
		{
			if (FSRFlag)
			{
				FlashStatus[1] &= FlashStatus[0];
			}
			else
			{
				FlashStatus[1] |= FlashStatus[0];
			}
		}

		if (FSRFlag)
		{
			if ((FlashStatus[1] & 0x80) != 0)
			{
				break;
			}
		}
		else
		{
			if ((FlashStatus[1] & 0x01) == 0)
			{
				break;
			}
		}
	}

	return 0;
}

// 根据互联类型，计算实际地址
u32 GetRealAddr(XQspiPsu *QspiPsuPtr, u32 Address)
{
	u32 RealAddr;

	switch (QspiPsuPtr->Config.ConnectionMode)
	{
	case XQSPIPSU_CONNECTION_MODE_SINGLE:
		XQspiPsu_SelectFlash(QspiPsuPtr,
							 XQSPIPSU_SELECT_FLASH_CS_LOWER,
							 XQSPIPSU_SELECT_FLASH_BUS_LOWER);
		RealAddr = Address;
		break;
	case XQSPIPSU_CONNECTION_MODE_STACKED:
		/* Select lower or upper Flash based on sector address */
		if (Address & Flash_Config_Table[FCTIndex].FlashDeviceSize)
		{

			XQspiPsu_SelectFlash(QspiPsuPtr,
								 XQSPIPSU_SELECT_FLASH_CS_UPPER,
								 XQSPIPSU_SELECT_FLASH_BUS_LOWER);
			/*
			 * Subtract first flash size when accessing second flash
			 */
			RealAddr = Address &
					   (~Flash_Config_Table[FCTIndex].FlashDeviceSize);
		}
		else
		{
			/*
			 * Set selection to L_PAGE
			 */
			XQspiPsu_SelectFlash(QspiPsuPtr,
								 XQSPIPSU_SELECT_FLASH_CS_LOWER,
								 XQSPIPSU_SELECT_FLASH_BUS_LOWER);

			RealAddr = Address;
		}
		break;
	case XQSPIPSU_CONNECTION_MODE_PARALLEL:
		/*
		 * The effective address in each flash is the actual
		 * address / 2
		 */
		XQspiPsu_SelectFlash(QspiPsuPtr,
							 XQSPIPSU_SELECT_FLASH_CS_BOTH,
							 XQSPIPSU_SELECT_FLASH_BUS_BOTH);
		RealAddr = Address / 2;
		break;
	default:
		/* RealAddr wont be assigned in this case; */
		break;
	}

	return (RealAddr);
}

// 使能qspi quad模式
int FlashEnableQuadMode(XQspiPsu *QspiPsuPtr)
{
	int Status;
	u8 WriteEnableCmd;
	u8 ReadStatusCmd;
	u8 FlashStatus[2];
	u8 StatusRegVal;
	u8 WriteBuffer[3] = {0};

	switch (FlashMake)
	{
	case SPANSION_ID_BYTE0:
		if (FCTIndex <= 2)
		{
			TxBfrPtr = READ_CONFIG_CMD;
			FlashMsg[0].TxBfrPtr = &TxBfrPtr;
			FlashMsg[0].RxBfrPtr = NULL;
			FlashMsg[0].ByteCount = 1;
			FlashMsg[0].BusWidth = XQSPIPSU_SELECT_MODE_SPI;
			FlashMsg[0].Flags = XQSPIPSU_MSG_FLAG_TX;

			FlashMsg[1].TxBfrPtr = NULL;
			FlashMsg[1].RxBfrPtr = &WriteBuffer[2];
			FlashMsg[1].ByteCount = 1;
			FlashMsg[1].BusWidth = XQSPIPSU_SELECT_MODE_SPI;
			FlashMsg[1].Flags = XQSPIPSU_MSG_FLAG_RX;

			Status = XQspiPsu_PolledTransfer(QspiPsuPtr,
											 FlashMsg, 2);
			if (Status != XST_SUCCESS)
			{
				return XST_FAILURE;
			}

			WriteEnableCmd = VOLATILE_WRITE_ENABLE_CMD;
			/*
			 * Send the write enable command to the
			 * Flash so that it can be written to, this
			 * needs to be sent as a separate transfer before
			 * the write
			 */
			FlashMsg[0].TxBfrPtr = &WriteEnableCmd;
			FlashMsg[0].RxBfrPtr = NULL;
			FlashMsg[0].ByteCount = 1;
			FlashMsg[0].BusWidth = XQSPIPSU_SELECT_MODE_SPI;
			FlashMsg[0].Flags = XQSPIPSU_MSG_FLAG_TX;

			Status = XQspiPsu_PolledTransfer(QspiPsuPtr,
											 FlashMsg, 1);
			if (Status != XST_SUCCESS)
			{
				return XST_FAILURE;
			}

			GetRealAddr(QspiPsuPtr, TEST_ADDRESS);

			WriteBuffer[0] = WRITE_CONFIG_CMD;
			WriteBuffer[1] |= 0;
			WriteBuffer[2] |= 1 << 1;

			FlashMsg[0].TxBfrPtr = WriteBuffer;
			FlashMsg[0].RxBfrPtr = NULL;
			FlashMsg[0].BusWidth = XQSPIPSU_SELECT_MODE_SPI;
			FlashMsg[0].Flags = XQSPIPSU_MSG_FLAG_TX;
			FlashMsg[0].ByteCount = 3;

			Status = XQspiPsu_PolledTransfer(QspiPsuPtr,
											 FlashMsg, 1);
			if (Status != XST_SUCCESS)
			{
				return XST_FAILURE;
			}

			TxBfrPtr = READ_CONFIG_CMD;
			FlashMsg[0].TxBfrPtr = &TxBfrPtr;
			FlashMsg[0].RxBfrPtr = NULL;
			FlashMsg[0].ByteCount = 1;
			FlashMsg[0].BusWidth = XQSPIPSU_SELECT_MODE_SPI;
			FlashMsg[0].Flags = XQSPIPSU_MSG_FLAG_TX;

			FlashMsg[1].TxBfrPtr = NULL;
			FlashMsg[1].RxBfrPtr = ReadBfrPtr;
			FlashMsg[1].ByteCount = 1;
			FlashMsg[1].BusWidth = XQSPIPSU_SELECT_MODE_SPI;
			FlashMsg[1].Flags = XQSPIPSU_MSG_FLAG_RX;

			Status = XQspiPsu_PolledTransfer(QspiPsuPtr,
											 FlashMsg, 2);
			if (Status != XST_SUCCESS)
			{
				return XST_FAILURE;
			}

			if (ReadBfrPtr[0] & 0x02)
			{
				Status = XST_SUCCESS;
			}
			else
			{
				Status = XST_FAILURE;
			}
		}
		break;
	case ISSI_ID_BYTE0:
		/*
		 * Read Status register
		 */
		ReadStatusCmd = READ_STATUS_CMD;
		FlashMsg[0].TxBfrPtr = &ReadStatusCmd;
		FlashMsg[0].RxBfrPtr = NULL;
		FlashMsg[0].ByteCount = 1;
		FlashMsg[0].BusWidth = XQSPIPSU_SELECT_MODE_SPI;
		FlashMsg[0].Flags = XQSPIPSU_MSG_FLAG_TX;
		FlashMsg[1].TxBfrPtr = NULL;
		FlashMsg[1].RxBfrPtr = FlashStatus;
		FlashMsg[1].ByteCount = 2;
		FlashMsg[1].BusWidth = XQSPIPSU_SELECT_MODE_SPI;
		FlashMsg[1].Flags = XQSPIPSU_MSG_FLAG_RX;
		if (QspiPsuPtr->Config.ConnectionMode ==
			XQSPIPSU_CONNECTION_MODE_PARALLEL)
		{
			FlashMsg[1].Flags |= XQSPIPSU_MSG_FLAG_STRIPE;
		}
		Status = XQspiPsu_PolledTransfer(QspiPsuPtr, FlashMsg, 2);
		if (Status != XST_SUCCESS)
		{
			return XST_FAILURE;
		}
		if (QspiPsuPtr->Config.ConnectionMode ==
			XQSPIPSU_CONNECTION_MODE_PARALLEL)
		{
			if (FSRFlag)
			{
				FlashStatus[1] &= FlashStatus[0];
			}
			else
			{
				FlashStatus[1] |= FlashStatus[0];
			}
		}
		/*
		 * Set Quad Enable Bit in the buffer
		 */
		StatusRegVal = FlashStatus[1];
		StatusRegVal |= 0x1 << QUAD_MODE_ENABLE_BIT;

		/*
		 * Write Enable
		 */
		WriteEnableCmd = WRITE_ENABLE_CMD;
		FlashMsg[0].TxBfrPtr = &WriteEnableCmd;
		FlashMsg[0].RxBfrPtr = NULL;
		FlashMsg[0].ByteCount = 1;
		FlashMsg[0].BusWidth = XQSPIPSU_SELECT_MODE_SPI;
		FlashMsg[0].Flags = XQSPIPSU_MSG_FLAG_TX;
		Status = XQspiPsu_PolledTransfer(QspiPsuPtr, FlashMsg, 1);
		if (Status != XST_SUCCESS)
		{
			return XST_FAILURE;
		}
		/*
		 * Write Status register
		 */
		WriteBuffer[COMMAND_OFFSET] = WRITE_STATUS_CMD;
		FlashMsg[0].TxBfrPtr = WriteBuffer;
		FlashMsg[0].RxBfrPtr = NULL;
		FlashMsg[0].ByteCount = 1;
		FlashMsg[0].BusWidth = XQSPIPSU_SELECT_MODE_SPI;
		FlashMsg[0].Flags = XQSPIPSU_MSG_FLAG_TX;

		FlashMsg[1].TxBfrPtr = &StatusRegVal;
		FlashMsg[1].RxBfrPtr = NULL;
		FlashMsg[1].ByteCount = 1;
		FlashMsg[1].BusWidth = XQSPIPSU_SELECT_MODE_SPI;
		FlashMsg[1].Flags = XQSPIPSU_MSG_FLAG_TX;
		if (QspiPsuPtr->Config.ConnectionMode ==
			XQSPIPSU_CONNECTION_MODE_PARALLEL)
		{
			FlashMsg[1].Flags |= XQSPIPSU_MSG_FLAG_STRIPE;
		}
		Status = XQspiPsu_PolledTransfer(QspiPsuPtr, FlashMsg, 2);
		if (Status != XST_SUCCESS)
		{
			return XST_FAILURE;
		}
		/*
		 * Write Disable
		 */
		WriteEnableCmd = WRITE_DISABLE_CMD;
		FlashMsg[0].TxBfrPtr = &WriteEnableCmd;
		FlashMsg[0].RxBfrPtr = NULL;
		FlashMsg[0].ByteCount = 1;
		FlashMsg[0].BusWidth = XQSPIPSU_SELECT_MODE_SPI;
		FlashMsg[0].Flags = XQSPIPSU_MSG_FLAG_TX;
		Status = XQspiPsu_PolledTransfer(QspiPsuPtr, FlashMsg, 2);
		if (Status != XST_SUCCESS)
		{
			return XST_FAILURE;
		}

	default:
		/*
		 * Currently only S25FL-L series requires the
		 * Quad enable bit to be set to 1.
		 */
		Status = XST_SUCCESS;
		break;
	}

	return Status;
}
