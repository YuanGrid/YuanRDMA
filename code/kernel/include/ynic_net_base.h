#ifndef __YNIC_UKCMD_HDR__
#define __YNIC_UKCMD_HDR__

#define YNIC_SUC 0
#define YNIC_ERR -1

#define ETH_ADR_LEN         6       /**< Octets in one ethernet addr   */
#define ETH_HDR_LEN         14      /**< Total octets in header.   */
#define ETH_MIN_LEN         60      /**< Min. octets in frame sans FCS */
#define ETH_CRC_LEN         4       /**< Ethernet CRC length */
#define ETH_HW_TYPE         1       /**< Ethernet hardware type */
#define ETH_GAP_LEN         20      /**< Frame head and tail length */

#define ERR_MSG_LEN 1024

/** 系统中最多有多少块FPGA网卡 */
#define MAX_PORT_PER_ADP 8

/** 每块网卡上最多有多少个网口 */
#define MAX_FPGA_ADAPTER 8

/** 一条流配置有多少个报文模板，正常情况下有一个，在IPv4或者IPv6分片时有多个 */
#define MAX_PKT_PER_STREAM 8

/** 每个网口上最多支持多少条流，默认1024，后期支持到6万 */
#define MAX_STREAM_PER_PORT         1024
#define MAX_STREAM_PER_PORT_100G    4096
#define MAX_STREAM_PER_PORT_400G    16384

#undef INET6_ADDRSTRLEN 
#define INET6_ADDRSTRLEN (48)

/** 系统中最多有多少个接口 */
#ifndef MAX_PORTS_COUNT
#define MAX_PORTS_COUNT 16
#endif

/** 64位CPU的cache size默认为64位 */
#define YNIC_CACHE_LINE_SIZE (64)

/** 跳变域的字段类型位列表时，列表的最大长度 */
#define MAX_MDF_VLIST_SIZE 16

/** 最多允许有多少个IP地址区域，比如17.1.1.2-17.1.1.100,17.2.1.1,17.2.2.2,17.2.2.2为4个区域 */
#ifndef MAX_IPRANGE_PER_SUBNET
#define MAX_IPRANGE_PER_SUBNET 64
#endif

#define YNIC_CLASS_NAME "ntsNetDevClass"
#define YNIC_SYS_NET_DEV "/dev/ynic_netdev"   //user use
#define YNIC_SYS_NET_NAME "ynic_netdev"   //kenel use

/** 定义鸣嘀卡跳变使用的MASK*/
#define MASK_ONE_BYTE     0x01
#define MASK_TWO_BYTE     0x03
#define MASK_THR_BYTE     0x07
#define MASK_FOR_BYTE     0x0F



#ifndef UNUSED_PARAM
#define UNUSED_PARAM __attribute__((unused))
#endif

#define __ynic_cache_packed __attribute__((packed))
#define __ynic_cache_aligned __attribute__((__aligned__(YNIC_CACHE_LINE_SIZE)))

typedef uint32_t in_addr_t;
typedef struct __gre_hdr gre_hdr_t;
typedef struct in6_addr in6_addr_t;
typedef struct __eth_adr eth_adr_t;
typedef struct __eth_hdr eth_hdr_t;
typedef struct __arp_hdr arp_hdr_t;
typedef struct __ynic_arp ynic_arp_t;
typedef struct __pfc_hdr pfc_hdr_t;
typedef struct __ah_header ah_hdr_t;
typedef struct __esp_tail ah_tail_t;
typedef unsigned __int128 uint128_t;
typedef struct __ynic_port ynic_port_t;
typedef struct __ospf_hdr ospf_hdr_t;
typedef struct __vlan_hdr vlan_hdr_t;
typedef struct __ipv6_adr ipv6_adr_t;
typedef struct __esp_header esp_hdr_t;
typedef struct __tcp_header tcp_hdr_t;
typedef struct __udp_header udp_hdr_t;
typedef struct __ynic_nsdev ynic_nsdev_t;
typedef struct __ynic_nserr ynic_nserr_t;
typedef struct __vxlan_hdr vxlan_hdr_t;
typedef struct __ipv4_header ipv4_hdr_t;
typedef struct __ipv6_header ipv6_hdr_t;
typedef struct __gre_key_hdr gre_key_hdr_t;
typedef struct __gre_seq_hdr gre_seq_hdr_t;
typedef struct __gre_sum_hdr gre_sum_hdr_t;
typedef struct __ynic_adapter ynic_adapter_t;
typedef struct __ospf_lsa_hdr ospf_lsa_hdr_t;
typedef struct nd_neighbor_advert ipv6_ndna_t;
typedef struct nd_neighbor_solicit ipv6_ndns_t;
typedef struct __ynic_tx_stream ynic_tx_stream_t;
typedef struct __ynic_rx_stream ynic_rx_stream_t;
typedef struct __ipv6_frag_header ipv6_frag_hdr_t;
typedef struct __ipv6_pseudo_hdr ipv6_pseudo_hdr_t;
typedef struct __mpls_header mpls_hdr_t;


#define ETHHDR_AT_SOCKBUF(buf) ((eth_hdr_t *)buf)
#define VLANHDR_BY_ETHHDR(buf) (vlan_hdr_t *)((char *)buf + sizeof(eth_hdr_t))
#define IP4HDR_BY_ETHHDR(buf)  ((ipv4_hdr_t *)((char *)buf + sizeof(eth_hdr_t)))
#define IP4HDR_BY_ETHHDR_VLAN(buf) \
    ((ipv4_hdr_t *)((char *)buf + sizeof(eth_hdr_t) + sizeof(vlan_hdr_t)))
#define IP4HDR_BY_ETHHDR_QINQ(buf) \
    ((ipv4_hdr_t *)((char *)buf + sizeof(eth_hdr_t) + (2 * sizeof(vlan_hdr_t))))
#define TCP4HDR_BY_IP4HDR(iph)  ((tcp_hdr_t *)((char *)iph + sizeof(ipv4_hdr_t)))
#define TCP4HDR_BY_ETHHDR(eth)  ((tcp_hdr_t *)((char *)eth + sizeof(eth_hdr_t) + sizeof(ipv4_hdr_t)))
#define UDP4HDR_BY_IP4HDR(iph)  ((udp_hdr_t *)((char *)iph + sizeof(ipv4_hdr_t)))
#define ICMP4HDR_BY_IP4HDR(iph) ((icmp_hdr_t *)((char *)iph + sizeof(ipv4_hdr_t)))
#define UDPHDR_BY_IP6HDR(iph)   ((udp_hdr_t *)((char *)iph + sizeof(ipv6_hdr_t)))

#define IEEE8023_ROUTER_INFO_HDR_BY_LOGICAL_LINK_HDR(logical_link)  \
    ((ieee8023_routing_info_ipv4_header_t *)((char *)logical_link + \
                                             sizeof(ieee8023_logical_link_ipv4_header_t)))

#define IP6HDR_BY_ETHHDR(buf) ((ipv6_hdr_t *)((char *)buf + sizeof(eth_hdr_t)))
#define IP6HDR_BY_ETHHDR_VLAN(buf) \
    ((ipv6_hdr_t *)((char *)buf + sizeof(eth_hdr_t) + sizeof(vlan_hdr_t)))
#define IP6HDR_BY_ETHHDR_QINQ(buf) \
    ((ipv6_hdr_t *)((char *)buf + sizeof(eth_hdr_t) + (2 * sizeof(vlan_hdr_t))))

#define TCP6HDR_BY_IP6HDR(ip6h)     ((tcp_hdr_t *)((char *)ip6h + sizeof(ipv6_hdr_t)))
#define TCP6HDR_BY_FRAG6HDR(frag6h) ((tcp_hdr_t *)((char *)frag6h + sizeof(struct ip6_frag)))
#define TCP6HDR_BY_ETHHDR(eth)      ((tcp_hdr_t *)((char *)eth + sizeof(eth_hdr_t) + sizeof(ipv6_hdr_t)))
#define UDP6HDR_BY_IP6HDR(ip6h)     ((udp_hdr_t *)((char *)ip6h + sizeof(ipv6_hdr_t)))
#define UDP6HDR_BY_FRAG6HDR(frag6h) ((udp_hdr_t *)((char *)frag6h + sizeof(struct ip6_frag)))
#define NSHDR_BY_IP6HDR(ip6h)       ((struct nd_neighbor_solicit *)((char *)ip6h + sizeof(ipv6_hdr_t)))
#define NAHDR_BY_IP6HDR(ip6h)       ((struct nd_neighbor_advert *)((char *)ip6h + sizeof(ipv6_hdr_t)))



#define IPPROTO_OSPF        89      /* OSPF protocol */
#ifndef IPPROTO_PIM
#define IPPROTO_PIM         103     /* PIM protocol */
#endif
#define IPPROTO_EVPN        143     /* evpn protocol */
#define IPPROTO_UNKNOWN     200     /* DDoS case unkown protocol attack */

#define ETH_HW_TYPE         1       /* Ethernet hardware type */
#define ETH_ADR_LEN         6       /* Octets in one ethernet addr   */
#define ETH_HDR_LEN         14      /* Total octets in header.   */
#define ETH_MIN_LEN         60      /* Min. octets in frame sans FCS */
#define ETH_CRC_LEN         4
#define ETH_GAP_LEN         20      /* Frame head and tail length */

#define IP_ICMP_ECHO_REPLY          0
#define IP_ICMP_DESTI_UNREACH       3
#define IP_ICMP_REDIRECT            5
#define IP_ICMP_ECHO_REQUEST        8
#define IP_ICMP_ADDR_MASK_REQUEST   17

/******************************************************************************
 * ipHdr_t.proto values in the IP Header.
 *  1     ICMP        Internet Control Message           [RFC792]
 *  2     IGMP        Internet Group Management         [RFC1112]
 *  4     IP          IP in IP (encapsulation)          [RFC2003]
 *  6     TCP         Transmission Control               [RFC793]
 * 17     UDP         User Datagram                  [RFC768,JBP]
 * 41     IPv6        Ipv6                              [Deering]
 * 43     IPv6-Route  Routing Header for IPv6           [Deering]
 * 44     IPv6-Frag   Fragment Header for IPv6          [Deering]
 * 58     IPv6-ICMP   ICMP for IPv6                     [RFC1883]
 * 59     IPv6-NoNxt  No Next Header for IPv6           [RFC1883]
 * 60     IPv6-Opts   Destination Options for IPv6      [RFC1883]
 */
#define PG_IPPROTO_NONE         0
#define PG_IPPROTO_IP           IPPROTO_IP
#define PG_IPPROTO_ICMP         IPPROTO_ICMP
#define PG_IPPROTO_IGMP         IPPROTO_IGMP
#define PG_IPPROTO_IPV4         IPPROTO_IPV4
#define PG_IPPROTO_TCP          IPPROTO_TCP
#define PG_IPPROTO_UDP          IPPROTO_UDP
#define PG_IPPROTO_IPV6         IPPROTO_IPV6
#define PG_IPPROTO_IPV6_ROUTE   43
#define PG_IPPROTO_IPV6_FRAG    44
#define PG_IPPROTO_ICMPV6       IPPROTO_ICMPV6
#define PG_IPPROTO_IPV6_ICMP    IPPROTO_ICMPV6
#define PG_IPPROTO_IPV6_NONXT   59
#define PG_IPPROTO_IPV6_OPTS    60
#define PG_IPPROTO_RAW          IPPROTO_RAW
#define PG_IPPROTO_MAX          256

#define PG_OFF_MASK             0x1fff
#define PG_OFF_MF               0x2000
#define PG_OFF_DF               0x4000
#define PG_ISFRAG(off)  ((off) & (PG_OFF_MF | PG_OFF_MASK))

#define GREVERSION              0

/* GRE Options */
#define GRE_OPTION_STRICT       0x01
#define GRE_OPTION_SEQUENCE     0x02
#define GRE_OPTION_KEY          0x04
#define GRE_OPTION_ROUTING      0x08
#define GRE_OPTION_CHECKSUM     0x10

#define GRE_OPTLEN_SEQUENCE    sizeof(gre_seq_hdr_t)
#define GRE_OPTLEN_KEY         sizeof(gre_key_hdr_t)
#define GRE_OPTLEN_CHECKSUM    sizeof(gre_sum_hdr_t)

#define PFC_ETH_TYPE            0x8808
#define PFC_PAUSE_OPCODE        0x0101

#define PFC_FLOW_NO_PAUSE       0x1
#define PFC_FLOW_IN_PAUSE       0x2

/** socket local low and top port, do not less than 10000 and moren than 65535 */
#define SOCKET_LOW_PORT         10000
#define SOCKET_TOP_PORT         65535

#define IS_BROADCAST_ADDRESS(addr) (addr == 0xFFFFFFFFL)
#define IS_MULTICAST_ADDRESS(addr) (((addr)&0x000000E0)==0x000000E0)

#define INET_NTOA(addr) inet_ntoa(*((struct in_addr*)&addr))

#define IPv4(a,b,c,d)    ((uint32_t)(((a) & 0xff) << 24) |       \
    (((b) & 0xff) << 16) | (((c) & 0xff) << 8)  | ((d) & 0xff))

/** int ioctl(int fd, unsigned long request, ...); ioctl 第二个参数数值 */
#define YNIC_DEV_IOCTL_REQ  1111

#define BIT_WIDTH  512

#define CLK  250 /**单位 Mhz*/

/**
MD卡停止打流原因:

BIT0: 1正在发送      0发送已停止
BIT1: 1达到最大包数停止
BIT2: 1 主机命令停止
BIT3: 1 达到最大发送时间
*/

#define STOP_TX_BY_PKT       0x02  //达到最大包数停止
#define STOP_TX_BY_CMD       0x04  //主机命令停止
#define STOP_TX_BY_TIME      0x08  //达到最大发送时间




enum {
    YNIC_LIB_VER0,           /**< YuanGrid SmartNIC lib库版本0 */
    YNIC_LIB_VER1,           /**< YuanGrid SmartNIC lib库版本1 */
    YNIC_LIB_VER2,           /**< YuanGrid SmartNIC lib库版本2 */
};

enum {
    WORK_MODE_DPDK = 0,
	WORK_MODE_MD_FPGA,
};


