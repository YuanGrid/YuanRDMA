#include <stdio.h>
#include <string.h>
#include <strings.h>
#include "rpd_check.h"

/* quartus_pfg 生成的 Agilex .rpd（active 区 R 与 boot 区 B）都以这 4 字节开头 */
static const unsigned char rpd_magic[4] = { 0x95, 0x48, 0x29, 0x62 };

static const char *base_name(const char *path)
{
	const char *slash = strrchr(path, '/');

	return slash ? slash + 1 : path;
}

int rpd_name_check(const char *name)
{
	const char *base = base_name(name);
	const char *dot = strrchr(base, '.');

	if (dot && strcasecmp(dot, ".rpd") == 0)
		return 0;

	printf("Only .rpd files can be written to flash, got: %s\n", base);
	if (dot && strcasecmp(dot, ".jic") == 0)
		printf("  .jic is the whole-flash image: program it with Quartus Programmer over JTAG.\n");
	else if (dot && strcasecmp(dot, ".sof") == 0)
		printf("  .sof is a volatile JTAG image: it must never be written to flash.\n");
	printf("  Use the .rpd from the release: -p takes <model>-R...-<commit>.rpd, -b takes <model>-B...-<commit>.rpd\n");
	fflush(stdout);
	return -1;
}

int rpd_data_check(const char *name, const unsigned char *buf, size_t size)
{
	if (size >= sizeof(rpd_magic) && memcmp(buf, rpd_magic, sizeof(rpd_magic)) == 0)
		return 0;

	printf("%s is not an Agilex .rpd image", base_name(name));
	if (size >= 4)
		printf(" (header %02x %02x %02x %02x, expected 95 48 29 62)",
		       buf[0], buf[1], buf[2], buf[3]);
	printf(".\n");
	if (size >= 4 && memcmp(buf, "JIC", 4) == 0)
		printf("  The content is a .jic: program it with Quartus Programmer over JTAG.\n");
	else if (size >= 2 && buf[0] == 0x1f && buf[1] == 0x8b)
		printf("  The content is gzip, i.e. a .sof: it must never be written to flash.\n");
	printf("  Do not rename other files to .rpd; use the .rpd from the release.\n");
	fflush(stdout);
	return -1;
}
