
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
#include <errno.h>
#include <regex.h>
#include <math.h>
#include "xil_sleep_api.h"
#include "xqspi_polled.h"
#include "xspi_polled.h"
#include "xfast_flash.h"
#include "ynictrl_main.h"
#include "build_version.h"
#include "altera_flash.h"


#define IS_POSITIVE_INTEGER(num) ((num) > 0 && (num) == (int)(num))
#define CARD_MODEL_100G			"100G"
#define CARD_MODEL_10G			"010G"
#define CARD_MODEL_25G			"025G"
#define CARD_MODEL_400G			"400G"
#define CARD_MODEL_BITWARE       "BW"
#define CARD_FALSE_ID			0xDEED
#define CARD_ADAPTER_FLAG		0xAD00
#define CARD_INTERFACE_ID		-1
#define CARD_SN_PREFIX			"MD"
#define CARD_MODEL_YN400G		"YN400GA7B027"	/* -q 的 TYPE：国产 400G 板统一型号 */
#define CARD_VERSION_PREFIX		"ba"
/*
 * 4 lane 引擎后 rpd 约 37MB，超过原来的 32MB；flash 是 2Gb(256MB)。
 * 400G Release 区从 ALTERA_HW_RELEASE1_ADDR(0x01630000) 起放 64MB，到 0x0562FFFF，
 * 不会碰到 ALTERA_IMG_SECTOR_ADDR(0x07FF0000) 的 MAC/fwinfo 扇区。
 */
#define FPGA_FWSIZE_LIMIT		(64*1024*1024) //64MB
#define CARD_FEC_ENABLE			"enable"
#define CARD_FEC_DISABLE		"disable"

//#define QSPI_FLASH

/*
 * 操作的卡的型号
 */
enum {
	MODEL_MIN = 0,
	MODEL_100G,
	MODEL_10G,
	MODEL_25GA,
	MODEL_25GB,
	MODEL_400G,
	MODEL_BITWARE,
	MODEL_MAX
};

const char* card[] = {
	"MD"
};
const char* speed[] = {
	"010G",
	"025G",
	"reserved",
	"100G",
	"400G",
};
const char* mode_speed[] = {
	"10G",
	"reserved",
	"reserved",
	"100G",
	"400G",
};
const char* iftype[] = {
	"F", //FIRBE
	"C", //COPPER
	"W", //WIFI
};
const char* brdtype[] = {
	"27L",
	"47L",
};
const char* hw_ver[] = {
	"A",
	"B",
	"C",
};

const char* ph_speed[] = {
	"unknown",
	"10M",
	"100M",
	"1G",
	"10G",
	"40G",
	"100G",
	"50G",
	"25G",
	"200G",
	"400G",
	"2.5G",
	"end",
};


int fd_user;
int flag = -1;   //当前卡的型号
uint16_t total_port = 0;
uint16_t adapter = CARD_FALSE_ID;
uint16_t interface = CARD_FALSE_ID;
uint8_t verbose = 0;
uint8_t hw_firmware = 1; //默认为第1个release

int neti_erase_flash(int model, const char *name);
int neti_param_valid(char *param);
int neti_model_code(const char *model);
int neti_program_update(int model, char cmd, const char *name, u32 addr, const char *sn);
int neti_write_mac(int model, u32 addr, u32 len, int if_id, char *buf);
int neti_get_sys_info(int ifport);
int neti_read_mac(int model, u32 addr, int if_id, struct neti_card *card);
int neti_erase_sector(u32 addr, u32 len, char *netname);
int neti_write_sernum(int model, u32 addr, u32 len, char *buf);
int neti_read_sernum(int model, u32 addr, char *buf, int len);
int neti_sernum_convert(u8 *src, int len);
int neti_write_fwinfo(int model, u32 addr, const char *name, const char *sn);
int neti_sernum_valid(const char *sn);
int neti_altera_info_update(u32 addr, const char *fwinfo, const char *sn, char *old_sn);
int neti_write_bootinfo(int model, u32 jump_addr, u32 img_addr, u8 num);
int neti_read_bootinfo(int model, u32 img_addr, u8 *num);
int neti_read_fwinfo(int model, u32 img_addr, char *buf, u8 num);
int neti_sync_clocks(void);

void usage(void)
{
	printf("%s %s-%s (%s %s)\n", NF_PROGRAM_NAME, VERSION, SVN_REVISION, __TIME__, __DATE__);
	printf("Usage: %s [-c model] [option]\n", NF_PROGRAM_NAME);
	printf("       %s [-h|--help] [-V|--version]\n", NF_PROGRAM_NAME);
	printf("\n");
	printf("  -c, --card model                Select the card model 400G/100G/25G/10G to be operated,\n");
	printf("                                  model name is YN400GA7B027A(YN400GA7B027B/YN400GA7B027C)/\n");
	printf("                                  MD2X100GF27LA/MD4X025GF27LB/MD4X025GF27LA/\n");
	printf("                                  MD2X025GF27LA/MD4X010GF27LA\n");
	printf("  -a, --adapter <num>             Select the Adapter to be operated,Use with -p/-s/-r\n");
	printf("  -i, --interface <num>           Select the Interface to be operated,Use with -s/-r\n");
	printf("  -p, --program <file>            Upargde/downgrade an adapter; add -n <SN> to also set the\n");
	printf("                                  serial number, otherwise the serial number in flash is kept\n");
	printf("  -b, --backup <file>             Upargde/downgrade an backup adapter\n");
	printf("  -s, --set <address>             Set an adapter mac address\n");
	printf("  -r, --read                      Read an adapter mac address\n");
	printf("  -e, --erase <file>              Erase image!\n");
	printf("  -n, --serial <SN>               Set an adapter serial number (MD..., at most %d chars)\n", NF_SERNUM_LEN);
	//printf("  -j, --jump <num>                Select the boot image, num range is 1-3\n");
	printf("  -y, --sync                      Synchronize all MD card clocks\n");
	printf("  -f, --fec enable/disable        Set Adapter fec enable/disable,only support 400G/100G\n");
	printf("  -u, --auto enable/disable       Set Adapter Auto-negotiation enable/disable\n");
	printf("  -q, --query                     Query adapters information\n");
	printf("  -v, --verbose                   Print execution process information\n");
	printf("  -h, --help                      Show this help message and exit\n");
	printf("  -V, --version                   Display version information and exit\n");
	printf("\n");
	printf("example:\n");
	printf("  update program\n");
	printf("    ynictrl -c YN400GA7B027A -a 0 -p YN400GA7B027A-R26.12.16-B6456-20261119-1X400G-a0db90d2.rpd\n");
	printf("  write the mac address of a port of the adapter\n");
	printf("    ynictrl -c YN400GA7B027A -a 0 -i 0 -s b0:47:5e:d0:00:00\n");
	printf("  read the mac address of all ports of the adapter\n");
	printf("    ynictrl -c YN400GA7B027A -a 0 -r\n");
	printf("  read the mac address of a port of the adapter\n");
	printf("    ynictrl -c YN400GA7B027A -a 0 -i 0 -r\n");
	printf("  update program and set the serial number in the same flash update\n");
	printf("    ynictrl -c YN400GA7B027A -a 0 -p YN400GA7B027A-R26.12.16-B6456-20261119-1X400G-a0db90d2.rpd -n MD400G260713002\n");
	printf("  write the serial number of the adapter\n");
	printf("    ynictrl -c YN400GA7B027A -a 0 -n MD010G250217001\n");
	//printf("  select the boot image 2\n");
	//printf("    ynictrl -c YN400GA7B027A -j 2\n");
	printf("  fec enable\n");
	printf("    ynictrl -c YN400GA7B027A -a 0 -i 0 -f enable\n");
	printf("  (其余型号把 -c 后面的型号换掉即可，如 -c MD2X100GF27LA)\n");
}


int neti_erase_flash(int model,const char *name)
{
	int Status;
	int file_fd = -1;
	int ret = XST_SUCCESS;
	size_t size;
	struct stat filestat;
	//unsigned char *src;

	if((model > MODEL_MIN) &&  (model < MODEL_MAX)) {
		/*do nothing*/
	} else {
		printf("Unsupported card model!\n");
		return XST_FAILURE;
	}


	file_fd = open(name, O_RDONLY | O_BINARY);
	if (file_fd < 0)
	{
		printf("Failed to open %s\n", name);
		ret = XST_FAILURE;
		goto neti_quit;
	}

	if (fstat(file_fd, &filestat) < 0)
	{
		printf("Failed to stat %s\n", name);
		ret = XST_FAILURE;
		goto neti_quit;
	}

	size = filestat.st_size;
	//printf("size=%ld\n", size);

	if(model == MODEL_100G || model == MODEL_25GB) {
#ifdef QSPI_FLASH
		// 调用QspiPsu Polled example
		Status = Qspi_Flash_init(&QspiPsuInstance, QSPIPSU_DEVICE_ID);
		if (Status != XST_SUCCESS)
		{
			xil_printf("QSPIPSU Generic Flash Polled Example Failed\r\n");
			ret = XST_FAILURE;
			goto neti_quit;
		}

		Qspi_Flash_erase(&QspiPsuInstance, TEST_ADDRESS, size);
#else
		Status = Xfast_FlashInit();
		if (Status != XST_SUCCESS)
		{
			xil_printf("Xfast Flash Init Failed\r\n");
			ret = XST_FAILURE;
			goto neti_quit;
		}
		xfast_flash_erase(XFAST_HW_RELEASE1_ADDR, size);
#endif

	} else if(model == MODEL_400G) {
		Status = altera_flash_erase(ALTERA_HW_RELEASE1_ADDR, size);
		if (Status != XST_SUCCESS) {
			xil_printf("Altera Flash Erase Failed\r\n");
			return XST_FAILURE;
		}

	} else {

		Status = SpiFlashInit(&SpiInstance, SPI_DEVICE_ID);
		if (Status != XST_SUCCESS) {
			xil_printf("Spi init Failed\r\n");
			return XST_FAILURE;
		}

		Spi_Flash_erase(&SpiInstance, MASTER_ADDRESS, size);

		// Spi_Flash_erase(&SpiInstance, addr, size);
		// Spi_Flash_write(&SpiInstance, addr, size, src);
		// Spi_Flash_verify(&SpiInstance, addr, size, src);

	}

	printf("erase success\n");

neti_quit:

	if (file_fd > 0) {
		close(file_fd);
	}

	return ret;
}

/*
 * -c 传的是型号；升级件校验时传的是文件名。
 * 型号只出现在名字开头，取到第一个 '-' 为止的型号段再判，避免整串文件名里的
 * "100G/400G" 被 strstr 误命中。
 */
int neti_model_code(const char *model)
{
	char name[32];
	size_t len;

	if(model == NULL)
		return MODEL_MIN;

	len = strcspn(model, "-_");
	if(len >= sizeof(name))
		return MODEL_MIN;
	memcpy(name, model, len);
	name[len] = '\0';

	/* 国产 400G 板：YN400GA7B027A / B / C，统一走 Altera QSPI flash 流程 */
	if(strncmp(name, "YN400GA7B027", 12) == 0 &&
	   (name[12] == '\0' || (name[12] >= 'A' && name[12] <= 'C' && name[13] == '\0'))) {
		return MODEL_400G;
	}

	/* 旧 MD 型号：MD<n>X<sss>G<t>nnL<ver>，前 3 位是 MD?X，第 8 位是 G */
	if(strlen(name) >= 8 && name[0] == 'M' && name[1] == 'D' && name[3] == 'X' && name[7] == 'G') {
		if(strstr(name, CARD_MODEL_100G)) {
			return MODEL_100G;
		} else if(strstr(name, CARD_MODEL_10G)) {
			return MODEL_10G;
		} else if(strstr(name, CARD_MODEL_25G)) {
			if(strstr(name, "A"))
				return MODEL_25GA;
			else if(strstr(name, "B"))
				return MODEL_25GB;
		} else if(strstr(name, CARD_MODEL_400G)) {
			return MODEL_400G;
		}
		return MODEL_MIN;
	}

	/* 兼容 "-c 400G/100G/25G/10G" 这种按速率传的旧用法 */
	if(strcmp(name, CARD_MODEL_400G) == 0)
		return MODEL_400G;
	if(strcmp(name, CARD_MODEL_100G) == 0)
		return MODEL_100G;
	if(strcmp(name, CARD_MODEL_10G) == 0)
		return MODEL_10G;
	if(strcmp(name, CARD_MODEL_25G) == 0)
		return MODEL_25GA;

	return MODEL_MIN;
}