enum {
    UKCMD_UNKOWN = 0,
    U2K_INIT_NET_DEV,                   /**< 初始化 YuanGrid FPGA 网卡 */
    U2K_GET_DEV_INFO,                   /**< 用户态->内核态，获取系统中的网卡和网口信息 */
    U2K_OPEN_TX_STREAM,                 /**< 用户态发送命令，要打开一个tx stream */
    U2K_SET_TX_STREAM_CFG,              /**< 设置或更新发送流的配置信息 */
    U2K_GET_TX_STREAM_STATS,            /**< 用户态获取tx stream的统计信息 */
    U2K_START_TX_STREAM,                /**< 开始发送流 */
    U2K_STOP_TX_STREAM,                 /**< 停止发送流 */
    U2K_CLOSE_TX_STREAM,                /**< 用户态发送命令，要关闭一个tx stream */
    U2K_OPEN_RX_STREAM,                 /**< 用户态发送命令，要打开一个rx stream */
    U2K_SET_RX_STREAM_CFG,              /**< 设置或更新接收流的配置信息 */
    U2K_GET_RX_STREAM_STATS,            /**< 用户态获取rx stream的统计信息 */
    U2K_START_RX_STREAM,                /**< 开始接收流 */
    U2K_STOP_RX_STREAM,                 /**< 停止接收流 */
    U2K_CLOSE_RX_STREAM,                /**< 用户态发送命令，要关闭一个rx stream */
    U2K_ENABLE_PROMISC_DEV,             /**< 启用混杂模式 */
    U2K_CLEAR_TX_STREAM,                /**< 清空发送流报文计数 */
    U2K_CLEAR_RX_STREAM,                /**< 清空接收流报文计数 */
    U2K_GET_TXRX_DEBUG_STATS,           /**< 用户态获取tx/rx debug的统计信息 */
    U2K_CLEAR_TXRX_DEBUG_STATS,         /**< 用户态清空tx/rx debug的统计信息 */
    U2K_SET_RX_QUEUE_ID,                /**< 用户态设置arp/ping 报文qid */
    U2K_SET_RX_WORK_MODE,               /**< 用户态设置rx的工作模式 */
    U2K_GET_TX_SEND_STATUS,             /**< 用户态获取tx的发送状态 */
    U2K_SET_RX_TD_TYPE,                 /**< 用户态设置rx的时延方式 */
    U2K_SET_TX_TD_TYPE,                 /**< 用户态设置tx的时延方式 */
    U2K_SET_PORT_DIRECT,                /**< 用户态设置客户端/服务端*/
    U2K_RESET_TXRX_STATUS,              /**< 用户态清除硬件状态，硬件恢复为初始状态*/
    U2K_SET_1G_IFTYPE,                  /**< 用户态设置网卡1G模式*/
    U2K_GET_TX_MULSTREAMS_STATS,        /**< 用户态获取流模板tx stream的统计信息 */
    U2K_GET_RX_MULSTREAMS_STATS,        /**< 用户态获取流模板rx stream的统计信息 */
    U2K_SET_TX_PKT_TIMESTAMP,           /**< 用户态设置报文时间戳配置信息 */
    U2K_GET_RX_ROCE_STATS,              /**< 用户态获取roce统计信息 */
    U2K_CLEAR_RX_ROCE_STATS,            /**< 用户态清除roce统计信息 */
    U2K_SET_RX_TS_BASE,                 /**< 用户态设置rx的时延基准值 */
    U2K_SET_RX_FILTER,                  /**< 用户态设置接收过滤器*/
    U2K_CLEAR_RX_FILTER,                 /**< 用户态设置清除接收过滤器 */
    U2K_SET_PFC_STATS,                  /**< 用户态设置pfc状态 */
    U2K_GET_RX_PFC_STATS                /** 用户态获取接收PAUSE/PFC统计信息 */
};

enum {
    UNKNIC_STREAM = 0,
    FPGA_L23_TX_STREAM,    /**< L2-3层流，只需要FPGA处理，无需通过PCIE送给CPU */
    FPGA_L23_RX_STREAM,    /**< L2-3层流，只需要FPGA处理，无需通过PCIE送给CPU */    
    PCIE_L47_TX_STREAM,    /**< L4-7层流，需要通过PCIE与CPU通信 */
    PCIE_L47_RX_STREAM,    /**< L4-7层流，需要通过PCIE与CPU通信 */
    DPDK_L47_TX_STREAM,    /**< DPDK流，目前DPDK是通过QDMA进行UIO，应当用不到这个流类型 */
    DPDK_L47_RX_STREAM,    /**< DPDK流，目前DPDK是通过QDMA进行UIO，应当用不到这个流类型 */
};

enum {
    SEND_STREAM = 0,
    RECV_STREAM,
    SEND_PCAP,
};

enum {
    ETH_ARP_TYPE = 0x0806,
    ETH_IPV4_TYPE = 0x0800,
    ETH_IPV6_TYPE = 0x86dd,
};

/* RARP and ARP opcodes */
enum {
    ARP_REQUEST = 1,
    ARP_REPLY = 2,
    RARP_REQUEST = 3,
    RARP_REPLY = 4,
    GRATUITOUS_ARP = 5,
};

enum {
    NEXT_MAC_BY_ARP_NSNA = 0,
    NEXT_MAC_BY_USER_INPUT = 1,
    NEXT_MAC_BY_AUTO_SET = 2,
};

/* GTPU */
enum gtp_version {
    GTPv1 = 1,
    GTPv2 = 2
};

enum gtp_type {
    TYPE_GTP = 0,                     /**< GTP'计费传输 */
    TYPE_GTP_UC = 1                               /**< GTP-U 用户面/GTP-C 控制面 */
};

enum gtp_msg_type {
    ECHO_REQS = 0x01,                 /**< echo request */
    T_PDU = 0xff                /**< T-PDU */
};

enum gtp_exten_type {
    PDU_SC = 0x85                     /**< PDU Session Container */
};

enum pdu_type {
    PDU_DL = 0x00,                          /**< DL PDU Session Information */
    PDU_UL = 0x01,                          /**< UL PDU Session Information */
};

enum {
    NOIP_PKT_FRGA = 0x00,
    IPv4_PKT_FRAG = 0x01,
    IPv6_PKT_FRAG = 0x02,
};

enum {
    URG_FLAG = 0x20,
    ACK_FLAG = 0x10,
    PSH_FLAG = 0x08,
    RST_FLAG = 0x04,
    SYN_FLAG = 0x02,
    FIN_FLAG = 0x01,
};

enum {
    MCAST_IGMP_V1 = 1,
    MCAST_IGMP_V2 = 2,
    MCAST_IGMP_V3 = 3,
    MCAST_MLD_V1 = 4,
    MCAST_MLD_V2 = 5,
};

enum {
    HAS_IPV4_ADDR = 0x10,
    HAS_IPV6_ADDR = 0x20,
    HAS_TCP_PROTO = 0x01,
    HAS_UDP_PROTO = 0x02,
};

enum MDLinkSpeed_e {
  MD_LINK_SPEED_UNKNOWN = 0,
  MD_LINK_SPEED_10M     = 0x01,  //!< 10 Mbps
  MD_LINK_SPEED_100M    = 0x02,  //!< 100 Mbps
  MD_LINK_SPEED_1G      = 0x04,  //!< 1 Gbps
  MD_LINK_SPEED_10G     = 0x08,  //!< 10 Gbps
  MD_LINK_SPEED_40G     = 0x10,  //!< 40 Gbps
  MD_LINK_SPEED_100G    = 0x20,  //!< 100 Gbps
  MD_LINK_SPEED_50G     = 0x40,  //!< 50 Gbps
  MD_LINK_SPEED_25G     = 0x80,  //!< 25 Gbps
  MD_LINK_SPEED_200G    = 0x100, //!< 200 Gbps
  MD_LINK_SPEED_400G    = 0x200, //!< 400 Gbps
  MD_LINK_SPEED_2D5G    = 0x400, //!< 2.5 Gbps
  MD_LINK_SPEED_END              //!< alwaysep this entry as the last in enum
};
typedef enum MDLinkSpeed_e MDLinkSpeed_t;

enum MDLinkState_e {
  MD_LINK_STATE_UNKNOWN = 0, //!< The link state has not been read yet
  MD_LINK_STATE_DOWN    = 1, //!< The link state is DOWN
  MD_LINK_STATE_UP      = 2, //!< The link state is UP
  MD_LINK_STATE_ERROR   = 3  //!< The link state could not be read
};
typedef enum MDLinkState_e MDLinkState_t, *MDLinkState_p;

typedef enum MDAdapterType_e {
  YNIC_ADAPTER_TYPE_UNKNOWN = 0, 		/**< Unknown adapter type */
  YNIC_ADAPTER_TYPE_NAPAMAX = 255,   	/**< 1-255，Napatech的网卡类型，如 NT_ADAPTER_TYPE_NT200A02_2X25 */
  YNIC_ADAPTER_MD4X001GC27LA_4X1G,	/**< ALINX黑卡，Xilinx KU5P芯片，4X1G电模式 */  
  YNIC_ADAPTER_MD4X010GF27LA_4X1G,	/**< ALINX黑卡，Xilinx KU5P芯片，4X1G光模式 */  
  YNIC_ADAPTER_MD4X010GF27LA_4X10G,	/**< ALINX黑卡，Xilinx KU5P芯片，4X10G光模式 */
  YNIC_ADAPTER_MD4X025GF27LA_4X1G,	/**< 锐文xfast-1000网卡，Xilinx KU5P芯片，4X1G光模式 */
  YNIC_ADAPTER_MD4X025GF27LA_4X2D5G,	/**< 锐文xfast-1000网卡，Xilinx KU5P芯片，4X2.5G光模式 */
  YNIC_ADAPTER_MD4X025GF27LA_4X10G,	/**< 锐文xfast-1000网卡，Xilinx KU5P芯片，4X10G光模式 */
  YNIC_ADAPTER_MD4X025GF27LA_4X25G,	/**< 锐文xfast-1000网卡，Xilinx KU5P芯片，4X25G光模式 */
  YNIC_ADAPTER_MD4X025GF27LB_4X1G,	/**< 锐文xfast-1000网卡，Xilinx VU3P芯片，4X1G光模式 */
  YNIC_ADAPTER_MD4X025GF27LB_4X2D5G,	/**< 锐文xfast-1000网卡，Xilinx VU3P芯片，4X2.5G光模式 */
  YNIC_ADAPTER_MD4X025GF27LB_4X10G,	/**< 锐文xfast-1000网卡，Xilinx VU3P芯片，4X10G光模式 */
  YNIC_ADAPTER_MD4X025GF27LB_4X25G,	/**< 锐文xfast-1000网卡，Xilinx VU3P芯片，4X25G光模式 */
  YNIC_ADAPTER_MD2X100GF27LA_2X100G,	/**< 锐文xfast-2000网卡，Xilinx VU3P芯片，2X100G光模式 */
  YNIC_ADAPTER_MD2X100GF27LA_2X50G,	/**< 锐文xfast-2000网卡，Xilinx VU3P芯片，2X50G光模式 */
  YNIC_ADAPTER_MD2X100GF27LA_2X40G,	/**< 锐文xfast-2000网卡，Xilinx VU3P芯片，2X40G光模式 */
  YNIC_ADAPTER_MD2X100GF27LA_8X25G,	/**< 锐文xfast-2000网卡，Xilinx VU3P芯片，8X25G光模式 */
  YNIC_ADAPTER_MD2X100GF27LA_8X10G,	/**< 锐文xfast-2000网卡，Xilinx VU3P芯片，8X10G光模式 */
  YNIC_ADAPTER_MD2X100GF27LA_4X25G,	/**< 锐文xfast-2000网卡，Xilinx VU3P芯片，4X25G光模式 */
  YNIC_ADAPTER_MD2X100GF27LA_4X10G,	/**< 锐文xfast-2000网卡，Xilinx VU3P芯片，4X10G光模式 */
  YNIC_ADAPTER_MD2X025GF27LA_2X1G,	/**< 锐文xfast-1000网卡，Xilinx KU5P芯片，2X1G光模式 */
  YNIC_ADAPTER_MD2X025GF27LA_2X2D5G,	/**< 锐文xfast-1000网卡，Xilinx KU5P芯片，2X2.5G光模式 */
  YNIC_ADAPTER_MD2X025GF27LA_2X10G,	/**< 锐文xfast-1000网卡，Xilinx KU5P芯片，2X10G光模式 */
  YNIC_ADAPTER_MD2X025GF27LA_2X25G,	/**< 锐文xfast-1000网卡，Xilinx KU5P芯片，2X25G光模式 */
  YNIC_ADAPTER_YN400GA7B027A_1X400G,	/**< altera 1x400G光模式--A 型板 */
  YNIC_ADAPTER_YN400GA7B027A_4X100G,	/**< altera 1x400G光模式--A 型板 */
  YNIC_ADAPTER_YN400GA7B027A_1X200G,	/**< altera 1x400G光模式--A 型板 */
  YNIC_ADAPTER_YN400GA7B027A_1X100G,	/**< altera 4x100G光模式--A 型板 */
  YNIC_ADAPTER_YN400GA7B027A_1X50G,	/**< altera 4x100G光模式--A 型板 */
  YNIC_ADAPTER_YN400GA7B027B_1X400G,	/**< altera 1x400G光模式--B 型板 */
  YNIC_ADAPTER_YN400GA7B027B_4X100G,	/**< altera 1x400G光模式--B 型板 */
  YNIC_ADAPTER_YN400GA7B027B_1X200G,	/**< altera 1x400G光模式--B 型板 */
  YNIC_ADAPTER_YN400GA7B027B_1X100G,	/**< altera 1x400G光模式--B 型板 */
  YNIC_ADAPTER_YN400GA7B027B_1X50G,	/**< altera 4x100G光模式--B 型板 */
  YNIC_ADAPTER_YN400GA7B027C_1X400G,	/**< altera 1x400G光模式--C 型板 */
  YNIC_ADAPTER_YN400GA7B027C_4X100G,	/**< altera 1x400G光模式--C 型板 */
  YNIC_ADAPTER_YN400GA7B027C_1X200G,	/**< altera 1x400G光模式--C 型板 */
  YNIC_ADAPTER_YN400GA7B027C_1X100G,	/**< altera 1x400G光模式--C 型板 */
  YNIC_ADAPTER_YN400GA7B027C_1X50G,	/**< altera 4x100G光模式--C 型板 */

  YNIC_ADAPTER_TYPE_MAX,			/**< YuanGrid 网卡类型的最大值，用于范围校验 */
} md_adapter_type_t;

/** 用 adapter_type 判断 FPGA 网卡是 YuanGrid 还是第三方卡 */
#define ADAPTER_IS_NPNIC(adt) (adt > 0 && adt < YNIC_ADAPTER_TYPE_NAPAMAX)
#define ADAPTER_IS_MDNIC(adt) (adt > YNIC_ADAPTER_TYPE_NAPAMAX && adt < YNIC_ADAPTER_TYPE_MAX)

#define HAS_IPV4_TCP_ADDR (HAS_IPV4_ADDR | HAS_TCP_PROTO)
#define HAS_IPV4_UDP_ADDR (HAS_IPV4_ADDR | HAS_UDP_PROTO)
#define HAS_IPV6_TCP_ADDR (HAS_IPV6_ADDR | HAS_TCP_PROTO)
#define HAS_IPV6_UDP_ADDR (HAS_IPV6_ADDR | HAS_UDP_PROTO)

//报文头名字的定义
enum {
    ENCAP_HDR_NULL = 0,
    ENCAP_HDR_TCP,
    ENCAP_HDR_UDP,
    ENCAP_HDR_ETH,
    ENCAP_HDR_IPV4,
    ENCAP_HDR_IPV6,
    ENCAP_HDR_ARP,
    ENCAP_HDR_VLAN,
    ENCAP_HDR_PPP,
    ENCAP_HDR_PPPOE,
    ENCAP_HDR_MPLS,
    ENCAP_HDR_L2TPV2_DATA,
    ENCAP_HDR_L2TPV2_CONTROL,
    ENCAP_HDR_DHCPV4,
    ENCAP_HDR_DHCPV6,
    ENCAP_HDR_GRE,
    ENCAP_HDR_VXLAN,
    ENCAP_HDR_GTPV1_HDR,
    ENCAP_HDR_GTPV1_OPTIONAL_FIELDS,
    ENCAP_HDR_GTPV1_EXTENSION_HDR,
    ENCAP_HDR_IGMP_V1_QUERY,
    ENCAP_HDR_IGMP_V1_REPORT,
    ENCAP_HDR_IGMP_V2_QUERY,
    ENCAP_HDR_IGMP_V2_REPORT,
    ENCAP_HDR_IGMP_V3_QUERY,
    ENCAP_HDR_IGMP_V3_REPORT,
    ENCAP_HDR_ICMPV4_ADDRESS_MASK_REPLY,
    ENCAP_HDR_ICMPV4_ADDRESS_MASK_REQUEST,
    ENCAP_HDR_ICMPV4_DESTUNREACH,
    ENCAP_HDR_ICMPV4_INSTANCE,
    ENCAP_HDR_ICMPV4_ECHOREPLY,
    ENCAP_HDR_ICMPV4_ECHOREQUEST,
    ENCAP_HDR_ICMPV4_INFORMATION_REPLY,
    ENCAP_HDR_ICMPV4_INFORMATION_REQUEST,
    ENCAP_HDR_ICMPV4_PARAMETERPROBLEM,
    ENCAP_HDR_ICMPV4_Redirct,
    ENCAP_HDR_ICMPV4_SOURCE_QUENCH,
    ENCAP_HDR_ICMPV4_TIMEEXCEEDED,
    ENCAP_HDR_ICMPV4_TIMESTAMPREOLY,
    ENCAP_HDR_ICMPV4_TIMESTAMPREQUST,
    ENCAP_HDR_ICMPV6_DESTINATION_UNREACHABLE,
    ENCAP_HDR_ICMPV6_ECHOREPLY,
    ENCAP_HDR_ICMPV6_ECHOREQUEST,
    ENCAP_HDR_ICMPV6_MLDV1_DONE,
    ENCAP_HDR_ICMPV6_MLDV1_QUERY,
    ENCAP_HDR_ICMPV6_MLDV1_REPORT,
    ENCAP_HDR_ICMPV6_MLDV2_QUERY,
    ENCAP_HDR_ICMPV6_MLDV2_REPORT,
    ENCAP_HDR_ICMPV6_PACKETTOOBIG,
    ENCAP_HDR_ICMPV6_PARAMETERPROBLEM,
    ENCAP_HDR_ICMPV6_TIMEEXCEED,
    ENCAP_HDR_ICMPV6_NDP,                                /*NDP报文，目前包含NS，NA，RS，RA四种类型报文*/
    ENCAP_HDR_VN_Tag,
    ENCAP_HDR_LLC,
    ENCAP_HDR_STP_CONFIG,
    ENCAP_HDR_STP_TOPOLOGY_CHANGE_NOTIFICATION,
    ENCAP_HDR_RSTP_CONFIG,
    ENCAP_HDR_RSTP_TOPOLOGY_CHANGE_NOTIFICATION,
    ENCAP_HDR_PFC,
    ENCAP_HDR_PAUSE,
    ENCAP_HDR_FCOE,
    ENCAP_HDR_CHASSIS_ID_TLV,


