#include <unistd.h>
#include <time.h>
#include "xfast_flash.h"
#include "xstatus_codes.h"
#include "ynictrl_main.h"

/************************** Constant Definitions *****************************/
u32 cmd_seq[]={0xffffffff,0xaa995566,0x20000000,0x30020001,0x00000000,0x30008001,0x0000000f,0x20000000};

/************************** Variable Definitions *****************************/
extern int fd_user;
extern uint8_t verbose;

/**************************** Type Definitions *******************************/


/***************** Macros (Inline Functions) Definitions *********************/


/************************** Function Prototypes ******************************/
//int time_get(char *pstime)
void time_get(void)
{
	char atime[XFAST_TEST_LOG_LEN] = {0};
	time_t rawtime;
	struct tm * timeinfo;
	//uint32_t len;
	//log = (char *)malloc(TOS_FAL_TEST_LOG_LEN);
	/*if(pstime == NULL)
	{
		printf("malloc log fail!\n");
		//update_result_record(UPDATE_MEMORY_ERROR);
		return XST_FAILURE;
	}*/

	time(&rawtime);
	timeinfo = localtime(&rawtime);
	//len = strftime(atime, XFAST_TEST_LOG_LEN, "[%Y/%m/%d %H:%M:%S] ", timeinfo);
	strftime(atime, XFAST_TEST_LOG_LEN, "[%Y/%m/%d %H:%M:%S] ", timeinfo);
	atime[XFAST_TEST_LOG_LEN - 1] = 0;
	printf("time:%s\n", atime);

	return;
}