int neti_proname_valid(char cmd, const char *name)
{
//MD4X010GF27LA-R25.06.03-B0020-20250224
//MD4X010GF27LA-B25.06.03-B0020-20250224
//MD*X***G*****-R&&.&&.&&-B%%%%-########
	int ret = XST_SUCCESS;
	char *str1 = "R";
	char *str2 = "B";
	char *str3 = "-";
	char *str4 = "MD";
	char *newname = NULL;
	char *res1 =  NULL;
	char *res2 =  NULL;
	int count = 0;
	int i;

	//文件格式判断
	if(!strstr(name,".bin")) {

		printf("file format error,");
		ret = XST_FAILURE;
		goto neti_quit;
	}


	//过滤路径
	newname = strstr(name,str4);
	if(!newname) {
		printf("file name error,");
		ret = XST_FAILURE;
		goto neti_quit;
	}

	//型号判断
	if(newname[0] != 'M' || newname[1] != 'D' || newname[3] != 'X' ||
	   newname[7] != 'G') {

		printf("network card error,");
		ret = XST_FAILURE;
		goto neti_quit;
	}


	//横线数量判断
	for(i=0;newname[i] != '\0';i++) {
		if(newname[i] == '-')
			count++;
	}
	if(count != 3) {
		printf("file name error,");
		ret = XST_FAILURE;
		goto neti_quit;

	}


	//Rxx.xx.xx or Bxx.xx.xx
	res1 = strstr(newname,str3);
	if(res1) {
		if(cmd == 'p') {
			res2 = strstr(newname,str1);
		} else if(cmd == 'b') {
			res2 = strstr(newname,str2);
		} else {
			printf("cmd is error!\n");
			ret = XST_FAILURE;
			goto neti_quit;
		}
		if(res2) {
			count = res2 - newname;
			if(newname[count+3] != '.' || newname[count+6] != '.') {
				printf("file name error,");
				ret = XST_FAILURE;
				goto neti_quit;
			}
		} else {
			printf("file name error,");
			ret = XST_FAILURE;
			goto neti_quit;
		}
	} else {
		printf("file name error,");
		ret = XST_FAILURE;
		goto neti_quit;
	}


	//B0019
	res1 = strrchr(newname,str2[0]);
	if(!res1) {
		printf("file name error,");
		ret = XST_FAILURE;
		goto neti_quit;
	}

	//时间
	res1 = strrchr(newname, '-');
	if((res1 == NULL) || (res1 == newname)) {
		printf("file name error,");
		ret = XST_FAILURE;
		goto neti_quit;
	}
	res2 = res1+1;
	count = strlen(res2);
	if(count != 12) {
		printf("file date format error,");
		ret = XST_FAILURE;
		goto neti_quit;
	}
	for(i=0;i<8;i++) {
		if(!isdigit(res2[i])) {
			printf("file date format error,");
			ret = XST_FAILURE;
			goto neti_quit;
		}
	}


neti_quit:
	if(ret == XST_FAILURE) {
		if(cmd == 'p') {
			printf("it should be <MD4X010GF27LA-R25.06.03-B0020-20250224.bin>\n");
		} else if(cmd == 'b') {
			printf("it should be <MD4X010GF27LA-B25.06.03-B0020-20250224.bin>\n");
		}
		fflush(stdout);
	}

	return ret;
}

int neti_proname_valid_new(char cmd, const char *name)
{
	regex_t regex;
	const char* pattern;
	int ret = -1;
	const char *slash = NULL;
	char *newname = NULL;

	/* 只按文件名匹配，带目录的路径（如 ../../firmware/xxx.rpd）不影响校验 */
	slash = strrchr(name, '/');
	newname = (char *)(slash ? slash + 1 : name);
	if(neti_model_code(newname) == MODEL_MIN) {
		ret = XST_FAILURE;
		goto neti_quit;
	}

	if(cmd == 'p') {
		pattern =
			"^(YN400GA7B027[ABC]|MD[0-9]X[0-9]{3}G[FCW][0-9]{2}L[ABC])"	  // 型号（新 YN400GA7B027A / 旧 MD2X100GF27LA）
			"-R[0-9]{2}\\.[0-9]{2}\\.[0-9]{2}"		   // 版本号（R25.06.07）
			"-B[0-9]{4,}"								// 构建编号（B0029）
			"-[0-9]{8}"								  // 日期（20250322）
			"-[0-9a-zA-Z]+X[0-9D]+G-[0-9a-zA-Z]{8}\\..+$";					 // 结尾和扩展名
	} else if(cmd == 'b') {
		pattern =
			"^(YN400GA7B027[ABC]|MD[0-9]X[0-9]{3}G[FCW][0-9]{2}L[ABC])"
			"-[AB][0-9]{2}\\.[0-9]{2}\\.[0-9]{2}"
			"-B[0-9]{4,}"
			"-[0-9]{8}"
			"-[0-9a-zA-Z]+X[0-9D]+G-[0-9a-zA-Z]{8}\\..+$";
	} else {
		printf("Upgrade cmd is error,it should be 'p' or 'b'!\n");
		return XST_FAILURE;
	}

	if (regcomp(&regex, pattern, REG_EXTENDED)) {
		return XST_FAILURE;
	}

	ret = regexec(&regex, newname, 0, NULL, 0);
	regfree(&regex);

	if(ret != 0) {
		ret = XST_FAILURE;
		goto neti_quit;
	}

neti_quit:
	if(ret == XST_FAILURE) {
		printf("File format error,it should be similar to ");
		if(cmd == 'p') {
			printf("<YN400GA7B027A-R26.12.16-B6456-20261119-1X400G-a0db90d2.rpd>\n");
		} else if(cmd == 'b') {
			printf("<YN400GA7B027A-B26.12.16-B6456-20261119-1X400G-a0db90d2.rpd>\n");
		}
		fflush(stdout);
	}

	return ret;
}

char* neti_find_second_last_manual(const char* str, int ch)
{
	if(str == NULL)
		return NULL;

	char* last = NULL;
	//char* second_last = NULL;

	for(; *str != '\0'; str++) {
		if (*str == ch) {
			//second_last = last;
			last = (char*)str;
		}
	}

	return last;
}

int neti_param_valid(char *param)
{
	int ret = XST_SUCCESS;
	char *endptr;

	errno = 0;

	strtol(param, &endptr, 10);

	if (param == endptr) {
		ret = XST_FAILURE;
	} else if (errno == ERANGE) {
		ret = XST_FAILURE;
	} else if (*endptr != '\0') {
		ret = XST_FAILURE;
	} else {
		/*do nothing*/
	}

	return ret;
}

int neti_get_mac(char *base_mac, char *new_mac, int num) {
	int ret = XST_SUCCESS;
	unsigned char mac_bytes[6];
	uint64_t mac_num;
	int len;

	if (sscanf(base_mac, "%02hhx:%02hhx:%02hhx:%02hhx:%02hhx:%02hhx",
			   &mac_bytes[0], &mac_bytes[1], &mac_bytes[2],
			   &mac_bytes[3], &mac_bytes[4], &mac_bytes[5]) != 6) {
		printf("MAC address Invalid\n");
		ret = XST_FAILURE;
		return ret;
	}

	mac_num = ((uint64_t)mac_bytes[0] << 40) |
			  ((uint64_t)mac_bytes[1] << 32) |
			  ((uint64_t)mac_bytes[2] << 24) |
			  ((uint64_t)mac_bytes[3] << 16) |
			  ((uint64_t)mac_bytes[4] << 8) |
						 mac_bytes[5];

	mac_num += num;

	mac_bytes[0] = (mac_num >> 40) & 0xFF;
	mac_bytes[1] = (mac_num >> 32) & 0xFF;
	mac_bytes[2] = (mac_num >> 24) & 0xFF;
	mac_bytes[3] = (mac_num >> 16) & 0xFF;
	mac_bytes[4] = (mac_num >> 8) & 0xFF;
	mac_bytes[5] = mac_num & 0xFF;


	len = snprintf(NULL, 0, "%02hhx:%02hhx:%02hhx:%02hhx:%02hhx:%02hhx",
			mac_bytes[0], mac_bytes[1], mac_bytes[2], mac_bytes[3], mac_bytes[4], mac_bytes[5]);
	snprintf(new_mac, (len+1), "%02hhx:%02hhx:%02hhx:%02hhx:%02hhx:%02hhx",
			mac_bytes[0], mac_bytes[1], mac_bytes[2], mac_bytes[3], mac_bytes[4], mac_bytes[5]);
	//printf("%s\n",new_mac);

	return ret;
}

int neti_program_update(int model, char cmd, const char *name, u32 addr, const char *sn)
{
	int Status;
	int file_fd = -1;
	int ret = XST_SUCCESS;
	size_t size;
	struct stat filestat;
	unsigned char *src = NULL;
	//u8 buffer[128];
	u32 fwaddr = 0;

	if((model > MODEL_MIN) &&  (model < MODEL_MAX)) {
		/*do nothing*/
	} else {
		printf("Unsupported card model!\n");
		return XST_FAILURE;
	}


	ret = neti_proname_valid_new(cmd, name);
	if(ret == XST_FAILURE) {
		goto neti_quit;
	}

	file_fd = open(name, O_RDONLY | O_BINARY);
	if (file_fd < 0)
	{
		printf("Failed to open %s\n", name);
		ret = XST_FAILURE;
		goto neti_quit;
	}

	if (fstat(file_fd, &filestat) < 0)
	{
		printf("Failed to stat %s\n", name);
		ret = XST_FAILURE;
		goto neti_quit;
	}

	size = filestat.st_size;
	if(cmd == 'p') {
		if(size > FPGA_FWSIZE_LIMIT) {
			printf("The file is too large (%zu bytes > %d bytes), it is not an upgrade file.\n",
				size, FPGA_FWSIZE_LIMIT);
			ret = XST_FAILURE;
			goto neti_quit;
		}
	}
	if(cmd == 'p' && model == MODEL_400G) {
		/* 擦除按 128KB 步进且多擦 1~2 个 64KB 扇区，留出余量后检查不越界 */
		u64 erase_end = (u64)addr + size + 3 * ALTERA_FLASH_SECTOR_64K;
		if(erase_end > ALTERA_IMG_SECTOR_ADDR) {
			printf("The file is too large (%zu bytes): image at 0x%08x would overlap 0x%08x.\n",
				size, addr, ALTERA_IMG_SECTOR_ADDR);
			ret = XST_FAILURE;
			goto neti_quit;
		}
	}
	src = malloc(size);
	if (!src)
	{
		printf("Failed to allocated memory\n");
		ret = XST_FAILURE;
		goto neti_quit;
	}
	memset(src, 0, size);

	if (read(file_fd, src, size) < size)
	{
		printf("Read file failed\n");
		ret = XST_FAILURE;
		goto neti_quit;
	}

	if(verbose)
		xil_printf("FPGA update program.\r\n");

	if(model == MODEL_100G || model == MODEL_25GB) {
#ifdef QSPI_FLASH
		// 调用QspiPsu Polled example
		Status = Qspi_Flash_init(&QspiPsuInstance, QSPIPSU_DEVICE_ID);
		if (Status != XST_SUCCESS)
		{
			xil_printf("QSPIPSU Generic Flash Polled Example Failed\r\n");
			ret = XST_FAILURE;
			goto neti_quit;
		}
		Qspi_Flash_erase(&QspiPsuInstance, addr, size);

		Qspi_Flash_update(&QspiPsuInstance, addr, src, size);

		// Qspi_Flash_read(&QspiPsuInstance, addr, ReadBuffer, 128);

		Qspi_Flash_verify(&QspiPsuInstance, addr, src, size);

		xil_printf("Successfully ran QSPIPSU Generic Flash Polled Test\r\n");
#else
		Status = Xfast_FlashInit();
		if (Status != XST_SUCCESS)
		{
			xil_printf("Xfast Flash Init Failed\r\n");
			ret = XST_FAILURE;
			goto neti_quit;
		}
		Status = xfast_flash_erase(addr, size);
		if (Status != XST_SUCCESS)
		{
			xil_printf("Xfast Flash Erase Failed\r\n");
			ret = XST_FAILURE;
			goto neti_quit;
		}
		Status = xfast_flash_write_high(addr , size, src);
		if (Status != XST_SUCCESS)
		{
			xil_printf("Xfast Flash Write Failed\r\n");
			ret = XST_FAILURE;
			goto neti_quit;
		}
		Status = xfast_flash_verify_high(addr , size, src);
		if (Status != XST_SUCCESS)
		{
			xil_printf("Xfast Flash verify Failed\r\n");
			ret = XST_FAILURE;
			goto neti_quit;
		}
		fwaddr = XFAST_IMG_SECTOR_ADDR;
#endif
	} else if(model == MODEL_400G) {

		Status = altera_flash_erase(addr, size);
		if (Status != XST_SUCCESS) {
			xil_printf("Altera Flash Erase Failed\r\n");
			ret = XST_FAILURE;
			goto neti_quit;
		}
		Status = altera_flash_write(addr, size, src);
		if (Status != XST_SUCCESS) {
			xil_printf("Altera Flash Write Failed\r\n");
			ret = XST_FAILURE;
			goto neti_quit;
		}
		Status = altera_flash_verify(addr, size, src);
		if (Status != XST_SUCCESS) {
			xil_printf("Altera Flash Verify Failed\r\n");
			ret = XST_FAILURE;
			goto neti_quit;
		}
		fwaddr = ALTERA_IMG_SECTOR_ADDR;
	} else {

		Status = SpiFlashInit(&SpiInstance, SPI_DEVICE_ID);
		if (Status != XST_SUCCESS) {
			xil_printf("Spi init Failed\r\n");
			ret = XST_FAILURE;
			goto neti_quit;
		}

		Status = Spi_Flash_erase(&SpiInstance, addr, size);
		if (Status != XST_SUCCESS) {
			xil_printf("Spi Erase Failed\r\n");
			ret = XST_FAILURE;
			goto neti_quit;
		}
		Status = Spi_Flash_write(&SpiInstance, addr, size, src);
		if (Status != XST_SUCCESS) {
			xil_printf("Spi Write Failed\r\n");
			ret = XST_FAILURE;
			goto neti_quit;
		}
		Status = Spi_Flash_verify(&SpiInstance, addr, size, src);
		if (Status != XST_SUCCESS) {
			xil_printf("Spi Verify Failed\r\n");
			ret = XST_FAILURE;
			goto neti_quit;
		}
		fwaddr = IMG_SECTOR_10G;
	}

	/* 版本串（以及 -n 给的序列号）必须在 RSU 切换之前写进 info 扇区：切换会重配 FPGA，之后 BAR 不可用 */
	ret = neti_write_fwinfo(model, fwaddr, name, sn);
	if(ret != XST_SUCCESS) {
		printf("firmware info write error!\n");
		ret = XST_FAILURE;
		goto neti_quit;
	}

	if(model == MODEL_400G) {
		printf("update success,");
		sleep(2);
		Status = rsu_image_update(ALTERA_HW_RELEASE1_ADDR);
		//Status = altera_update_act();
		if (Status == XST_SUCCESS) {
			printf("please execute the 'reboot' command.\n");
		} else {
			printf("please turn off the power.\n");
		}
	} else {
		printf("update success,");
		xfast_flash_update();
		Status = xfast_update_act();
		if (Status == XST_SUCCESS) {
			printf("please execute the 'reboot' command.\n");
		} else {
			printf("please turn off the power.\n");
		}
	}

neti_quit:

	if (file_fd > 0) {
		close(file_fd);
	}
	if(src) {
		free(src);
	}

	return ret;
}

