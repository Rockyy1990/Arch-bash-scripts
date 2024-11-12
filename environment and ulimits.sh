#!/bin/bash
echo ""
echo "Read this script before execute!!"
read -p "Set environment variables and set ulimits to unlimit. Press any key to continue.."
echo ""

echo -e "Set environment variables"
echo -e "
CPU_LIMIT=0
GPU_USE_SYNC_OBJECTS=1
SHARED_MEMORY=1
MALLOC_CONF=background_thread:true
MALLOC_CHECK=0
MALLOC_TRACE=0
LD_DEBUG_OUTPUT=0
MESA_DEBUG=0
LIBGL_DEBUG=0
LIBGL_NO_DRAWARRAYS=1
LIBGL_THROTTLE_REFRESH=1
LIBC_FORCE_NOCHECK=1
HISTCONTROL=ignoreboth:eraseboth
HISTSIZE=5
LESSHISTFILE=-
LESSHISTSIZE=0
LESSSECURE=1
PAGER=less" | sudo tee -a /etc/environment
echo ""

echo -e "Set some ulimits to unlimited"
echo -e "
* soft nofile 524288
* hard nofile 524288
root soft nofile 524288
root hard nofile 524288
* soft as unlimited
* hard as unlimited
root soft as unlimited
root hard as unlimited
* soft memlock unlimited
* hard memlock unlimited
root soft memlock unlimited
root hard memlock unlimited
* soft core unlimited
* hard core unlimited
root soft core unlimited
root hard core unlimited
* soft nproc unlimited
* hard nproc unlimited
root soft nproc unlimited
root hard nproc unlimited
* soft sigpending unlimited
* hard sigpending unlimited
root soft sigpending unlimited
root hard sigpending unlimited
* soft stack unlimited
* hard stack unlimited
root soft stack unlimited
root hard stack unlimited
* soft data unlimited
* hard data unlimited
root soft data unlimited
root hard data unlimited" | sudo tee /etc/security/limits.conf
echo ""
echo -e "Set realtime to unlimited"
echo -e "@realtime - rtprio 99
@realtime - memlock unlimited" | sudo tee -a /etc/security/limits.conf