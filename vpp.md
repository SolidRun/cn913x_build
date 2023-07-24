# VPP on CN9130 Clearfog Base

## Compile VPP

VPP release 21.01 requires a small number of patches to both otself, and the dpdk plugin.
Additionally while compiling VPP access to the Marvell `musdk` library and headers is required.

Therefore VPP should be compiled from source - either natively on the CN913x unit, or using an adequate aarch64 (virtual) machine:

### 1. (re-)build libmusdk to install development files

```
apt-get update
apt-get install build-essential

wget https://solidrun-common.sos-de-fra-1.exo.io/cn913x/marvell/SDK11.22.07/sources-musdk-marvell-SDK11.22.07.tar.bz2
tar -vxf sources-musdk-marvell-SDK11.22.07.tar.bz2
rm -f sources-musdk-marvell-SDK11.22.07.tar.bz2
cd musdk-marvell-SDK11.22.07
patch -p1 < ../0001-fix-headers-for-cma-module.patch
patch -p1 < ../0002-remove-harmless-warnings.patch
./bootstrap
./configure --prefix=/usr CFLAGS="-fPIC -O2"
make
make install
```

### 2. build vpp

- Install basic dependencies:

  ```
  apt-get update
  apt-get install build-essential ca-certificates git
  ```

- Download sources:

  ```
  git clone https://gerrit.fd.io/r/vpp
  cd vpp
  git reset --hard v21.01
  ```

- Apply VPP Patches (from `patches/vpp-v21.01/`):

  ```
  git am ../0001-DPDK-plugin-new-cli-command-to-close-a-dpdk-virtual-.patch
  git am ../0002-shlibs-ignore-missing-version-information.patch
  git am ../0003-marvell-fix-warn_unused_result-when-calling-vlib_tra.patch
  ```

- Apply DPDK Patches (from `patches/dpdk-v20.11/`):

  ```
  mkdir -p build/external/patches/dpdk_20.11
  cp -v ../0001-Modify-MUSDK-structs-to-match-SDK11.22.07-MUSDK.patch build/external/patches/dpdk_20.11/
  cp -v ../0002-Use-pkg-config-to-find-libmusdk.patch build/external/patches/dpdk_20.11/
  ```

- Install VPP build dependencies

  ```
  make install-dep
  make install-ext-deps
  ```

  This will generate `build/external/packages/vpp-ext-deps_21.01-16_arm64.deb` that can be reused in future builds to skip `make install-ext-deps` step.

- Build VPP
  ```
  make build-release
  make pkg-deb
  ```

- Find the generated packages in `build-root/`:

  ```
  # ls -lh build-root/*.deb
  -rw-r--r-- 1 root root 132K Jul 20 12:08 build-root/libvppinfra-dev_21.01.0-3~g99b36ebcb_arm64.deb
  -rw-r--r-- 1 root root 116K Jul 20 12:08 build-root/libvppinfra_21.01.0-3~g99b36ebcb_arm64.deb
  -rw-r--r-- 1 root root  25K Jul 20 12:09 build-root/python3-vpp-api_21.01.0-3~g99b36ebcb_arm64.deb
  -rw-r--r-- 1 root root 1.4K Jul 20 12:09 build-root/vpp-api-python_21.01.0-3~g99b36ebcb_arm64.deb
  -rw-r--r-- 1 root root  56M Jul 20 12:09 build-root/vpp-dbg_21.01.0-3~g99b36ebcb_arm64.deb
  -rw-r--r-- 1 root root 1.1M Jul 20 12:09 build-root/vpp-dev_21.01.0-3~g99b36ebcb_arm64.deb
  -rw-r--r-- 1 root root 2.1M Jul 20 12:09 build-root/vpp-plugin-core_21.01.0-3~g99b36ebcb_arm64.deb
  -rw-r--r-- 1 root root 2.8M Jul 20 12:09 build-root/vpp-plugin-dpdk_21.01.0-3~g99b36ebcb_arm64.deb
  -rw-r--r-- 1 root root 2.1M Jul 20 12:09 build-root/vpp_21.01.0-3~g99b36ebcb_arm64.deb
  ```

## Install VPP

Progress update:
I was able to ping with vpp, without marvell's plugin
Here are the steps I followed:

1. Compile a fresh image (https://github.com/SolidRun/cn913x_build) and flash it to a uSD card

       docker run --rm -i -t -v "$PWD":/cn913x_build_dir -v /etc/gitconfig:/etc/gitconfig cn913x_build bash -c "BOARD_CONFIG=1 UBUNTU_VERSION=focal ./runme.sh"

2. Boot the new image, update system and resize partition

   ```
   apt update && apt upgrade -y

   fdisk /dev/mmcblk1
   # Command (m for help): d
   # Command (m for help): n
   # Select (default p): p
   # Partition number (1-4, default 1): 1
   # First sector (2048-31116287, default 2048): 131072
   # Last sector, +sectors or +size{K,M,G,T,P} (131072-31116287, default 31116287): 31116287
   # Do you want to remove the signature? [Y]es/[N]o: N
   # Command (m for help): w

   resize2fs /dev/mmcblk1p1
   ```

3. Copy deb packages to C913x box

   ```
   mkdir /tmp/plugins
   dhclient
   scp user@ip_addr:/location/in/server/with/deb/packages/* /tmp/plugins/
   ```

4. Install the following deb packages and reboot

   ```
   cd /tmp/plugins
   apt install ./libvppinfra_21.01-release_arm64.deb ./vpp_21.01-release_arm64.deb
   apt install ./vpp-plugin-core_21.01-release_arm64.deb
   apt install ./vpp-plugin-dpdk_21.01-release_arm64.deb

   systemctl disable vpp

   reboot
   ```

5. Verify that all plugins are installed

   ```
   vppctl show plugins
    Plugin path is: /usr/lib/aarch64-linux-gnu/vpp_plugins:/usr/lib/vpp_plugins

        Plugin                                   Version                          Description
     1. ioam_plugin.so                           21.01.0-2~gbeab0b08f-dirty       Inbound Operations, Administration, and Maintenance (OAM)
     2. lldp_plugin.so                           21.01.0-2~gbeab0b08f-dirty       Link Layer Discovery Protocol (LLDP)
     3. tracedump_plugin.so                      21.01.0-2~gbeab0b08f-dirty       Streaming packet trace dump plugin
     4. urpf_plugin.so                           21.01.0-2~gbeab0b08f-dirty       Unicast Reverse Path Forwarding (uRPF)
     5. tlspicotls_plugin.so                     21.01.0-2~gbeab0b08f-dirty       Transport Layer Security (TLS) Engine, Picotls Based
     6. l3xc_plugin.so                           21.01.0-2~gbeab0b08f-dirty       L3 Cross-Connect (L3XC)
     7. mdata_plugin.so                          21.01.0-2~gbeab0b08f-dirty       Buffer metadata change tracker.
     8. ping_plugin.so                           21.01.0-2~gbeab0b08f-dirty       Ping (ping)
     9. avf_plugin.so                            21.01.0-2~gbeab0b08f-dirty       Intel Adaptive Virtual Function (AVF) Device Driver
    10. l2tp_plugin.so                           21.01.0-2~gbeab0b08f-dirty       Layer 2 Tunneling Protocol v3 (L2TP)
    11. pppoe_plugin.so                          21.01.0-2~gbeab0b08f-dirty       PPP over Ethernet (PPPoE)
    12. crypto_native_plugin.so                  21.01.0-2~gbeab0b08f-dirty       Intel IA32 Software Crypto Engine
    13. srv6am_plugin.so                         21.01.0-2~gbeab0b08f-dirty       Masquerading Segment Routing for IPv6 (SRv6) Proxy
    14. l2e_plugin.so                            21.01.0-2~gbeab0b08f-dirty       Layer 2 (L2) Emulation
    15. dpdk_plugin.so                           21.01.0-2~gbeab0b08f-dirty       Data Plane Development Kit (DPDK)
    16. det44_plugin.so                          21.01.0-2~gbeab0b08f-dirty       Deterministic NAT (CGN)
    17. adl_plugin.so                            21.01.0-2~gbeab0b08f-dirty       Allow/deny list plugin
    18. acl_plugin.so                            21.01.0-2~gbeab0b08f-dirty       Access Control Lists (ACL)
    19. crypto_openssl_plugin.so                 21.01.0-2~gbeab0b08f-dirty       OpenSSL Crypto Engine
    20. dslite_plugin.so                         21.01.0-2~gbeab0b08f-dirty       Dual-Stack Lite
    21. tlsmbedtls_plugin.so                     21.01.0-2~gbeab0b08f-dirty       Transport Layer Security (TLS) Engine, Mbedtls Based
    22. ikev2_plugin.so                          21.01.0-2~gbeab0b08f-dirty       Internet Key Exchange (IKEv2) Protocol
    23. svs_plugin.so                            21.01.0-2~gbeab0b08f-dirty       Source Virtual Routing and Fowarding (VRF) Select
    24. vrrp_plugin.so                           21.01.0-2~gbeab0b08f-dirty       VRRP v3 (RFC 5798)
    25. hs_apps_plugin.so                        21.01.0-2~gbeab0b08f-dirty       Host Stack Applications
    26. nsim_plugin.so                           21.01.0-2~gbeab0b08f-dirty       Network Delay Simulator
    27. dns_plugin.so                            21.01.0-2~gbeab0b08f-dirty       Simple DNS name resolver
    28. cnat_plugin.so                           21.01.0-2~gbeab0b08f-dirty       CNat Translate
    29. dhcp_plugin.so                           21.01.0-2~gbeab0b08f-dirty       Dynamic Host Configuration Protocol (DHCP)
    30. marvell_plugin.so                        21.01.0-2~gbeab0b08f-dirty       Marvell PP2 Device Driver
    31. rdma_plugin.so                           21.01.0-2~gbeab0b08f-dirty       RDMA IBverbs Device Driver
    32. gbp_plugin.so                            21.01.0-2~gbeab0b08f-dirty       Group Based Policy (GBP)
    33. igmp_plugin.so                           21.01.0-2~gbeab0b08f-dirty       Internet Group Management Protocol (IGMP)
    34. nat_plugin.so                            21.01.0-2~gbeab0b08f-dirty       Network Address Translation (NAT)
    35. memif_plugin.so                          21.01.0-2~gbeab0b08f-dirty       Packet Memory Interface (memif) -- Experimental
    36. nsh_plugin.so                            21.01.0-2~gbeab0b08f-dirty       Network Service Header (NSH)
    37. nat64_plugin.so                          21.01.0-2~gbeab0b08f-dirty       NAT64
    38. lisp_plugin.so                           21.01.0-2~gbeab0b08f-dirty       Locator ID Separation Protocol (LISP)
    39. abf_plugin.so                            21.01.0-2~gbeab0b08f-dirty       Access Control List (ACL) Based Forwarding
    40. ila_plugin.so                            21.01.0-2~gbeab0b08f-dirty       Identifier Locator Addressing (ILA) for IPv6
    41. srv6mobile_plugin.so                     21.01.0-2~gbeab0b08f-dirty       SRv6 GTP Endpoint Functions
    42. tlsopenssl_plugin.so                     21.01.0-2~gbeab0b08f-dirty       Transport Layer Security (TLS) Engine, OpenSSL Based
    43. gtpu_plugin.so                           21.01.0-2~gbeab0b08f-dirty       GPRS Tunnelling Protocol, User Data (GTPv1-U)
    44. map_plugin.so                            21.01.0-2~gbeab0b08f-dirty       Mapping of Address and Port (MAP)
    45. wireguard_plugin.so                      21.01.0-2~gbeab0b08f-dirty       Wireguard Protocol
    46. geneve_plugin.so                         21.01.0-2~gbeab0b08f-dirty       GENEVE Tunnels
    47. stn_plugin.so                            21.01.0-2~gbeab0b08f-dirty       VPP Steals the NIC (STN) for Container Integration
    48. builtinurl_plugin.so                     21.01.0-2~gbeab0b08f-dirty       vpp built-in URL support
    49. af_xdp_plugin.so                         21.01.0-2~gbeab0b08f-dirty       AF_XDP Device Plugin
    50. http_static_plugin.so                    21.01.0-2~gbeab0b08f-dirty       HTTP Static Server
    51. ct6_plugin.so                            21.01.0-2~gbeab0b08f-dirty       IPv6 Connection Tracker
    52. cdp_plugin.so                            21.01.0-2~gbeab0b08f-dirty       Cisco Discovery Protocol (CDP)
    53. lacp_plugin.so                           21.01.0-2~gbeab0b08f-dirty       Link Aggregation Control Protocol (LACP)
    54. flowprobe_plugin.so                      21.01.0-2~gbeab0b08f-dirty       Flow per Packet
    55. crypto_sw_scheduler_plugin.so            21.01.0-2~gbeab0b08f-dirty       SW Scheduler Crypto Async Engine plugin
    56. mactime_plugin.so                        21.01.0-2~gbeab0b08f-dirty       Time-based MAC Source Address Filter
    57. lb_plugin.so                             21.01.0-2~gbeab0b08f-dirty       Load Balancer (LB)
    58. srv6as_plugin.so                         21.01.0-2~gbeab0b08f-dirty       Static Segment Routing for IPv6 (SRv6) Proxy
    59. nat66_plugin.so                          21.01.0-2~gbeab0b08f-dirty       NAT66
    60. srv6ad_plugin.so                         21.01.0-2~gbeab0b08f-dirty       Dynamic Segment Routing for IPv6 (SRv6) Proxy
    61. vmxnet3_plugin.so                        21.01.0-2~gbeab0b08f-dirty       VMWare Vmxnet3 Device Driver
   ```

### Run VPP

6. Create startup.conf

   ```
   cat > /etc/vpp/startup.conf << EOF
   unix {
     interactive
     log /var/log/vpp/vpp.log
     full-coredump
     cli-listen /run/vpp/cli.sock
     gid vpp
     coredump-size unlimited
   }

   api-trace {
     on
   }

   api-segment {
     gid vpp
   }

   socksvr {
     default
   }

   cpu {
   }

   dpdk {
     vdev eth_mvpp2,iface=eth1
   }
   EOF
   ```

(Please note that unix is not running in nodaemon mode but in interactive mode)

7. Insmod kernel modules

   ```
   insmod /root/musdk_modules/mv_pp_uio.ko
   insmod /root/musdk_modules/musdk_cma.ko
   ```

8. Preload the MUSDK shared library

   Running vpp will lead to a loader error: "undefined symbol: mv_sys_dma_mem_init"
   mv_sys_dma_mem_init symbol is defined in the musdk shared library, so, preload the library with the following command:

       export LD_PRELOAD=/usr/lib/libmusdk.so

9. Start VPP

   ```
   mkdir -p /var/log/vpp
   vpp -c /etc/vpp/startup.conf
   ```

   ```
   clib_elf_parse_file: open `/usr/bin/vpp�': No such file or directorydpdk             [warn  ]: not enough DPDK crypto resources
   dpdk             [warn  ]: unsupported rx offloads requested on port 0: scatter
   dpdk/cryptodev   [warn  ]: dpdk_cryptodev_init: Not enough cryptodevs
   vat-plug/load    [error ]: vat_plugin_register: oddbuf plugin not loaded...
       _______    _        _   _____  ___
    __/ __/ _ \  (_)__    | | / / _ \/ _ \
    _/ _// // / / / _ \   | |/ / ___/ ___/
    /_/ /____(_)_/\___/   |___/_/  /_/

   vpp#
   ```

10. Configure eth1 interface

   List interfaces, you should see eth1 now

   ```
   vpp# show int
                 Name               Idx    State  MTU (L3/IP4/IP6/MPLS)     Counter          Count
   UnknownEthernet0                  1     down         9000/0/0/0
   local0                            0     down          0/0/0/0
   ```

   Bring up eth1 and ask for a IP address:

   ```
   vpp# set interface state UnknownEthernet0 up
   [  454.452597] [ERROR] failed to disable vlan filtering
   vpp# set dhcp client intfc UnknownEthernet0
   ```

   (After a few seconds)

   ```
   vpp# show int addr
   UnknownEthernet0 (up):
     L3 192.168.15.198/24
   local0 (dn):
   ```

That's it, VPP is working :)

#### Ping

```
vpp# ping 192.168.15.1
116 bytes from 192.168.15.1: icmp_seq=1 ttl=64 time=.3515 ms
116 bytes from 192.168.15.1: icmp_seq=2 ttl=64 time=.2670 ms
116 bytes from 192.168.15.1: icmp_seq=3 ttl=64 time=.2668 ms
116 bytes from 192.168.15.1: icmp_seq=4 ttl=64 time=.2639 ms
116 bytes from 192.168.15.1: icmp_seq=5 ttl=64 time=.5407 ms

Statistics: 5 sent, 5 received, 0% packet loss
```

#### Enable Additional Interfaces

Please note that the same can be done with more eth interfaces, for example, we can tweak the dpdk entry in startup.conf to:

```
dpdk {
  vdev eth_mvpp2,iface=eth0,iface=eth1,iface=eth2,iface=eth3,iface=eth4,iface=eth5
}
```

Then, we'll see 6 interfaces:

```
vpp# show int
              Name               Idx    State  MTU (L3/IP4/IP6/MPLS)     Counter          Count
UnknownEthernet0                  1     down         9000/0/0/0
UnknownEthernet1                  2     down         9000/0/0/0
UnknownEthernet2                  3     down         9000/0/0/0
UnknownEthernet3                  4     down         9000/0/0/0
UnknownEthernet4                  5     down         9000/0/0/0
UnknownEthernet5                  6     down         9000/0/0/0
local0                            0     down          0/0/0/0                     0     down          0/0/0/0
```

#### L2 Switch

VPP can be do Layer-2 Switching:

1. Create L2 Bridge

   ```
   create bridge-domain 1 arp-term 1 mac-age 60 learn 1 forward 1
   ```

2. Add Interfaces to Bridge:

   ```
   vpp# set interface l2 bridge UnknownEthernet0 1
   vpp# set interface l2 bridge UnknownEthernet1 1
   vpp# set interface l2 bridge UnknownEthernet2 1
   vpp# set interface l2 bridge UnknownEthernet3 1
   vpp# set interface l2 bridge UnknownEthernet4 1
   vpp# set interface l2 bridge UnknownEthernet5 1
   ```

3. Enable all Interfaces:

   ```
   vpp# set interface state UnknownEthernet0 up
   vpp# set interface state UnknownEthernet1 up
   vpp# set interface state UnknownEthernet2 up
   vpp# set interface state UnknownEthernet3 up
   vpp# set interface state UnknownEthernet4 up
   vpp# set interface state UnknownEthernet5 up
   ```

L2 Switch is now operating:

```
vpp# show bridge-domain 1 detail
  BD-ID   Index   BSN  Age(min)  Learning  U-Forwrd   UU-Flood   Flooding  ARP-Term  arp-ufwd   BVI-Intf
    1       1        60        on        on       flood        on        on       off        N/A
             SPAN (span-l2-input)
   INPUT_CLASSIFY (l2-input-classify)
   INPUT_FEAT_ARC (l2-input-feat-arc)
     POLICER_CLAS (l2-policer-classify)
              ACL (l2-input-acl)
            VPATH (vpath-input-l2)
 L2_IP_QOS_RECORD (l2-ip-qos-record)
              VTR (l2-input-vtr)
 GBP_LPM_CLASSIFY (l2-gbp-lpm-classify)
 GBP_SRC_CLASSIFY (gbp-src-classify)
GBP_NULL_CLASSIFY (gbp-null-classify)
GBP_LPM_ANON_CLAS (l2-gbp-lpm-anon-classify)
        GBP_LEARN (gbp-learn-l2)
     L2_EMULATION (l2-emulation)
            LEARN (l2-learn)
               RW (l2-rw)
              FWD (l2-fwd)
          GBP_FWD (gbp-fwd)
         UU_FLOOD (l2-flood)
         ARP_TERM (arp-term-l2bd)
            FLOOD (l2-flood)
         XCONNECT (l2-output)

           Interface           If-idx ISN  SHG  BVI  TxFlood        VLAN-Tag-Rewrite
       UnknownEthernet0          1     1    0    -      *                 none
       UnknownEthernet1          2     1    0    -      *                 none
       UnknownEthernet2          3     1    0    -      *                 none
       UnknownEthernet4          5     1    0    -      *                 none
       UnknownEthernet5          6     1    0    -      *                 none
       UnknownEthernet3          4     1    0    -      *                 none

  IP4/IP6 to MAC table for ARP Termination
```