int neti_write_mac(int model, u32 addr, u32 len,int if_id, char *buf)
{
	int Status;
	int ret = XST_SUCCESS;
	int i,j;
	u8 *buffer = NULL;
	char *token = NULL;
	u8 port = 0;
	u16 offset = 0;
	u8 *fs_buf = NULL;

	if((model > MODEL_MIN) &&  (model < MODEL_MAX)) {
		/*do nothing*/
	} else {
		printf("Unsupported card model!\n");
		return XST_FAILURE;
	}

	//mac地址有效性检测
	if (strlen(buf) != 17) {
		printf("mac address invalid\n");
		ret = XST_FAILURE;
		goto neti_quit;
	}
	for (i = 0; i < 17; i++) {
		if (i % 3 == 2) {
			if ((buf[i] != ':') && (buf[i] != '-')) {
				printf("invalid mac address separator\n");
				ret = XST_FAILURE;
				goto neti_quit;
			}
		} else {
			if (!isxdigit(buf[i])) {
				printf("invalid mac address number\n");
				ret = XST_FAILURE;
				goto neti_quit;
			}
		}
	}


	if(if_id == CARD_FALSE_ID) {
		printf("Missing -i parameters!\n");
		ret = XST_FAILURE;
		goto neti_quit;
	} else {
		port = if_id & 0xff;
	}

	buffer = malloc(len);
	if(!buffer) {
		printf("Failed to allocate memory\n");
		ret = XST_FAILURE;
		goto neti_quit;
	}
	memset(buffer, 0, len);

	j = 0;
	token = strtok(buf, ":");
	while(token != NULL) {
		if(j >= 6 ) {
			printf("Invalid mac address\n");
			ret = XST_FAILURE;
			goto neti_quit;
		}
		buffer[j++] = (uint8_t)strtol(token, NULL, 16);
		token = strtok(NULL, ":");
	}
	//for(i = 0;i< len;i++) {
	//	printf("buf=0x%02x,", buffer[i]);
	//}
	//printf("\n");

	if(model == MODEL_100G || model == MODEL_25GB) {
#ifdef QSPI_FLASH
		// 调用QspiPsu Polled example
		Status = Qspi_Flash_init(&QspiPsuInstance, QSPIPSU_DEVICE_ID);
		if (Status != XST_SUCCESS)
		{
			xil_printf("QSPIPSU Generic Flash Polled Example Failed\r\n");
			ret = XST_FAILURE;
			goto neti_quit;
		}

		//先读出数据再擦除
		fs_buf = malloc(sizeof(u8) * (NF_PORT_SIZE * MAX_FPGA_ADAPTER));
		if(!fs_buf) {
			printf("failed to malloc memory read flash\n");
			ret = XST_FAILURE;
			goto neti_quit;
		}
		memset(fs_buf, 0, sizeof(u8) * (NF_PORT_SIZE * MAX_FPGA_ADAPTER));
		ReadCmd = QUAD_READ_CMD;
		Qspi_Flash_read(&QspiPsuInstance, addr, fs_buf, (NF_PORT_SIZE * MAX_FPGA_ADAPTER));
		offset += (port) * NF_PORT_SIZE;
		memcpy((fs_buf + offset), buffer, len);
		// for(int j = 0; j < 128; j++) {
		//	 if((j % 16) == 0) {
		//		 printf("\n");
		//	 }
		//	 printf("0x%02x ", fs_buf[j]);
		// }
		// printf("\n");


		Qspi_Flash_erase(&QspiPsuInstance, addr, (NF_PORT_SIZE * MAX_FPGA_ADAPTER));
		Qspi_Flash_update(&QspiPsuInstance, addr, fs_buf, (NF_PORT_SIZE * MAX_FPGA_ADAPTER));
		// Qspi_Flash_read(&QspiPsuInstance, addr, ReadBuffer, 32);
		Qspi_Flash_verify(&QspiPsuInstance, addr, fs_buf, (NF_PORT_SIZE * MAX_FPGA_ADAPTER));

#else
		Status = Xfast_FlashInit();
		if (Status != XST_SUCCESS)
		{
			xil_printf("Xfast Flash Init Failed\n");
			ret = XST_FAILURE;
			goto neti_quit;
		}

		//先读出数据再擦除
		fs_buf = malloc(sizeof(u8) * NF_WRITE_SIZE);
		if(!fs_buf) {
			printf("failed to malloc memory read flash\n");
			ret = XST_FAILURE;
			goto neti_quit;
		}
		memset(fs_buf, 0, sizeof(u8) * NF_WRITE_SIZE);
		xfast_flash_read_high(addr, NF_WRITE_SIZE, fs_buf);
		offset += (port) * NF_PORT_SIZE;
		memcpy((fs_buf + offset), buffer, len);
#if 0
		for(int j = 0; j < 128; j++) {
			if((j % 16) == 0) {
				printf("\n");
			}
			printf("0x%02x ", fs_buf[j]);
		}
		printf("\n");
#endif

		xfast_flash_erase(addr, NF_WRITE_SIZE);
		xfast_flash_write_high(addr , NF_WRITE_SIZE, fs_buf);
		xfast_flash_verify_high(addr , NF_WRITE_SIZE, fs_buf);
#endif
		xfast_update_mac();
	} else if(model == MODEL_400G) {

		//先读出数据再擦除
		fs_buf = malloc(sizeof(u8) * NF_WRITE_SIZE);
		if(!fs_buf) {
			printf("failed to malloc memory read flash\n");
			ret = XST_FAILURE;
			goto neti_quit;
		}
		memset(fs_buf, 0, sizeof(u8) * NF_WRITE_SIZE);
		altera_flash_read(addr, NF_WRITE_SIZE, fs_buf);
		offset += (port) * NF_PORT_SIZE;
		memcpy((fs_buf + offset), buffer, len);
#if 0
		for(int j = 0; j < 128; j++) {
			if((j % 16) == 0) {
				printf("\n");
			}
			printf("0x%02x ", fs_buf[j]);
		}
		printf("\n");
#endif
		altera_flash_erase(addr, NF_WRITE_SIZE);
		altera_flash_write(addr , NF_WRITE_SIZE, fs_buf);
		altera_flash_verify(addr , NF_WRITE_SIZE, fs_buf);

	} else {
		Status = SpiFlashInit(&SpiInstance, SPI_DEVICE_ID);
		if (Status != XST_SUCCESS) {
			xil_printf("Spi init Failed\r\n");
			return XST_FAILURE;
		}
		//先读出数据再擦除
		fs_buf = malloc(sizeof(u8) * NF_WRITE_SIZE);
		if(!fs_buf) {
			printf("failed to malloc memory read flash\n");
			ret = XST_FAILURE;
			goto neti_quit;
		}
		memset(fs_buf, 0, sizeof(u8) * NF_WRITE_SIZE);

		Spi_Flash_read(&SpiInstance, addr, NF_WRITE_SIZE, fs_buf);
		offset += (port) * NF_PORT_SIZE;

		memcpy((fs_buf + offset), buffer, len);

		// for(int j = 0; j < 128; j++) {
		//	 if((j % 16) == 0) {
		//		 printf("\n");
		//	 }
		//	 printf("0x%02x ", fs_buf[j]);
		// }
		// printf("\n");

		Spi_Flash_erase(&SpiInstance, addr, NF_WRITE_SIZE);
		Spi_Flash_write(&SpiInstance, addr, NF_WRITE_SIZE, fs_buf);
		Spi_Flash_verify(&SpiInstance, addr, NF_WRITE_SIZE, fs_buf);
	}
	printf("set one mac address success\n");

neti_quit:
	if(buffer) {
		free(buffer);
	}
	if(fs_buf) {
		free(fs_buf);
	}

	return ret;
}

