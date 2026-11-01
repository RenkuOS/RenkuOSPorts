#!/usr/bin/env python3
# Per-port build times from HaikuPorts buildmaster master.log files: the latest
# successful build of each port, from "starting build" to "succeeded".
# Usage: bm-times.py <log>... > times.tsv  (port, seconds, version, builder, buildrun)
import re, sys
from datetime import datetime

START = re.compile(r'^(\S+ \S+): starting build (\d+), (\S+) on builder (\S+)')
DONE = re.compile(r'^(\S+ \S+): build (\d+), \S+ succeeded')

def ts(s):
	return datetime.strptime(s, '%Y-%m-%d %H:%M:%S,%f').timestamp()

latest = {}
for path in sys.argv[1:]:
	run = int(path.rsplit('/', 1)[-1].split('.')[0])
	started = {}
	for line in open(path, errors='replace'):
		m = START.match(line)
		if m:
			started[m.group(2)] = (ts(m.group(1)), m.group(3), m.group(4))
			continue
		m = DONE.match(line)
		if m and m.group(2) in started:
			t0, versioned, builder = started[m.group(2)]
			port, version = versioned.rsplit('-', 1)
			if port not in latest or latest[port][3] < run:
				latest[port] = (int(ts(m.group(1)) - t0), version, builder, run)
for port, (secs, version, builder, run) in sorted(latest.items()):
	print(f'{port}\t{secs}\t{version}\t{builder}\t{run}')
