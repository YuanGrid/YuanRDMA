#ifndef __MCDMA_DPDK_COMPAT_H__
#define __MCDMA_DPDK_COMPAT_H__

#include <rte_version.h>

#if RTE_VERSION_NUM(21, 11, 0, 0) <= RTE_VERSION
//#include <ethdev_driver.h>
//#include <ethdev_pci.h>

#define ETH_LINK_UP RTE_ETH_LINK_UP
#define ETH_LINK_FULL_DUPLEX RTE_ETH_LINK_FULL_DUPLEX
#endif


#endif /* ifndef __MCDMA_DPDK_COMPAT_H__ */