int neti_get_sys_info(int ifport)
{
	int ret = XST_SUCCESS;
	nf_adapters *u_nfadpt;
	nf_sys_info *u_nfsys = NULL;
	int i,j,k;
	char hw_info[16];
	char *token = NULL;
	const char *str1 = "ff:ff:ff:ff:ff:ff";
	const char *str2 = "00:00:00:00:00:00";
	int id;
	uint8_t tspd,tport,tif,tbrd,thw;
	uint8_t mulpt;
	char tmpmac[20];
	char *pos = NULL;
	uint8_t len = 0;
	uint16_t ph_cnt;
	//u8 hw_pos = 0;
	u8 link_pos = 0;


	u_nfadpt = malloc(sizeof(nf_adapters));
	if(!u_nfadpt) {
		printf("Adapter failed to allocate memory\n");
		ret = XST_FAILURE;
		goto neti_quit;
	}
	memset(u_nfadpt, 0, sizeof(nf_adapters));
	for(i=0;i<MAX_PORT_PER_ADP;i++) {
		u_nfsys = malloc(sizeof(nf_sys_info) * MAX_FPGA_ADAPTER);
		if(!u_nfsys) {
			printf("Failed to allocate memory,adapter=%d\n",i);
			ret = XST_FAILURE;
			goto neti_quit;
		}
		memset(u_nfsys, 0, sizeof(nf_sys_info) * MAX_FPGA_ADAPTER);
		u_nfadpt->info[i] = u_nfsys;
		//u_nfadpt.info = u_nfsys;
	}

	ret = ioctl(fd_user, IOCTL_SET_NET_INFO, u_nfadpt);
	if(ret < 0) {
		printf("%s ioctl failed\n", __func__);
		ret = XST_FAILURE;
		goto neti_quit;
	} else {
		if(ifport == CARD_FALSE_ID) {

			if(u_nfadpt->info == NULL) {
				printf("info is NULL\n");
			}
			if (u_nfadpt->info && u_nfadpt->num > 0) {
				for(i=0;i<u_nfadpt->num;i++) {
					link_pos = 0;
					u_nfadpt->adp_id[i] = i;
					printf("Adapter %d:\n", u_nfadpt->adp_id[i]);

					printf(" FPGA IMAGE:\n");
					tspd = tport = tif = tbrd = thw = 0;
					tspd = (u_nfadpt->model[i] >> 12) & 0xf;
					tport = (u_nfadpt->model[i] >> 8) & 0xf;
					tif = (u_nfadpt->model[i] >> 6) & 0x3;
					tbrd = (u_nfadpt->model[i] >> 4) & 0x3;
					thw = u_nfadpt->model[i] & 0xf;
					/* 当前运行的镜像：Boot 镜像的版本寄存器最高字节固定为 0xba，其余为 Active 镜像 */
					printf("   BANK        : ");
					if(((u_nfadpt->version[i] >> 24) & 0xff) == 0xba) {
						printf("%s\n", "Boot");
					} else {
						printf("%s\n", "Active");
					}
					printf("   MODE        : ");
					if((u_nfadpt->speed[i] > MD_LINK_SPEED_UNKNOWN) &&
							(u_nfadpt->speed[i] < MD_LINK_SPEED_END)) {
						ph_cnt = log2(u_nfadpt->speed[i]);
						if(IS_POSITIVE_INTEGER(ph_cnt) &&
							   (u_nfadpt->totalport[i] > 0 && u_nfadpt->totalport[i] <= MAX_PORT_PER_ADP)) {
							printf("%dX%s\n",u_nfadpt->totalport[i], ph_speed[(ph_cnt+1)]);
						} else {
							printf("unknown\n");
						}
					} else {
						printf("unknown\n");
					}
					printf("   TYPE        : ");
					if(tspd == 4) {
						/* 400G 板（YN400GA7B027A/B/C）统一显示产品型号 */
						printf("%s\n", CARD_MODEL_YN400G);
					} else if((tspd >= 0) && (tspd <= 4) && (tif >= 0) && (tif <= 2)
							&& (tbrd >= 0) && (tbrd <= 1) && (thw >= 0) && (thw <= 2)) {
						snprintf(hw_info, sizeof(hw_info), "%s%dX%s%s%s%s",
							card[0], tport, speed[tspd], iftype[tif], brdtype[tbrd], hw_ver[thw]);
						printf("%.*s\n", 13, hw_info);
					} else {
						printf("%s\n", "");
					}
					printf("   VERSION     : ");
					if(((u_nfadpt->version[i] >> 24) & 0xff) != 0xba) {
						#if 0
						if(tspd == 3) { //100G卡
							neti_read_bootinfo(MODEL_100G, XFAST_IMG_SECTOR_ADDR, &hw_pos);
							if((hw_pos == FIRMWARE_2) || (hw_pos == FIRMWARE_3)) {
								neti_read_fwinfo(MODEL_100G, XFAST_IMG_SECTOR_ADDR, (char *)u_nfadpt->firmware[i], hw_pos);
							}
						}
						#endif
						if(u_nfadpt->firmware[i][0] == 'R' || u_nfadpt->firmware[i][0] == 'A') {
							pos = neti_find_second_last_manual((char *)u_nfadpt->firmware[i], '-');
							if(pos) {
								len = pos - (char*)u_nfadpt->firmware[i];
							} else {
								len = 24;
							}
							printf("%.*s\n", len, u_nfadpt->firmware[i]);
						} else {
							printf("%s\n", "");
						}
					} else {
						printf("%s\n", "");
					}
					printf("   CHIPVERSION : ");
					printf("%x", u_nfadpt->version[i]);
					if(((u_nfadpt->version[i] >> 24) & 0xff) != 0xba) {
						if(u_nfadpt->firmware[i][0] == 'R' || u_nfadpt->firmware[i][0] == 'A') {
							pos = strrchr((char*)u_nfadpt->firmware[i], '-');
							if(pos) {
								printf("-%s\n", (pos+1));
							} else {
								printf("\n");
							}
						} else {
							printf("\n");
						}
					} else {
						printf("\n");
					}
					printf(" Serial Number : ");
					if(strstr((char *)u_nfadpt->sernum[i], CARD_SN_PREFIX)) {
						printf("%.*s\n", NF_SERNUM_LEN, u_nfadpt->sernum[i]);
					} else {
						printf("%s\n", "");
					}
					for(j=0;j<u_nfadpt->pnum[i];j++) {
						((u_nfadpt->info)[i][j]).if_id = j;
						printf("  Interface %d:\n", ((u_nfadpt->info)[i][j]).if_id);
						printf("    PCI SLOT            : %s\n", ((u_nfadpt->info)[i][j]).slot);
						printf("    PCI DEVICE ID       : %s\n", ((u_nfadpt->info)[i][j]).id);

						mulpt = (u_nfadpt->info)[i][j].mulport;
						if(mulpt == 1) {
							printf("    MAC                 : ");
							if((strncmp(((u_nfadpt->info)[i][j]).mac, str1, strlen(str1)) == 0) ||
							   (strncmp(((u_nfadpt->info)[i][j]).mac, str2, strlen(str2)) == 0)) {
								 printf("%s\n", "");
							} else {
								printf("%s\n", ((u_nfadpt->info)[i][j]).mac);
							}
							printf("    SPEED               : ");
							if((u_nfadpt->speed[i] > MD_LINK_SPEED_UNKNOWN) &&
									(u_nfadpt->speed[i] < MD_LINK_SPEED_END)) {
								ph_cnt = log2(u_nfadpt->speed[i]);
								if(IS_POSITIVE_INTEGER(ph_cnt)) {
									printf("%s\n",ph_speed[ph_cnt+1]);
								} else {
									printf("unknown\n");
								}
							} else {
								printf("\n");
							}
							printf("    STATUS              : ");
							printf("%s\n",((((u_nfadpt->info)[i][j].status >> j) & 0x1)== 1) ? "up" : "down");
						} else if((mulpt > 1) && (mulpt <= 8)) {
							memcpy(tmpmac, (u_nfadpt->info)[i][j].mac, 17);
							for(k=0;k<mulpt;k++) {
								printf("      PORT%d:\n", k);
								printf("        MAC             : ");
								if((strncmp(tmpmac, str1, strlen(str1)) == 0) ||
								   (strncmp(tmpmac, str2, strlen(str2)) == 0)) {
									printf("%s\n", "");
								} else {
									neti_get_mac((u_nfadpt->info)[i][j].mac, tmpmac, k);
									printf("%s\n", tmpmac);
								}
								printf("        SPEED           : ");
								if((u_nfadpt->speed[i] > MD_LINK_SPEED_UNKNOWN) &&
										(u_nfadpt->speed[i] < MD_LINK_SPEED_END)) {
									ph_cnt = log2(u_nfadpt->speed[i]);
									if(IS_POSITIVE_INTEGER(ph_cnt)) {
										printf("%s\n",ph_speed[ph_cnt+1]);
									} else {
										printf("unknown\n");
									}
								} else {
									printf("\n");
								}
								printf("        STATUS          : ");
								printf("%s\n",((((u_nfadpt->info)[i][j].status >> link_pos) & 0x1) == 1) ? "up" : "down");
								link_pos++;
							}
						} else {
							/*do nothing*/
						}
					}
					total_port += j;

				}
			} else {
				printf("network card not exist\n");
			}
		} else {
			if(u_nfadpt->info == NULL) {
				printf("info is NULL\n");
			}
			if (u_nfadpt->info && u_nfadpt->num > 0) {
				for(i=0;i<u_nfadpt->num;i++) {

					u_nfadpt->adp_id[i] = i;
					for(j=0;j<u_nfadpt->pnum[i];j++) {
						((u_nfadpt->info)[i][j]).if_id = j;
					}
					total_port += j;
				}
			}

			if((ifport & 0xff00) == CARD_ADAPTER_FLAG) {
				id = ifport & 0xff;
				if(id < u_nfadpt->num) {
					for(i=0;i<u_nfadpt->num;i++) {
						if(id == u_nfadpt->adp_id[i]) {
							k = 0;
							token = strtok(((u_nfadpt->info)[i][0]).slot, ":.");
							while(token != NULL) {
								ret += (uint8_t)strtol(token, NULL, 16) << ((3-k)* 8);
								k++;
								token = strtok(NULL, ":.");
							}
						}
					}
					//printf("adapter ret=0x%08x\n",ret);
				} else {
					printf("input adapter %d error.\n",id);
					ret = -(XST_FAILURE);
					goto neti_quit;
				}
			} else {
				if(ifport < MAX_FPGA_ADAPTER) {
					for(i=0;i<u_nfadpt->num;i++) {
						for(j=0;j<u_nfadpt->pnum[i];j++) {
							if(ifport == ((u_nfadpt->info)[i][j]).if_id) {
								k = 0;
								token = strtok(((u_nfadpt->info)[i][j]).slot, ":.");
								while(token != NULL) {
									ret += (uint8_t)strtol(token, NULL, 16) << ((3-k)* 8);
									k++;
									token = strtok(NULL, ":.");
								}
							}
						}
					}
					//printf("interface ret=0x%08x\n",ret);
				} else {
					printf("input interface %d error.\n",ifport);
					ret = -(XST_FAILURE);
					goto neti_quit;
				}
			}
		}
	}


neti_quit:
	if(u_nfsys) {
		free(u_nfsys);
	}

	return ret;
}

int neti_read_mac(int model, u32 addr,int if_id, struct neti_card *card)
{
	int status;
	int ret = XST_SUCCESS;
	int i,j;
	u8 *fs_buf = NULL;
	//u8 readbuf[128];

	if((model > MODEL_MIN) &&  (model < MODEL_MAX)) {
		/*do nothing*/
	} else {
		printf("Unsupported card model!\n");
		return XST_FAILURE;
	}

	fs_buf = malloc(sizeof(u8) * (NF_PORT_SIZE * MAX_FPGA_ADAPTER));
	if(!fs_buf) {
		printf("failed to malloc memory read flash\n");
		ret = XST_FAILURE;
		goto neti_quit;
	}
	memset(fs_buf, 0, sizeof(u8) * (NF_PORT_SIZE * MAX_FPGA_ADAPTER));

	if(model == MODEL_100G || model == MODEL_25GB) {
#ifdef QSPI_FLASH
		// 调用QspiPsu Polled example
		status = Qspi_Flash_init(&QspiPsuInstance, QSPIPSU_DEVICE_ID);
		if (status != XST_SUCCESS)
		{
			xil_printf("QSPIPSU Generic Flash Polled Example Failed\r\n");
			ret = XST_FAILURE;
			goto neti_quit;
		}

		ReadCmd = QUAD_READ_CMD;
		Qspi_Flash_read(&QspiPsuInstance, addr, fs_buf, (NF_PORT_SIZE * MAX_FPGA_ADAPTER)); //8*16
		// for(j = 0; j < 128; j++) {
		//	 if((j % 16) == 0) {
		//		 printf("\n");
		//	 }
		//	 printf("0x%02x ", fs_buf[j]);
		// }
		// printf("\n");
#else
		status = Xfast_FlashInit();
		if (status != XST_SUCCESS)
		{
			xil_printf("Xfast Flash Init Failed\r\n");
			ret = XST_FAILURE;
			goto neti_quit;
		}

		xfast_flash_read_high(addr, (NF_PORT_SIZE * MAX_FPGA_ADAPTER), fs_buf);

#if 0
		for(int j = 0; j < 256; j++) {
			if((j % 16) == 0) {
				printf("\n");
			}
			printf("0x%02x ", fs_buf[j]);
		}
		printf("\n");
#endif
#endif
	} else if(model == MODEL_400G) {
		status = altera_flash_read(addr, (NF_PORT_SIZE * MAX_FPGA_ADAPTER), fs_buf);
		if (status != XST_SUCCESS)
		{
			xil_printf("Altera Flash Read Failed\r\n");
			ret = XST_FAILURE;
			goto neti_quit;
		}

	} else {

		status = SpiFlashInit(&SpiInstance, SPI_DEVICE_ID);
		if (status != XST_SUCCESS) {
			xil_printf("Spi init Failed\r\n");
			return XST_FAILURE;
		}

		status = Spi_Flash_read(&SpiInstance, addr, (NF_PORT_SIZE * MAX_FPGA_ADAPTER), fs_buf);
		if(status != XST_SUCCESS)
		{
			xil_printf("Spi read Failed\r\n");
			return XST_FAILURE;
		}

	}

	if(verbose)
		printf("read mac address success\n");
	if((if_id >= 0) && (if_id < MAX_FPGA_ADAPTER)) {
		j = if_id * 16;
		if((fs_buf[j] != 0xff) && (fs_buf[j+1] != 0xff) && \
		(fs_buf[j+2] != 0xff)) {
			snprintf(card[if_id].name, IFNAMSIZ, "port%d", (if_id+1));
			snprintf(card[if_id].mac, sizeof(card[if_id].mac),"%02x:%02x:%02x:%02x:%02x:%02x" ,fs_buf[j], fs_buf[j+1], fs_buf[j+2], fs_buf[j+3], fs_buf[j+4], fs_buf[j+5]);
			printf("%s:%s\n", card[if_id].name, card[if_id].mac);
		}
		printf("\n");
	} else if(if_id == CARD_FALSE_ID) {
		j = 0;
		for(i = 0; i < MAX_FPGA_ADAPTER; i++) {
			if((fs_buf[j] != 0xff) && (fs_buf[j+1] != 0xff) && \
			(fs_buf[j+2] != 0xff)) {
				snprintf(card[i].name, IFNAMSIZ, "port%d", (i+1));
				snprintf(card[i].mac, sizeof(card[i].mac),"%02x:%02x:%02x:%02x:%02x:%02x" ,fs_buf[j], fs_buf[j+1], fs_buf[j+2], fs_buf[j+3], fs_buf[j+4], fs_buf[j+5]);
				printf("%s:%s\n", card[i].name, card[i].mac);
			}
			j += 16;

		}
		printf("\n");

	} else {
		printf("parameter -i invalid\n");
		return XST_FAILURE;
	}

neti_quit:
	if(fs_buf) {
		free(fs_buf);
	}

	return ret;
}

#if 0
int neti_erase_sector(u32 addr, u32 len, char *netname)
{
	int status;
	int ret = XST_SUCCESS;
	int netlen = 0;

	//一个网卡多个网口情况
	netlen = strlen(netname);
	if((netname == NULL) || (netname[0] == '\0')) {
		printf("invalid netname %s\n", netname);
		ret = XST_FAILURE;
		goto neti_quit;
	}
	if(netname[netlen-1] >= '0' && netname[netlen-1] <= '9') {
		//do nothing
	} else {
		printf("netname %s invalid\n", netname);
		ret = XST_FAILURE;
		goto neti_quit;
	}

	ret = ioctl(fd_user, IOCTL_SET_NET_NAME, netname);
	if(ret < 0) {
		perror("ioctl failed\n");
		ret = XST_FAILURE;
		goto neti_quit;
	}

	// 调用QspiPsu Polled example
	status = Qspi_Flash_init(&QspiPsuInstance, QSPIPSU_DEVICE_ID);
	if (status != XST_SUCCESS)
	{
		xil_printf("QSPIPSU Generic Flash Polled Example Failed\r\n");
		ret = XST_FAILURE;
		goto neti_quit;
	}
	Qspi_Flash_erase(&QspiPsuInstance, addr, len);

	xil_printf("erase a sector success\r\n");

neti_quit:


	return ret;
}
#endif


