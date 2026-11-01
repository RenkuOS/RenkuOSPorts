#!/bin/bash
# Logs the CPU package temperature every minute. Pauses the phase1b QEMU (by the
# PID in the status file) at 85°C and resumes it below 70°C.
# Environment: BUILD_ROOT.
A=${BUILD_ROOT:-$HOME/haiku-build}
LOG=$A/logs/cputemp.log
mkdir -p $A/logs
paused=
while :; do
	t=$(sensors 2> /dev/null | awk '/Package id 0/ { gsub(/[+°C]/, "", $4); print int($4) }')
	q=$(awk '/^boot [0-9]+ pid/ { p = $4 } END { print p }' $A/phase1b.status 2> /dev/null)
	echo "$(date +%F_%T) $t${paused:+ paused}" >> $LOG
	if [ -n "$t" ] && [ -n "$q" ] && kill -0 $q 2> /dev/null; then
		if [ -z "$paused" ] && [ $t -ge 85 ]; then
			kill -STOP $q; paused=1; echo "$(date +%F_%T) PAUSE qemu $q at $t" >> $LOG
		elif [ -n "$paused" ] && [ $t -lt 70 ]; then
			kill -CONT $q; paused=; echo "$(date +%F_%T) RESUME qemu $q at $t" >> $LOG
		fi
	fi
	sleep 60
done