    ENCAP_Geo_Basic_Header,
    ENCAP_Geo_Common_Header,
    ENCAP_Geo_Extend_Header,

    ENCAP_HDR_GEO,//GEO头
    ENCAP_HDR_MF,//MF头
    ENCAP_HDR_BTP_B,//BTP-B头
    ENCAP_HDR_SELF_DATA,//自定义数据
    ENCAP_TLV_NDN, // NDN TLV
    ENCAP_HDR_POWERLINK,
    ENCAP_HDR_SRV6,
    ENCAP_HDR_SEANET,
    ENCAP_HDR_NDN_TL,
    ENCAP_HDR_NDN_VALUE,
    ENCAP_HDR_IPV6_AH,            /* IPv6 Authentication Header */
    ENCAP_HDR_IPV6_DEST_OPT,      /* IPv6 Destination Options Header */
    ENCAP_HDR_IPV6_ESP,           /* IPv6 Encapsulating Security Payload Header */
    ENCAP_HDR_IPV6_HBH,           /* IPv6 Hop-By-Hop Options Header */
    ENCAP_HDR_IPV6_FRAG,          /* IPv6 Fragment Header */
    ENCAP_HDR_IPV6_ROUTING,       /* IPv6 Routing Header */
    ENCAP_HDR_IPV6_SRH,           /* IPv6 Segment Routing Header (RFC 8754) */
    ENCAP_HDR_IB,//rocev2头
};

/** var_type: 字符串，跳变域的字段类型，char/uint8/uint16/uint32，含义为字符，单字节数字，双字节数字，四字节数字 */
typedef enum {
    MDF_ZONE_INIT_TYPE = 0,
    MDF_ZONE_CHAR_TYPE = 0x0001,        /**< "char"，字符变量 */
    MDF_ZONE_UINT8_TYPE = 0x0002,             /**< "uint8", 单字节无符号整数 */
    MDF_ZONE_UINT16_TYPE = 0x0004,                  /**< "uint16"，双字节无符号整数，放到报文里面时，转成网络字节序 */
    MDF_ZONE_UINT32_TYPE = 0x0008,                  /**< "uint32"，四字节无符号整数，放到报文里面时，转成网络字节序 */
    MDF_ZONE_IP4_ADR_TYPE = 0x0010,                       /**< 4字节无符号整数，主要用于IPv4地址，放到报文里面时，转成网络字节序 */
    MDF_ZONE_IP6_ADR_TYPE = 0x0020,                       /**< 16字节无符号整数，主要用于IPv6地址，放到报文里面时，转成网络字节序 */
    MDF_ZONE_MAC_ADR_TYPE = 0x0040,                       /**< MAC地址类型，6个字节的MAC地址 */
    MDF_ZONE_MEMORY_TYPE = 0x0080,                  /**< memory类型，字节不固定,只有为列表跳变时特殊(通过内存拷贝，不采用value_next) */
    MDF_ZONE_IMSI_TYPE = 0x0081,                  /**< "uint32"，四字节无符号整数，放到报文里面时，转成网络字节序 */
} mdf_zone_type_t;

/** value_mode: 字符串，跳变域的跳变方式，fixed/increment/decrement/random/vlist，分别代表固定/递增/递减/随机/列表 */
typedef enum {
    MDF_ZONE_INT_MODE = 0,
    MDF_ZONE_FIX_MODE = 0x01,                 /**< "fixed"，跳变域的跳变方式为固定 */
    MDF_ZONE_INC_MODE = 0x02,                 /**< "increment"，跳变域的跳变方式为递增 */
    MDF_ZONE_DEC_MODE = 0x04,                 /**< "decrement"，跳变域的跳变方式为递减 */
    MDF_ZONE_RAN_MODE = 0x08,                 /**< "random"，跳变域的跳变方式为随机 */
    MDF_ZONE_LST_MODE = 0x10,                 /**< "vlist"，跳变域的跳变方式为列表 */
    MDF_ZONE_ATO_MODE = 0x20,                 /**< "auto"，跳变域的跳变方式为自动 */
    MDF_ZONE_IMIX_MODE = 0x40,                 /**< "auto"，跳变域的跳变方式为自动 */
} mdf_zone_mode_t;

typedef enum {
    MDFILT_QDMA = 0,            /**< Pass, 过滤器匹配到，接收报文 */
    MDFILT_DROP = 1,            /**< Drop, 过滤器匹配到，丢弃报文 */
} filter_action_t;

typedef enum {
    FILTER_PASS = 0,            /**< Pass, 过滤器匹配到，接收报文 */
    FILTER_DROP = 1,            /**< Drop, 过滤器匹配到，丢弃报文 */
    FILTER_QUEUE = 2,           /**< Queue, 过滤器匹配到，将报文入队到指定流 */
} mdfilt_action_t;

typedef enum {
    LIFO_MODE = 0,        /**< 时延类型为      后进先出 */
	LILO_MODE,            /**< 时延类型为      先进先出 */
	FIFO_MODE,            /**< 时延类型为      后进后出 */
	FILO_MODE,            /**< 时延类型为      先进后出 */
} delay_mode_t;


typedef enum {
    DIRECT_CLIENT = 0,   /**< 向驱动传递标识为客户端 */
	DIRECT_SERVER,       /**< 向驱动传递标识为服务端 */
} direct_mode_t;


typedef enum {
    FILTER_OR = 0,             /**< 多过滤条件，与操作 */
    FILTER_AND = 1,              /**< 多过滤条件，或操作 */
    FILTER_NOT = 2,             /**< 多过滤条件，非操作 */
} filter_relate_t;

typedef struct ntdrv_stats {
  unsigned long rxPackets;
  unsigned long rxBytes;
} __ynic_cache_aligned ntdrv_stats_t;


#define NTNET_SETIFF   _IOW('g', 200, struct ifreq)
#define NETIF_INC_RECV _IOW('g', 201, struct ntdrv_stats)
#define NETIF_RX_DATA  _IOW('g', 202, int)

typedef struct __eth_adr {
    uint8_t addr_bytes[ETH_ADR_LEN];    /**< 为了避免使用scanf的时候，最后一个字节强制当作int类型越界，所以增加4个字节的空间 */
} __ynic_cache_packed eth_adr_t;

typedef struct __eth_hdr {
    eth_adr_t d_addr;            /* destination eth addr */
    eth_adr_t s_addr;            /* source ether addr    */
    uint16_t ether_type;        /* packet type ID field */
} __ynic_cache_packed eth_hdr_t;

/**
 * Ethernet VLAN Header.
 * Contains the 16-bit VLAN Tag Control Identifier and the Ethernet type
 * of the encapsulated frame.
 */
typedef struct __vlan_hdr {
    uint16_t vlan_tci; /**< Priority (3) + CFI (1) + Identifier Code (12) */
    uint16_t eth_proto;/**< Ethernet type of encapsulated frame. */
} __ynic_cache_packed vlan_hdr_t;

/**
 * VXLAN protocol header.
 * Contains the 8-bit flag, 24-bit VXLAN Network Identifier and
 * Reserved fields (24 bits and 8 bits)
 */
typedef struct __vxlan_hdr {
    uint32_t vx_flags; /**< flag (8) + Reserved (24). */
    uint32_t vx_vni;   /**< VNI (24) + Reserved (8). */
} __ynic_cache_packed vxlan_hdr_t;

/* 5-tuple key type, ipv4 socket on dpdk network follow this */
typedef struct __vlan_cfg {
    uint8_t vlan_en:2;     				/**< 通用的内层802.1q 普通VLAN是否启用 */
    uint8_t qinq_en:2;					/**< 外层的802.1ad QinQ 是否启用 */
    uint8_t vlan_pri:3;  				/**vlan头部中的3位优先级，可以用作PFC的优先级，默认0 */
    uint8_t vlan_cfi:1;    				/**< vlan头部中的1位CFI字段，用于标识是否CFI网络，默认0 */
    uint16_t qinq_id;      				/**< 如果外层的802.1ad QinQ启用，此为VLAN ID，本地字节序 */        
    uint16_t vlan_id;      				/**< 如果内层通用的802.1q普通VLAN启用，此为VLAN ID，本地字节序 */    
} __ynic_cache_packed vlan_cfg_t;

typedef struct __vxlan_cfg {
    uint16_t vxlan_flags;                   
    uint16_t policy_id;    
    uint32_t vni_id:24;
    uint32_t vni_rev:8;
} __ynic_cache_packed vxlan_cfg_t;

typedef struct __ah_header {
	uint8_t next_proto;     /**< IPv4 or IPv6 or next layer header */
	uint8_t payload_len;    /**< number of payload bytes (0-255) */
	uint8_t pad_len;        /**< number of pad bytes (0-255) */
    uint16_t reserved;
	uint32_t spi;           /**< Security Parameters Index */
	uint32_t seq;           /**< packet sequence number */
} __ynic_cache_packed ah_hdr_t;

/**
 * ESP Header
 */
typedef struct __esp_header {
	uint32_t spi;  /**< Security Parameters Index */
	uint32_t seq;  /**< packet sequence number */
} __ynic_cache_packed esp_hdr_t;

/**
 * ESP Trailer
 */
typedef struct __esp_tail {
	uint8_t pad_len;     /**< number of pad bytes (0-255) */
	uint8_t next_proto;  /**< IPv4 or IPv6 or next layer header */
} __ynic_cache_packed esp_tail_t;

/**
    PFC(Priority-based flow control)帧，其特征如下：

    PFC Pause 帧：是一种特殊的控制帧，用于基于优先级的流量控制。
        这种帧类型允许网络设备对具有不同优先级的流量进行单独控制，
        从而可以独立暂停和恢复各种优先级的数据流。PFC Pause帧基于传统
        的802.3x Pause帧扩展而来，并增加了优先级的概念。

    PFC Pause帧的特点是：

        目的MAC地址：01-80-C2-00-00-01（用于以太网流控制的保留多播地址）
        EtherType: 0x8808，表示MAC Control帧
        操作码（Opcode）：0x0101，代表是PFC帧
        优先级使能向量（Priority Enable Vector）：指示哪些优先级被暂停的位字段。
        优先级的PAUSE时间：对每个被启用的优先级都有一个对应的PAUSE时间值，
            以决定暂停该优先级流量的时长。
 
    在IEEE 802.1Qbb Priority-Based Flow Control (PFC) 中，PAUSE 帧用于协调以太网流量控制，
    其中每个优先级的流量可以独立地暂停和恢复。PAUSE 帧中包含了一个优先级使能向量
    （Priority Enable Vector），它是一个8位字段，每一位代表一个不同的优先级。
    此外，PAUSE 帧为每个优先级分别提供一个 PAUSE 时间值。

    优先级使能向量指示哪些优先级的流量应被暂停。例如，如果向量的值是二进制的 ​00000101​，
    这意味着第0和第2优先级的流量应该暂停，而其他优先级的流量应该继续。

    每个被激活暂停的优先级都有相应的 PAUSE 时间值，它们通常包含在 PAUSE 帧的后续字段中。
    PAUSE 时间值是一个16位字段，定义了暂停发送特定优先级流量的时间长度，
    单位是slot time (512比特时间)。对于每一个启用暂停的优先级，网络设备读取相应的 PAUSE 时间，
    并基于这个值暂停发送数据。

    换句话说，计算暂停时间不单是依赖于优先级使能向量，而是还需要读取与每个激活的优先级关联的
    PAUSE 时间值。以下是一个简化的例子：

    假设优先级使能向量是 ​00000101​，并且我们有两个 PAUSE 时间值：

    对应第0优先级的PAUSE时间是0x0010
    对应第2优先级的PAUSE时间是0x0020

    那么设备将会：
    暂停第0优先级的流量大约为 0x0010 × 512比特时间
    暂停第2优先级的流量大约为 0x0020 × 512比特时间
    其他的优先级将不会被暂停。

    实际的时间量需要进一步转换为微秒、毫秒或者秒，具体取决于网络的速度。
    例如，在1 Gbps的网络上，一个比特时间是1纳秒，因此0x0010 × 512比特时间将是    0x0010 × 512 纳秒。           
 */
typedef struct __pfc_hdr {
	uint16_t opcode;
	uint16_t pri_vector;
	uint16_t pause_times[8];
} __ynic_cache_packed pfc_hdr_t;

/* ARP packet format */
typedef struct __arp_hdr {
    uint16_t hrd;                            /**< ARP Hardware type */
    uint16_t pro;                            /**< ARP Protocol type */
    uint8_t hln;                       /**< Hardware length */
    uint8_t pln;                       /**< Protocol length */
    uint16_t op;                       /**< opcode */
    eth_adr_t sha;                                     /**< Sender hardware address */
    in_addr_t spa;                                     /**< Sender IP address */
    eth_adr_t tha;                                     /**< Target hardware address */
    in_addr_t tpa;                                      /**< Target protocol address */
} __ynic_cache_packed arp_hdr_t;

/** Network arp list */
typedef struct __ynic_arp {
    uint8_t portid;                               /**< ARP entry on this port */
    int arp_entry_id;                 /**< ARP entry in buffer pool 中的偏移量，删除此ARP条目的时候使用 */
    in_addr_t ip4addr;                      /**< IP v4 address in network order */
    in6_addr_t ip6addr;                           /**< IP v6 address in network order*/
    eth_adr_t macaddr;                      /**< Mac address bind with IP address */
} __ynic_cache_packed ynic_arp_t;

/**
 * ICMP Header
 */
typedef struct __icmp_hdr {
    uint8_t icmp_type;            /* ICMP packet type. */
    uint8_t icmp_code;            /* ICMP packet code. */
    uint16_t icmp_cksum;        /* ICMP packet checksum. */
    uint16_t icmp_ident;        /* ICMP packet identifier. */
    uint16_t icmp_seq_nb;        /* ICMP packet sequence number. */
} icmp_hdr_t;

typedef struct __icmpv6_hdr {
    uint8_t type;            /* ICMPv6 packet type. */
    uint8_t code;            /* ICMPv6 packet code. */
    uint16_t cksum;        /* ICMPv6 packet checksum. */
    uint8_t msg_body[0];
} icmpv6_hdr_t;

typedef struct __mac_masq_cfg {
    uint8_t mac_masq_en;            /**< 端口有没有启用mac伪装，0为禁用，1为启用 */
    char mac_masq_prefix[10];       /**< MAC的前两个字节，第一个字节的最低位不能为1 */
    uint8_t mac_masq_bytes[2];      /**< user defined first 2 bytes for mac masquerade */
} __ynic_cache_packed mac_masq_cfg_t;