int neti_write_sernum(int model, u32 addr, u32 len, char *buf)
{
	int Status;
	int ret = XST_SUCCESS;
	u8 *buffer = NULL;
	//u8 port = 0;
	u16 offset = 0;
	u8 *fs_buf = NULL;

	if((model > MODEL_MIN) &&  (model < MODEL_MAX)) {
		/*do nothing*/
	} else {
		printf("Unsupported card model!\n");
		return XST_FAILURE;
	}


	if(model == MODEL_100G || model == MODEL_25GB) {
#ifdef QSPI_FLASH
		// 调用QspiPsu Polled example
		Status = Qspi_Flash_init(&QspiPsuInstance, QSPIPSU_DEVICE_ID);
		if (Status != XST_SUCCESS)
		{
			xil_printf("QSPIPSU Generic Flash Polled Example Failed\r\n");
			ret = XST_FAILURE;
			goto neti_quit;
		}

		//先读出数据再擦除
		fs_buf = malloc(sizeof(u8) * (NF_PORT_SIZE * MAX_FPGA_ADAPTER));
		if(!fs_buf) {
			printf("failed to malloc memory read flash\n");
			ret = XST_FAILURE;
			goto neti_quit;
		}
		memset(fs_buf, 0, sizeof(u8) * (NF_PORT_SIZE * MAX_FPGA_ADAPTER));
		ReadCmd = QUAD_READ_CMD;
		Qspi_Flash_read(&QspiPsuInstance, addr, fs_buf, (NF_PORT_SIZE * MAX_FPGA_ADAPTER));
		offset += (port) * NF_PORT_SIZE;
		memcpy((fs_buf + offset), buffer, len);
		// for(int j = 0; j < 128; j++) {
		//	 if((j % 16) == 0) {
		//		 printf("\n");
		//	 }
		//	 printf("0x%02x ", fs_buf[j]);
		// }
		// printf("\n");


		Qspi_Flash_erase(&QspiPsuInstance, addr, (NF_PORT_SIZE * MAX_FPGA_ADAPTER));
		Qspi_Flash_update(&QspiPsuInstance, addr, fs_buf, (NF_PORT_SIZE * MAX_FPGA_ADAPTER));
		// Qspi_Flash_read(&QspiPsuInstance, addr, ReadBuffer, 32);
		Qspi_Flash_verify(&QspiPsuInstance, addr, fs_buf, (NF_PORT_SIZE * MAX_FPGA_ADAPTER));
#else

		Status = Xfast_FlashInit();
		if (Status != XST_SUCCESS)
		{
			xil_printf("Xfast Flash Init Failed\n");
			ret = XST_FAILURE;
			goto neti_quit;
		}

		//先读出数据再擦除
		fs_buf = malloc(sizeof(u8) * NF_WRITE_SIZE);
		if(!fs_buf) {
			printf("failed to malloc memory read flash\n");
			ret = XST_FAILURE;
			goto neti_quit;
		}
		memset(fs_buf, 0, sizeof(u8) * NF_WRITE_SIZE);
		xfast_flash_read_high(addr, NF_WRITE_SIZE, fs_buf);
		offset += NF_SERNUM_ADDR;
		memcpy((fs_buf + offset), buf, strlen(buf));
#if 0
		for(int j = 0; j < 128; j++) {
			if((j % 16) == 0) {
				printf("\n");
			}
			printf("0x%02x ", fs_buf[j]);
		}
		printf("\n");
#endif

		xfast_flash_erase(addr, NF_WRITE_SIZE);
		xfast_flash_write_high(addr , NF_WRITE_SIZE, fs_buf);
		xfast_flash_verify_high(addr , NF_WRITE_SIZE, fs_buf);

		memset(fs_buf, 0, sizeof(u8) * NF_WRITE_SIZE);
		Status = xfast_flash_read_high(addr, NF_WRITE_SIZE, fs_buf);
		if (Status != XST_SUCCESS) {
			xil_printf("Spi Read Failed\r\n");
			return XST_FAILURE;
		}
#endif
	} else if(model == MODEL_400G) {

		char old_sn[NF_SERNUM_LEN_RU];

		ret = neti_altera_info_update(addr, NULL, buf, old_sn);
		if(ret != XST_SUCCESS)
			goto neti_quit;
		printf("set success,");
		printf("Serial number : %s (was %s)\n", buf, old_sn[0] ? old_sn : "empty");
		goto neti_quit;

	} else {
		Status = SpiFlashInit(&SpiInstance, SPI_DEVICE_ID);
		if (Status != XST_SUCCESS) {
			xil_printf("Spi init Failed\r\n");
			return XST_FAILURE;
		}
		//先读出数据再擦除
		fs_buf = malloc(sizeof(u8) * NF_WRITE_SIZE);
		if(!fs_buf) {
			printf("failed to malloc memory read flash\n");
			ret = XST_FAILURE;
			goto neti_quit;
		}
		memset(fs_buf, 0, sizeof(u8) * NF_WRITE_SIZE);

		Spi_Flash_read(&SpiInstance, addr, NF_WRITE_SIZE, fs_buf);
		offset += NF_SERNUM_ADDR;

		memcpy((fs_buf + offset), buf, strlen(buf));

		//for(int j = 0; j < 160; j++) {
		//	if((j % 16) == 0) {
		//		printf("\n");
		//	}
		//	printf("0x%02x ", fs_buf[j]);
		//}
		//printf("\n");

		Spi_Flash_erase(&SpiInstance, addr, NF_WRITE_SIZE);
		Spi_Flash_write(&SpiInstance, addr, NF_WRITE_SIZE, fs_buf);
		Spi_Flash_verify(&SpiInstance, addr, NF_WRITE_SIZE, fs_buf);

		memset(fs_buf, 0, sizeof(u8) * NF_WRITE_SIZE);
		Status = Spi_Flash_read(&SpiInstance, addr, NF_WRITE_SIZE, fs_buf);
		if (Status != XST_SUCCESS) {
			xil_printf("Spi Read Failed\r\n");
			return XST_FAILURE;
		}
	}
	printf("set success,");
	printf("Serial number : %.*s\n",(int)strlen(buf), (fs_buf + NF_SERNUM_ADDR));

neti_quit:
	if(buffer) {
		free(buffer);
	}
	if(fs_buf) {
		free(fs_buf);
	}

	return ret;
}


int neti_read_sernum(int model, u32 addr, char *buf, int len)
{
	int status;
	int ret = XST_SUCCESS;
	u8 *fs_buf = NULL;

	if((model > MODEL_MIN) &&  (model < MODEL_MAX)) {
		/*do nothing*/
	} else {
		printf("Unsupported card model!\n");
		return XST_FAILURE;
	}


	if(model == MODEL_100G || model == MODEL_25GB) {
		// 调用QspiPsu Polled example
#ifdef QSPI_FLASH
		status = Qspi_Flash_init(&QspiPsuInstance, QSPIPSU_DEVICE_ID);
		if (status != XST_SUCCESS)
		{
			xil_printf("QSPIPSU Generic Flash Polled Example Failed\r\n");
			ret = XST_FAILURE;
			goto neti_quit;
		}
		fs_buf = malloc(sizeof(u8) * (NF_PORT_SIZE * MAX_FPGA_ADAPTER));
		if(!fs_buf) {
			printf("failed to malloc memory read flash\n");
			ret = XST_FAILURE;
			goto neti_quit;
		}
		memset(fs_buf, 0, sizeof(u8) * (NF_PORT_SIZE * MAX_FPGA_ADAPTER));

		ReadCmd = QUAD_READ_CMD;
		Qspi_Flash_read(&QspiPsuInstance, addr, fs_buf, (NF_PORT_SIZE * MAX_FPGA_ADAPTER)); //8*16
		// for(j = 0; j < 128; j++) {
		//	 if((j % 16) == 0) {
		//		 printf("\n");
		//	 }
		//	 printf("0x%02x ", fs_buf[j]);
		// }
		// printf("\n");
#endif
	} else {

		status = SpiFlashInit(&SpiInstance, SPI_DEVICE_ID);
		if (status != XST_SUCCESS) {
			xil_printf("Spi init Failed\r\n");
			return XST_FAILURE;
		}

		fs_buf = malloc(sizeof(u8) * len);
		if(!fs_buf) {
			printf("failed to malloc memory read flash\n");
			ret = XST_FAILURE;
			goto neti_quit;
		}

		memset(fs_buf, 0, sizeof(u8) * len);

		status = Spi_Flash_read(&SpiInstance, addr, len, fs_buf);
		if(status != XST_SUCCESS)
		{
			xil_printf("Spi read Failed\r\n");
			return XST_FAILURE;
		}

		memcpy(buf, fs_buf, len);
	}

	if(verbose)
		printf("read serial number success\n");

neti_quit:
	if(fs_buf) {
		free(fs_buf);
	}

	return ret;
}


int neti_sernum_convert(u8 *src, int len)
{
	int ret = XST_SUCCESS;
	int i;
	u8 tmp;

	for(i=0;i< len;i+=4) {

		tmp = src[i];
		src[i] = src[i+3];
		src[i+3] = tmp;

		tmp = src[i+1];
		src[i+1] = src[i+2];
		src[i+2] = tmp;
	}

	return ret;


}

/*
 * 从升级件文件名取版本串：YN400GA7B027C-R26.12.02-B0116-20261123-1X400G-4203a24c.rpd
 * → R26.12.02-B0116-20261123-1X400G-4203a24c（型号后第一个 '-' 到扩展名之前）。
 * 只看文件名本身，不看目录（目录里带 '-' 时会截错位置），不改写调用者的字符串。
 * 返回 1 = 取到版本串；0 = 不是 Release/All 升级件（如 Boot 镜像），不写版本串；-1 = 格式错。
 */
static int neti_fwinfo_from_name(const char *name, char *out, size_t outlen)
{
	const char *base = strrchr(name, '/');
	const char *start;
	const char *dot;
	size_t n;

	base = base ? base + 1 : name;
	start = strchr(base, '-');
	if(!start || start[1] == '\0')
		return -1;
	start++;
	if(start[0] != 'R' && start[0] != 'A')
		return 0;
	dot = strrchr(start, '.');
	n = dot ? (size_t)(dot - start) : strlen(start);
	if(n == 0 || n >= outlen)
		return -1;
	memcpy(out, start, n);
	out[n] = '\0';
	return 1;
}

/*
 * 序列号：CARD_SN_PREFIX 开头、只含字母数字、不超过 NF_SERNUM_LEN 个字符。
 * -q 只显示带 CARD_SN_PREFIX 的序列号；超长会写进后面的版本串区域。
 */
int neti_sernum_valid(const char *sn)
{
	size_t n;

	if(!sn)
		return XST_FAILURE;
	n = strlen(sn);
	if(n == 0 || n > NF_SERNUM_LEN || strncmp(sn, CARD_SN_PREFIX, strlen(CARD_SN_PREFIX)) != 0)
		return XST_FAILURE;
	for(size_t i = 0; i < n; i++) {
		if(!isalnum((unsigned char)sn[i]))
			return XST_FAILURE;
	}
	return XST_SUCCESS;
}

/*
 * 400G 板 info 扇区（MAC / 序列号 / 版本串，共 NF_WRITE_SIZE 字节）的读改写。
 * fwinfo / sn 为 NULL 的字段保持 flash 原值不动。几百字节的小块不打进度条，
 * 每一步失败都返回失败（原来擦/写/校验的返回值都被忽略）。
 * old_sn 非空时带回改写前的序列号（NF_SERNUM_LEN_RU 字节，不是序列号时为空串）。
 */
int neti_altera_info_update(u32 addr, const char *fwinfo, const char *sn, char *old_sn)
{
	int ret = XST_SUCCESS;
	u8 *fs_buf = NULL;
	u8 *slot;
	char prev_sn[NF_SERNUM_LEN_RU];

	fs_buf = malloc(NF_WRITE_SIZE);
	if(!fs_buf) {
		printf("failed to malloc memory read flash\n");
		return XST_FAILURE;
	}
	altera_flash_set_quiet(1);
	memset(fs_buf, 0, NF_WRITE_SIZE);
	if(altera_flash_read(addr, NF_WRITE_SIZE, fs_buf) != XST_SUCCESS) {
		printf("info sector read failed\n");
		ret = XST_FAILURE;
		goto out;
	}
	memcpy(prev_sn, fs_buf + NF_SERNUM_ADDR, NF_SERNUM_LEN);
	prev_sn[NF_SERNUM_LEN] = '\0';
	if(!strstr(prev_sn, CARD_SN_PREFIX))
		prev_sn[0] = '\0';
	if(old_sn)
		memcpy(old_sn, prev_sn, NF_SERNUM_LEN_RU);

	if(fwinfo) {
		slot = fs_buf + NF_FIRMWARE_ADDR + (NF_FIRMWARE_LEN * (hw_firmware - 1));
		memset(slot, 0xff, NF_FIRMWARE_LEN);
		memcpy(slot, fwinfo, strlen(fwinfo) + 1);
	}
	if(sn) {
		slot = fs_buf + NF_SERNUM_ADDR;
		memset(slot, 0xff, NF_SERNUM_LEN_RU);
		memcpy(slot, sn, strlen(sn));
		slot[strlen(sn)] = '\0';
	}

	if(altera_flash_erase(addr, NF_WRITE_SIZE) != XST_SUCCESS ||
	   altera_flash_write(addr, NF_WRITE_SIZE, fs_buf) != XST_SUCCESS ||
	   altera_flash_verify(addr, NF_WRITE_SIZE, fs_buf) != XST_SUCCESS) {
		printf("info sector update failed\n");
		ret = XST_FAILURE;
		goto out;
	}

out:
	altera_flash_set_quiet(0);
	free(fs_buf);
	return ret;
}

/*
 * 写入软件版本号 version（升级后 -q 的 VERSION / CHIPVERSION 读的就是它）；
 * sn 非空时同一次读改写里一起更新序列号，为空则序列号保持 flash 原值。
 */
