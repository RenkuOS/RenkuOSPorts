#!/bin/bash
# Waits for the next event worth a look in a phase1b-run.sh run on $BUILD_HOST,
# prints it, and exits. Events seen before are remembered in $STATE, so each
# fires once. Run it from the machine you watch from, not the build host.
H=${BUILD_HOST:?set BUILD_HOST to user@host of the build machine}
STATE=${STATE:-$HOME/.cache/renkuos-phase1-monitor.state}
mkdir -p "$(dirname $STATE)"
touch $STATE
check() {
	timeout 30 ssh -o BatchMode=yes $H '
		S=~/haiku-build/phase1b.status
		L=~/haiku-build/wt-phase1/gen.arm64-bootstrap/phase1b/serial.log
		sed "s/^/status: /" $S
		grep -a -E "PHASE1 (exit [1-9]|watchdog|stage A|system packages|begin phase1-bootstrap|begin phase1-[a-z]|full python|network|no full python|end|already done)" $L |
			grep -av "PHASE1 begin phase1-A-" | tr -d "\r" | cut -c1-200
		# A port still running after 10 hours is worth a look.
		b=$(grep -a "PHASE1 begin" $L | tail -1 | tr -d "\r"); t=${b##* }
		[ -n "$t" ] && [ $(( $(date +%s) - t )) -gt 36000 ] && echo "long: ${b% *} over 10 h"
		true
	' < /dev/null
}
while :; do
	out=$(check) || { sleep 300; continue; }
	new=$(echo "$out" | grep -vxF -f $STATE)
	if [ -n "$new" ]; then
		echo "$new" >> $STATE
		echo "$new"
		timeout 30 ssh -o BatchMode=yes $H 'grep -a PHASE1 ~/haiku-build/wt-phase1/gen.arm64-bootstrap/phase1b/serial.log | grep -av "PHASE1 hb" | tail -12 | cut -c1-200' < /dev/null
		exit 0
	fi
	sleep 900
done
