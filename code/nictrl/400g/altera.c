#include "altera.h"
#include "xstatus.h"
#include "main.h"


extern int fd_user;
extern uint8_t verbose;

// 全局变量
static int fd = -1;
static void *base_addr = NULL;

typedef struct {
	int valid;
	int pcie_mode;
	int bus;
	uint32_t pdf;
} altera_adapter_mode_t;

static altera_adapter_mode_t altera_adapter_modes[MAX_PORT_PER_ADP];
static int altera_current_adapter = -1;
static int altera_flash_passthrough = 0;

static inline int altera_read_pcie_mode_from_current_device(void)
{
	unsigned int page_size;
	unsigned int read_result = 0;
	void *mm_base;

	page_size = sysconf(_SC_PAGESIZE);
	mm_base = mmap(NULL, page_size, PROT_READ, MAP_SHARED, fd_user, 0);
	if (mm_base == (void *)-1) {
		printf("Can't map the memory to user space.\n");
		return 0;
	}

	read_result = *((unsigned int *)mm_base);
	if (munmap(mm_base, page_size) == -1) {
		printf("Can't unmap memory from user space.\n");
		return 0;
	}

	if (verbose) {
		printf("400G pcie mode: %s (bar2[0]=0x%08x)\n",
			(read_result == ALTERA_PCIE5_BAR2_MAGIC) ? "pcie5" : "pcie4", read_result);
	}

	return (read_result == ALTERA_PCIE5_BAR2_MAGIC) ? 1 : 0;
}

static inline int altera_detect_pcie_mode(void)
{
	if (altera_current_adapter >= 0 && altera_current_adapter < MAX_PORT_PER_ADP) {
		altera_adapter_mode_t *entry = &altera_adapter_modes[altera_current_adapter];
		if (entry->valid)
			return entry->pcie_mode;

		entry->pcie_mode = altera_read_pcie_mode_from_current_device();
		entry->valid = 1;
		return entry->pcie_mode;
	}

	return altera_read_pcie_mode_from_current_device();
}

static inline int altera_is_pcie5_cached(void)
{
	return altera_detect_pcie_mode();
}

static inline unsigned long long altera_mailbox_base(void)
{
	return altera_is_pcie5_cached() ? ((unsigned long long)BASE_ADDRESS << 1) : BASE_ADDRESS;
}

static inline uint32_t altera_reg_offset(uint32_t offset)
{
	return altera_is_pcie5_cached() ? (offset << 1) : offset;
}

static inline int altera_flash_base_passthrough(uint32_t base_addr)
{
	return (base_addr == ALTERA_HW_RELEASE1_ADDR || base_addr == ALTERA_IMG_SECTOR_ADDR);
}

static inline uint32_t altera_flash_addr(uint32_t addr)
{
	if (!altera_is_pcie5_cached())
		return addr;

	if (altera_flash_passthrough)
		return addr;

	return addr << 1;
}

double get_time_seconds() {
	struct timeval tv;
	gettimeofday(&tv, NULL);
	return tv.tv_sec + tv.tv_usec / 1000000.0;
}

int init_hardware(void) {
	fd = open("/dev/mem", O_RDWR | O_SYNC);
	if (fd == -1) {
		perror("open /dev/mem");
		return -1;
	}

	base_addr = mmap(NULL, 4096, PROT_READ | PROT_WRITE, MAP_SHARED, fd, altera_mailbox_base());
	if (base_addr == MAP_FAILED) {
		perror("mmap");
		close(fd);
		fd = -1;
		return -1;
	}

	return 0;
}

void cleanup_hardware(void) {
	if (base_addr != NULL && base_addr != MAP_FAILED) {
		munmap(base_addr, 4096);
		base_addr = NULL;
	}
	if (fd != -1) {
		close(fd);
		fd = -1;
	}
}

uint32_t read_register(uint32_t offset)
{
	unsigned int page_size = sysconf(_SC_PAGESIZE);
	unsigned long long addr = altera_mailbox_base() + altera_reg_offset(offset);
	unsigned int page_addr = (addr & ~(page_size - 1));
	unsigned int page_offset = addr - page_addr;
	unsigned int read_result = 0;
	void *mm_base = mmap(NULL, page_size, PROT_READ, MAP_SHARED, fd_user, page_addr);
	if (mm_base == (void *)-1) {
		printf("Can't map the memory to user space.\n");
		return -1;
	}
	read_result = *((unsigned int *)((u8 *)mm_base + page_offset));
	if (munmap(mm_base, page_size) == -1) {
		printf("Can't unmap memory from user space.\n");
		return -1;
	}
	return read_result;
}

