#!/bin/bash

# 需要配合executor.sh一起运行

# 系统已运行时长 单位：秒
uptime=$(prep $(int "$(cat /proc/uptime | awk '{ print $1 }')"))

# 已登陆的会话数量
sessions=$(prep "$(who | wc -l)")

# 进程数量 
processes=$(prep "$(ps axc | wc -l)")

# 文件描述符
# 文件的状态指示file-nr，一共三个值
# 第一个代表全局已经分配的文件描述符数量，第二个代表自由的文件描述符（待重新分配的），第三个代表总的文件描述符的数量。
file_nr=$(cat /proc/sys/fs/file-nr)
file_handles=$(prep $(num "$(echo $file_nr | awk '{ print $1 }')"))
file_handles_limit=$(prep $(num "$(echo $file_nr | awk '{ print $3 }')"))

# 内存使用情况
mem_info=$(cat /proc/meminfo)
ram_total=$(prep $(num "$(echo "$mem_info" | grep ^MemTotal: | awk '{ print $2 }')"))
ram_free=$(prep $(num "$(echo "$mem_info" | grep ^MemFree: | awk '{ print $2 }')"))
ram_cached=$(prep $(num "$(echo "$mem_info" | grep ^Cached: | awk '{ print $2 }')"))
ram_buffers=$(prep $(num "$(echo "$mem_info" | grep ^Buffers: | awk '{ print $2 }')"))
# 单位变为 字节
ram_usage=$((($ram_total-($ram_free+$ram_cached+$ram_buffers))*1024))
ram_total=$(($ram_total*1024))

# 交换区使用情况
swap_total=$(prep $(num "$(echo "$mem_info" | grep ^SwapTotal: | awk '{ print $2 }')"))
swap_free=$(prep $(num "$(echo "$mem_info" | grep ^SwapFree: | awk '{ print $2 }')"))
# 单位变为 字节
swap_usage=$((($swap_total-$swap_free)*1024))
swap_total=$(($swap_total*1024))

# 磁盘使用情况
# df -P, --portability 使用 POSIX 输出格式 -B, --block-size=SIZE 按照SIZE字节划分可以划分多少块
# sed :a 循环起始 ta标志前如果成功跳到:a(t test) N将下一行合并到当前 $!最后一行不跳转到标记a，即退出循环 将换行符替换为+号
disk_info=$(df -P -B 1)
disk_total=$(prep $(num "$(($(echo "$disk_info" | grep '^/' | awk '{ print $2 }' | sed -e :a -e '$!N;s/\n/+/;ta')))"))
disk_usage=$(prep $(num "$(($(echo "$disk_info" | grep '^/' | awk '{ print $3 }' | sed -e :a -e '$!N;s/\n/+/;ta')))"))

# 磁盘 总的使用情况sda
# disk_array=$(prep "$(df -P -B 1 | grep '^/' | awk '{ print $1" "$2" "$3";" }' | sed -e :a -e '$!N;s/\n/ /;ta' | awk '{ print $0 } END { if (NR == 0) print "N/A" }')")
# 磁盘总读写时间 读时间+写时间 单位 ms
disk_rw_time=$(prep "$(num "$(cat /proc/diskstats | grep 'sda' | head -n1 | awk '{print $13}  END { if (NR == 0) print "-1" }')")")

# 活跃的连接数 -n not zero
# ss sockets 检查工具 -n 禁止解析服务名; -t 显示 tcp socket; -u 显示 udp socket
if [ -n "$(command -v ss)" ]
then
	connections=$(prep $(num "$(ss -tun | tail -n +2 | wc -l)"))
else
	connections=$(prep $(num "$(netstat -tun | tail -n +3 | wc -l)"))
fi

# rx/tx_bytes 网口接收/发送字节数
if [ -d /sys/class/net/$nic/statistics ]
then
	rx=$(prep $(num "$(cat /sys/class/net/$nic/statistics/rx_bytes)"))
	tx=$(prep $(num "$(cat /sys/class/net/$nic/statistics/tx_bytes)"))
else
	rx=$(prep $(num "$(ip -s link show $nic | grep '[0-9]*' | grep -v '[A-Za-z]' | awk '{ print $1 }' | sed -n '1 p')"))
	tx=$(prep $(num "$(ip -s link show $nic | grep '[0-9]*' | grep -v '[A-Za-z]' | awk '{ print $1 }' | sed -n '2 p')"))
fi

# 系统负载
# 系统平均负载被定义为在特定时间间隔内运行队列中的平均进程树
# 命令输出的最后内容表示在过去的1、5、15分钟内运行队列中的平均进程数量
# 除以CPU核数如果大于5，则认为系统负载较高
load=$(prep "$(cat /proc/loadavg | awk '{ print $1" "$2" "$3 }')")