int neti_write_fwinfo(int model, u32 addr, const char *name, const char *sn)
{
	//int Status;
	int ret = XST_SUCCESS;
	u8 *buffer = NULL;
	//u8 port = 0;
	u16 offset = 0;
	u8 *fs_buf = NULL;
	char fwinfo[NF_FIRMWARE_LEN];
	char *newbuf = fwinfo;
	int has_fw;
	u32 len;

	if((model > MODEL_MIN) &&  (model < MODEL_MAX)) {
		/*do nothing*/
	} else {
		printf("Unsupported card model!\n");
		return XST_FAILURE;
	}

	has_fw = neti_fwinfo_from_name(name, fwinfo, sizeof(fwinfo));
	if(has_fw < 0) {
		printf("can not get firmware version from file name %s\n", name);
		return XST_FAILURE;
	}

	if(model == MODEL_400G) {
		char old_sn[NF_SERNUM_LEN_RU];

		if(has_fw == 0 && !sn)
			return XST_SUCCESS;
		ret = neti_altera_info_update(addr, has_fw ? fwinfo : NULL, sn, old_sn);
		if(ret != XST_SUCCESS)
			return ret;
		if(has_fw)
			printf("firmware info : %s\n", fwinfo);
		if(sn)
			printf("serial number : %s (updated, was %s)\n", sn, old_sn[0] ? old_sn : "empty");
		else
			printf("serial number : %s (unchanged)\n", old_sn[0] ? old_sn : "empty");
		return XST_SUCCESS;
	}

	if(has_fw == 0) {
		goto neti_quit;
	}
	len = strlen(fwinfo);
	(void)len;

	if(model == MODEL_100G || model == MODEL_25GB) {
#ifdef QSPI_FLASH
		// 调用QspiPsu Polled example
		Status = Qspi_Flash_init(&QspiPsuInstance, QSPIPSU_DEVICE_ID);
		if (Status != XST_SUCCESS)
		{
			xil_printf("QSPIPSU Generic Flash Polled Example Failed\r\n");
			ret = XST_FAILURE;
			goto neti_quit;
		}

		//先读出数据再擦除
		fs_buf = malloc(sizeof(u8) * (NF_PORT_SIZE * MAX_FPGA_ADAPTER));
		if(!fs_buf) {
			printf("failed to malloc memory read flash\n");
			ret = XST_FAILURE;
			goto neti_quit;
		}
		memset(fs_buf, 0, sizeof(u8) * (NF_PORT_SIZE * MAX_FPGA_ADAPTER));
		ReadCmd = QUAD_READ_CMD;
		Qspi_Flash_read(&QspiPsuInstance, addr, fs_buf, (NF_PORT_SIZE * MAX_FPGA_ADAPTER));
		offset += (port) * NF_PORT_SIZE;
		memcpy((fs_buf + offset), buffer, len);
		// for(int j = 0; j < 128; j++) {
		//	 if((j % 16) == 0) {
		//		 printf("\n");
		//	 }
		//	 printf("0x%02x ", fs_buf[j]);
		// }
		// printf("\n");


		Qspi_Flash_erase(&QspiPsuInstance, addr, (NF_PORT_SIZE * MAX_FPGA_ADAPTER));
		Qspi_Flash_update(&QspiPsuInstance, addr, fs_buf, (NF_PORT_SIZE * MAX_FPGA_ADAPTER));
		// Qspi_Flash_read(&QspiPsuInstance, addr, ReadBuffer, 32);
		Qspi_Flash_verify(&QspiPsuInstance, addr, fs_buf, (NF_PORT_SIZE * MAX_FPGA_ADAPTER));
#else
		//先读出数据再擦除
		fs_buf = malloc(sizeof(u8) * NF_WRITE_SIZE);
		if(!fs_buf) {
			printf("failed to malloc memory read flash\n");
			ret = XST_FAILURE;
			goto neti_quit;
		}
		memset(fs_buf, 0, sizeof(u8) * NF_WRITE_SIZE);
		xfast_flash_read_high(addr, NF_WRITE_SIZE, fs_buf);
		offset += (NF_FIRMWARE_ADDR + (NF_FIRMWARE_LEN * (hw_firmware - 1)));
		memcpy((fs_buf + offset), newbuf, strlen(newbuf)+1);
		xfast_flash_erase(addr, NF_WRITE_SIZE);
		xfast_flash_write_high(addr, NF_WRITE_SIZE, fs_buf);
		xfast_flash_verify_high(addr, NF_WRITE_SIZE, fs_buf);
#endif

	} else {
#if 0
		Status = SpiFlashInit(&SpiInstance, SPI_DEVICE_ID);
		if (Status != XST_SUCCESS) {
			xil_printf("Spi init Failed\r\n");
			return XST_FAILURE;
		}
#endif
		//先读出数据再擦除
		fs_buf = malloc(sizeof(u8) * NF_WRITE_SIZE);
		if(!fs_buf) {
			printf("failed to malloc memory read flash\n");
			ret = XST_FAILURE;
			goto neti_quit;
		}
		memset(fs_buf, 0, sizeof(u8) * NF_WRITE_SIZE);

		Spi_Flash_read(&SpiInstance, addr, NF_WRITE_SIZE, fs_buf);
		offset += NF_FIRMWARE_ADDR;
		memcpy((fs_buf + offset), newbuf, strlen(newbuf)+1);

		Spi_Flash_erase(&SpiInstance, addr, NF_WRITE_SIZE);
		Spi_Flash_write(&SpiInstance, addr, NF_WRITE_SIZE, fs_buf);
		Spi_Flash_verify(&SpiInstance, addr, NF_WRITE_SIZE, fs_buf);

	}

neti_quit:
	if(buffer) {
		free(buffer);
	}
	if(fs_buf) {
		free(fs_buf);
	}

	return ret;
}


/*
 * 选择启动哪个固件
 */
int neti_write_bootinfo(int model, u32 jump_addr, u32 img_addr, u8 num)
{
	int ret = XST_SUCCESS;
	u16 offset = 0;
	u8 *fs_buf = NULL;

	if((model > MODEL_MIN) &&  (model < MODEL_MAX)) {
		/*do nothing*/
	} else {
		printf("Unsupported card model!\n");
		return XST_FAILURE;
	}


	if(model == MODEL_100G || model == MODEL_25GB) {

		//写入启动的固件
		fs_buf = malloc(sizeof(u8) * NF_WRITE_SIZE);
		if(!fs_buf) {
			printf("failed to malloc memory read flash\n");
			ret = XST_FAILURE;
			goto neti_quit;
		}
		memset(fs_buf, 0, sizeof(u8) * NF_WRITE_SIZE);
		xfast_flash_read_high(img_addr, NF_WRITE_SIZE, fs_buf);

		offset += NF_BOOT_FW_ADDR;
		memcpy((fs_buf + offset), &num, sizeof(num));
		xfast_flash_erase(img_addr, NF_WRITE_SIZE);
		xfast_flash_write_high(img_addr, NF_WRITE_SIZE, fs_buf);
		xfast_flash_verify_high(img_addr, NF_WRITE_SIZE, fs_buf);
	}
	else if(model == MODEL_400G) {

		//写入启动的固件
		fs_buf = malloc(sizeof(u8) * NF_WRITE_SIZE);
		if(!fs_buf) {
			printf("failed to malloc memory read flash\n");
			ret = XST_FAILURE;
			goto neti_quit;
		}
		memset(fs_buf, 0, sizeof(u8) * NF_WRITE_SIZE);
		altera_flash_read(img_addr, NF_WRITE_SIZE, fs_buf);

		offset += NF_BOOT_FW_ADDR;
		memcpy((fs_buf + offset), &num, sizeof(num));
		altera_flash_erase(img_addr, NF_WRITE_SIZE);
		altera_flash_write(img_addr, NF_WRITE_SIZE, fs_buf);
		altera_flash_verify(img_addr, NF_WRITE_SIZE, fs_buf);
	}
	printf("select boot image success.\n");

neti_quit:
	if(fs_buf) {
		free(fs_buf);
	}

	return ret;
}

/*
 * 读取启动的固件
 */
int neti_read_bootinfo(int model, u32 img_addr, u8 *num)
{
	int ret = XST_SUCCESS;
	u8 *fs_buf = NULL;

	if((model > MODEL_MIN) &&  (model < MODEL_MAX)) {
		/*do nothing*/
	} else {
		printf("Unsupported card model!\n");
		return XST_FAILURE;
	}

	if(model == MODEL_100G || model == MODEL_25GB) {
		fs_buf = malloc(sizeof(u8) * NF_WRITE_SIZE);
		if(!fs_buf) {
			printf("failed to malloc memory read flash\n");
			ret = XST_FAILURE;
			goto neti_quit;
		}
		memset(fs_buf, 0, sizeof(u8) * NF_WRITE_SIZE);
		xfast_flash_read_high(img_addr, NF_WRITE_SIZE, fs_buf);
		*num = fs_buf[NF_BOOT_FW_ADDR];
	}
	else if(model == MODEL_400G) {
		fs_buf = malloc(sizeof(u8) * NF_WRITE_SIZE);
		if(!fs_buf) {
			printf("failed to malloc memory read flash\n");
			ret = XST_FAILURE;
			goto neti_quit;
		}
		memset(fs_buf, 0, sizeof(u8) * NF_WRITE_SIZE);
		altera_flash_read(img_addr, NF_WRITE_SIZE, fs_buf);
		*num = fs_buf[NF_BOOT_FW_ADDR];
	}

neti_quit:
	if(fs_buf) {
		free(fs_buf);
	}

	return ret;
}

/*
 * 读取固件版本
 */
int neti_read_fwinfo(int model, u32 img_addr, char *buf, u8 num)
{
	int ret = XST_SUCCESS;
	u8 *fs_buf = NULL;
	u16 offset = 0;

	if((model > MODEL_MIN) &&  (model < MODEL_MAX)) {
		/*do nothing*/
	} else {
		printf("Unsupported card model!\n");
		return XST_FAILURE;
	}

	if(model == MODEL_100G || model == MODEL_25GB) {
		fs_buf = malloc(sizeof(u8) * NF_WRITE_SIZE);
		if(!fs_buf) {
			printf("failed to malloc memory read flash\n");
			ret = XST_FAILURE;
			goto neti_quit;
		}
		memset(fs_buf, 0, sizeof(u8) * NF_WRITE_SIZE);
		xfast_flash_read(img_addr, NF_WRITE_SIZE, fs_buf);
		offset += (NF_FIRMWARE_ADDR + (NF_FIRMWARE_LEN * (num - 1)));
		memcpy(buf, (fs_buf+offset), strlen(buf));
		//memcpy((fs_buf + offset), buf, strlen(buf));

	}

neti_quit:
	if(fs_buf) {
		free(fs_buf);
	}

	return ret;
}

int neti_sync_clocks(void)
{
	int ret = XST_SUCCESS;

	ret = ioctl(fd_user, IOCTL_SET_CLOCK, NULL);
	if(ret < 0) {
		printf("%s ioctl failed\n", __func__);
		ret = XST_FAILURE;
		goto neti_quit;
	}
	printf("clock sync success.\n");

neti_quit:

	return ret;
}

int neti_set_fec(int flag)
{
	int ret = XST_SUCCESS;

	ret = ioctl(fd_user, IOCTL_SET_FEC, &flag);
	if(ret < 0) {
		printf("%s ioctl failed\n", __func__);
		ret = XST_FAILURE;
		goto neti_quit;
	}
	printf("fec %s success.\n", ((flag == 1) ? "enable" : "disable"));

neti_quit:

	return ret;
}

int neti_set_up(int flag)
{
	int ret = XST_SUCCESS;

	ret = ioctl(fd_user, IOCTL_SET_UP, &flag);
	if(ret < 0) {
		printf("%s ioctl failed\n", __func__);
		ret = XST_FAILURE;
		goto neti_quit;
	}
	printf("Auto-negotiation: %s.\n", (((flag & 0xf) == 1) ? "on" : "off"));

neti_quit:

	return ret;
}


#if 0
int neti_program_load(int model, const char *name, u32 addr)
{
	int status;
	int ret = XST_SUCCESS;
	u32 fwaddr = 0;

	if(model == MODEL_100G || model == MODEL_10G || model == MODEL_25G) {
		/*do nothing*/
	} else {
		printf("Unsupported card model!\n");
		return XST_FAILURE;
	}

	if(model == MODEL_100G) {
		status = Xfast_FlashInit();
		if (status != XST_SUCCESS)
		{
			xil_printf("Xfast Flash Init Failed\r\n");
			ret = XST_FAILURE;
			goto neti_quit;
		}
		xfast_flash_erase(addr, size);
		xfast_flash_write_high(addr , size, src);
		xfast_flash_verify_high(addr , size, src);
		fwaddr = XFAST_IMG_SECTOR_ADDR;
	} else {

		status = SpiFlashInit(&SpiInstance, SPI_DEVICE_ID);
		if (status != XST_SUCCESS) {
			xil_printf("Spi init Failed\r\n");
			ret = XST_FAILURE;
			goto neti_quit;
		}

		Spi_Flash_erase(&SpiInstance, addr, size);
		Spi_Flash_write(&SpiInstance, addr, size, src);
		Spi_Flash_verify(&SpiInstance, addr, size, src);
		fwaddr = IMG_SECTOR_10G;
	}

	printf("update success.\n");


neti_quit:


	return ret;
}
#endif

#define MAX_LINE_LEN 512
#define MAX_FILES 64

typedef struct {
    char name[256];
    long size;
} file_entry_t;

typedef struct{
	char mac[64];
	char sn[64];
}bw_info_struct;