void write_register(uint32_t offset, uint32_t value)
{
	unsigned int page_size = sysconf(_SC_PAGESIZE);
	unsigned long long addr = altera_mailbox_base() + altera_reg_offset(offset);
	u32 page_addr = (addr & ~(page_size - 1));
	u32 page_offset = addr - page_addr;
	void *mm_base = mmap(NULL, page_size, PROT_READ | PROT_WRITE, MAP_SHARED, fd_user, page_addr);
	if (mm_base == (void *)-1) {
		printf("Can't map the memory to user space.\n");
		return;
	}
	*((u32 *)((u8 *)mm_base + page_offset)) = value;
	if (munmap(mm_base, page_size) == -1) {
		printf("Can't unmap memory from user space.\n");
		return;
	}
}

int read_command_fifo_empty_space(void) {
	return read_register(REG_CMD_FIFO);
}

int read_resp_fill_level(void)
{
	uint32_t response = read_register(REG_RESP_FIFO);
	uint32_t fill_level = (response & 0xFFFFFFFC) >> 2;
	return fill_level;
}

int exec_command(uint32_t command, uint32_t *args, int num_args)
{
	uint32_t header = num_args * 0x1000 + command;
	if (num_args > 0) {
		while (!read_command_fifo_empty_space()) {
			usleep(1000);
		}
		write_register(REG_CMD, header);
		for (int i = 0; i < num_args; i++) {
			while (!read_command_fifo_empty_space()) {
				usleep(1000);
			}
			if (i == num_args - 1)
				write_register(REG_CMD_LAST, args[i]);
			else
				write_register(REG_CMD, args[i]);
		}
	} else {
		while (!read_command_fifo_empty_space()) {
			usleep(1000);
		}
		write_register(REG_CMD_LAST, header);
	}
	return 0;
}

int read_response(uint32_t *response, int max_response)
{
	uint32_t i;
	uint32_t isr = read_register(REG_ISR);
	while (!(isr & 0x00000001)) {
		isr = read_register(REG_ISR);
		usleep(1000);
	}
	while (!read_resp_fill_level()) {
		usleep(1000);
	}
	uint32_t header = read_register(REG_RESP_DATA);
	uint32_t error_code = header & 0x3FF;
	uint32_t num_arg = (header & 0x007FF000) >> 12;
	if (error_code) {
		printf("Error: 0x%08x\n", error_code);
		return -1;
	}
	if (num_arg > 0) {
		if (num_arg > (uint32_t)max_response) {
			printf("Response buffer too small\n");
			return -1;
		}
		for (i = 0; i < num_arg; i++) {
			while (!read_resp_fill_level()) {
				usleep(1000);
			}
			response[i] = read_register(REG_RESP_DATA);
		}
		return num_arg;
	}
	return 0;
}

int rsu_image_update(uint32_t addr)
{
	uint32_t command = CMD_RSU_UPDATE;
	uint32_t args[2] = {altera_flash_addr(addr), 0x0};
	uint32_t response[10];
	exec_command(command, args, 2);
	if (read_response(response, 10) != 0) {
		printf("Fail to execute rsu image update\n");
		return -1;
	}
	return 0;
}

int rsu_status(void) {
	uint32_t command = CMD_RSU_STATUS;
	uint32_t response[10];
	exec_command(command, NULL, 0);
	int resp_len = read_response(response, 10);
	if (resp_len != 9) {
		printf("Read RSU_STATUS error\n");
		return -1;
	}
	printf("current image address: 0x%08x\n", response[0]);
	printf("first failing image address: 0x%08x\n", response[2]);
	printf("failing code: 0x%08x\n", response[4]);
	printf("error_location: 0x%08x\n", response[6]);
	printf("max_retry_counter: 0x%08x\n", response[8]);
	return 0;
}

int read_idcode(void) {
	uint32_t command = CMD_GET_IDCODE;
	uint32_t response[10];
	int resp_len;
	exec_command(command, NULL, 0);
	resp_len = read_response(response, 10);
	printf("resp_len=%d\n", resp_len);
	if (resp_len != 1) {
		printf("Read IDCODE error\n");
		return -1;
	}
	printf("IDCODE: 0x%08x\n", response[0]);
	return 0;
}