unsigned int Xfast_ReadReg(unsigned long long BaseAddress, unsigned int RegOffset)
{
	unsigned int page_size = sysconf(_SC_PAGESIZE);
	unsigned long long addr = BaseAddress + RegOffset;

	unsigned int page_addr = (addr & ~(page_size - 1));
	unsigned int page_offset = addr - page_addr;
	unsigned int read_result = 0;

	void *mm_base = mmap(NULL, page_size, PROT_READ, MAP_SHARED, fd_user, page_addr);
	if (mm_base == (void *)-1)
	{
		printf("Can't map the memory to user space.\n");
		return -1;
	}

	read_result = *((unsigned int *)((u8 *)mm_base + page_offset));
	//printf("addr=0x%llx,Baseaddr=0x%llx,Regoffset=0x%08x,page_size=0x%08x\n",addr,BaseAddress,RegOffset,page_size);
	//printf("read-page_addr=0x%08x,page_offset=0x%08x,mm_base=0x%llx,read=0x%08x\n",page_addr, page_offset, mm_base,read_result);

	if (munmap(mm_base, page_size) == -1)
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
void Xfast_WriteReg(unsigned long long BaseAddress, unsigned int RegOffset, unsigned int RegisterValue)
{
	unsigned int page_size = sysconf(_SC_PAGESIZE);
	unsigned long long addr = BaseAddress + RegOffset;

	u32 page_addr = (addr & ~(page_size - 1));
	u32 page_offset = addr - page_addr;

	void *mm_base = mmap(NULL, page_size, PROT_READ | PROT_WRITE, MAP_SHARED, fd_user, page_addr);
	if (mm_base == (void *)-1)
	{
		printf("Can't map the memory to user space.\n");
		return;
	}

	//printf("write-page_addr=0x%08x,page_offset=0x%08x,mm_base=0x%llx,write=0x%08x\n",page_addr, page_offset, mm_base,RegisterValue);
	*((u32 *)((u8 *)mm_base + page_offset)) = RegisterValue;
	if (munmap(mm_base, page_size) == -1)
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

int Xfast_GetStatus(void)
{
	u32 count = 100000;
	int status = XFAST_STATUS_BUSY;
	while((count--) && (status)) {
		status = Xfast_ReadReg(XFAST_BASE_ADDR, XFAST_BPI_STATUS_REG);
		usleep(1);
	}
	return status;
}

int Xfast_WriteWord(u32 addr, u8 *data)
{
	int ret = XST_SUCCESS;
	int status;

	Xfast_WriteReg(XFAST_BASE_ADDR, XFAST_BPI_WRITE_DATA_REG, (data[1] << 8) | data[0]);
	Xfast_WriteReg(XFAST_BASE_ADDR, XFAST_BPI_WRITE_CMD_REG, addr);
	status = Xfast_GetStatus();
	if(status) {
		ret = XST_FAILURE;
	}

	return ret;
}

/*
 * 写buffer,一次1024byte,256个4字节(u32).
 */
int Xfast_WriteBuffer(u32 addr, u8 *data)
{
	int ret = XST_SUCCESS;
	int status;
	u32 val = 0;
	int i;

	Xfast_WriteReg(XFAST_BASE_ADDR, XFAST_BPI_WRBUF_OFFSET_REG, 0);
	for(i=0;i<XFAST_WRBUF_DATA_SIZE;i+=4) {
		val = (data[i+3] << 24) | (data[i+2] << 16) | (data[i+1] << 8) | data[i];
		Xfast_WriteReg(XFAST_BASE_ADDR, XFAST_BPI_WRBUF_DATA_REG, val);
	}
	Xfast_WriteReg(XFAST_BASE_ADDR, XFAST_BPI_WRBUF_CMD_REG, addr);
	status = Xfast_GetStatus();
	if(status) {
		ret = XST_FAILURE;
	}

	return ret;
}

int Xfast_UpdateLoad(u32 *data,int len)
{
	int ret = XST_SUCCESS;
	//int status;
	int i;

	for(i=0;i<len;i++) {
		Xfast_WriteReg(XFAST_BASE_ADDR, XFAST_BPI_UPDATE_REG, data[i]);
	}
	Xfast_WriteReg(XFAST_BASE_ADDR, XFAST_BPI_CONTROL_REG, 1);

	return ret;
}

int Xfast_ReadWord(u32 addr,u8 *data)
{
	int ret = XST_SUCCESS;
	int status;
	u16 val;

	Xfast_WriteReg(XFAST_BASE_ADDR, XFAST_BPI_READ_CMD_REG, addr);
	status = Xfast_GetStatus();
	if(status) {
		ret = XST_FAILURE;
	} else {
		val = Xfast_ReadReg(XFAST_BASE_ADDR, XFAST_BPI_READ_DATA_REG);
		data[0] = (u8)(val & 0xFF);
		data[1] = (u8)((val >> 8)& 0xFF);
	}

	return ret;
}

/*
 * 读buffer,一次32byte,8个4字节(u32).
 */
int Xfast_ReadBuffer(u32 addr,u8 *data)
{
	int ret = XST_SUCCESS;
	int status;
	u32 val;
	int i;

	Xfast_WriteReg(XFAST_BASE_ADDR, XFAST_BPI_RDBUF_CMD_REG, addr);
	status = Xfast_GetStatus();
	if(status) {
		ret = XST_FAILURE;
	} else {
		for(i=0;i<XFAST_RDBUF_DATA_SIZE;i+=4) {
			val = Xfast_ReadReg(XFAST_BASE_ADDR, XFAST_BPI_RDBUF_DATA_REG);
			data[i] = (u8)(val & 0xFF);
			data[i+1] = (u8)((val >> 8)& 0xFF);
			data[i+2] = (u8)((val >> 16)& 0xFF);
			data[i+3] = (u8)((val >> 24)& 0xFF);
		}
	}

	return ret;
}

int Xfast_EraseSector(u32 addr)
{
	int ret = XST_SUCCESS;
	int status;

	Xfast_WriteReg(XFAST_BASE_ADDR, XFAST_BPI_ERASE_CMD_REG, addr);
	status = Xfast_GetStatus();
	if(status) {
		ret = XST_FAILURE;
	}

	return ret;
}

int Xfast_Flash_ReadId(void)
{
	//int status;

	//printf("flash id: %02x%02x%02x\n",ReadBuffer[1],ReadBuffer[2],ReadBuffer[3]);
	return XST_SUCCESS;
}

void xfast_demo(void)
{
	int status,value;
	status = Xfast_ReadReg(XFAST_BASE_ADDR, XFAST_BPI_STATUS_REG);
	if(status == 0) {
		value = Xfast_ReadReg(0, 0);
		printf("date=0x%08x\n",value);
	} else {
		printf("date read faild!\n");
	}

	Xfast_WriteReg(XFAST_BASE_ADDR, XFAST_BPI_READ_CMD_REG, XFAST_IMG_SECTOR_ADDR);
	status = Xfast_ReadReg(XFAST_BASE_ADDR, XFAST_BPI_STATUS_REG);
	if(status == 0) {
		value = Xfast_ReadReg(XFAST_BASE_ADDR, XFAST_BPI_READ_DATA_REG);
		printf("0xb000-value=0x%08x\n",value);
	} else {
		printf("mac addr read faild!\n");
	}
#if 0
	Xfast_WriteReg(XFAST_BASE_ADDR, XFAST_BPI_READ_CMD_REG, 0x50);
	status = Xfast_ReadReg(XFAST_BASE_ADDR, XFAST_BPI_STATUS_REG);
	if(status == 0) {
		value = Xfast_ReadReg(XFAST_BASE_ADDR, XFAST_BPI_READ_DATA_REG);
		printf("0xb000-value=0x%08x\n",value);
	}
#endif
}

void xfast_demo1(void)
{
	//int ret = XST_SUCCESS;
	int status,value;
	//u8 readbuf[1024];
	u8 writebuf[1024];

	status = Xfast_GetStatus();
	if(status == XFAST_STATUS_IDLE) {
		value = Xfast_ReadReg(0, 0);
		printf("date=0x%08x\n",value);
	}

#if 1
	for(int i=0;i<sizeof(writebuf);i++) {
		writebuf[i] = 0xab;
	}
	xfast_flash_erase(XFAST_IMG_SECTOR_ADDR,1);
	xfast_flash_write(XFAST_IMG_SECTOR_ADDR , sizeof(writebuf), writebuf);
	printf("write done!\n");


	xfast_flash_verify(XFAST_IMG_SECTOR_ADDR, sizeof(writebuf), writebuf);
	printf("write done!\n");
#endif
}

int Xfast_EraseSector_verify(u32 addr)
{
	int status;
	u8 tdata[2];
	u32 count;
	int i;

	count = XFAST_FLASH_SECTOR_64K/XFAST_FLASH_DATA_LEN;
	for ( i = 0; i < count; i++ ) {
		status = Xfast_ReadWord(addr, tdata);
		if(status != XST_SUCCESS) {
			printf("%s read addr 0x%08x faild!\n", __func__, addr);
			return XST_FAILURE;
		} else if(0) {
			;
		} else {
			if( i < 10 )
				printf("%s:%d,addr:0x%x,tdata0:0x%02x,tdata1:0x%02x\n", __func__, __LINE__, addr, tdata[0], tdata[1]);
		}

	}


	return XST_SUCCESS;
}

/*
 * erase flash by length
 */
int xfast_flash_erase(u32 address, u32 len)
{
	int status;
	//int sector,remain;
	int sector;
	u32 addr = address;
	u16 prorate = 0;
	u16 prev_prorate = 0;

#if 0
	remain = len % XFAST_FLASH_SECTOR_64K;
	if(remain == 0) {
		sector = len / XFAST_FLASH_SECTOR_64K;
	} else {
		sector = (len / XFAST_FLASH_SECTOR_64K) + 1;
	}
#endif
	sector = ((len / 2) / XFAST_FLASH_SECTOR_64K) + 1;

	if(((addr + len) & XFAST_FLASH_SECTOR_64K_MASK) == ((addr + (sector * XFAST_FLASH_SECTOR_64K)) & XFAST_FLASH_SECTOR_64K_MASK)) {
		sector++;
	}

	printf("erase: ");
	printf("%3d%%", prorate);
	fflush(stdout);

	for(int i=0;i<sector;i++) {
		prorate = i * 100 / sector;
		if(prev_prorate != prorate) {
			printf("\033[4D");
			printf("%3d%%", prorate);
			fflush(stdout);
			prev_prorate = prorate;
		}

		status = Xfast_EraseSector(addr);
		if(status != XST_SUCCESS) {
			printf("%s erase addr 0x%08x faild!\n", __func__, addr);
			return XST_FAILURE;
		}
#if 0
		int iRet = Xfast_EraseSector_verify(addr);
		if (iRet != XST_SUCCESS )
			printf("sector%d erase failed!addr:0x%x\n", sector, addr);
#endif
		addr += XFAST_FLASH_SECTOR_64K;
	}

	printf("\033[4D");
	printf("%3d%%", 100);
	printf("\033[2K");
	printf("\r");
	fflush(stdout);

	if(verbose) {
		printf("erase success.\n");
	}

	return XST_SUCCESS;

}

/*
 * write flash by length
 */
int xfast_flash_write(u32 address, u32 len, u8 *wbuf)
{
	int status;
	u32 addr = address;
	u8 *ptr = wbuf;
	int count,remain;
	u16 prorate = 0;
	u16 prev_prorate = 0;

#if 0
	for (i = 0; i < len; i++) {
		if ( i%16 == 0 && i != 0 )
			printf("\n");
		printf("0x%02x ", wbuf[i]);
	}
	printf("\n");
#endif
	remain = len % XFAST_FLASH_DATA_LEN;
	if(remain == 0) {
		count = len / XFAST_FLASH_DATA_LEN;
	} else {
		count = (len / XFAST_FLASH_DATA_LEN) + 1;
	}

	printf("program: ");
	printf("%3d%%", prorate);
	fflush(stdout);

	for (int i = 0; i < count; i++)
	{
		prorate = i * 100 / count;
		if(prev_prorate != prorate) {
			printf("\033[4D");
			printf("%3d%%", prorate);
			fflush(stdout);
			prev_prorate = prorate;
		}

		status = Xfast_WriteWord(addr, ptr);
		if(status != XST_SUCCESS) {
			printf("%s write addr 0x%08x faild!\n", __func__, addr);
			return XST_FAILURE;
		}
		addr += XFAST_FLASH_ADDR_LEN;
		ptr += XFAST_FLASH_DATA_LEN;
		//Xfast_WriteWord(u32 addr, u8 *data);
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
 * write flash use buffer
 * faster than xfast_flash_write func.
 */
int xfast_flash_write_high(u32 address, u32 len, u8 *wbuf)
{
	int status;
	u32 addr = address;
	u8 *ptr = wbuf;
	int count,remain;
	u16 prorate = 0;
	u16 prev_prorate = 0;
	u8 lastbuf[XFAST_WRBUF_DATA_SIZE] = {0xff};

	remain = len % XFAST_WRBUF_DATA_SIZE;
	count = len / XFAST_WRBUF_DATA_SIZE;
	if(remain != 0) {
		memcpy(lastbuf, &(wbuf[len-remain]), remain);
	}

	printf("program: ");
	printf("%3d%%", prorate);
	fflush(stdout);

	for (int i = 0; i < count; i++)
	{
		prorate = i * 100 / count;
		if(prev_prorate != prorate) {
			printf("\033[4D");
			printf("%3d%%", prorate);
			fflush(stdout);
			prev_prorate = prorate;
		}

		status = Xfast_WriteBuffer(addr, ptr);
		if(status != XST_SUCCESS) {
			printf("%s write addr 0x%08x faild!\n", __func__, addr);
			return XST_FAILURE;
		}
		addr += XFAST_WRBUF_ADDR_SIZE;
		ptr += XFAST_WRBUF_DATA_SIZE;

	}
	if(remain != 0) {
		status = Xfast_WriteBuffer(addr, lastbuf);
		if(status != XST_SUCCESS) {
			printf("%s write addr 0x%08x faild!\n", __func__, addr);
			return XST_FAILURE;
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
int xfast_flash_read(u32 address, u32 len, u8 *res)
{
	int status;
	u32 addr = address;
	u32 count,remain;
	u8 *ptr = res;

	remain = len % XFAST_FLASH_DATA_LEN;
	if(remain == 0) {
		count = len / XFAST_FLASH_DATA_LEN;
	} else {
		count = (len / XFAST_FLASH_DATA_LEN) + 1;
	}
	for(int i = 0; i < count; i++) {
		status = Xfast_ReadWord(addr, ptr);
		if(status != XST_SUCCESS) {
			printf("%s read addr 0x%08x faild!\n", __func__, addr);
			return XST_FAILURE;
		}
		addr += XFAST_FLASH_ADDR_LEN;
		ptr += XFAST_FLASH_DATA_LEN;
	}

	if(verbose)
		printf("read success. \n");

	return XST_SUCCESS;
}

/*
 * read flash use buffer
 */
int xfast_flash_read_high(u32 address, u32 len, u8 *res)
{
	int status;
	u32 addr = address;
	u32 count,remain;
	u8 *ptr = res;
	u8 lastbuf[XFAST_RDBUF_DATA_SIZE] = {0xff};

	remain = len % XFAST_RDBUF_DATA_SIZE;
	count = len / XFAST_RDBUF_DATA_SIZE;

	for(int i = 0; i < count; i++) {
		status = Xfast_ReadBuffer(addr, ptr);
		if(status != XST_SUCCESS) {
			printf("%s read addr 0x%08x faild!\n", __func__, addr);
			return XST_FAILURE;
		}
		addr += XFAST_RDBUF_ADDR_SIZE;
		ptr += XFAST_RDBUF_DATA_SIZE;
	}
	if(remain != 0) {
		status = Xfast_ReadBuffer(addr, lastbuf);
		if(status != XST_SUCCESS) {
			printf("%s read addr 0x%08x faild!\n", __func__, addr);
			return XST_FAILURE;
		}
		memcpy(ptr, lastbuf, remain);
	}

	if(verbose)
		printf("read success. \n");

	return XST_SUCCESS;
}

int xfast_flash_verify(u32 address, u32 len, u8 *src)
{
	int status;
	u32 addr = address;
	u32 count,remain;
	u8 *ptr = src;
	u8 tdata[2];
	u16 prorate = 0;
	u16 prev_prorate = 0;

	remain = len % XFAST_FLASH_DATA_LEN;
	if(remain == 0) {
		count = len / XFAST_FLASH_DATA_LEN;
	} else {
		count = (len / XFAST_FLASH_DATA_LEN) + 1;
	}
	printf("verify: ");
	printf("%3d%%", prorate);
	fflush(stdout);

	for(int i = 0; i < count; i++) {
		prorate = i * 100 / count;
		if(prev_prorate != prorate) {
			printf("\033[4D");
			printf("%3d%%", prorate);
			fflush(stdout);
			prev_prorate = prorate;
		}
		status = Xfast_ReadWord(addr, tdata);
		if(status != XST_SUCCESS) {
			printf("%s read addr 0x%08x faild!\n", __func__, addr);
			return XST_FAILURE;
		} else {
			if((tdata[0] != ptr[0]) || (tdata[1] != ptr[1])) {
				printf("verify error pos %d, read data0=0x%02x,origin data0=0x%02x, \
						read data1=0x%02x,origin data1=0x%02x\n", i, \
						tdata[0], ptr[0], tdata[1], ptr[1]);
				return XST_FAILURE;
			}
		}

		addr += XFAST_FLASH_ADDR_LEN;
		ptr += XFAST_FLASH_DATA_LEN;

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


int xfast_flash_verify_high(u32 address, u32 len, u8 *src)
{
	int status;
	u32 addr = address;
	u32 count,remain;
	u8 *ptr = src;
	u8 tdata[XFAST_RDBUF_DATA_SIZE] = {0x00};
	u16 prorate = 0;
	u16 prev_prorate = 0;
	int err_cnt = 0;

	remain = len % XFAST_RDBUF_DATA_SIZE;
	count = len / XFAST_RDBUF_DATA_SIZE;

	printf("verify: ");
	printf("%3d%%", prorate);
	fflush(stdout);

	for(int i = 0; i < count; i++) {
		prorate = i * 100 / count;
		if(prev_prorate != prorate) {
			printf("\033[4D");
			printf("%3d%%", prorate);
			fflush(stdout);
			prev_prorate = prorate;
		}
		status = Xfast_ReadBuffer(addr, tdata);
		if(status != XST_SUCCESS) {
			printf("%s read addr 0x%08x faild!\n", __func__, addr);
			return XST_FAILURE;
		} else {
			for(int j=0;j<XFAST_RDBUF_DATA_SIZE;j++) {
				if((tdata[j] != ptr[j])) {
					printf("verify error pos %d, read data=0x%02x,origin data=0x%02x\n",
							j, tdata[j], ptr[j]);
					err_cnt++;
					if(err_cnt == 16)
						return XST_FAILURE; //zc:todo
				}
			}
		}
		addr += XFAST_RDBUF_ADDR_SIZE;
		ptr += XFAST_RDBUF_DATA_SIZE;
	}
	if(remain != 0) {
		status = Xfast_ReadBuffer(addr, tdata);
		if(status != XST_SUCCESS) {
			printf("%s read addr 0x%08x faild!\n", __func__, addr);
			return XST_FAILURE;
		} else {
			for(int j=0;j<remain;j++) {
				if((tdata[j] != ptr[j])) {
					printf("verify error pos %d, read data=0x%02x,origin data=0x%02x\n",
							j, tdata[j], ptr[j]);
					err_cnt++;
					if(err_cnt == 16)
						return XST_FAILURE; //zc:todo
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
		printf("verify success.\n");

	return XST_SUCCESS;
}

int xfast_flash_update(void)
{
	int ret = XST_SUCCESS;
	Xfast_UpdateLoad(cmd_seq, (sizeof(cmd_seq)/sizeof(u8)));

	return ret;
}

int xfast_update_act(void)
{
	int ret = XST_SUCCESS;
	u32 value = 0xaa55;
	//u8 data[4] = {0};

	sleep(1);
	value = Xfast_ReadReg(0, 0);
	if(verbose)
		printf("value=0x%08x\n",value);
	if((value == 0xffffffff) || (value == 0x0)) {
		/*do nothing*/
	} else {
		ret = XST_FAILURE;
	}

	return ret;
}


int xfast_update_mac(void)
{
	int ret = XST_SUCCESS;

	Xfast_WriteReg(0xb000, 0, 1);
	Xfast_WriteReg(0xb000, 4, 1);
	usleep(5000);

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
int Xfast_FlashInit(void)
{
	int ret = XST_SUCCESS;
	int status,value;

	status = Xfast_ReadReg(XFAST_BASE_ADDR, XFAST_BPI_STATUS_REG);
	if(status == 0) {
		value = Xfast_ReadReg(0, 0);
	} else {
		printf("date read faild!\n");
		ret = XST_FAILURE;
	}

	if(verbose)
		//printf("flash id: %02x%02x%02x\n",ReadBuffer[1],ReadBuffer[2],ReadBuffer[3]);
		printf("date=0x%08x\n",value);

	return ret;
}

int test_xfast_highaddr(void)
{
	int ret = XST_SUCCESS;
	int status,value;
	//u32 data;
	u8 readbuf[2048];

	status = Xfast_ReadReg(XFAST_BASE_ADDR, XFAST_BPI_STATUS_REG);
	if(status == 0) {
		value = Xfast_ReadReg(0, 0);
	} else {
		printf("date read faild!\n");
		ret = XST_FAILURE;
	}
	printf("date=0x%08x\n",value);

	//read high and low address.
	xfast_flash_read_high(XFAST_HW_BASE_ADDR, sizeof(readbuf), readbuf);
	printf("BASE:\n");
	for(int i=0;i<512;i++) {
		printf("0x%02x ",readbuf[i]);
		if((i+1) % 16 == 0)
			printf("\n");
	}
#if 0
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
#endif

	memset(readbuf, 0 , sizeof(readbuf));
	xfast_flash_read_high(XFAST_HW_RELEASE1_ADDR, sizeof(readbuf), readbuf);
	printf("release 1:\n");
	for(int i=0;i<512;i++) {
		printf("0x%02x ",readbuf[i]);
		if((i+1) % 16 == 0)
			printf("\n");
	}

#if 0
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
#endif
	memset(readbuf, 0 , sizeof(readbuf));
	xfast_flash_read_high(XFAST_HW_RELEASE2_ADDR, sizeof(readbuf), readbuf);
	printf("release 2:\n");
	for(int i=0;i<512;i++) {
		printf("0x%02x ",readbuf[i]);
		if((i+1) % 16 == 0)
			printf("\n");
	}

	memset(readbuf, 0 , sizeof(readbuf));
	xfast_flash_read_high(XFAST_HW_RELEASE3_ADDR, sizeof(readbuf), readbuf);
	printf("release 3:\n");
	for(int i=0;i<512;i++) {
		printf("0x%02x ",readbuf[i]);
		if((i+1) % 16 == 0)
			printf("\n");
	}

	memset(readbuf, 0 , sizeof(readbuf));
	xfast_flash_read_high(XFAST_HW_RELEASE4_ADDR, sizeof(readbuf), readbuf);
	printf("release 4:\n");
	for(int i=0;i<512;i++) {
		printf("0x%02x ",readbuf[i]);
		if((i+1) % 16 == 0)
			printf("\n");
	}

	memset(readbuf, 0 , sizeof(readbuf));
	xfast_flash_read_high(XFAST_IMG_SECTOR_ADDR, sizeof(readbuf), readbuf);
	printf("mac sector:\n");
	for(int i=0;i<NF_WRITE_SIZE;i++) {
		printf("0x%02x ",readbuf[i]);
		if((i+1) % 16 == 0)
			printf("\n");
	}
	printf("version1:%.*s\n",64, &readbuf[144]);
	printf("version2:%.*s\n",64, &readbuf[208]);
	printf("version3:%.*s\n",64, &readbuf[272]);
	printf("version4:%.*s\n",64, &readbuf[336]);

	return ret;
}

