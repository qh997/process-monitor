#!/bin/bash

DEFAULT_INTERVAL=30
FS_RECORD='filesystem.log'
PAGE_SIZE_K=$(($(getconf PAGE_SIZE) / 0x400))

function init {
	ARGS=$(getopt -o ht:p: --long help --long interval-time: --long process-name:\
		-n "$0" -- "$@")

	if [ $? != 0 ]; then
		usage
		exit 1
	fi

	eval set -- "$ARGS"

	while true ; do
		case "$1" in
			-h|--help) : ${HELP:=1}; shift;;
			-t|--interval-time) INTERVAL=$2; shift 2;;
			-p|--process-name) PROCESS=$PROCESS' '$2; shift 2;;
			--) shift; break;;
			*) echo "Internal error."; exit 1;;
		esac
	done

	if [ $HELP ]; then
		usage 1
		exit 0
	fi

	: ${INTERVAL:=${DEFAULT_INTERVAL}}
	: ${PROCESS:=''}
}

function usage {
    cat <<EOF
Usage:
	$0 [options]

	  Options:
	  -h, --help
	  -t <second>, --interval-time <second>
	  -p <process-name>, --process-name <process-name>
EOF

    if [[ $# > 0 ]]; then
cat <<EOF

Options:
	-h, --help
		Show this help message and exit.

	-t <second>, --interval-time <second>
		Specify the interval time for monitor in second.
		Default is 30s.

	-p <process-name>, --process-name <process-name>
		Specify the name of the process to monitor.
		Default is empty.
EOF
    fi
}

function filesystem_monitor {
	if [ ! -r "$FS_RECORD" ]; then
		echo 'Date,Second,Filesystem,Size,Used,Avail,Use%,MountPoint'
	fi

	for _data in $(df | sed '1d' | grep -v -P 'none|udev|tmpfs' | \
		awk 'BEGIN{OFS=","}{print $1,$2,$3,$4,$5,$6}'); do
		echo "${current_date},${current_second},${_data}"
	done
}

function system_process_monitor {
	local _pro_name=$1

	local _data="${current_date},${current_second},${_pro_name}"

	if [ "$_pro_name" == "SYSTEM" ]; then
		if [ ! -r "${_pro_name}.log" ]; then
			echo 'Date,Time,Porcess,cpu,mem_total,mem_used,swap_total,swap_used'
		fi

		local _mem_total=$(cat /proc/meminfo | grep -P '^MemTotal:' | awk '{print $2}')
		_data="${_data},${_mem_total}"
		local _mem_used=$(cat /proc/meminfo | grep -P '^MemAvailable:' | awk '{print $2}')
		_data="${_data},${_mem_used}"
		local _swap_total=$(cat /proc/meminfo | grep -P '^SwapTotal:' | awk '{print $2}')
		_data="${_data},${_swap_total}"
		local _swap_used=$(cat /proc/meminfo | grep -P '^SwapTotal:' | awk '{print $2}')
		_data="${_data},${_swap_used}"
	else
		if [ ! -r "${_pro_name}.log" ]; then
			echo 'Date,Time,Process,Args,PID,CPU%,Mem,VMem,SWAP'
			_data="${_data},"$(process_monitor "${_pro_name}")
		fi
	fi

	echo ${_data}
}

function process_monitor {
	local _pro_name=$1

	
}

init $@

current_date=$(date +"%Y-%m-%d.%H:%M:%S")
current_second=$(date +"%s")
#current_second=$(date +"%s.%N" | sed 's/\(\.[0-9][0-9][0-9]\).*/\1/')

#filesystem_monitor "${current_time}"

#system_process_monitor 'SYSTEM'

system_process_monitor 'tmux'

exit 0

echo 'Porcess,time,cpu,mem_total,mem_used,vmem,swap'

CPULOG_1=$(cat /proc/stat | grep 'cpu ' | awk '{print $2" "$3" "$4" "$5" "$6" "$7" "$8}')
SYS_IDLE_1=$(echo $CPULOG_1 | awk '{print $4}')
Total_1=$(echo $CPULOG_1 | awk '{print $1+$2+$3+$4+$5+$6+$7}')

sleep 5

CPULOG_2=$(cat /proc/stat | grep 'cpu ' | awk '{print $2" "$3" "$4" "$5" "$6" "$7" "$8}')
SYS_IDLE_2=$(echo $CPULOG_2 | awk '{print $4}')
Total_2=$(echo $CPULOG_2 | awk '{print $1+$2+$3+$4+$5+$6+$7}')

SYS_IDLE=`expr $SYS_IDLE_2 - $SYS_IDLE_1`

Total=`expr $Total_2 - $Total_1`
SYS_USAGE=`expr $SYS_IDLE/$Total*100 |bc -l`

SYS_Rate=`expr 100-$SYS_USAGE |bc -l`

Disp_SYS_Rate=`expr "scale=3; $SYS_Rate/1" |bc`
echo $Disp_SYS_Rate%