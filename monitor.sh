#!/bin/bash

DEFAULT_INTERVAL=30
FS_RECORD='filesystem.csv'
PAGE_SIZE_K=$(($(getconf PAGE_SIZE) / 0x400))
WORKDIR=$(cd `dirname "$0"`; pwd)
declare -a PROCESS=()

function init {
	ARGS=$(getopt -o ht:p:o: --long help --long interval-time: \
		--long process-name: --long outdir: -n "$0" -- "$@")

	if [ $? != 0 ]; then
		usage
		exit 1
	fi

	eval set -- "$ARGS"

	while true ; do
		case "$1" in
			-h|--help) : ${HELP:=1}; shift;;
			-t|--interval-time) INTERVAL=$2; shift 2;;
			-p|--process-name) PROCESS[${#PROCESS[*]}]=$2; shift 2;;
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
	: ${OUTDIR:=${WORKDIR}/monitor-out}

	[ ! -d ${OUTDIR} ] && mkdir -p ${OUTDIR}
}

function usage {
	cat <<EOF
Usage:
	$0 [options]

	  Options:
	  -h, --help
	  -t <second>, --interval-time <second>
	  -p <process-name>, --process-name <process-name>
	  -o <output-dir>, --outdir <output-dir>
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

	-o <output-dir>, --outdir <output-dir>
		Specify the output directory.
		Default is {CURRENT-DIR}/monitor-out
EOF
	fi
}

function filesystem_monitor {
	if [ ! -r "${OUTDIR}/$FS_RECORD" ]; then
		echo 'Date,Time,Filesystem,Size,Used,Avail,Use%,MountPoint' > "${OUTDIR}/${FS_RECORD}"
	fi

	for _data in $(df | sed '1d' | grep -v -P 'none|udev|tmpfs' | \
		awk 'BEGIN{OFS=","}{print $1,$2,$3,$4,$5,$6}'); do
		echo "${current_date},${current_second},${_data}" >> "${OUTDIR}/${FS_RECORD}"
	done
}

function system_process_monitor {
	local _pro_name=$1

	_pro_name=$(echo "${_pro_name}" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')
	local _data="${current_date},${current_second},\"${_pro_name}\""

	if [ "$_pro_name" == "SYSTEM" ]; then
		if [ ! -r "${OUTDIR}/${_pro_name}.csv" ]; then
			echo 'Date,Time,Porcess,CPU,MemTotal,MemAvailable,SwapTotal,SwapCached' \
				> "${OUTDIR}/${_pro_name}.csv"
		fi

		_data="${_data},$(system_pcpu)%"
		_data="${_data},$(cat /proc/meminfo | awk '$1 == "MemTotal:"{print $2}')"
		_data="${_data},$(cat /proc/meminfo | awk '$1 == "MemAvailable:"{print $2}')"
		_data="${_data},$(cat /proc/meminfo | awk '$1 == "SwapTotal:"{print $2}')"
		_data="${_data},$(cat /proc/meminfo | awk '$1 == "SwapCached:"{print $2}')"

		echo ${_data} >> "${OUTDIR}/${_pro_name}.csv"
	else
		if [ ! -r "${OUTDIR}/${_pro_name}.csv" ]; then
			echo 'Date,Time,Process,Args,PID,CPU%,Mem%,Mem(RSS in kB),VMem(VSZ in kB),SWAP(kB)' \
				> "${OUTDIR}/${_pro_name}.csv"
		fi

		process_monitor "${_pro_name}" "${_data}"
	fi
}

function system_pcpu {
	cpu_s=$(top -n 2 | awk -F: '$1 ~ /Cpu/{print $2}' | sed -n '$p')
	cpu_idle=$(echo $cpu_s | awk 'BEGIN{FS=",";OFS="\n"}{NF=NF; print}' | awk '$3 ~ "id"{print $2}')
	echo $(echo "scale=3; 100 - ${cpu_idle}" | bc)
}

function process_monitor {
	local _pro_name=$1
	local _data=$2

	__pro_name=$(echo "${_pro_name}" | sed 's/\./\\./g')

	if pgrep "${__pro_name}" > /dev/null; then
		for _pid in $(pgrep "${__pro_name}"); do
			local __data=${_data}

			__data="${__data},\""$(ps -p ${_pid} -o 'args' | sed '1d')'"'
			__data="${__data},${_pid}"
			__data="${__data},$(ps -p ${_pid} -o 'pcpu' | sed -e '1d' -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')%"
			__data="${__data},$(ps -p ${_pid} -o 'pmem' | sed -e '1d' -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')%"
			__data="${__data},$(ps -p ${_pid} -o 'rss' | sed -e '1d' -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
			__data="${__data},$(ps -p ${_pid} -o 'vsz' | sed -e '1d' -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
			__data="${__data},$(awk '/Swap:/{a=a+$2}END{print a}' /proc/${_pid}/smaps)"

			echo "${__data}" >> "${OUTDIR}/${_pro_name}.csv"
		done
	else
		echo "${_data},,<NO SUCH PROCESS>,,,,,," >> "${OUTDIR}/${_pro_name}.csv"
	fi
}

init $@

last_checked_time=0
checked=0
while [ 1 ]; do
	current_date=$(date +"%Y-%m-%d %H:%M:%S")
	current_second=$(date +"%s")
	#current_second=$(date +"%s.%N" | sed 's/\(\.[0-9][0-9][0-9]\).*/\1/')

	# We check the time every second
	if [ $current_second -ge $((${last_checked_time} + ${INTERVAL})) ] && [ 0 -eq ${checked} ]; then
		echo "[$current_date] Starting monitor."

		filesystem_monitor
		system_process_monitor 'SYSTEM'

		for ((i=0; i<${#PROCESS[*]}; i++)); do
			system_process_monitor "${PROCESS[$i]}"
		done

		checked=1
		last_checked_time=${current_second}
	else
		sleep 1
		checked=0
	fi
done

exit 0
