#ifndef __DPDK_QDMA_RSS_HDR__
#define __DPDK_QDMA_RSS_HDR__

#include <stdint.h>

#include <rte_ethdev.h>
#include <ethdev_driver.h>

/*
 * QDMA默认RSS的hash key长度为40字节，地址空间如下：
 * 0x1600	0x0600		RW		RSS hash key
 * 0x1627	0x0627
 */
#define MCDMA_RSS_KEY_SIZE 40

/*
 * QDMA默认的RSS RETA表长度为128，地址空间如下：
 * 0x1400	0x0400		RW		RSS indirection table
 * 0x15FF	0x05FF				31:16 - reserved; 15:0 - queue ID at index
 */
#define MCDMA_RSS_RETA_SIZE RTE_ETH_RSS_RETA_SIZE_128

/**
 * DPDK callback to update the RETA indirection table.
 * Code like mlx5_dev_rss_reta_update
 *
 * @param dev
 *   Pointer to Ethernet device structure.
 * @param reta_conf
 *   Pointer to RETA configuration structure array.
 * @param reta_size
 *   Size of the RETA table.
 *
 * @return
 *   0 on success, a negative errno value otherwise and rte_errno is set.
 */
int
mcdma_dev_rss_reta_update(struct rte_eth_dev *dev,
	struct rte_eth_rss_reta_entry64 *reta_conf, uint16_t reta_size);

/**
 * DPDK callback to get the RETA indirection table.
 * Code like mlx5_dev_rss_reta_query
 *
 * @param dev
 *   Pointer to Ethernet device structure.
 * @param reta_conf
 *   Pointer to RETA configuration structure array.
 * @param reta_size
 *   Size of the RETA table.
 *
 * @return
 *   0 on success, a negative errno value otherwise and rte_errno is set.
 */
int
mcdma_dev_rss_reta_query(struct rte_eth_dev *dev,
	struct rte_eth_rss_reta_entry64 *reta_conf, uint16_t reta_size);

/**
 * DPDK callback to update the RSS hash configuration.
 * Code like mlx5_rss_hash_update
 *
 * @param dev
 *   Pointer to Ethernet device structure.
 * @param[in] rss_conf
 *   RSS configuration data.
 *
 * @return
 *   0 on success, a negative errno value otherwise and rte_errno is set.
 */
int
mcdma_dev_rss_hash_update(struct rte_eth_dev *dev, struct rte_eth_rss_conf *rss_conf);

/**
 * DPDK callback to get the RSS hash configuration.
 * Code like mlx5_rss_hash_conf_get
 *
 * @param dev
 *   Pointer to Ethernet device structure.
 * @param[in, out] rss_conf
 *   RSS configuration data.
 *
 * @return
 *   0 on success, a negative errno value otherwise and rte_errno is set.
 */
int
mcdma_dev_rss_hash_conf_get(struct rte_eth_dev *dev, struct rte_eth_rss_conf *rss_conf);


#endif