typedef struct __next_mac_cfg {
    uint8_t next_mac_method;    /**< Get the MAC address method for next jump interface, NEXT_MAC_BY_ARP_NSNA or NEXT_MAC_BY_USER_INPUT */
    eth_adr_t next_mac;         /**< the MAC address for next jump interface */
} __ynic_cache_packed next_mac_cfg_t;

typedef struct __ieee8023_logical_link_ipv4_header {
    uint8_t ig_bit:1;
    uint8_t sap1:7;
    uint8_t cr_bit:1;
    uint8_t sap2:7;    
    uint8_t frame_type:2;
    uint8_t command:6;    
} __ynic_cache_packed ieee8023_logical_link_ipv4_header_t;

typedef struct __ieee8023_routing_info_ipv4_header {
    uint8_t routing_protocal_disc;
    uint8_t len_indicator;
    uint8_t version_id_ext;
    uint8_t id_len;
    uint8_t pdu_type:5;
    uint8_t reserved1:3;    
    uint8_t version;
    uint8_t reserved2;
    uint8_t max_area_addr;
} __ynic_cache_packed ieee8023_routing_info_ipv4_header_t;

/* Internet protocol header structure */
/* Basic IPv4 packet header
 *
 *                        IPv4 Header Format
 *
 *    0                   1                   2                   3
 *    0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1
 *   +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
 *   | Ver   | hlen  |      TOS      |         Total length          |
 *   +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
 *   |         Ident                 |flags|     fragment offset     |
 *   +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
 *   |    TTL        |    Protocol   |       Header Checksum         |
 *   +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
 *   |                    Source Address (32  Bits)                  |
 *   +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
 *   |                 Destination Address (32  Bits)                |
 *   +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
 *   |                             data                              |
 *   +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
 */
typedef struct __ipv4_header {
#if __BYTE_ORDER == __LITTLE_ENDIAN
    uint8_t header_len:4;
    uint8_t version:4;
#elif __BYTE_ORDER == __BIG_ENDIAN
    uint8_t version:4;
    uint8_t header_len:4;
#else
#error "Please fix libc <bits/endian.h> or kernel <asm/byteorder.h>"
#endif
    uint8_t tos;
    uint16_t tot_len;      /** IPv4头部 + 后面的TCP/UDP头部 + 载荷长度，没有CRC4个字节，但是包括ROCE报文的ICRC */
    uint16_t id;
#if __BYTE_ORDER == __LITTLE_ENDIAN
    uint16_t frag_off1:5;
    uint16_t mf:1;
    uint16_t df:1;
    uint16_t res:1;
    uint16_t frag_off2:8;
#define IP_SET_FRAGOFF(ip,v) {(ip)->frag_off1=((v)&0x1F00)>>8;(ip)->frag_off2=(v)&0x00FF;}
#define IP_GET_FRAGOFF(ip) (0x1FFFF & ((((ip)->frag_off1&0x1F)<<8) | ((ip)->frag_off2&0xFF)))
#elif __BYTE_ORDER == __BIG_ENDIAN
    uint16_t res:1;
    uint16_t df:1;
    uint16_t mf:1;
    uint16_t frag_off:13;
#define IP_SET_FRAGOFF(ip,v) (ip)->frag_off=(v)
#define IP_GET_FRAGOFF(ip) ((ip)->frag_off)
#else
#error "Please fix libc <bits/endian.h> or kernel <asm/byteorder.h>"
#endif
    uint8_t ttl;
    uint8_t protocol;
    uint16_t check;
    uint32_t saddr;
    uint32_t daddr;
} __ynic_cache_packed ipv4_hdr_t;

typedef struct __ipv4_option_hdr {
#if __BYTE_ORDER == __LITTLE_ENDIAN
    uint8_t number:5;
    uint8_t clas:2;
    uint8_t copy:1;
#elif __BYTE_ORDER == __BIG_ENDIAN
    uint8_t copy:1;
    uint8_t clas:2;
    uint8_t number:5;
#else
#error "Please fix libc <bits/endian.h> or kernel <asm/byteorder.h>"
#endif
    uint8_t length;
} __ynic_cache_packed ipv4_option_hdr_t;

typedef struct __nsnic_ipv6_header_hard_version {
#if __BYTE_ORDER == __LITTLE_ENDIAN
        uint32_t flow_label:20;
        uint32_t traffic_class:8;
        uint32_t version:4;
#elif __BYTE_ORDER == __BIG_ENDIAN
        uint32_t version:4;
        uint32_t traffic_class:8;
        uint32_t flow_label:20;
#else
#error "Please fix libc <bits/endian.h> or kernel <asm/byteorder.h>"
#endif
} __ynic_cache_packed nsnic_ipv6_header_hard_version_hdr_t;
typedef struct __nsnic_ipv6_header {
    union {
        uint32_t u32_version;
        nsnic_ipv6_header_hard_version_hdr_t ipv6_header_version;
    };
    uint16_t payload_length;    /**< 除了IPv6头部之外，后面的扩展头部和载荷的长度 */
    uint8_t next_header;
    uint8_t hop_limit;
    union {
        uint8_t saddr[16];
        struct in6_addr ipv6_saddr;
    };
    union {
        uint8_t daddr[16];
        struct in6_addr ipv6_daddr;
    };
} __ynic_cache_packed nsnic_ipv6_hdr_t;

typedef struct __nsnic_tcp_header {
    uint16_t source;
    uint16_t dest;
    uint32_t seq;                    /**< Synchronize sequence number in this packet */
    uint32_t ack_seq;                /**< Acknowledgment Number in this packet */
#if __BYTE_ORDER == __LITTLE_ENDIAN
    uint16_t flags:6;
    uint16_t reserved:6;                              /**< TCP header length inclue option in 4 bytes words */
    uint16_t data_offset:4;                              /**< The flat bit indicate No more data from sender */
#elif __BYTE_ORDER == __BIG_ENDIAN
    uint16_t data_offset:4;                              /**< TCP header length inclue option in 4 bytes words */
    uint16_t reserved:6;
    uint16_t flags:6;
#else
#error "Please fix libc <bits/endian.h> or kernel <asm/byteorder.h>"
#endif
    /** 
     * The number of data octets beginning with the one indicated in the
     * acknowledgment field which the sender of this segment is willing to accept.
     */
    uint16_t window;
    uint16_t check;
    uint16_t urg_ptr;
} __ynic_cache_packed nsnic_tcp_hdr_t;

typedef struct __pppoe_hdr {
#if __BYTE_ORDER == __LITTLE_ENDIAN
    unsigned int type:4;
    unsigned int version:4;
#elif __BYTE_ORDER == __BIG_ENDIAN
    unsigned int version:4;
    unsigned int type:4;
#else
#error "Please fix <bits/endian.h>"
#endif
    uint8_t code;
    uint16_t session_id;
    uint16_t payload_length;
}__ynic_cache_packed pppoe_hdr_t;

typedef struct __ppp_hdr {
    uint8_t address;
    uint8_t control;
    uint16_t protocol;
}__ynic_cache_packed ppp_hdr_t;

typedef struct __nsnic_l2tpv2_hdr {
#if __BYTE_ORDER == __LITTLE_ENDIAN
    uint16_t version:4;
    uint16_t reserved2:4;
    uint16_t use_priority:1;
    uint16_t use_offset:1;
    uint16_t reserved1:1;
    uint16_t use_sequence:1;
    uint16_t reserved:2;
    uint16_t use_length:1;
    uint16_t type:1;
#elif __BYTE_ORDER == __BIG_ENDIAN
    uint16_t type:1;
    uint16_t use_length:1;
    uint16_t reserved:2;
    uint16_t use_sequence:1;
    uint16_t reserved1:1;
    uint16_t use_offset:1;
    uint16_t use_priority:1;
    uint16_t reserved2:4;
    uint16_t version:4;
#else
#error "Please fix libc <bits/endian.h> or kernel <asm/byteorder.h>"
#endif
    uint16_t tunnel_id;
    uint16_t session_id;
} __ynic_cache_packed nsnic_l2tpv2_hdr_t;

typedef struct __nsnic_l2tpv2_ctr_hdr {
#if __BYTE_ORDER == __LITTLE_ENDIAN
    uint16_t version:4;
    uint16_t reserved2:4;
    uint16_t use_priority:1;
    uint16_t use_offset:1;
    uint16_t reserved1:1;
    uint16_t use_sequence:1;
    uint16_t reserved:2;
    uint16_t use_length:1;
    uint16_t type:1;
#elif __BYTE_ORDER == __BIG_ENDIAN
    uint16_t type:1;
    uint16_t use_length:1;
    uint16_t reserved:2;
    uint16_t use_sequence:1;
    uint16_t reserved1:1;
    uint16_t use_offset:1;
    uint16_t use_priority:1;
    uint16_t reserved2:4;
    uint16_t version:4;
#else
#error "Please fix libc <bits/endian.h> or kernel <asm/byteorder.h>"
#endif
    uint16_t length;
    uint16_t tunnel_id;
    uint16_t session_id;
    uint16_t ns_value;
    uint16_t nr_value;
} __ynic_cache_packed nsnic_l2tpv2_ctr_hdr_t;


/* The struct of DHCP packet header */
typedef struct __nsnic_dhcp_hdr {
    uint8_t message_type;                                      /**< The op code of this dhcp packet */
    uint8_t htype;                             /**< The hw type of this dhcp packet */
    uint8_t hlen;                        /**< The hw address length of this dhcp packet */
    uint8_t hops;                        /**< The hops of this dhcp packet */
    uint32_t xid;                        /**< The transaction id of this dhcp packet */
    uint16_t secs;                             /**< The seconds elapsed of this dhcp packet */
    uint16_t flags;                                  /**< The flags of this dhcp packet */
    in_addr_t ciaddr;                    /**< The client ip address of this dhcp packet */
    in_addr_t yiaddr;                    /**< Your ip address of this dhcp packet */
    in_addr_t siaddr;                    /**< Next server ip address of this dhcp packet */
    in_addr_t giaddr;                    /**< Relay agent ip address of this dhcp packet */
    eth_adr_t ue_mac;                    /**< UE mac address of this dhcp packet */
    uint8_t us_mac_padding[10];                      /**< UE mac address padding of this dhcp packet */
    char sname[64];                                  /**< Server hostname of this dhcp packet */
    char file[128];                                  /**< Boot file name of this dhcp packet */
    uint32_t magic;                                  /**< DHCP magic of this dhcp packet */
    unsigned char option[0];       /**< DHCP option of this dhcp packet */
} __ynic_cache_packed nsnic_dhcp_hdr_t;

/* The struct of IGMPv1 packet header */
typedef struct __nsnic_igmp_hdr {
    uint8_t type;
    uint8_t reserved;
    uint16_t checksum;
    uint32_t maddr;
} __ynic_cache_packed nsnic_igmp_hdr_t;

/* The struct of IGMPv1 packet header */
typedef struct __nsnic_igmpv3_report_hdr {
    uint8_t type;
    uint8_t reserved;
    uint16_t checksum;
    uint16_t reserved1;
    uint16_t num_group_records;
} __ynic_cache_packed nsnic_igmpv3_report_hdr_t;


/* Basic IPv6 packet header
 *
 *                        IPv6 Header Format
 *
 *    0                   1                   2                   3
 *    0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1
 *   +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
 *   | Ver   | Traffic Class |            Flow Label                 |
 *   +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
 *   |         Payload Length        |  Next Header  |   Hop Limit   |
 *   +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
 *   |                                                               |
 *   |                    Source Address (128 Bits)                  |
 *   |                                                               |
 *   |                                                               |
 *   +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
 *   |                                                               |
 *   |                 Destination Address (128 Bits)                |
 *   |                                                               |
 *   |                                                               |
 *   +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
 *   |                             data                              |
 *   +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
 */
typedef struct __ipv6_header {
#if __BYTE_ORDER == __LITTLE_ENDIAN
    uint8_t priority:4;
    uint8_t version:4;
#elif __BYTE_ORDER == __BIG_ENDIAN
    uint8_t version:4;
    uint8_t priority:4;
#else
#error "Please fix libc <bits/endian.h> or kernel <asm/byteorder.h>"
#endif
    uint8_t flow_lbl[3];
    uint16_t payload_length;    /**< 除了IPv6头部之外，后面的扩展头部和载荷的长度 */
    uint8_t next_header;
    uint8_t hop_limit;
    union {
        uint8_t saddr[16];
        struct in6_addr ipv6_saddr;
    };
    union {
        uint8_t daddr[16];
        struct in6_addr ipv6_daddr;
    };
} __ynic_cache_packed ipv6_hdr_t;

typedef struct __ipv6_frag_header {
	uint8_t next_header;
	uint8_t reserve;
    uint16_t frag_off;  /**< 13位偏移量 + 2位保留 + 1位MF（more flag，是否还有分片） */
	uint32_t id;
} __ynic_cache_packed ipv6_frag_hdr_t;

typedef struct __ipv6_pseudo_hdr {
    in6_addr_t saddr;
    in6_addr_t daddr;
    volatile uint32_t ulp_length;
    volatile uint32_t zero:24;
    volatile uint32_t next_header:8;
} __ynic_cache_packed ipv6_pseudo_hdr_t;

typedef struct tcp4_pseudohdr {
    uint32_t saddr;
    uint32_t daddr;
    uint8_t pad;
    uint8_t protocol;
    uint16_t len;
} __ynic_cache_packed tcp4_pseudo_hdr_t;

typedef struct tcp6_pseudohdr {
    in6_addr_t saddr;
    in6_addr_t daddr;
    uint32_t len;
    uint32_t protocol;
} __ynic_cache_packed tcp6_pseudo_hdr_t;

typedef struct __ip_addr {
    uint16_t domain;                /**< AF_INET/AF_INET6: IPv4/v6 Internet protocols */
    char ip_str[INET6_ADDRSTRLEN];              /**< Minimum local ip address like "17.1.2.2" or "3ffe:1:1:1::2" */
    union {
        in_addr_t ipv4_addr;        /**< IPv4地址，主机字节序 */
        in6_addr_t ipv6_addr;             /**< IPv6地址，主机字节序 */
    };
    union {
        in_addr_t net_ipv4_addr;    /**< IPv4地址，网络字节序 */
        in6_addr_t net_ipv6_addr;         /**< IPv6地址，网络字节序 */
    };
    uint128_t ipv6_uint128;                           /**< 如果是ipv6地址，内容与ipv6_addr相同，只是类型变成了uint128_t */
} __ynic_cache_packed ip_addr_t;

typedef struct __ipv6_pad_addr {
    uint32_t padding1;
    uint32_t padding2;
    uint32_t padding3;
    in_addr_t ipv4_addr;
} __ynic_cache_packed ipv6_pad_addr_t;

typedef struct __ipv6_adr {
    union {
        uint128_t u128;
        uint8_t u8[16];
    };
} __ynic_cache_packed ipv6_adr_t;

/** IP地址区间，比如17.1.1.2-17.1.1.100，如果只有一个IP地址，也是一个区域，比如17.1.1.100，则最大最小都相同 */
typedef struct __ipaddr_range {
    uint16_t domain;                    /**< AF_INET/AF_INET6: IPv4/v6 Internet protocols */
    uint64_t nb_ipaddr;                	/**< 这个IP地址区间总共有多少个IP地址 */
	eth_adr_t min_mac;
    eth_adr_t max_mac;    
    union {
        in_addr_t min_ipv4_addr;        /**< IP地址区间的最小IPv4地址，主机字节序 */
        in6_addr_t min_ipv6_addr;       /**< IP地址区间的最小IPv6地址，主机字节序 */
    };
    uint128_t min_ipv6_uint128;         /**< 如果是ipv6地址，内容与min_ipv6_addr相同，只是类型变成了uint128_t */
    union {
        in_addr_t max_ipv4_addr;        /**< IP地址区间的最大IPv4地址，主机字节序 */
        in6_addr_t max_ipv6_addr;       /**< IP地址区间的最大IPv6地址，主机字节序 */
    };
    uint128_t max_ipv6_uint128;         /**< 如果是ipv6地址，内容与min_ipv6_addr相同，只是类型变成了uint128_t */
    union {
        in_addr_t step_addr;        	/**< IP地址区间的步进值 */
        in6_addr_t step_ipv6_addr;      /**< IP地址区间的步进值 */
    };
    uint128_t step_ipv6_uint128;        /**< 如果是ipv6地址，内容与step_ipv6_addr相同，只是类型变成了uint128_t */
} __ynic_cache_packed ipaddr_range_t;