int read_chipid(void) {
	uint32_t command = CMD_GET_CHIPID;
	uint32_t response[10];
	int resp_len;
	exec_command(command, NULL, 0);
	resp_len = read_response(response, 10);
	if (resp_len != 2) {
		printf("Read CHIPID error\n");
		return -1;
	}
	printf("CHIPID_LSW: 0x%08x\n", response[0]);
	printf("CHIPID_MSW: 0x%08x\n", response[1]);
	return 0;
}

int read_usercode(void)
{
	uint32_t command = CMD_GET_USERCODE;
	uint32_t response[10];
	int resp_len;
	exec_command(command, NULL, 0);
	resp_len = read_response(response, 10);
	if (resp_len != 1) {
		printf("Read USERCODE error\n");
		return -1;
	}
	printf("USERCODE: 0x%08x\n", response[0]);
	return 0;
}

int read_temp(uint32_t bmask)
{
	uint32_t command = CMD_GET_TEMP;
	uint32_t response[10];
	uint32_t args[1] = {bmask};
	int i;
	int sval;
	float temp;
	int resp_len;
	exec_command(command, args, 1);
	resp_len = read_response(response, 10);
	for(i = 0; i < resp_len; i++) {
		if(response[i] >= 0x80000000)
			sval = response[i] - 0x100000000;
		else
			sval = response[i];
		temp = sval / 256.0;
		printf("temp%d: 0x%08x,temp=%f\n", i, response[i], temp);
	}
	return 0;
}

int read_vol(uint32_t bmask)
{
	uint32_t command = CMD_GET_VOLTAGE;
	uint32_t response[10] = {0};
	uint32_t args[1] = {bmask};
	int wcnt = 0;
	int i;
	int resp_len;
	exec_command(command, args, 1);
	resp_len = read_response(response, 10);
	while (bmask) {
		wcnt += bmask & 1;
		bmask >>= 1;
	}
	if (resp_len != wcnt) {
		printf("Read VOLTAGE error\n");
		return -1;
	}
	for (i = 0; i < wcnt; i++)
		printf("vol%d: 0x%08x\n", i, response[i]);
	return 0;
}

int qspi_open(void) {
	uint32_t response[10];
	exec_command(CMD_QSPI_OPEN, NULL, 0);
	if (read_response(response, 10) != 0) {
		printf("Fail to execute QSPI Open\n");
		return -1;
	}
	return 0;
}

int qspi_close(void) {
	uint32_t response[10];
	exec_command(CMD_QSPI_CLOSE, NULL, 0);
	if (read_response(response, 10) != 0) {
		printf("Fail to execute QSPI Close\n");
		return -1;
	}
	return 0;
}

int qspi_set_cs(void) {
	uint32_t args[1] = {0x00000000};
	uint32_t response[10];

	exec_command(CMD_QSPI_SET_CS, args, 1);
	if (read_response(response, 10) != 0) {
		printf("Fail to set nCS\n");
		return -1;
	}
	return 0;
}

int qspi_read_one_word(uint32_t addr, uint32_t *data)
{
	uint32_t args[2] = {altera_flash_addr(addr), 1};
	uint32_t response[1];
	int resp_len;
	if (qspi_open() != 0 || qspi_set_cs() != 0)
		return -1;
	exec_command(CMD_QSPI_READ, args, 2);
	resp_len = read_response(response, 1);
	if (resp_len == 1 && data != NULL)
		*data = response[0];
	qspi_close();
	return resp_len;
}

int qspi_read(uint32_t addr, uint32_t word_count, uint32_t *data)
{
	uint32_t args[2] = {altera_flash_addr(addr), word_count};
	uint32_t response[1024];
	int resp_len;
	int i;
	if (qspi_open() != 0 || qspi_set_cs() != 0)
		return -1;
	exec_command(CMD_QSPI_READ, args, 2);
	resp_len = read_response(response, 1024);
	if (resp_len > 0) {
		for (i = 0; i < resp_len; i++) {
			if (data != NULL && i < (int)word_count)
				data[i] = response[i];
		}
	}
	qspi_close();
	return resp_len;
}

int qspi_write_one_word(uint32_t addr, uint32_t data)
{
	uint32_t args[3] = {altera_flash_addr(addr), 0x00000001, data};
	uint32_t response[10];
	if (qspi_open() != 0 || qspi_set_cs() != 0)
		return -1;
	exec_command(CMD_QSPI_WRITE, args, 3);
	if (read_response(response, 10) != 0) {
		printf("Fail to execute qspi write one word\n");
		qspi_close();
		return -1;
	}
	qspi_close();
	return 0;
}