int bw_pciID(char *pci_id)
{
	FILE *fp;
	int ret = XST_SUCCESS;
    char line[256];
    char *first_colon, *second_colon;

	fp = popen("bw_card_list -v", "r");
    if (fp == NULL) {
        ret = XST_FAILURE;
        return ret;
    }

    while (fgets(line, sizeof(line), fp) != NULL) {
        if (strstr(line, "Location") != NULL) {
            first_colon = strchr(line, ':');
            if (first_colon != NULL) {
                second_colon = strchr(first_colon + 1, ':');
                if (second_colon != NULL) {
                    sscanf(second_colon + 1, "%s", pci_id);
                }
            }
            break;
        }
    }
    pclose(fp);
	return ret;
}

int bw_readMAC(int if_id, struct neti_card *card)
{
    FILE *fp;
    int ret = XST_SUCCESS;
    char cmd[128], mac[64];
    char pci_id[64];
    char line[256];
    char *first_colon, *second_colon;

    bw_pciID(pci_id);

    sprintf(cmd, "bw_bmc_file_utility -d PCI:%s -c 0 download /lfs/bw_mac.txt", pci_id);
    system(cmd);
   
    fp = fopen("bw_mac.txt", "r");
    if (fp == NULL) {
        ret = XST_FAILURE;
        return ret;
    }

	while (fgets(line, sizeof(line), fp) != NULL) {
        if (strstr(line, "MAC") != NULL) {
            first_colon = strchr(line, ':');
            if (first_colon != NULL) {
                second_colon = strchr(first_colon, ':');
                if (second_colon != NULL) {
                    sscanf(second_colon + 1, "%s", mac);
                }
            }
        }
    }
    fclose(fp);

    if(verbose)
        printf("read mac address success\n");
    if((if_id >= 0) && (if_id < MAX_FPGA_ADAPTER)) {
            snprintf(card[if_id].name, IFNAMSIZ, "port%d", (if_id+1));
            strcpy(card[if_id].mac, mac);
            printf("%s:%s\n", card[if_id].name, card[if_id].mac);
    }
    printf("\n");

	sprintf(cmd, "rm bw_mac.txt");
    system(cmd);

	return ret;
}

int bw_info(bw_info_struct *info)
{
    FILE *fp;
    int ret = XST_SUCCESS;
    char cmd[128];
    char pci_id[64];
    char line[256];
    char *first_colon, *second_colon;

    bw_pciID(pci_id);

    sprintf(cmd, "bw_bmc_file_utility -d PCI:%s -c 0 download /lfs/bw_mac.txt", pci_id);
    system(cmd);

    fp = fopen("bw_mac.txt", "r");
    if (fp == NULL) {
		strcpy(info->sn, "XXXXXXXX");
		strcpy(info->mac, "00:11:22:33:44:55");
        ret = XST_FAILURE;
        return ret;
    }

	while (fgets(line, sizeof(line), fp) != NULL) {
		if (strstr(line, "MAC") != NULL) {
            first_colon = strchr(line, ':');
            if (first_colon != NULL) {
                second_colon = strchr(first_colon, ':');
                if (second_colon != NULL) {
                    sscanf(second_colon + 1, "%s", info->mac);
                }
            }
        } else if (strstr(line, "SN") != NULL) {
            first_colon = strchr(line, ':');
            if (first_colon != NULL) {
                second_colon = strchr(first_colon, ':');
                if (second_colon != NULL) {
                    sscanf(second_colon + 1, "%s", info->sn);
                }
            }
        }
	}

    fclose(fp);

	printf("SN:%s\n", info->sn);
	printf("MAC:%s\n", info->mac);

	sprintf(cmd, "rm bw_mac.txt");
    system(cmd);

	return ret;
}

int build_infofile(void)
{
	FILE *fp;
	bw_info_struct info;
	bw_info(&info);

	fp = fopen("/migadmin/syscfg/bw_info.txt", "w");

	fprintf(fp, "MAC:%s\n", info.mac);
	fprintf(fp, "Serial Number:%s\n", info.sn);

    fclose(fp);

	return 0;
}

int bw_writeMac(char *mac)
{
	FILE *fp;
	int ret = XST_SUCCESS;
	int i;
	char cmd[128];
	char pci_id[64];
	bw_info_struct info;

    if (strlen(mac) != 17) {
        printf("mac address invalid\n");
        ret = XST_FAILURE;
        return ret;
    }

	bw_info(&info);

    for (i = 0; i < 17; i++) {
        if (i % 3 == 2) {
            if ((mac[i] != ':') && (mac[i] != '-')) {
                printf("invalid mac address separator\n");
                ret = XST_FAILURE;
                return ret;
            }
        } else {
            if (!isxdigit(mac[i])) {
                printf("invalid mac address number\n");
                ret = XST_FAILURE;
                return ret;
            }
        }
    }

    if (access("/var/run", F_OK) != 0) {
        if (mkdir("/var/run", 0755) != 0) {
            return 1;
        }
    }

    fp = fopen("bw_mac.txt", "w");
    if (fp == NULL) {
		ret = XST_FAILURE;
        return ret;
    }

    fprintf(fp, "MAC:%s\n", info.mac);
	fprintf(fp, "SN:%s\n", info.sn);
    fclose(fp);

	bw_pciID(pci_id);

	sprintf(cmd, "bw_bmc_file_utility -d PCI:%s -c 0 upload bw_mac.txt", pci_id); 
	system(cmd);

	sprintf(cmd, "rm bw_mac.txt");
    system(cmd);

	return ret;
}

int count_indent(const char *line) 
{
    int count = 0;
    while (line[count] == ' ' || line[count] == '\t') {
        count++;
    }
    return count;
}

int parse_file_line(const char *line, file_entry_t *file) 
{
    const char *paren = strchr(line, '(');
    if (!paren) return -1;

    int indent = count_indent(line);
    const char *start = line + indent;
    int name_len = paren - start;
    while (name_len > 0 && isspace(start[name_len - 1])) {
        name_len--;
    }
    if (name_len <= 0 || name_len >= sizeof(file->name)) return -1;
    strncpy(file->name, start, name_len);
    file->name[name_len] = '\0';

    sscanf(paren, "(%ld bytes)", &file->size);
    return 0;
}

int extract_fpga_files(FILE *input, file_entry_t *files, int max_files) 
{
    char line[MAX_LINE_LEN];
    int fpga_depth = -1;
    int in_fpga = 0;
    int file_count = 0;

    while (fgets(line, sizeof(line), input)) {
        line[strcspn(line, "\n")] = '\0';
        if (strlen(line) == 0) continue;

        int depth = count_indent(line);

        if (strstr(line, "fpga") && strstr(line, "(dir)")) {
            fpga_depth = depth;
            in_fpga = 1;
            continue;
        }

        if (in_fpga && depth > fpga_depth) {
            if (strstr(line, "(dir)")) {
                continue;
            }
            if (file_count < max_files) {
                if (parse_file_line(line, &files[file_count]) == 0) {
                    file_count++;
                }
            }
        }

        if (in_fpga && depth <= fpga_depth && strstr(line, "(dir)") && !strstr(line, "fpga")) {
            in_fpga = 0;
        }
    }
    return file_count;
}

int bw_program(char *name)
{
	char pci_id[64], cmd[256];
	file_entry_t fpga_files[MAX_FILES];
    int count = 0;

	bw_pciID(pci_id);

	FILE *fp = popen("bw_bmc_file_utility -d PCI:01:00.1 -c 0 list -t 2>&1", "r");
    if (fp) {
        count = extract_fpga_files(fp, fpga_files, MAX_FILES);
        pclose(fp);
    }

    for (int i = 0; i < count; i++) {    
		if(strcmp(fpga_files[i].name, name) == 0){
			sprintf(cmd, "bw_bmc_file_utility -d PCI:%s -c 0 delete /fpga/%s", pci_id, name);
    		system(cmd);
			break;
		}
    }

    sprintf(cmd, "bw_bmc_fpga_load -d PCI:%s -c 0 program %s", pci_id, name);
    system(cmd);

    return 0;
}

int bw_writeSN(char *sn)
{
	FILE *fp;
	int ret = XST_SUCCESS;
	char cmd[128];
	char pci_id[64];
	bw_info_struct info;

	bw_info(&info);

    fp = fopen("bw_mac.txt", "w");
	//printf("open /var/run/bw_mac.txt\n");
    if (fp == NULL) {
		ret = XST_FAILURE;
        return ret;
    }

    fprintf(fp, "MAC:%s\n", info.mac);
	fprintf(fp, "SN:%s\n", sn);
    fclose(fp);

	bw_pciID(pci_id);

	sprintf(cmd, "bw_bmc_file_utility -d PCI:%s -c 0 upload bw_mac.txt", pci_id); 
	system(cmd);

	sprintf(cmd, "rm bw_mac.txt");
    system(cmd);

	return 0;
}

int card_bitware(int argc, char *argv[])
{
	int ret = XST_SUCCESS;
	uint8_t has_option = FALSE;
	int opt;
	struct neti_card card[MAX_FPGA_ADAPTER] = {0};
	struct option long_options[] = {
		{"help",		no_argument,	   0, 'h'},
		{"version",		no_argument,	   0, 'V'},
		{"card",		required_argument, 0, 'c'},
		{"program",		required_argument, 0, 'p'},
		{"backup",		required_argument, 0, 'b'},
		{"erase",		required_argument, 0, 'e'},
		{"set",			required_argument, 0, 's'},
		{"serial",		required_argument, 0, 'n'},
		{"read",		no_argument,	   0, 'r'},
		{"adapter",		required_argument, 0, 'a'},
		{"interface",	required_argument, 0, 'i'},
		{"verbose",		no_argument,	   0, 'v'},
		{"jump",		required_argument, 0, 'j'},
		{"sync",		no_argument,	   0, 'y'},
		{"fec",			required_argument, 0, 'f'},
		{"auto",		required_argument, 0, 'u'},
		{0, 0, 0, 0}  // 结构体结束标志
	};

	if (argc < 2) {
		usage();
		return XST_FAILURE;
	}

	// 设置支持的选项
	while ((opt = getopt_long(argc, argv, "hqVvryp:b:e:s:c:a:i:n:j:f:u:", long_options, NULL)) != -1) {
		has_option = TRUE;
		switch (opt) {
			case 'h':
				usage();
				break;
			case 'v':
				verbose = 1;
				break;
			case 'V':
				printf("ynictrl %s (%s %s)\n", VERSION, __TIME__, __DATE__);
				break;
			case 'c':
				if(strstr(optarg, CARD_MODEL_BITWARE)) {
                    flag = MODEL_BITWARE;
                } else {
					printf("card model error!\n");
					ret = XST_FAILURE;
					goto quit_pro;
				}
				if(verbose)
					printf("-c-flag=%d\n", flag);
				break;
			case 'i':
				interface = atoi(optarg);
				if(verbose)
					printf("interface=%d\n",interface);
				break;
			case 'n':
				bw_writeSN(optarg);
				break;
			case 'r':
				if(flag == MODEL_BITWARE) {
					bw_readMAC(interface, card);
				}
				break;
			case 's':
				if(flag == MODEL_BITWARE){
					ret = bw_writeMac(optarg);
					break;
				}
				break;
			case 'p':
				bw_program(optarg);
				break;
			case '?':
			case ':':
			default:
				break;
		}
	}
	if(!has_option) {
		printf("no option input\n");
		ret = XST_FAILURE;
		goto quit_pro;
	}

quit_pro:
	if(fd_user > 0) {
		close(fd_user);
	}

	return ret;
}