typedef struct __ipaddr_list {
    uint16_t domain;            /**< AF_INET/AF_INET6: IPv4/v6 Internet protocols */
    uint16_t iprange_count;     /**< 总共有多少个IP地址区间，每个逗号分开的，都是一个IP地址区间 */
    uint128_t ipaddr_count;     /**< IP地址区间中，总共包含多少个IP地址 */
    union {
        in_addr_t ipv4_step;    /**< IPv4 Step Value, 主机字节 */
        uint128_t ipv6_step;    /**< IPv6 Step Value, 主机字节 */
    };
    uint16_t mac_step;
    ipaddr_range_t ipaddr_range[MAX_IPRANGE_PER_SUBNET];
} __ynic_cache_packed ipaddr_list_t;

/* 5-tuple key type, ipv4 socket on dpdk network follow this */
typedef struct ipv4_5tuple {
    uint8_t proto;                          /**< protocol, should be 'IPPROTO_TCP' or 'IPPROTO_UDP' */
    in_addr_t ip_src;                 /**< src ip in network order */
    in_addr_t ip_dst;                 /**< dst ip in network order */
    uint16_t port_src;                      /**< src port in network order */
    uint16_t port_dst;                      /**< dst port in network order */
} __ynic_cache_packed ipv4_5tuple_t;

/* 5-tuple key type, ipv6 socket on dpdk network follow this */
typedef struct ipv6_5tuple {
    uint8_t proto;                          /**< protocol, should be 'IPPROTO_TCP' or 'IPPROTO_UDP' */
    in6_addr_t ip_src;                      /**< src ip in network order */
    in6_addr_t ip_dst;                      /**< dst ip in network order */
    uint16_t port_src;                      /**< src port in network order */
    uint16_t port_dst;                      /**< dst port in network order */
} __ynic_cache_packed ipv6_5tuple_t;

/** IP地址区间，比如17.1.1.2-17.1.1.100，如果只有一个IP地址，也是一个区域，比如17.1.1.100，则最大最小都相同 */
typedef struct __port_range {
    uint16_t min_port;		/**< 端口最小值，>= 此值 */
	uint16_t max_port;		/**< 端口最大值，<= 此值 */
	uint16_t port_step;		/**< 端口步进值 */
	uint16_t port_count;	/**< 端口数量, max_port - min_port + 1 */
} __ynic_cache_packed port_range_t;

/** FPGA执行指定虚拟用户数量5元组跳变的数据结构 */
typedef struct __simuser_5tuple {  
	uint32_t nb_simuser;			/**< 虚拟用户的数量，0表示在五元组区域循环，> 1表示只循环固定个数五元组 */
	ipaddr_range_t src_ipaddr;	/**< 按照 源IP -> 目的IP -> 源端口 -> 目的端口 进行跳变，跳变数量为nb_simuser */	
	ipaddr_range_t dst_ipaddr;	/**< 按照 源IP -> 目的IP -> 源端口 -> 目的端口 进行跳变，跳变数量为nb_simuser */	
	port_range_t src_port;		/**< 按照 源IP -> 目的IP -> 源端口 -> 目的端口 进行跳变，跳变数量为nb_simuser */	
	port_range_t dst_port;		/**< 按照 源IP -> 目的IP -> 源端口 -> 目的端口 进行跳变，跳变数量为nb_simuser */	
} simuser_5tuple_t;

typedef struct __md_imix_cfg {  
	int proportion;         /**< 比重*/   
	uint32_t frm_size;           /**< 帧长*/
} md_imix_cfg_t;	


typedef struct __udp_header {
    uint16_t source;
    uint16_t dest;
    uint16_t len;           /**< UDP头部8字节 + UDP载荷长度 */
    uint16_t check;
} __ynic_cache_packed udp_hdr_t;

/* TCP HEADER
 * Ripped straight out of glibc-2.2.2, modified for RFC22481
 * Reproduced here to prevent nasty #defines on non-linux boxes
 */
typedef struct __tcp_header {
    uint16_t source;
    uint16_t dest;
    uint32_t seq;                    /**< Synchronize sequence number in this packet */
    uint32_t ack_seq;                /**< Acknowledgment Number in this packet */
#if __BYTE_ORDER == __LITTLE_ENDIAN
    uint16_t res:4;
    uint16_t off:4;                              /**< TCP header length inclue option in 4 bytes words */
    uint16_t fin:1;                              /**< The flat bit indicate No more data from sender */
    uint16_t syn:1;                              /**< The flag bit of Synchronize sequence numbers */
    uint16_t rst:1;                              /**< The flag bit for Reset the connection */
    uint16_t psh:1;                              /**< Push Function, this packet and cached packets must deliver to upper layer at one */
    uint16_t ack:1;
    uint16_t urg:1;
    uint16_t cwr:1;
    uint16_t ecn:1;
#elif __BYTE_ORDER == __BIG_ENDIAN
    uint16_t off:4;                              /**< TCP header length inclue option in 4 bytes words */
    uint16_t res:4;
    uint16_t ecn:1;
    uint16_t cwr:1;
    uint16_t urg:1;
    uint16_t ack:1;
    uint16_t psh:1;                              /**< Push Function, this packet and cached packets must deliver to upper layer at one */
    uint16_t rst:1;                              /**< The flag bit for Reset the connection */
    uint16_t syn:1;                              /**< The flag bit of Synchronize sequence numbers */
    uint16_t fin:1;                              /**< The flat bit indicate No more data from sender */
#else
#error "Please fix libc <bits/endian.h> or kernel <asm/byteorder.h>"
#endif
    /** 
     * The number of data octets beginning with the one indicated in the
     * acknowledgment field which the sender of this segment is willing to accept.
     */
    uint16_t window;
    uint16_t check;
    uint16_t urg_ptr;
} __ynic_cache_packed tcp_hdr_t;

typedef struct __socket_tuple_string {
    uint8_t proto;
    uint16_t port_src;
    uint16_t port_dst;
    char ip_src[INET6_ADDRSTRLEN];
    char ip_dst[INET6_ADDRSTRLEN];    
} __ynic_cache_packed socket_tuple_string_t;

#define NOVA_MPLS_LS_LABEL_SHIFT 12
#define NOVA_MPLS_LS_EXP_SHIFT 9
#define NOVA_MPLS_LS_S_SHIFT 8
#define NOVA_MPLS_LS_TTL_SHIFT 0

typedef struct __mpls_header {
#if __BYTE_ORDER == __LITTLE_ENDIAN
    uint32_t ttl:8;
    uint32_t s:1;
    uint32_t exp:3;
    uint32_t label:20;
#elif __BYTE_ORDER == __BIG_ENDIAN
    uint32_t label:20;
    uint32_t exp:3;
    uint32_t s:1;
    uint32_t ttl:8;
#else
#error "Please fix libc <bits/endian.h> or kernel <asm/byteorder.h>"
#endif
} __ynic_cache_packed mpls_hdr_t;

typedef struct __gtpu_exten {
    uint16_t seq_num;                   /**< e,s,Pn三者任意为1时存在，s位为1时，包含一个序列号 */
    uint8_t n_pdu;                      /**< e,s,Pn三者任意为1时存在，Pn位为1时，包含一个N-PDU号 */
    uint8_t e_type;                     /**< e,s,Pn三者任意为1时存在，e位为1时，解析为Next Extension header type */
    uint8_t exten_length;               /**< Extension Header Length, 包含本身字节，单位：4字节倍数 */

#if __BYTE_ORDER == __LITTLE_ENDIAN
    uint8_t spare:4;                    /**< 剩余位 */
    uint8_t pdu_type:4;                 /**< PDU Type UL/DL */
#elif __BYTE_ORDER == __BIG_ENDIAN
    uint8_t pdu_type:4;                 /**< PDU Type UL/DL */
    uint8_t spare:4;                    /**< 剩余位 */
#else
#error "Please fix libc <bits/endian.h> or kernel <asm/byteorder.h>"
#endif

#if __BYTE_ORDER == __LITTLE_ENDIAN
    uint8_t qfi:6;                              /**< Qos Flow Identifier (QFI) */
    uint8_t rqi:1;                              /**< Refective Qos Indicator (RQI) DL类型会解析 */
    uint8_t ppp:1;                              /**< Paging Policy Presence (PPP) DL类型会解析 */
#elif __BYTE_ORDER == __BIG_ENDIAN
    uint8_t ppp:1;                              /**< Paging Policy Presence (PPP) DL类型会解析 */
    uint8_t rqi:1;                              /**< Refective Qos Indicator (RQI) DL类型会解析 */
    uint8_t qfi:6;                              /**< Qos Flow Identifier (QFI) */
#else
#error "Please fix libc <bits/endian.h> or kernel <asm/byteorder.h>"
#endif

    uint8_t next_type;                          /**< Next Extension Header Type */
} __ynic_cache_packed gtpu_exten_t;

typedef struct __gtpu_header {
#if __BYTE_ORDER == __LITTLE_ENDIAN
    uint8_t Pn:1;
    uint8_t s:1;
    uint8_t e:1;
    uint8_t reserved:1;
    uint8_t proto_type:1;
    uint8_t version:3;
#elif __BYTE_ORDER == __BIG_ENDIAN
    uint8_t version:3;              /**< 001 GTPv1, 010 GTPv2  */
    uint8_t proto_type:1;           /**< 0 GTP' GPRS计费采集协议, 1 GTP-U 封装用户数据协议/GTP-C 信令控制协议 */
    uint8_t reserved:1;             /**< 保留 0 */
    uint8_t e:1;                    /**< Next Extension header flag, 0 no, 1 has next */
    uint8_t s:1;                    /**< Sequence Number flag, 0 no, 1 add sequence number */
    uint8_t Pn:1;                   /**< N-PDU Number flag, 0 no set, 1 add PDU number */
#else
#error "Please fix libc <bits/endian.h> or kernel <asm/byteorder.h>"
#endif

    uint8_t msg_type;               /**< Message Type: 0x01 echo request, 0xff T-PDU  */
    uint16_t length;                /**< 不包含gtpu_hdr_t 8字节 */
    uint32_t teid;                  /**< 32位Tunnel Endpoint Identifier  */
} __ynic_cache_packed gtpu_hdr_t;

/**
 * Generic Routing Encapsulation (GRE) (RFC 1701)
 *
 * The GRE packet header has form:
 *
 *      0                   1                   2                   3
 *      0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1
 *     +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
 *     |C|R|K|S|s|Recur|  Flags  | Ver |         Protocol Type         |
 *     +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
 *     |      Checksum (optional)      |       Offset (optional)       |
 *     +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
 *     |                         Key (optional)                        |
 *     +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
 *     |                    Sequence Number (optional)                 |
 *     +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
 *     |                         Routing (optional)
 *     +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
 *
 * Key and Sequence Number Extensions to GRE (RFC 2890)
 *
 * The proposed GRE header will have the following format:
 *
 *      0                   1                   2                   3
 *      0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1
 *     +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
 *     |C| |K|S| Reserved0       | Ver |         Protocol Type         |
 *     +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
 *     |      Checksum (optional)      |       Reserved1 (Optional)    |
 *     +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
 *     |                         Key (optional)                        |
 *     +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
 *     |                 Sequence Number (Optional)                    |
 *     +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
 */
typedef struct __gre_hdr {
#if __BYTE_ORDER == __LITTLE_ENDIAN
    uint16_t recur:3,            /* recursion control       */
     s:1,                        /* strict source route     */
     S:1,                        /* sequence number present */
     K:1,                        /* key present             */
     R:1,                        /* routing present         */
     C:1,                        /* checksum present        */
     version:3,                    /* version                 */
     flags:5;                    /* flags                   */
#elif __BYTE_ORDER == __BIG_ENDIAN
    uint16_t C:1,                /* checksum present        */
     R:1,                        /* routing present         */
     K:1,                        /* key present             */
     S:1,                        /* sequence number present */
     s:1,                        /* strict source route     */
     recur:3,                    /* recursion control       */
     flags:5,                    /* flags                   */
     version:3;                    /* version                 */
#else
#error  "Please fix libc <bits/endian.h> or kernel <asm/byteorder.h>"
#endif
    uint16_t proto;                /* protocol */
    uint8_t __optional[0];        /* optional */
} __ynic_cache_packed gre_hdr_t;

/**
 * Generic Routing Encapsulation (GRE) (RFC 1701)
 *
 * Offset (2 octets)
 *
 *    The  offset  field  indicates  the octet offset from the start of the
 *    Routing  field  to  the  first octet of the active Source Route Entry
 *    to be examined.  This  field  is  present  if  the Routing Present or
 *    the Checksum Present bit is set to 1, and contains valid  information
 *    only if the Routing Present bit is set to 1.
 *
 *  Checksum (2 octets)
 *
 *    The Checksum  field  contains the IP (one's complement)  checksum  of
 *    the GRE  header  and  the  payload  packet.  This field is present if
 *    the  Routing  Present  or  the  Checksum Present bit is set to 1, and
 *    contains  valid  information  only if the Checksum Present bit is set
 *    to 1.
 */
typedef struct __gre_sum_hdr {
    uint16_t check;                /* checksum */
    uint16_t offset;            /* offset   */
} __ynic_cache_packed gre_sum_hdr_t;

/**
 * Generic Routing Encapsulation (GRE) (RFC 1701)
 *
 * Key (4 octets)
 *
 *    The  Key  field  contains  a  four octet number which was inserted by
 *    the encapsulator.  It may be used by the receiver to authenticate the
 *    source of the packet. The techniques for determining authenticity are
 *    outside of the scope of this document.  The Key field is only present
 *    if the Key Present field is set to 1.
 */
typedef struct __gre_key_hdr {
    uint32_t key;                /* key */
} __ynic_cache_packed gre_key_hdr_t;

/**
 * Generic Routing Encapsulation (GRE) (RFC 1701)
 *
 * Sequence Number (4 octets)
 *
 *    The Sequence Number  field  contains an unsigned 32 bit integer which
 *    is inserted by  the  encapsulator.  It may be used by the receiver to
 *    establish the  order  in which packets have been transmitted from the
 *    encapsulator to the receiver. The exact algorithms for the generation
 *    of  the  Sequence  Number  and  the  semantics  of their reception is
 *    outside of the scope of this document.
 */
typedef struct __gre_seq_hdr {
    uint32_t sequence;            /* sequence number */
} __ynic_cache_packed gre_seq_hdr_t;

typedef struct __txrx_counter {
    int64_t send_bytes;
    int64_t recv_bytes;
    int64_t recv_payload_bytes;
    int64_t send_packets;
    int64_t recv_packets;
    int64_t drop_packets;
    int64_t tx_ucast_pkts;
    int64_t rx_ucast_pkts;
    int64_t tx_mcast_pkts;
    int64_t rx_mcast_pkts;
    int64_t tx_bcast_pkts;
    int64_t rx_bcast_pkts;
    int64_t rx_crc_errors;
    int64_t rx_ip_cksum_err;
    int64_t rx_tcp_cksum_err;
    int64_t rx_udp_cksum_err;
    int64_t udp_fpga_rx_pkts;
} __ynic_cache_packed txrx_counter_t;

