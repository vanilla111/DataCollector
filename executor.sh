#!/bin/bash

# 设置内存使用规则
# vm.swappiness 当剩余物理内存低于该值时，开始使用交换区，默认60
echo 10 > /proc/sys/vm/swappiness

# vm.overcommit_ratio 单个进程允许分配的虚拟空间大小(phy * ratio + swap)，默认ratio=50
# echo 90 > /proc/sys/vm/overcommit_ratio

export server_ip="192.168.1.104"

# 网络接口状况
# 获取可用的网络接口设备 如 eth0
export nic=$(ip route get ${server_ip} | grep dev | awk -F'dev' '{ print $2 }' | awk '{ print $1 }')

# IP地址和网络使用情况
export ipv4=$(ip addr show $nic | grep 'inet ' | awk '{ print $2 }' | awk -F\/ '{ print $1 }' | grep -v '^127' | awk '{ print $0 } END { if (NR == 0) print "N/A" }')

# 环境设置
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

# 版本号
export version="1"

# 配置验证密钥，只有密钥通过接口验证才能提交数据，暂时不开启
export auth="bfiuob892gbvia0"

# 收集数据服务地址
export server="${server_ip}:8081/indicators/"

# 预处理输出，去掉开头和结尾的空格
function prep ()
{
	echo "$1" | sed -e 's/^ *//g' -e 's/ *$//g' | sed -n '1 p'
}

# base64加密 / => %2F, + => %2B
function base ()
{
	echo "$1" | tr -d '\n' | base64 | tr -d '\n'
}

# 变整型
function int ()
{
	echo ${1/\.*}
}

# 纯(正)数字直接返回，否则返回0
function num ()
{
	case $1 in
	    ''|*[!0-9\.]*) echo 0 ;;
	    *) echo $1 ;;
	esac
}

export -f prep
export -f base
export -f int
export -f num

while true; do
	./collector.sh
	sleep 1
done