int qspi_write(uint32_t addr, uint32_t word_count, uint32_t *data)
{
	uint32_t *args = NULL;
	uint32_t response[10];
	int resp_len;
	if (qspi_open() != 0 || qspi_set_cs() != 0)
		return -1;
	args = malloc(sizeof(uint32_t) * (2 + word_count));
	if (!args) {
		printf("Fail to malloc mem\n");
		qspi_close();
		return -1;
	}
	args[0] = altera_flash_addr(addr);
	args[1] = word_count;
	memcpy(args + 2, data, word_count * sizeof(uint32_t));
	exec_command(CMD_QSPI_WRITE, args, 2 + word_count);
	resp_len = read_response(response, 10);
	free(args);
	if (resp_len != 0) {
		printf("Fail to execute qspi write one word\n");
		qspi_close();
		return -1;
	}
	qspi_close();
	return 0;
}

int qspi_erase(uint32_t addr, uint32_t num_sectors)
{
	uint32_t args[2] = {altera_flash_addr(addr), num_sectors * 0x4000};
	uint32_t response[10];
	if (qspi_open() != 0 || qspi_set_cs() != 0)
		return -1;
	exec_command(CMD_QSPI_ERASE, args, 2);
	if (read_response(response, 10) != 0) {
		printf("Fail to erase QSPI\n");
		qspi_close();
		return -1;
	}
	qspi_close();
	return 0;
}

int altera_flash_erase(u32 address, u32 len)
{
	int status;
	int sector;
	int prev_passthrough;
	u32 addr = address;
	u16 prorate = 0;
	u16 prev_prorate = 0;

	prev_passthrough = altera_flash_passthrough;
	altera_flash_passthrough = altera_flash_base_passthrough(address);
	sector = (len / ALTERA_FLASH_SECTOR_64K) + 1;
	if (((addr + len) & ALTERA_FLASH_SECTOR_64K_MASK) ==
		((addr + (sector * ALTERA_FLASH_SECTOR_64K)) & ALTERA_FLASH_SECTOR_64K_MASK)) {
		sector++;
	}
	printf("erase: ");
	printf("%3d%%", prorate);
	fflush(stdout);
	for (int i = 0; i < sector; i++) {
		prorate = i * 100 / sector;
		if (prev_prorate != prorate) {
			printf("\033[4D");
			printf("%3d%%", prorate);
			fflush(stdout);
			prev_prorate = prorate;
		}
		status = qspi_erase(addr, 2);
		if (status != XST_SUCCESS) {
			printf("%s erase addr 0x%08x faild!\n", __func__, addr);
			altera_flash_passthrough = prev_passthrough;
			return XST_FAILURE;
		}
		addr += (ALTERA_FLASH_SECTOR_64K * 2);
	}
	printf("\033[4D");
	printf("%3d%%", 100);
	printf("\033[2K");
	printf("\r");
	fflush(stdout);
	if (verbose)
		printf("erase success.\n");
	altera_flash_passthrough = prev_passthrough;
	return XST_SUCCESS;
}

int altera_flash_write(u32 address, u32 len, u8 *wbuf)
{
	int status;
	int prev_passthrough;
	u32 addr = address;
	int count, remain;
	u16 prorate = 0;
	u16 prev_prorate = 0;
	u8 lastbuf[ALTERA_BUF_DATA_SIZE] = {0xff};
	u32 *ptr = (u32 *)wbuf;
	prev_passthrough = altera_flash_passthrough;
	altera_flash_passthrough = altera_flash_base_passthrough(address);
	remain = len % ALTERA_BUF_DATA_SIZE;
	count = len / ALTERA_BUF_DATA_SIZE;
	if (remain != 0)
		memcpy(lastbuf, &(wbuf[len - remain]), remain);
	printf("program: ");
	printf("%3d%%", prorate);
	fflush(stdout);
	for (int i = 0; i < count; i++) {
		prorate = i * 100 / count;
		if (prev_prorate != prorate) {
			printf("\033[4D");
			printf("%3d%%", prorate);
			fflush(stdout);
			prev_prorate = prorate;
		}
		status = qspi_write(addr, ALTERA_BUF_DATA_LEN, ptr);
		if (status != XST_SUCCESS) {
			printf("%s write addr 0x%08x faild!\n", __func__, addr);
			altera_flash_passthrough = prev_passthrough;
			return XST_FAILURE;
		}
		addr += ALTERA_BUF_ADDR_SIZE;
		ptr += ALTERA_BUF_DATA_LEN;
	}
	if (remain != 0) {
		ptr = (u32 *)lastbuf;
		status = qspi_write(addr, ALTERA_BUF_DATA_LEN, ptr);
		if (status != XST_SUCCESS) {
			printf("%s write addr 0x%08x faild!\n", __func__, addr);
			altera_flash_passthrough = prev_passthrough;
			return XST_FAILURE;
		}
	}
	printf("\033[4D");
	printf("%3d%%", 100);
	printf("\033[2K");
	printf("\r");
	fflush(stdout);
	if (verbose)
		printf("write success.\n");
	altera_flash_passthrough = prev_passthrough;
	return XST_SUCCESS;
}