typedef struct __ynic_port {
    uint8_t enable;
	uint8_t ispcie5;         /**< 判断是否是pcie5 */
	uint8_t portoffset;      /**< 一分多模式记录端口偏移量 */
    uint8_t adapter_portid; /**< 每个网口在一块卡上序号，比如NT200A02上面的2个10G口，分别是0,1 */
    uint8_t system_portid;  /**< 每个网卡在整个系统Napatech网卡序号，比如两块NT200A02卡，4个口序号是0,1,2,3 */
    uint32_t featureMask;   /**< */
    char port_mac[40];
    char port_name[20];  
    char port_speed[20];
    char port_status[20];    
    char port_duplex[10];    
    char port_bus[40];
    ynic_adapter_t *ynic_adapter;
    int nb_tx_stream;
    int nb_rx_stream;
    ynic_tx_stream_t *tx_streams[MAX_STREAM_PER_PORT];
    ynic_rx_stream_t *rx_streams[MAX_STREAM_PER_PORT];
} __ynic_cache_aligned ynic_port_t;

typedef struct __ynic_adapter {
    uint8_t enable;
    uint8_t nb_ports;
    uint8_t numa_id;
    uint8_t adapter_id;   
    uint8_t support_dpdk;
    uint32_t adapter_type;    		/**< NtAdapterType_t or md_adapter_type_t */
    char bus_id[4];                 /**< PCIE的bus地址中的bus_id，比如03:00.0中的03，05:00.1中的05 */    
    char busdev[4];
    char busfuc[4];
    char busadr[40];                /**< PCIE的bus地址全称格式，<domain>:<bus>:<device>.<function>比如0000:05:00.1 */ 
    char adapter_name[32];          /** NT200A02/NT40E3_4_PTP/NT20E3_2_PTP */
    int fpga_rev;
    int fpga_ver;
    int fpga_product;
    int fpga_item;
    int fpga_build; 
    char fpga_profile[40];
    char fpga_partnum[40];          /**< P/N : 810-0048-05-10 */
    char bank0_fpgaid[40];          /**< FPGA Image #0 ID, 格式例如：200-9543-28-07 */
    char bank1_fpgaid[40];          /**< FPGA Image #1 ID, 格式例如：200-9543-28-07 */
    char running_fpgaid[40];        /**< 当前正在运行的FPGAID，格式例如200-9543-28-07 */
    int running_bankid;             /**< 如果两个bank相同，就显示为0 */
    ynic_port_t ynic_port[MAX_PORT_PER_ADP];        
}__ynic_cache_aligned ynic_adapter_t;

/**
"GlobalConfig": {
    "PortPciID": [
        {"PortName": "port1": "PciID": "07:00.0", "NapaID": -1},
        {"PortName": "port2": "PciID": "07:00.1", "NapaID": -1}
    ]
}
 */
typedef struct __port_pcicfg {
    uint8_t port_enable;        /**< 这个端口有没有被使用，比如46E平台4个口，有可能只用了port1和port3 */
    char port_name[10];         /**< 端口名称，比如port1或者port2 */
    char port_pciid[16];        /**< 端口对应的PCIID，比如07:00.0或者07:00.1 */
    char port_driver[24];       /**< 端口的驱动名称，比如ixgbe/i40e/mlx5 */
	int napa_id;                /**< 如果是FPGA网卡，对应的FPGA网卡ID，-1表示非FPGA网卡 */
} __ynic_cache_aligned port_pcicfg_t;

typedef struct __bond_port {
    uint8_t numa_id;                        /**< bond端口所在的numa id */
    uint8_t bond_portid;                    /**< bond的端口序号 */
    uint8_t bond_mode;                      /**< bond的7中模式，0-6 */
    uint8_t xmit_policy;                    /**< 如果bond的模式是balance，知道hash的策略 */
    uint8_t nb_physical_port;               /**< 总共有多少个物理端口 */
    uint16_t lcap_priority;                 /**< LACP优先级 */
    char bond_port_name[20];                /**< bond端口的名字，比如bond1，bond2 */
    char host_mgmtip[INET6_ADDRSTRLEN];     /**< bond口所属的主机的管理地址 */
    uint8_t slave_portid[MAX_PORTS_COUNT];  /**< 所有的子接口的DPDK端口ID */
    port_pcicfg_t physical_ports[MAX_PORTS_COUNT];               /** 各个物理端口的名称 */
} __ynic_cache_aligned bond_port_t;

typedef struct __bond_netcfg {
    uint8_t nb_bond_port;
    bond_port_t bond_port[MAX_PORTS_COUNT];
} __ynic_cache_aligned bond_netcfg_t;

typedef struct __ynic_nsdev {
    int inited;         /** 1表示系统中的FPGA网卡信息已经初始化过了 */
    int nslib_ver;      /** FPGA库版本信息，从0开始 */      
    int nb_numa;        /** 系统中有多少个NUMA节点 */
    int nb_adapters;    /** 系统中有多少个网卡 */
    int nb_ports;       /** 系统中有多少个网口 */ 
    char err_msg[ERR_MSG_LEN];   
    ynic_adapter_t ynic_adapter[MAX_FPGA_ADAPTER];    
} __ynic_cache_aligned ynic_nsdev_t;

typedef struct __mdf_uint8_zone {
    uint8_t zone_type;              /**< 为0时在value_start和value_end之间跳变，为1时根据zone_count进行跳变 */
    uint8_t zone_over;              /**< 跳变完一遍，马上从头开始跳变*/
    uint32_t zone_count;            /**< 跳变次数,达到跳变次数时完成一个发送循环,跳回起始值*/
    uint64_t nb_zone_updated;       /**< 这个跳变域已经跳变了多少次 */
    uint8_t value_next;             /**< 跳变域下一次要使用的值，变量会先预处理，然后在load_vbuf进行变换 */
    uint8_t value_start;            /**< 跳变方式为固定/递增/递减/随机时，为固定值或起始值，比如0x01，为16进制数值；跳变方式为列表时值为0，表示此值无效；从value_start开始，包括value_start */
    uint8_t value_end;              /**< 跳变方式为固定/递增/递减/随机时，为固定值或最终值，比如0xF1，为16进制数值；跳变方式为列表时值为0，表示此值无效；从value_start开始，包括value_start */
    uint8_t value_step;             /**< 跳变方式为递增/递减时，表示递增或递减量，为10进制数值；跳变方式为固定/随机/列表时值为0，表示此字段无效 */
    uint8_t value_mask;             /**< 掩码，用来指定该变化域中参与变化的位。值为1的位参与变化，值为0的位不参与变化 */
    uint8_t list_index;             /**< 跳变方式为列表时，表明下一个要取值的列表下标， 跳变方式为固定/递增/递减/随机时，值为0，表示此字段无效 */
    uint8_t list_count;             /**< 跳变方式为列表时，value_list数组的实际长度 */
    uint8_t *value_list;            /**< 跳变方式为列表时，从这个列表取值，取值后，依然使用value_mask进行位运算 */
    uint16_t list_zone_len;         /**< 跳变为列表时字段长度*/
} __ynic_cache_aligned mdf_uint8_zone_t;

typedef struct __mdf_uint16_zone {
    uint8_t zone_type;              /**< 为0时在value_start和value_end之间跳变，为1时根据zone_count进行跳变 */
    uint8_t zone_over;              /**< 跳变完一遍，马上从头开始跳变*/
    uint32_t zone_count;            /**< 跳变次数,达到跳变次数时完成一个发送循环,跳回起始值*/
    uint64_t nb_zone_updated;       /**< 这个跳变域已经跳变了多少次 */
    uint16_t value_next;            /**< 跳变域下一次要使用的值，变量会先预处理，然    后在load_vbuf进行变换 */
    uint16_t value_start;           /**< 跳变方式为固定/递增/递减/随机时，为固定值或起始值，比如0x01，为16进制数值；跳变方式为列表时值为0，表示此值无效；从value_start开始，包括value_start */
    uint16_t value_end;             /**< 跳变方式为固定/递增/递减/随机时，为固定值或起始值，比如0xF1，为16进制数值；跳变方式为列表时值为0，表示此值无效；从value_start开始，包括value_start */
    uint16_t value_step;            /**< 跳变方式为递增/递减时，表示递增或递减量，为10进制数值；跳变方式为固定/随机/列表时值为0，表示此字段无效 */
    uint16_t value_mask;            /**< 掩码，用来指定该变化域中参与变化的位。值为1的位参与变化，值为0的位不参与变化 */
    uint8_t list_index;             /**< 跳变方式为列表时，表明下一个要取值的列表下标， 跳变方式为固定/递增/递减/随机时，值为0，表示此字段无效 */
    uint8_t list_count;             /**< 跳变方式为列表时，value_list数组的实际长度 */
    uint16_t *value_list;           /**< 跳变方式为列表时，从这个列表取值，取值后，依然使用value_mask进行位运算 */
    uint16_t list_zone_len;         /**< 跳变为列表时字段长度*/
} __ynic_cache_aligned mdf_uint16_zone_t;

typedef struct __mdf_uint32_zone {
    uint8_t zone_type;              /**< 为0时在value_start和value_end之间跳变，为1时根据zone_count进行跳变 */
    uint8_t zone_over;              /**< 跳变完一遍，马上从头开始跳变*/
    uint32_t zone_count;            /**< 跳变次数,达到跳变次数时完成一个发送循环,跳回起始值*/
    uint64_t nb_zone_updated;       /**< 这个跳变域已经跳变了多少次 */
    uint32_t value_next;            /**< 跳变域下一次要使用的值，变量会先预处理，然后在load_vbuf进行变换 */
    uint32_t value_start;           /**< 跳变方式为固定/递增/递减/随机时，为固定值或起始值，比如0x01，为16进制数值；跳变方式为列表时值为0，表示此值无效；从value_start开始，包括value_start */
    uint32_t value_end;             /**< 跳变方式为固定/递增/递减/随机时，为固定值或起始值，比如0xF1，为16进制数值；跳变方式为列表时值为0，表示此值无效；从value_start开始，包括value_start */
    uint32_t value_step;            /**< 跳变方式为递增/递减时，表示递增或递减量，为10进制数值；跳变方式为固定/随机/列表时值为0，表示此字段无效 */
    uint32_t value_mask;            /**< 掩码，用来指定该变化域中参与变化的位。值为1的位参与变化，值为0的位不参与变化 */
    uint8_t list_index;             /**< 跳变方式为列表时，表明下一个要取值的列表下标， 跳变方式为固定/递增/递减/随机时，值为0，表示此字段无效 */
    uint8_t list_count;             /**< 跳变方式为列表时，value_list数组的实际长度 */
    uint32_t *value_list;           /**< 跳变方式为列表时，从这个列表取值，取值后，依然使用value_mask进行位运算 */
    uint16_t list_zone_len;         /**< 跳变为列表时字段长度*/
} __ynic_cache_aligned mdf_uint32_zone_t;

typedef struct __mdf_macaddr_zone {
    uint8_t zone_type;              /**< 为0时在value_start和value_end之间跳变，为1时根据zone_count进行跳变*/
    uint8_t zone_over;              /**< 跳变完一遍，马上从头开始跳变*/
    uint32_t zone_count;            /**< 跳变次数,达到跳变次数时完成一个发送循环,跳回起始值*/
    uint8_t list_index;             /**< 跳变方式为列表时，表明下一个要取值的列表下标， 跳变方式为固定/递增/递减/随机时，值为0，表示此字段无效 */
    uint8_t list_count;             /**< 跳变方式为列表时，value_list数组的实际长度 */
    uint64_t nb_zone_updated;       /**< 这个跳变域已经跳变了多少次 */
    eth_adr_t value_next;           /**< 跳变域下一次要使用的值，变量会先预处理，然后在load_vbuf进行变换 */
    eth_adr_t value_start;          /**< 跳变方式为固定/递增/递减/随机时，为固定值或起始值，比如0x01，为16进制数值；跳变方式为列表时值为0，表示此值无效；从value_start开始，包括value_start */
    eth_adr_t value_end;            /**< 跳变方式为固定/递增/递减/随机时，为固定值或起始值，比如0xF1，为16进制数值；跳变方式为列表时值为0，表示此值无效；从value_start开始，包括value_start */
    eth_adr_t value_step;           /**< 跳变方式为递增/递减时，表示递增或递减量，为10进制数值；跳变方式为固定/随机/列表时值为0，表示此字段无效 */
    eth_adr_t value_mask;           /**< 掩码，用来指定该变化域中参与变化的位。值为1的位参与变化，值为0的位不参与变化 */
    eth_adr_t *value_list;          /**< 跳变方式为列表时，从这个列表取值，取值后，依然使用value_mask进行位运算 */
    uint16_t list_zone_len;         /**< 跳变为列表时字段长度*/
} __ynic_cache_aligned mdf_macaddr_zone_t;

typedef struct __mdf_ipaddr_zone {
    uint8_t zone_type;              /**< 为0时在value_start和value_end之间跳变，为1时根据zone_count进行跳变*/
    uint8_t zone_over;              /**< 跳变完一遍，马上从头开始跳变*/
    uint32_t zone_count;            /**< 跳变次数,达到跳变次数时完成一个发送循环,跳回起始值*/
    uint8_t ip_domain;              /**< AF_INET/AF_INET6，对应IPv4和IPv6地址 */
    uint8_t list_index;             /**< 跳变方式为列表时，表明下一个要取值的列表下标， 跳变方式为固定/递增/递减/随机时，值为0，表示此字段无效 */
    uint8_t list_count;             /**< 跳变方式为列表时，value_list数组的实际长度 */
    uint64_t nb_zone_updated;       /**< 这个跳变域已经跳变了多少次 */
    ip_addr_t value_next;           /**< 跳变域下一次要使用的值，变量会先预处理，然后在load_vbuf进行变换 */
    ip_addr_t value_start;          /**< 跳变方式为固定/递增/递减/随机时，为固定值或起始值，比如0x01，为16进制数值；跳变方式为列表时值为0，表示此值无效；从value_start开始，包括value_start */
    ip_addr_t value_end;            /**< 跳变方式为固定/递增/递减/随机时，为固定值或起始值，比如0xF1，为16进制数值；跳变方式为列表时值为0，表示此值无效；从value_start开始，包括value_start */
    ip_addr_t value_step;           /**< 跳变方式为递增/递减时，表示递增或递减量，为10进制数值；跳变方式为固定/随机/列表时值为0，表示此字段无效 */
    ip_addr_t value_mask;           /**< 掩码，用来指定该变化域中参与变化的位。值为1的位参与变化，值为0的位不参与变化 */
    ip_addr_t *value_list;          /**< 跳变方式为列表时，从这个列表取值，取值后，依然使用value_mask进行位运算 */
    uint16_t list_zone_len;         /**< 跳变为列表时字段长度*/
} __ynic_cache_aligned mdf_ipaddr_zone_t;

/** 
 * 跳变域 ${__vbuf_modifiers(pkt_id,mdf_objid,field_name;value_type,value_mode,value_count;buf_pos,buf_size;value_start,value_end,value_step,value_mask,value_list)} 
 * 例如: ${__vbuf_modifiers(0,5f76e71219ec2a67e84ee2bc,tcp.reassembled.data;uint8,increment,8;4,1;0x00,0xFF,2,0x0F,[])}
 */
