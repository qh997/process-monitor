#!/bin/bash

DEFAULT_INTERVAL=30
FS_RECORD='filesystem.log'
PAGE_SIZE_K=$(($(getconf PAGE_SIZE) / 0x400))

function init {
	ARGS=$(getopt -o ht:p:o: --long help --long interval-time: --long process-name:\
		--long outdir: -n "$0" -- "$@")

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
			-o|--outdir) OUTDIR=$2; shift 2;;
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

	_pro_name=$(echo "${_pro_name}" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')
	local _data="${current_date},${current_second},\"${_pro_name}\""

	if [ "$_pro_name" == "SYSTEM" ]; then
		if [ ! -r "${_pro_name}.log" ]; then
			echo 'Date,Time,Porcess,cpu,mem_total,mem_used,swap_total,swap_used'
		fi

		_data="${_data},$(cat /proc/meminfo | awk '$1 == "MemTotal:"{print $2}')"
		_data="${_data},$(cat /proc/meminfo | awk '$1 == "MemAvailable:"{print $2}')"
		_data="${_data},$(cat /proc/meminfo | awk '$1 == "SwapTotal:"{print $2}')"
		_data="${_data},$(cat /proc/meminfo | awk '$1 == "SwapCached:"{print $2}')"

		echo ${_data}
	else
		if [ ! -r "${_pro_name}.log" ]; then
			echo 'Date,Time,Process,Args,PID,CPU%,Mem%,Mem(RSS in kB),VMem(VSZ in kB),SWAP(kB)'
		fi

		process_monitor "${_pro_name}" "${_data}"
	fi
}

function process_monitor {
	local _pro_name=$1
	local _data=$2

	_pro_name=$(echo "${_pro_name}" | sed 's/\./\\./g')

	for _pid in $(pgrep "^${_pro_name}\$"); do
		local __data=${_data}

		__data="${__data},\""$(ps -p ${_pid} -o 'args' | sed '1d')'"'
		__data="${__data},${_pid}"
		__data="${__data},$(ps -p ${_pid} -o 'pcpu' | sed -e '1d' -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')%"
		__data="${__data},$(ps -p ${_pid} -o 'pmem' | sed -e '1d' -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')%"
		__data="${__data},$(ps -p ${_pid} -o 'rss' | sed -e '1d' -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
		__data="${__data},$(ps -p ${_pid} -o 'vsz' | sed -e '1d' -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
		__data="${__data},$(awk '/Swap:/{a=a+$2}END{print a}' /proc/${_pid}/smaps)"

		echo ${__data}
	done
}

init $@

current_date=$(date +"%Y-%m-%d.%H:%M:%S")

current_second=$(date +"%s")
#current_second=$(date +"%s.%N" | sed 's/\(\.[0-9][0-9][0-9]\).*/\1/')

filesystem_monitor "${current_time}"

system_process_monitor 'SYSTEM'

system_process_monitor "${PROCESS}"

exit 0
