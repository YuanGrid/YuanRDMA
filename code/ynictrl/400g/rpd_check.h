#ifndef RPD_CHECK_H
#define RPD_CHECK_H

#include <stddef.h>

/*
 * 400G（Agilex）写 flash 的升级件只能是 .rpd。
 *
 * 文件名格式校验（neti_proname_valid_new）对扩展名不设限：-p 时 <型号>-R….sof 能通过，
 * -b 时 <型号>-A….jic 也能通过。.sof 是 gzip 压缩的 JTAG 易失镜像，.jic 是 Programmer
 * 用的整片 flash 镜像，写进 flash 都会把对应区域写坏。所以写 flash 前再做两道检查：
 *   rpd_name_check：扩展名必须是 .rpd（不分大小写），打开文件之前做；
 *   rpd_data_check：文件头必须是 Agilex 配置位流的 95 48 29 62，防止改了扩展名的 .sof / .jic。
 * 两个函数通过返回 0，不通过返回 -1，并把原因打印到 stdout。
 */
int rpd_name_check(const char *name);
int rpd_data_check(const char *name, const unsigned char *buf, size_t size);

#endif