int altera_flash_read(u32 address, u32 len, u8 *res)
{
	int status;
	int prev_passthrough;
	u32 addr = address;
	u32 count, remain;
	u32 *ptr = (u32 *)res;
	u8 lastbuf[ALTERA_BUF_DATA_SIZE] = {0xff};
	prev_passthrough = altera_flash_passthrough;
	altera_flash_passthrough = altera_flash_base_passthrough(address);
	remain = len % ALTERA_BUF_DATA_SIZE;
	count = len / ALTERA_BUF_DATA_SIZE;
	for (u32 i = 0; i < count; i++) {
		status = qspi_read(addr, ALTERA_BUF_DATA_LEN, ptr);
		if (status == (-XST_FAILURE)) {
			printf("%s read addr 0x%08x faild!\n", __func__, addr);
			altera_flash_passthrough = prev_passthrough;
			return XST_FAILURE;
		}
		addr += ALTERA_BUF_ADDR_SIZE;
		ptr += ALTERA_BUF_DATA_LEN;
	}
	if (remain != 0) {
		status = qspi_read(addr, ALTERA_BUF_DATA_LEN, (u32 *)lastbuf);
		if (status == (-XST_FAILURE)) {
			printf("%s read addr 0x%08x faild!\n", __func__, addr);
			altera_flash_passthrough = prev_passthrough;
			return XST_FAILURE;
		}
		memcpy((u8 *)ptr, lastbuf, remain);
	}
	if (verbose)
		printf("read success. \n");
	altera_flash_passthrough = prev_passthrough;
	return XST_SUCCESS;
}