typedef struct __mdf_zone_var {
	uint8_t  filter_id;         /**< 过滤器id */
	uint8_t  action;            /**< 过滤器动作  'drop/queue' */
	uint8_t  relation;          /**< 逻辑关系 ‘与/或’ */
	uint8_t  filter_type;       /**< 配置类型 */
	uint8_t  filter_ruler;      /**< 过滤匹配规则 ‘== !=’ */
	//uint16_t  filter_fras;       /**< 过滤匹配规则 帧长 */
    uint16_t priority;          /**< 这个跳变处理的优先级，在报文接收的时候使用，0优先级最高，比如源端口为10000的报文优先级是10，流ID是1，所有报文优先级为20，流ID是0，那边源端口   为10000的报文优先匹配出来，送到流1 */
    uint32_t pkt_id;            /**< 表明报文在pcap中的顺序，比如第1个报文或者第3个报文,从0开始 */
    uint16_t value_type;        /**< 跳变域的字段类型，mdf_zone_type_t */
    uint16_t value_mode;        /**< 跳变域的跳变方式，mdf_zone_mode_t */
    uint16_t value_count;       /**< 跳变域包含的字段数量，比如value_type为char，value_count为4，就是指4个字符串，目前只实现了1，一个跳变域只有一个字段 */
    uint16_t buf_pos;           /**< 这个跳变域从buffer首地址开始的偏移量，比如pos="14"，buf_pos就是14，首地址从0开始 */
    uint32_t buf_size;          /**< 这个跳变域占据的长度，比如size="1"，buf_size就是1 */
    char mdf_objid[32];         /**< 字符串，跳变域对象的数据库保存ID */
    uint8_t stream_type;        /**< 根据streamtype进行先后跳变，intramodifier(流内)为1;intermodifier(流间)为2,intramodifier先跳变              (lmg add for encap)*/
    //uint16_t stream_count;    /**< 跳变的次数*/
    char field_name[128];       /**< 字符串，报文中这个字段的名称，比如name="eth.dst"，则field_name为eth.dst */
    uint16_t memory_type;       /**< 内存跳变类型*/
    char pattern_type[128];
    union {
        mdf_uint8_zone_t *mdf_uint8_zone;                /**< 跳变域为单字节数值时，具体的跳变方式 */
        mdf_uint16_zone_t *mdf_uint16_zone;              /**< 跳变域为双字节数值时，具体的跳变方式 */
        mdf_uint32_zone_t *mdf_uint32_zone;              /**< 跳变域为四字节数值时，具体的跳变方式 */
        mdf_ipaddr_zone_t *mdf_ip4adr_zone;              /**< 跳变域为IPv4地址时，具体的跳变方式 */
        mdf_ipaddr_zone_t *mdf_ip6adr_zone;              /**< 跳变域为IPv6地址时，具体的跳变方式 */
        mdf_macaddr_zone_t *mdf_macaddr_zone;            /**< 跳变域为MAC地址时，具体的跳变方式 */
    };
} __ynic_cache_aligned  mdf_zone_var_t;


/** 
  * For a newly allocated mbuf, the area at which the data begins
  * in the message buffer is RTE_PKTMBUF_HEADROOM bytes after the
  * beginning of the buffer, which is cache aligned.
  *
  * #define RTE_PKTMBUF_HEADROOM 128
  */
typedef struct __mbuf_priv {
#if __BYTE_ORDER == __LITTLE_ENDIAN
    uint8_t mbuf_type:2;                /**< NORM_DPDK_MBUF / RAW_SOCK_MBUF */
    uint8_t is_rx_pkt:1;                /**< 是否为从网卡接收的mbuf */
    uint8_t is_valid_mbuf:1;            /**< 检查VLANID，1表示是合法的mbuf，0表示非法的mbuf */
    uint8_t is_soft_l3_cksum:1;         /**< 强制使用软件计算IP层头部的checksum */
    uint8_t is_soft_l4_cksum:1;         /**< 强制使用软件计算UDP/TCP层头部的checksum */
    uint8_t is_arp_nsna_mbuf:1;         /**< 接收的报文是否是ARP/NSNA报文 */
    uint8_t is_rx_ping_mbuf:1;          /**< 接收的报文是否是PING报文 */
#elif __BYTE_ORDER == __BIG_ENDIAN
    uint8_t is_rx_ping_mbuf:1;          /**< 接收的报文是否是PING报文 */
    uint8_t is_arp_nsna_mbuf:1;         /**< 接收的报文是否是ARP/NSNA报文 */
    uint8_t is_soft_l4_cksum:1;         /**< 强制使用软件计算UDP/TCP层头部的checksum */
    uint8_t is_soft_l3_cksum:1;         /**< 强制使用软件计算IP层头部的checksum */
    uint8_t is_valid_mbuf:1;            /**< 检查VLANID，1表示是合法的mbuf，0表示非法的mbuf */
    uint8_t is_rx_pkt:1;                /**< 是否为从网卡接收的mbuf */
    uint8_t mbuf_type:2;                /**< NORM_DPDK_MBUF / RAW_SOCK_MBUF */
#else
#error "Please fix libc <bits/endian.h> or kernel <asm/byteorder.h>"
#endif    
    uint8_t is_retrans_mbuf;            /**< 发送的是重传报文*/
    uint8_t domain;                     /**< 最外层封装的IP地址版本，AF_INET/AF_INET6: IPv4/v6 Internet protocols */
    uint8_t protocol;                   /**< 最外层封装的应用协议类型，IPPROTO_TCP or IPPROTO_UDP */
    uint16_t mbuf_len;                  /**< dpdk_pktmbuf_pkt_len(m)，不包括4字节CRC，所以64字节最小包的mbuf_len为60 */    
    uint16_t ether_type;                /**< 除了QINQ和VLAN头部之外，最外部的以太网类型，主机字节序 */    
    vlan_cfg_t vlan_cfg;                /**< VLAN和QINQ的配置 */
	void *sock;                         /**< mbuf对应的socket指针 */
    void *eth_header;                   /**< 最外层的以太网头部地址 */    
    void *encap_l3_header;              /**< 外层封装的的layer3头部指针，比如VXLAN和GTPU使用UDP封装 */
    void *encap_l4_header;              /**< 外层封装的的layer4头部指针，比如VXLAN和GTPU使用UDP封装 */
    void *encap_gtpu_hdr;               /**< 外层的GTPU的封装头部地址，如果没有GTPU封装为NULL */
    void *encap_vxlan_hdr;              /**< 外层的VXLAN的封装头部地址，如果没有VXLAN封装为NULL */
    void *inner_eth_header;             /**< VXLAN封装的时候，外层包括ETH/IP/UDP/VXLAN，内层也包括ETH/IP/TCP */
    union {
        void *inner_l3_header;          /**< 最内层的socket的layer3的头部指针，比如IPv4或者IPv6头部指针 */
        void *ieee8023_l3_header;       /**< mbuf中IEEE8023中最外层layer3的头部指针，用于S7comm协议 */
    };
    union {
        void *inner_l4_header;          /**< 最内层的socket的layer4的头部指针，比如TCP或者UDP头部指针 */
        void *ieee8023_l4_header;       /**< mbuf中IEEE8023中最外层layer4的头部指针，用于S7comm协议 */
    };
    union {
        void *gtpu_sock;                /**<  mbuf对应的gtpu socket指针*/
        void *vxlan_sock;               /**< mbuf对应的vxlan socket指针 */
    };
    void *mbuf;                         /**< 对应的mbuf指针 */
} __ynic_cache_aligned mbuf_priv_t;

typedef struct __ynic_nic_txd {
    uint16_t hdr_len;           /**< 报文头部长度，比如MAC头+IP头+UDP头长度，不包括载荷长度 */
    uint16_t pkt_len;           /**< 报文长度，从以太网头部开始到CRC之前，不包含帧头帧尾和CRC，也就是pkt_cnt的数组有效数据长度 */
    uint8_t *pkt_cnt;           /**< 报文的模板内容，从以太网头部开始到CRC之前，不包含帧头帧尾和CRC */
    uint32_t *gap_array;         /**< 记录计算出来的GAP的值 */
    int      gap_len;           /**< 记录计算出来的GAP的值长度 */
    void *l2_outer_hdr;         /**< 如果有封装是外部封装二层头部，没有封装是报文二层头部 */
    void *l3_outer_hdr;         /**< 如果有封装是外部封装三层头部，没有封装是报文三层头部 */
    void *l4_outer_hdr;         /**< 如果有封装是外部封装四层头部，没有封装是报文四层头部 */
    void *l2_inner_hdr;         /**< 如果有封装是内部封装二层头部，没有封装为空 */
    void *l3_inner_hdr;         /**< 如果有封装是内部封装三层头部，没有封装为空 */
    void *l4_inner_hdr;         /**< 如果有封装是内部封装四层头部，没有封装为空 */
    void *idts_tag_hdr;         /**< 报文内部的流标记开始地址 */
} __ynic_cache_aligned ynic_nic_txd_t;

typedef struct __ynic_nic_rxd {
    uint16_t hdr_len;           /**< 报文头部长度，比如MAC头+IP头+UDP头长度，不包括载荷长度 */
    uint16_t pkt_len;           /**< 报文长度，从以太网头部开始到CRC之前，不包含帧头帧尾和CRC，也就是pkt_cnt的数组有效数据长度 */
    uint8_t *pkt_cnt;           /**< 报文的模板内容，从以太网头部开始到CRC之前，不包含帧头帧尾和CRC */
    void *l2_outer_hdr;         /**< 如果有封装是外部封装二层头部，没有封装是报文二层头部 */
    void *l3_outer_hdr;         /**< 如果有封装是外部封装三层头部，没有封装是报文三层头部 */
    void *l4_outer_hdr;         /**< 如果有封装是外部封装四层头部，没有封装是报文四层头部 */
    void *l2_inner_hdr;         /**< 如果有封装是内部封装二层头部，没有封装为空 */
    void *l3_inner_hdr;         /**< 如果有封装是内部封装三层头部，没有封装为空 */
    void *l4_inner_hdr;         /**< 如果有封装是内部封装四层头部，没有封装为空 */
    void *idts_tag_hdr;         /**< 报文内部的流标记开始地址 */
    uint64_t rx_pkt_ts;         /**< 接收到报文的时间戳 */
} __ynic_cache_aligned ynic_nic_rxd_t;

typedef struct __pkt_id_tag {
    uint16_t id_pad;            /**< 每发送一个报文，报文ID要加1，使用这个字段把checksum配平 */
    uint32_t tx_pkt_id;         /**< 每个报文的顺序ID，每发一个报文加1，网络字节序，加1之后   按照 0xffff - tx_pkt_id % 0xffff 给配平字段赋值 */
} __ynic_cache_packed pkt_id_tag_t;

typedef struct __pkt_ts_tag {
    uint16_t ts_pad;            /**< 打入硬件时间戳之后，进行UDP的checksum配平，公式 0xffff - tx_pkt_nsec % 0xffff */        
    uint64_t tx_pkt_ns;         /**< 单位纳秒，64位时间戳，由FPGA硬件打入，或者由struct timespec计算而来 */
} __ynic_cache_packed pkt_ts_tag_t;

/** 流标记字段，标记每条流、报文ID、时间戳 */
typedef struct __flow_tag {   
    pkt_id_tag_t id_tag;        /**< 用来进行报文丢包乱序统计的报文ID和checksum配平字段 */
    union {
        uint16_t tx_pcore_id;   /**< 发送报文的核ID，网络字节序, UDP吞吐或者RFC2544时延使用核ID计算乱序 */    
        uint16_t tx_stream_id;  /**< 发送报文的流ID，网络字节序，TCP/UDP会话流控或者FPGA流控使用stream_id */  
    };
    pkt_ts_tag_t ts_tag;        /**< 用来进行报文时延统计的报文时间戳和checksum配平字段 */
} __ynic_cache_packed flow_tag_t;

typedef struct __ynic_encap_tx_stats {
	uint64_t tx_mul_pkts;
    uint64_t tx_mul_bytes;
	uint64_t tx_ucast_pkts;
    uint64_t tx_mcast_pkts;
    uint64_t tx_bcast_pkts;

    uint64_t tx_pkts_speed;
    uint64_t tx_bytes_speed;
} __ynic_cache_packed ynic_encap_tx_stats_t;

typedef struct __ynic_encap_rx_stats {
    uint64_t rx_ucast_pkts;
    uint64_t rx_mcast_pkts;
    uint64_t rx_bcast_pkts;

	uint64_t rx_mul_pkts;
    uint64_t rx_mul_bytes;

	uint64_t rmul_ts_sum_delay;
    uint64_t rmul_ts_max_delay;
    uint64_t rmul_ts_min_delay;
    uint64_t rmul_ts_sum_jitter;
    uint64_t rmul_ts_max_jitter;
    uint64_t rmul_ts_min_jitter;
    uint64_t rx_flt_pkts;
    uint64_t rx_flt_bytes;

    uint64_t rx_drop_rate;
    uint64_t rx_pkts_speed;
    uint64_t rx_bytes_speed;
} __ynic_cache_packed ynic_encap_rx_stats_t;



typedef struct __ynic_txrx_stats {
    uint64_t send_bytes;
    uint64_t recv_bytes;
    uint64_t recv_payload_bytes;
    uint64_t send_packets;
    uint64_t recv_packets;
    uint64_t drop_packets;
    uint64_t tx_ucast_pkts;
    uint64_t rx_ucast_pkts;
    uint64_t tx_mcast_pkts;
    uint64_t rx_mcast_pkts;
    uint64_t tx_bcast_pkts;
    uint64_t rx_bcast_pkts;
    uint64_t rx_crc_errors;
    uint64_t rx_ip_cksum_err;
    uint64_t rx_tcp_cksum_err;
    uint64_t rx_udp_cksum_err;
    uint64_t udp_fpga_rx_pkts;
    uint64_t tx_pkts_speed;
    uint64_t tx_bytes_speed;
    uint64_t rx_pkts_speed;
    uint64_t rx_bytes_speed;
    uint64_t tx_time_start;
    uint64_t tx_time_stop;
    uint64_t tx_status;
    uint64_t rx_ts_sum_delay;
    uint64_t rx_ts_max_delay;
    uint64_t rx_ts_min_delay;
    uint64_t rx_ts_sum_jitter;
    uint64_t rx_ts_max_jitter;
    uint64_t rx_ts_min_jitter;
    uint64_t rx_drop_bytes;
    uint64_t rx_time_start;
    uint64_t rx_time_stop;
    uint64_t rx_mul_pkts;
    uint64_t rx_mul_bytes;
    uint64_t rmul_ts_sum_delay;
    uint64_t rmul_ts_max_delay;
    uint64_t rmul_ts_min_delay;
    uint64_t rmul_ts_sum_jitter;
    uint64_t rmul_ts_max_jitter;
    uint64_t rmul_ts_min_jitter;
    uint64_t tx_mul_pkts;
    uint64_t tx_mul_bytes;
    uint64_t roce_real_delay;
    uint64_t roce_max_delay;
    uint64_t roce_min_delay;
    uint64_t roce_sum_delay;
    uint64_t roce_real_jitter;
    uint64_t roce_max_jitter;
    uint64_t roce_min_jitter;
    uint64_t roce_sum_jitter;
    uint64_t roce_pkts;
    uint32_t rx_pause_start;
    uint32_t rx_pfc_start[8];
    uint32_t rx_pause_stop;
    uint32_t rx_pfc_stop[8];
} __ynic_cache_packed ynic_txrx_stats_t;

typedef struct __ynic_txrx_debug {
    uint32_t fpga_temp;
    uint64_t h2c_tready_sum;
    uint64_t c2h_tready_sum;
    uint32_t h2c_tready_sec;
    uint32_t c2h_tready_sec;
    uint64_t qdma0_tx_cnt;
    uint64_t qdma1_tx_cnt;
    uint64_t qdma2_tx_cnt;
    uint64_t qdma3_tx_cnt;
    uint64_t qdma0_rx_cnt;
    uint64_t qdma1_rx_cnt;
    uint64_t qdma2_rx_cnt;
    uint64_t qdma3_rx_cnt;
    uint64_t mac0_tx_cnt;
    uint64_t mac1_tx_cnt;
    uint64_t mac2_tx_cnt;
    uint64_t mac3_tx_cnt;
    uint64_t mac0_rx_cnt;
    uint64_t mac1_rx_cnt;
    uint64_t mac2_rx_cnt;
    uint64_t mac3_rx_cnt;
    uint64_t adapter0_rx_cnt;
    uint64_t adapter1_rx_cnt;
    uint64_t adapter2_rx_cnt;
    uint64_t adapter3_rx_cnt;
} __ynic_cache_packed ynic_txrx_debug_t;


typedef struct __ynic_tx_speed {
    uint64_t tx_bps;    /**< 限速速率，单位bps */
} __ynic_cache_packed ynic_tx_speed_t;

