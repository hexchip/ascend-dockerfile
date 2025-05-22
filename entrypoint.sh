#!/bin/bash

if [[ ${HEXCHIP_ASCEND_DEVICE_WHERE} == "local" ]]; then
    source ${HEXCHIP_ASCEND_HOME}/ascend-toolkit/set_env.sh

    mkdir /dev/shm/dmp
    mkdir /home/HwHiAiUser/hdc_ppc
    nohup /var/dmp_daemon -I -M -U 8087 >&/dev/null &
    /var/slogd -d
fi

exec $@