int altera_flash_verify(u32 address, u32 len, u8 *src)
{
	int status;
	int prev_passthrough;
	u32 addr = address;
	u32 count, remain;
	u8 *ptr = src;
	u8 tdata[ALTERA_BUF_DATA_SIZE] = {0};
	u16 prorate = 0;
	u16 prev_prorate = 0;
	int err_cnt = 0;
	prev_passthrough = altera_flash_passthrough;
	altera_flash_passthrough = altera_flash_base_passthrough(address);
	remain = len % ALTERA_BUF_DATA_SIZE;
	count = len / ALTERA_BUF_DATA_SIZE;
	printf("verify: ");
	printf("%3d%%", prorate);
	fflush(stdout);
	for (u32 i = 0; i < count; i++) {
		prorate = i * 100 / count;
		if (prev_prorate != prorate) {
			printf("\033[4D");
			printf("%3d%%", prorate);
			fflush(stdout);
			prev_prorate = prorate;
		}
		status = qspi_read(addr, ALTERA_BUF_DATA_LEN, (u32 *)tdata);
		if (status == (-XST_FAILURE)) {
			printf("%s read addr 0x%08x faild!\n", __func__, addr);
			altera_flash_passthrough = prev_passthrough;
			return XST_FAILURE;
		}
		for (int j = 0; j < ALTERA_BUF_DATA_SIZE; j++) {
			if (tdata[j] != ptr[j]) {
				printf("verify error pos %d, read data=0x%02x,origin data=0x%02x\n", j, tdata[j], ptr[j]);
				err_cnt++;
				if (err_cnt == 16) {
					altera_flash_passthrough = prev_passthrough;
					return XST_FAILURE;
				}
			}
		}
		addr += ALTERA_BUF_ADDR_SIZE;
		ptr += ALTERA_BUF_DATA_SIZE;
	}
	if (remain != 0) {
		status = qspi_read(addr, ALTERA_BUF_DATA_LEN, (u32 *)tdata);
		if (status == (-XST_FAILURE)) {
			printf("%s read addr 0x%08x faild!\n", __func__, addr);
			altera_flash_passthrough = prev_passthrough;
			return XST_FAILURE;
		}
		for (u32 j = 0; j < remain; j++) {
			if (tdata[j] != ptr[j]) {
				printf("verify error pos %d, read data=0x%02x,origin data=0x%02x\n", j, tdata[j], ptr[j]);
				err_cnt++;
				if (err_cnt == 16) {
					altera_flash_passthrough = prev_passthrough;
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
	if (verbose)
		printf("verify success.\n");
	altera_flash_passthrough = prev_passthrough;
	return XST_SUCCESS;
}

int altera_update_act(void)
{
	int ret = XST_SUCCESS;
	u32 value;
	sleep(1);
	value = read_register((0x1200000 - BASE_ADDRESS));
	if (verbose)
		printf("value=0x%08x\n", value);
	if ((value == 0xffffffff) || (value == 0x0)) {
	} else {
		ret = XST_FAILURE;
	}
	return ret;
}

int test_altera_highaddr(void)
{
	int ret = XST_SUCCESS;
	u8 readbuf[2048];
	altera_flash_read(ALTERA_HW_BASE_ADDR, sizeof(readbuf), readbuf);
	printf("BASE:\n");
	for (int i = 0; i < 512; i++) {
		printf("0x%02x ", readbuf[i]);
		if ((i + 1) % 16 == 0)
			printf("\n");
	}
	memset(readbuf, 0, sizeof(readbuf));
	altera_flash_read(ALTERA_HW_RELEASE1_ADDR, sizeof(readbuf), readbuf);
	printf("RELEASE1:\n");
	for (int i = 0; i < 512; i++) {
		printf("0x%02x ", readbuf[i]);
		if ((i + 1) % 16 == 0)
			printf("\n");
	}

	memset(readbuf, 0, sizeof(readbuf));
	altera_flash_read(ALTERA_HW_RELEASE2_ADDR, sizeof(readbuf), readbuf);
	printf("RELEASE2:\n");
	for (int i = 0; i < 512; i++) {
		printf("0x%02x ", readbuf[i]);
		if ((i + 1) % 16 == 0)
			printf("\n");
	}

	memset(readbuf, 0, sizeof(readbuf));
	altera_flash_read(ALTERA_HW_RELEASE3_ADDR, sizeof(readbuf), readbuf);
	printf("RELEASE3:\n");
	for (int i = 0; i < 512; i++) {
		printf("0x%02x ", readbuf[i]);
		if ((i + 1) % 16 == 0)
			printf("\n");
	}

	memset(readbuf, 0, sizeof(readbuf));
	altera_flash_read(ALTERA_HW_RELEASE4_ADDR, sizeof(readbuf), readbuf);
	printf("RELEASE4:\n");
	for (int i = 0; i < 512; i++) {
		printf("0x%02x ", readbuf[i]);
		if ((i + 1) % 16 == 0)
			printf("\n");
	}

	memset(readbuf, 0, sizeof(readbuf));
	altera_flash_read(ALTERA_IMG_SECTOR_ADDR, sizeof(readbuf), readbuf);
	printf("mac setcor:\n");
	for (int i = 0; i < NF_WRITE_SIZE; i++) {
		printf("0x%02x ", readbuf[i]);
		if ((i + 1) % 16 == 0)
			printf("\n");
	}
	printf("version1:%.*s\n",64, &readbuf[144]);
	printf("version2:%.*s\n",64, &readbuf[208]);
	printf("version3:%.*s\n",64, &readbuf[272]);
	printf("version4:%.*s\n",64, &readbuf[336]);

	return ret;
}

int altera_is_pcie5(void)
{
	return altera_is_pcie5_cached();
}

void altera_set_current_adapter(int adapter_index, uint32_t pdf)
{
	if (adapter_index < 0 || adapter_index >= MAX_PORT_PER_ADP)
		return;

	altera_current_adapter = adapter_index;
	altera_adapter_modes[adapter_index].pdf = pdf;
	altera_adapter_modes[adapter_index].bus = (pdf >> 16) & 0xff;
	altera_adapter_modes[adapter_index].valid = 0;

	if (verbose) {
		printf("400G adapter cache: adapter=%d,bus=0x%02x,pdf=0x%08x\n",
			adapter_index, altera_adapter_modes[adapter_index].bus, pdf);
	}
}