// 主函数
int main(int argc, char *argv[])
{
	int ret = XST_SUCCESS;
	uint8_t has_option = FALSE;
	int opt;
	struct neti_card card[MAX_FPGA_ADAPTER] = {0};
	u32 addr,addr1;
	struct option long_options[] = {
		{"help",		no_argument,	   0, 'h'},
		{"version",		no_argument,	   0, 'V'},
		{"card",		required_argument, 0, 'c'},
		{"program",		required_argument, 0, 'p'},
		{"backup",		required_argument, 0, 'b'},
		{"erase",		required_argument, 0, 'e'},
		{"set",			required_argument, 0, 's'},
		{"serial",		required_argument, 0, 'n'},
		{"read",		no_argument,	   0, 'r'},
		{"adapter",		required_argument, 0, 'a'},
		{"interface",	required_argument, 0, 'i'},
		{"verbose",		no_argument,	   0, 'v'},
		{"jump",		required_argument, 0, 'j'},
		{"sync",		no_argument,	   0, 'y'},
		{"fec",			required_argument, 0, 'f'},
		{"auto",		required_argument, 0, 'u'},
		{0, 0, 0, 0}  // 结构体结束标志
	};
	uint32_t pdf;
	uint32_t fec;
	uint32_t uflag;
	char *pname;
	/*
	 * -p / -n 在全部参数解析完之后才执行：-p 带 -n 时序列号要和版本串在同一次 info 扇区
	 * 更新里写进去（RSU 切换之后 BAR 不可用，不能再单独写），且 -n 写在 -p 前后都行。
	 */
	const char *prog_name = NULL;
	u32 prog_addr = 0;
	const char *sn_arg = NULL;


	if (argc < 2) {
		usage();
		return XST_FAILURE;
	}
	//for(int i=0; i < argc; i++) {
	//	printf("argv[%d]=%s  ",i, argv[i]);
	//}
	//printf("\n");

	for(int i=0;i<argc;i++){
		if(!strcmp(argv[i],"BW")){
			card_bitware(argc, argv);
			return 0;
		}
	}

	fd_user = open(IMG_DEV, O_RDWR | O_SYNC);
	if (fd_user < 0)
	{
		printf("Can't open %s.\n", IMG_DEV);
		return XST_FAILURE;
	}

	// 设置支持的选项
	while ((opt = getopt_long(argc, argv, "hqVvryp:b:e:s:c:a:i:n:j:f:u:", long_options, NULL)) != -1) {
		has_option = TRUE;
		switch (opt) {
			case 'h':
				usage();
				break;
			case 'q':
				neti_get_sys_info(CARD_FALSE_ID);
				break;
			case 'V':
				printf("ynictrl %s (%s %s)\n", VERSION, __TIME__, __DATE__);
				break;
			case 'v':
				verbose = 1;
				break;
			case 'c':
				flag = neti_model_code(optarg);
				if(flag == MODEL_MIN) {
					printf("card model error! should be YN400GA7B027A/B/C or MDxxxxxx\n");
					ret = XST_FAILURE;
					goto quit_pro;
				}
				if(verbose)
					printf("-c-flag=%d\n", flag);
				break;
			case 'a':
				ret = neti_param_valid(optarg);
				if(ret == XST_FAILURE) {
					printf("Parameter -a Invalid!\n");
					goto quit_pro;
				}
				if((atoi(optarg)) < 0 || (atoi(optarg) >= MAX_PORT_PER_ADP)) {
					printf("Parameter -a Invalid!\n");
					ret = XST_FAILURE;
					goto quit_pro;
				}
				adapter = CARD_ADAPTER_FLAG | atoi(optarg);
				pdf = neti_get_sys_info(adapter);
				if(verbose)
					printf("adapter=0x%08x,pdf=0x%08x\n",adapter,pdf);
				if(pdf > 0) {
					ret = ioctl(fd_user, IOCTL_SET_NET_ID, &pdf);
					if(ret < 0) {
						perror("ioctl failed\n");
						ret = XST_FAILURE;
						goto quit_pro;
					}
					if(flag == MODEL_400G) {
						altera_set_current_adapter(atoi(optarg), pdf);
					}
				} else {
					printf("Parameter -a get bus error!\n");
					ret = XST_FAILURE;
					goto quit_pro;
				}
				break;
			case 'i':
				ret = neti_param_valid(optarg);
				if(ret == XST_FAILURE) {
					printf("Parameter -i Invalid!\n");
					goto quit_pro;
				}
				if((atoi(optarg)) < 0 || (atoi(optarg) >= MAX_FPGA_ADAPTER)) {
					printf("Parameter -i Invalid!\n");
					ret = XST_FAILURE;
					goto quit_pro;
				}
				interface = atoi(optarg);
				if(verbose)
					printf("interface=%d\n",interface);
				break;
			case 'r':
				if(flag == MODEL_100G || flag == MODEL_25GB) {
#ifdef QSPI_FLASH
					addr = IMG_SECTOR_100G;
#else
					addr = XFAST_IMG_SECTOR_ADDR;
#endif
				} else if(flag == MODEL_400G) {
					addr = ALTERA_IMG_SECTOR_ADDR;
				} else {
					addr = IMG_SECTOR_10G;
				}
				neti_read_mac(flag, addr, interface, card);
				if(verbose) {
					if(flag == MODEL_100G || flag == MODEL_25GB) {
						test_xfast_highaddr();
					} else if(flag == MODEL_400G) {
						test_altera_highaddr();
					} else {
						test_10g_highaddr();
					}
				}
				break;
			case 'p':
				if(flag == MODEL_100G || flag == MODEL_25GB) {
#ifdef QSPI_FLASH
					addr = TEST_ADDRESS;
#else
					if(strstr((char *)optarg, CARD_SN_PREFIX)) {
						addr = XFAST_HW_RELEASE1_ADDR;
					} else if(isdigit(optarg[0])) {
						if(argv[optind] != NULL && (strstr(argv[optind], CARD_SN_PREFIX))) {
							if(atoi(optarg) == 1) {
								hw_firmware = 1;
								addr = XFAST_HW_RELEASE1_ADDR;
							} else if(atoi(optarg) == 2) {
								hw_firmware = 2;
								addr = XFAST_HW_RELEASE2_ADDR;
							} else if(atoi(optarg) == 3) {
								hw_firmware = 3;
								addr = XFAST_HW_RELEASE3_ADDR;
							} else if(atoi(optarg) == 4) {
								hw_firmware = 4;
								addr = XFAST_HW_RELEASE4_ADDR;
							} else {
								printf("Parameter -p %s Invalid!\n",optarg);
								ret = XST_FAILURE;
								goto quit_pro;
							}
						} else {
							printf("Parameter -p Invalid,missing upgrade file\n");
							ret = XST_FAILURE;
							goto quit_pro;
						}
					} else {
						printf("Parameter -p %s Invalid!\n",optarg);
						ret = XST_FAILURE;
						goto quit_pro;
					}
#endif
				} else if(flag == MODEL_400G) {
					addr = ALTERA_HW_RELEASE1_ADDR;

				} else {
					addr = MASTER_ADDRESS;
				}
				if(verbose)
					printf("optarg=%s,optind=%d,argv[optind]=%s\n", optarg, optind,
						   argv[optind] ? argv[optind] : "(null)");
				/*
				 * 文件名本身就是升级件时直接用 optarg（新 YN400GA7B027A 镜像不含 "MD"，
				 * 旧代码在这里会把 optarg 丢掉、拿 argv[optind] 顶替，而 -p 的参数已经
				 * 被 optarg 吃掉，argv[optind] 可能是 NULL）。
				 * "1 xxx.bin" / "MD..." 开头的旧用法（100G 多镜像）保持原样。
				 */
				pname = strrchr(optarg, '/');
				pname = pname ? pname + 1 : optarg;
				if(strstr(pname, CARD_SN_PREFIX) || neti_model_code(pname) != MODEL_MIN ||
				   strchr(pname, '.')) {
					prog_name = optarg;
					prog_addr = addr;
				} else if(argv[optind] != NULL) {
					prog_name = argv[optind];
					prog_addr = addr;
				} else {
					printf("Parameter -p Invalid,missing upgrade file\n");
					ret = XST_FAILURE;
					goto quit_pro;
				}
				break;
			case 'b':
				if(flag == MODEL_100G || flag == MODEL_25GB) {
#ifdef QSPI_FLASH
					addr = BACK_ADDRESS;
#else
					addr = XFAST_HW_BASE_ADDR;
#endif
				} else if(flag == MODEL_400G){
					addr = ALTERA_HW_BASE_ADDR;
				} else {
					addr = SLAVE_ADDRESS;
				}
				ret = neti_program_update(flag, 'b', optarg, addr, NULL);
				if(ret != XST_SUCCESS) {
					ret = XST_FAILURE;
					goto quit_pro;
				}
				break;
			case 'e':
				if(argv[optind] != NULL) {
					printf("argv[bind]=%s\n",argv[optind]);
					ret = XST_FAILURE;
					goto quit_pro;
				}
				neti_erase_flash(flag, optarg);
				break;
			case 's':
#if 0
				if(argc != 9) {
					printf("mac missing parameter\n");
					ret = XST_FAILURE;
					goto quit_pro;
				}
#endif
				if(flag == MODEL_100G || flag == MODEL_25GB) {
#ifdef QSPI_FLASH
					addr = IMG_SECTOR_100G;
#else
					addr = XFAST_IMG_SECTOR_ADDR;
#endif
				} else if(flag == MODEL_400G){
					addr = ALTERA_IMG_SECTOR_ADDR;
				} else {
					addr = IMG_SECTOR_10G;
				}
				ret = neti_write_mac(flag, addr, MAC_ADDR_LENGTH, interface, optarg);
				if(ret != XST_SUCCESS) {
					ret = XST_FAILURE;
					goto quit_pro;
				}
				break;
			case 'n':
				if(flag == MODEL_100G || flag == MODEL_25GB) {
#ifdef QSPI_FLASH
					addr = IMG_SECTOR_100G;
#else
					addr = XFAST_IMG_SECTOR_ADDR;
#endif
				} else if(flag == MODEL_400G) {
					addr = ALTERA_IMG_SECTOR_ADDR;
				} else {
					addr = IMG_SECTOR_10G;
				}
				if(neti_sernum_valid(optarg) != XST_SUCCESS) {
					printf("Parameter -n %s Invalid! should start with %s, letters/digits only, at most %d chars\n",
						optarg, CARD_SN_PREFIX, NF_SERNUM_LEN);
					ret = XST_FAILURE;
					goto quit_pro;
				}
				sn_arg = optarg;
				break;
			case 'j':
				ret = neti_param_valid(optarg);
				if(ret == XST_FAILURE) {
					printf("Parameter -j Invalid!\n");
					goto quit_pro;
				}
				if((atoi(optarg)) <= 0 || (atoi(optarg) > XFAST_HW_IMAGE_NUM)) {
					printf("Parameter -j Invalid!\n");
					ret = XST_FAILURE;
					goto quit_pro;
				}
				if(flag == MODEL_100G || flag == MODEL_25GB) {
					addr = XFAST_HW_JUMPTABLE_ADDR;
					addr1 = XFAST_IMG_SECTOR_ADDR;
				} else if(flag == MODEL_400G) {
					addr = ALTERA_HW_JUMPTABLE_ADDR;
					addr1 = ALTERA_IMG_SECTOR_ADDR;
				} else {
					printf("card model error,should be YN400GA7B027A/B/C or 100G/25G model\n");
					ret = XST_FAILURE;
					goto quit_pro;
				}
				if(verbose)
					printf("jump=%d\n", atoi(optarg));
				neti_write_bootinfo(flag, addr, addr1, atoi(optarg));
				break;
			case 'y':
				neti_sync_clocks();
				break;
			case 'f':
				if(adapter == CARD_FALSE_ID) {
					printf("Parameter -a Missing!\n");
					ret = XST_FAILURE;
					goto quit_pro;
				}
				if(interface == CARD_FALSE_ID) {
					printf("Parameter -i Missing!\n");
					ret = XST_FAILURE;
					goto quit_pro;
				}
				if(interface >= 2) {
					printf("Parameter -i out of range!\n");
					ret = XST_FAILURE;
					goto quit_pro;
				}

				if(flag == MODEL_100G) {
					addr = XFAST_IMG_SECTOR_ADDR;
				} else if(flag == MODEL_400G) {
					addr = ALTERA_IMG_SECTOR_ADDR;
				} else {
					printf("card model error,should be YN400GA7B027A/B/C or 100G/25G model\n");
					ret = XST_FAILURE;
					goto quit_pro;
				}
				if(strncmp(optarg,CARD_FEC_ENABLE,strlen(CARD_FEC_ENABLE)) == 0) {
					fec = 1;
				} else if(strncmp(optarg,CARD_FEC_DISABLE,strlen(CARD_FEC_DISABLE)) == 0) {
					fec = 0;
				} else {
					printf("Parameter -f Invalid!\n");
					ret = XST_FAILURE;
					goto quit_pro;
				}
				fec |= (interface << 8);
				ret = neti_set_fec(fec);
				if(ret != XST_SUCCESS) {
					ret = XST_FAILURE;
					goto quit_pro;
				}
				break;
			case 'u':
				if(adapter == CARD_FALSE_ID) {
					printf("Parameter -a Missing!\n");
					ret = XST_FAILURE;
					goto quit_pro;
				}
				if(interface == CARD_FALSE_ID) {
					printf("Parameter -i Missing!\n");
					ret = XST_FAILURE;
					goto quit_pro;
				}
				if(strncmp(optarg,CARD_FEC_ENABLE,strlen(CARD_FEC_ENABLE)) == 0) {
					uflag = 1;
				} else if(strncmp(optarg,CARD_FEC_DISABLE,strlen(CARD_FEC_DISABLE)) == 0) {
					uflag = 0;
				} else {
					printf("Parameter -u Invalid!\n");
					ret = XST_FAILURE;
					goto quit_pro;
				}
				uflag |= (interface << 8);
				ret = neti_set_up(uflag);
				if(ret != XST_SUCCESS) {
					ret = XST_FAILURE;
					goto quit_pro;
				}
				break;
			case '?':
			case ':':
			default:
				break;
		}
	}
	if(!has_option) {
		printf("no option input\n");
		ret = XST_FAILURE;
		goto quit_pro;
	}

	if(prog_name) {
		/* 400G：序列号并进 -p 的 info 扇区更新；旧型号保持原来的先升级、再单独写序列号 */
		ret = neti_program_update(flag, 'p', prog_name, prog_addr,
					  (flag == MODEL_400G) ? sn_arg : NULL);
		if(ret != XST_SUCCESS) {
			ret = XST_FAILURE;
			goto quit_pro;
		}
		if(flag == MODEL_400G)
			sn_arg = NULL;
	}
	if(sn_arg) {
		if(flag == MODEL_100G || flag == MODEL_25GB) {
#ifdef QSPI_FLASH
			addr = IMG_SECTOR_100G;
#else
			addr = XFAST_IMG_SECTOR_ADDR;
#endif
		} else if(flag == MODEL_400G) {
			addr = ALTERA_IMG_SECTOR_ADDR;
		} else {
			addr = IMG_SECTOR_10G;
		}
		ret = neti_write_sernum(flag, addr, MAC_ADDR_LENGTH, (char *)sn_arg);
		if(ret != XST_SUCCESS) {
			ret = XST_FAILURE;
			goto quit_pro;
		}
	}

quit_pro:
	if(fd_user > 0) {
		close(fd_user);
	}

	return ret;
}

