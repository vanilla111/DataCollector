#!/bin/bash

# 设置内存使用规则
# vm.swappiness 当剩余物理内存低于该值时，开始使用交换区，默认60
# echo 20 > /proc/sys/vm/swappiness

# vm.overcommit_ratio 单个进程允许分配的虚拟空间大小(phy * ratio + swap)，默认ratio=50
# echo 90 > /proc/sys/vm/overcommit_ratio

while true; do
	generator="$(ps axc --noheaders | grep ErrorGenerator)"

	if [ -n "${generator}" ] 
	then
		# 后期把生成命令加入到系统路径
		/root/ErrorGenerator/ErrorGenerator >> /etc/collector/error_generator.log 2>&1 &
	fi
	sleep 60
done