# 详细系统负载计算
# /proc/stat 第一行 CPU指标：user，nice, system, idle, iowait, irq, softirq
# 指的是CPU处于用户态、nice用户态、内核态、空闲时间... 单位 0.01s
# iowait时间是不可靠值，具体原因如下：
# 1）CPU不会等待I/O执行完成，而Iowait是等待I/O完成的时间。当CPU进入空闲状态时，很可能会调度另一个任务执行，所以iowait计算时间偏小;
# 2）多核CPU中，iowait的计算并非某个核，因此计算每一个cpu的iowait非常困难
# 3）这个值在某些情况下会减少
time=$(date +%s)
stat=($(cat /proc/stat | head -n1 | sed 's/[^0-9 ]*//g' | sed 's/^ *//'))
cpu=$((${stat[0]}+${stat[1]}+${stat[2]}+${stat[3]}))
io=$((${stat[3]}+${stat[4]}))
idle=${stat[3]}

# 计算这一段时间的CPU、IO效率（百分之多少 * 100）
if [ -e /etc/collector/data.log ]
then
	data=($(cat /etc/collector/data.log))
	interval=$(($time-${data[0]}))
	cpu_gap=$(($cpu-${data[1]}))
	io_gap=$(($io-${data[2]}))
	idle_gap=$(($idle-${data[3]}))
	
	if [[ $cpu_gap > "0" ]]
	then
		load_cpu=$((10000*($cpu_gap-$idle_gap)/$cpu_gap))
	fi
	
	if [[ $io_gap > "0" ]]
	then
		load_io=$((10000*($io_gap-$idle_gap)/$io_gap))
	fi
fi

label=0
generator="$(ps axc --noheaders | grep ErrorGenerator)"
if [ -n "${generator}" ] 
then
	label=($(cat /tmp/label.txt))
fi

# 记录数据(覆盖)
# 时间戳、CPU时间、IO时间、空闲时间、网口收发字节数
echo "$time $cpu $io $idle" > /etc/collector/data.log

# 负载
load_cpu=$(prep $(num "$load_cpu"))
# iostat -x -t 2
load_io=$(prep $(num "$load_io"))

# 构造提交的数据
# data_post="token=${auth[0]}&data=$(base "$version") $(base "$uptime") $(base "$sessions") $(base "$processes") $(base "$file_handles") $(base "$file_handles_limit") $(base "$ram_total") $(base "$ram_usage") $(base "$swap_total") $(base "$swap_usage") $(base "$disk_total") $(base "$disk_usage") $(base "$disk_rw_time") $(base "$connections") $(base "$ipv4") $(base "$rx") $(base "$tx") $(base "$load") $(base "$load_cpu") $(base "$load_io") $(base "$label")"

data_post="token=${auth[0]}\
&version=${version}\
&uptime=${uptime}\
&sessions=${sessions}\
&processes=${processes}\
&fileHandles=${file_handles}\
&fileHandlesLimit=${file_handles_limit}\
&ramTotal=${ram_total}\
&ramUsage=${ram_usage}\
&swapTotal=${swap_total}\
&swapUsage=${swap_usage}\
&diskTotal=${disk_total}\
&diskUsage=${disk_usage}\
&diskRwTime=${disk_rw_time}\
&connections=${connections}\
&ipv4=${ipv4}\
&rx=${rx}\
&tx=${tx}\
&load=$(base "$load")\
&loadCpu=${load_cpu}\
&loadIo=${load_io}\
&label=${label}
"

#echo $data_post

# 向收集数据的接口提交数据
if [ -n "$(command -v timeout)" ]
then
	# -q 不显示执行过程 -o 记录日志 -O 输出文档？ -T 超时设置，默认秒 --post-data 使用POST讲数据以str的形式发送 --no-check-certificate 不要验证证书
	timeout -s SIGKILL 30 wget -q -o /dev/null -O /etc/collector/agent.log -T 25 --post-data "$data_post" --no-check-certificate "$server"
else
	wget -q -o /dev/null -O /etc/collector/agent.log -T 25 --post-data "$data_post" --no-check-certificate "$server"
	wget_pid=$! 
	wget_counter=0
	wget_timeout=30
	
	while kill -0 "$wget_pid" && (( wget_counter < wget_timeout ))
	do
	    sleep 1
	    (( wget_counter++ ))
	done
	
	kill -0 "$wget_pid" && kill -s SIGKILL "$wget_pid"
fi

# 完
exit 1