typedef struct __ynic_stream_txpkt {
    uint16_t stream_id;         /**< 要发送报文的stream id */
    uint32_t nb_tx_pkts;        /**< 此流一次burst要发送报文的数量 */
} __ynic_cache_packed ynic_stream_txpkt_t;

typedef struct __ynic_stream_burst {
    uint16_t nb_stream;                     /**< 一次burst要发送的流数量，为此端口上正在发送的流数量，tx_stream_array的长度 */
    uint32_t tx_gap_byte;                   /**< 每发送一个报文的时间间隔，单位为字节 */
    ynic_stream_txpkt_t *tx_stream_array;    /**< 每次burst要发送的各个流的报文数量，比如流0发1个，流1发10个 */
} __ynic_cache_packed ynic_stream_burst_t;

/*
* Compatibility for systems that have a bpf.h that
* predates the bpf typedefs for 64-bit support.
*/
typedef struct __pcap_fileheader {
    uint32_t magic;
    uint16_t version_major;
    uint16_t version_minor;
    int32_t thiszone;        /* gmt to local correction */
    uint32_t sigfigs;        /* accuracy of timestamps */
    uint32_t snaplen;        /* max length saved portion of each pkt */
    uint32_t linktype;       /* data link type (LINKTYPE_*) */
} __ynic_cache_packed pcap_fileheader_t;

typedef struct __stream_pcappkthdr {               /**< 定义 PCAP 数据包头部结构体*/
    unsigned int ts_sec;
    unsigned int ts_usec;
    unsigned int incl_len;
    unsigned int orig_len;
} __ynic_cache_packed stream_pcappkthdr_t;

#define MAX_CONDITIONS  32
#define MAX_FILTERS     64


typedef struct md_match_condition{
    uint8_t  field_type;
    uint8_t  filed_enable;
    uint8_t  rule;
    char     type[32];
    char     mask[128];
    uint8_t  s_mac[6];
    uint8_t  d_mac[6];
    uint16_t vlan_id;
    uint32_t src_ip4;
    uint32_t dst_ip4;
    uint8_t  src_ip6[16];
    uint8_t  dst_ip6[16];
    uint16_t src_port;
    uint16_t dst_port;
    uint8_t  protocol;
    uint16_t frame_size_min;
    uint16_t frame_size_max;
} __ynic_cache_aligned md_match_condition_t;

typedef struct {
    int                  filter_id;
    char                 filter_name[16];
    uint8_t              relation;
    uint8_t              action;
    uint16_t             framsize;
    int                  condition_count;
    md_match_condition_t conditions[MAX_CONDITIONS];
} md_filter_cfg_t;

typedef struct md_filter_info{
	char port_pciid[40];                /**< 调用ioctl时，用户态给内核传递的pciid */  
    int             filter_count;
    md_filter_cfg_t filters[MAX_FILTERS];
} __ynic_cache_aligned md_filter_info_t;


typedef struct __ynic_stream_cfg {
	char srm_name[128];
	uint8_t is_rebind;								/**< 是否重置限速*/
	uint8_t msg_mode;								/**< 打流信息的传递方式 0 五元组结构 1 MDF跳变结构*/
    uint8_t bwr_en;                                 /**< 带宽占比开关*/
	uint8_t bwratio;                                /**< 带宽占比*/
	uint8_t strm_prio;                              /**< 流优先级*/
	uint8_t nb_mix;                                 /**< 混合帧长数量*/
	uint8_t srm_idx;                                /**< 这条流的下标*/
    uint16_t nb_txd;                                /**< 这个流有多少个报文模板，正常只有一个，在IPv4或者v6分片时有多个 */
    uint16_t nb_mdf_zones;                          /**< 报文中跳变域数量 */
	uint16_t nb_streams;							/**< 流的数量 */
    uint64_t need_send;                             /**< 指定需要发送的报文数量 */
	uint64_t send_time;								/**< 指定需要发送的时间 单位 秒*/
    ynic_tx_speed_t tx_speed;                        /**< 这条流发送的速率，限速使用 */
    ynic_nic_txd_t *txd_array;                       /**< 报文模板数组 */  
    mdf_zone_var_t *nsnic_mdf_zone_array;           /**< 针对报文内容跳变域数组，内存malloc申请 */ 
	simuser_5tuple_t * simuser_5tuple;				/**< 五元组配置信息 */ 
	md_imix_cfg_t *md_imix_cfg;                     /**< 混合帧长配置信息 */
} __ynic_cache_aligned ynic_stream_cfg_t;

typedef struct __ynic_tx_stream {
    uint32_t stream_id;         /**< 流ID，由内核分配 */
    uint16_t fpga_portid;       /**< 由内核分配的端口ID，整个系统分配，从0开始 */ 
    uint8_t stream_type;        /**< FPGA_L23_TX_STREAM/PCIE_L47_TX_STREAM */
    void * stream_cfg;          /**< 指向流配置，发送流载荷和跳变 */
    char stream_name[40];       /**< 流名称字符串 */
    ynic_txrx_stats_t stats;     /**< 流量统计 */
} __ynic_cache_aligned ynic_tx_stream_t;

typedef struct __ynic_rx_stream {
    uint32_t stream_id;         /**< 流ID，由内核分配 */
    uint16_t fpga_portid;       /**< 由内核分配的端口ID，整个系统分配，从0开始 */
    uint8_t stream_type;        /**< FPGA_L23_TX_STREAM/PCIE_L47_TX_STREAM */
    void * stream_cfg;          /**< 指向流配置，接收流filter配置 */
    char stream_name[40];       /**< 流名称字符串 */
    ynic_txrx_stats_t stats;     /**< 流量统计 */
} __ynic_cache_aligned ynic_rx_stream_t;

typedef struct __ynic_nserr {
    int err_code;                   /**< 错误码，YNIC_SUC为成功，YNIC_ERR为失败 */
    char err_mesg[ERR_MSG_LEN];     /**< 错误信息 */
} __ynic_cache_aligned ynic_nserr_t;

typedef struct __ynic_args {
    int ynic_mode;                       /**< -s:SEND_STREAM,-r:RECV_STREAM  */    
    int fpga_port_id;                   /**< 根据port_name，从获取到的dev info中查找对应的fpgaid */
    uint16_t port;                      /**< -p 8080，dst port */
    int duration;                       /**< -d 5，在自定义的秒数内调用monitor函数，统计接收 */
    int promisc;                        /**< -e:开启混杂模式 默认不开启*/     
    char port_name[20];                 /**< -i port1，字符串 */
    char file_name[64];                 /**< -f file name，比如udp.pcap */
    uint64_t stream_speed;              /**< -v 测试gap传输速率，比如2g */
} __ynic_cache_aligned ynic_args_t;
typedef struct __ynic_ukcmd {
    uint32_t cmd;          /**< 用户态和内核态执行的命令，如U2KCMD_GET_DEV_INFO */
    uint32_t u2k_len;      /**< u2k_mem的内存大小，用于用户态向内核态传递数据 */
    uint8_t *u2k_mem;      /**< 用户态空间的内存地址，用户态程序已经申请了内存空间，用于向内核传递数据 */
    uint32_t k2u_len;      /**< k2u_mem的内存大小，用于内核态向用户态传递数据 */ 
    uint8_t *k2u_mem;      /**< 用户态空间的内存地址，用户态程序已经申请了内存空间，用于从内核获取数据 */
    ynic_nserr_t *k2u_err;  /**< 调用ioctl时，内核跟用户态返回的错误信息 */
} ynic_ukcmd_t;

typedef struct __ynic_timestamps_pkt_cfg {
	uint8_t   timestp_en;                   /**< 是否启用时间戳功能 0 禁用              1启用*/   
	uint8_t   opcode_len;                   /**< roce里面需要加时间戳的报文的opcode字段占的字节数*/     
	uint16_t  op_offset;				    /**< roce里报文中opcode字段在报文中的偏移量*/   
	uint16_t  udp_len;			            /**< roce里报文中udp头中length字段占的字节数*/  
	uint16_t  pyl_offset;   				/**< roce里报文中udp头中length字段在报文中的偏移量*/  
	uint16_t  min_payload_len;			        /**< 与roce里报文中udp头中length值比较, 该值至少要大于48才能加时间戳*/
	char      port_pciid[40];               /**< 调用ioctl时，用户态给内核传递的pciid */  
} __ynic_cache_aligned ynic_timestamps_pkt_cfg_t;


typedef struct __ynic_uk_cfg {
	uint8_t system_portid;              /**< 记录鸣嘀卡端口id*/
	uint8_t modle_type;                 /**< 记录端口使用模块类型 高四位 0 1G光模块 1 1G电模块 低四位 0 表示10Mbps 1 100Mbps 2 1000Mbps*/ 
	uint8_t work_mode;					/**< 设置网卡的工作模式，高四位 0表示流模版 1表示rfc2544                     低四位 0表示 默认DPDK模式，1为23层打流模式*/  
    uint8_t promisc;                    /**< 设置网卡开启关闭混杂模式，0表示关闭，1表示开启 */
    uint8_t delay_type;                 /**< 设置网卡时延方式，0表示LIFO，1表示LILO */
    uint8_t direct;                     /**< 设置网卡端口方向，0表示客户端，1表示服务端 */
	uint8_t pfc_enable;                 /**< 设置网卡端口流控使能，0表示关闭，1表示开启 */
    uint16_t pfc_priority;              /**< 设置网卡端口流控优先级，bit0为优先级0,以此类推。0表示关闭，1表示开启 */
    char port_pciid[40];                /**< 调用ioctl时，用户态给内核传递的pciid */  
    uint16_t rxque_id;                  /**< 调用ioctl时，用户态给内核传递的用于接收arp的队列id*/  
    uint32_t ts_base[10];               /**< 设置网卡端口的时延基准值 */
	ynic_timestamps_pkt_cfg_t ynic_timestamps_pkt_cfg;   /**< 调用ioctl时，用户态给内核传递设置时间戳的配置信息*/  
} __ynic_cache_aligned ynic_uk_cfg_t;


typedef struct __ynic_get_fpga_info {
    char port_pciid[16];               /**< 调用ioctl时，用户态给内核传递的pciid */  
    ynic_txrx_debug_t txrx_debug ;
} __ynic_cache_aligned ynic_get_fpga_info_t;

typedef struct __ynic_set_promisc {
    char port_pciid[16];               /**< 调用ioctl时，用户态给内核传递的pciid */  
    int boor ;                         /**< 混杂开启或者关闭 */ 
} __ynic_cache_aligned ynic_set_promisc_t;


typedef struct __md_stream_cfg {
	uint8_t bind_ok;
	uint8_t simtpl_idx;				   /**< 2544用例这个端口上下发的五元组数量 */
	int nb_tx_streams;                     /**< 这个端口共有多少条发送流 */
	int nb_rx_streams;                     /**< 这个端口共有多少条接收流 */
	int nb_filter;                     /**< 这个端口共有多少条流 */
	int stat_idx;                   /**< 记录统计信息下标 */
	int mst_idx;					/**< 记录tx_stream下标 */
	int bind_count;                     /**< FPGA单包攻击记录这个口上已经绑定了几个 */
	uint32_t mdf_idx;                   /**< 记录流模版获取每个核上mbuf指针的下标 */
	uint8_t tx_stream_en;				/**< 鸣嘀卡这个端口上是否open tx_stream */
	uint8_t rx_stream_en;				/**< 鸣嘀卡这个端口上是否open rx_stream */
	uint8_t start_tx_stream;			/**< 鸣嘀卡这个端口上是否已经开始发流 */
	uint8_t start_rx_stream;			/**< 鸣嘀卡这个端口上是否已经开始发流 */
	int mdnet_id;						/**< 鸣嘀卡的端口id，根据portname获取 */
	ynic_stream_cfg_t *tx_stream_config;    /**< 鸣嘀卡给驱动传参的相关配置*/
	ynic_stream_cfg_t *rx_stream_config;    /**< 鸣嘀卡给驱动传参的相关配置*/
	ynic_tx_stream_t **tx_stream;        /**< tx流 */
    ynic_rx_stream_t **rx_stream;        /**< rx流 */
	//encap_change_template_mdf_t **tmp_mdf;        /**< 流模版用例流列表*/
	void **tmp_mdf;                                 /**< 流模版用例流列表*/
	ynic_encap_tx_stats_t *encap_tx_stats;       /**< 流模版用例每条流的发送相关统计*/
	ynic_encap_rx_stats_t *encap_rx_stats;       /**< 流模版用例每条流的接收相关统计*/
} __ynic_cache_aligned md_stream_cfg_t;

enum {
    EQUALS = 0,       // 对应 "=="
    NOT_EQUALS,   // 对应 "!="
    GREATER_THAN, // 对应 ">"
    GREATER_EQUAL,// 对应 ">="
    LESS_THAN,    // 对应 "<"
    LESS_EQUAL    // 对应 "<="
};

enum {
    FILTER_SRC_MAC = 0,    // 对应 "源MAC"
    FILTER_DST_MAC,        // 对应 "目的MAC"
    FILTER_VLAN,           // 对应 "VLAN"
    FILTER_SRC_IPV4,       // 对应 "源IPV4"
    FILTER_DST_IPV4,       // 对应 "目的IPV4"
    FILTER_SRC_IPV6,       // 对应 "源IPV6"
    FILTER_DST_IPV6,       // 对应 "目的IPV6"
    FILTER_PROTOCOL_TYPE,  // 对应 "协议类型"
    FILTER_SRC_PORT,       // 对应 "源端口"
    FILTER_DST_PORT,      // 对应 "目的端口"
    FILTER_FRAM_SIZE        // 对应 "帧长"
};

enum {
    RX_FILTER_DROP  = 0,
    RX_FILTER_QUEUE = 1,
};
enum {
    RX_FILTER_AND = 0,
    RX_FILTER_OR  = 1,
};


/* long option 枚举，避免与短选项冲突 */
enum {
    OPT_FILTER_ID   = 256,
    OPT_FILTER_NAME,
    OPT_FILTER_SIZE,
    OPT_ACTION,
    OPT_RELATION,
    OPT_NEXT_FILTER,
    OPT_FIELD,
    OPT_RULE,
    OPT_VALUE,
    OPT_MASK,
    OPT_ENABLE,
    OPT_NEXT_COND,
};





/*****nictrl use*******/
#define NF_SERNUM_LEN       15
#define NF_SERNUM_LEN_RU    (NF_SERNUM_LEN+1)
#define NF_FIRMWARE_LEN     64
/*网卡的每个port信息*/
typedef struct {
    uint8_t if_id;                      /*网卡的port号*/
    char slot[16];
    char id[8];
    char lane[8];
    char adapter_type[256];
    char mac[20];
    uint8_t status;
    uint8_t mulport;

} nf_sys_info;

/*网卡的信息*/
typedef struct {
    int num;                                /*网卡数量*/
    int pnum[MAX_PORT_PER_ADP];             /*每个网卡网口的数量*/
    uint32_t adp_id[MAX_PORT_PER_ADP];      /*每个网卡的编号*/
    uint32_t model[MAX_PORT_PER_ADP];
    uint32_t version[MAX_PORT_PER_ADP];
    uint32_t speed[MAX_PORT_PER_ADP];
    uint32_t totalport[MAX_PORT_PER_ADP];
    uint8_t sernum[MAX_PORT_PER_ADP][NF_SERNUM_LEN_RU];
    uint8_t firmware[MAX_PORT_PER_ADP][NF_FIRMWARE_LEN];
    nf_sys_info *info[MAX_PORT_PER_ADP];    /*每个网卡网口的信息*/
} nf_adapters;

#define IOCTL_SET_NET_ID   _IOW('P', 1, uint32_t)
#define IOCTL_SET_NET_INFO _IOWR('P', 2, nf_adapters)
#define IOCTL_SET_CLOCK    _IO('P', 3)
#define IOCTL_SET_FEC      _IOW('P', 4, uint32_t)
#define IOCTL_SET_UP       _IOW('P', 5, uint32_t)

/*****nictrl use*******/

#endif
