#!/usr/bin/env python3
# Joins a resolve.py report with x86_64 buildmaster times (bm-times.py) and
# estimates arm64 build time under TCG. "any" ports are not built: the existing
# packages are reused.
# Usage: estimate.py <report> <times.tsv> <recipes.json> <factor> > table
import json, sys

report, timesFile, recipes, factor = sys.argv[1], sys.argv[2], sys.argv[3], float(sys.argv[4])
times = {}
for line in open(timesFile):
	port, secs, version, builder, run = line.rstrip('\n').split('\t')
	times[port] = (int(secs), version, builder)
anyPorts = {r['port'] for r in json.load(open(recipes))
	if r.get('attrs', {}).get('ARCHITECTURES', '').split() == ['any']}

rows, section = [], None
for line in open(report):
	if line.startswith('## '):
		section = line[3:].split()[0]
		continue
	f = line.rstrip('\n').split('\t')
	if section == 'ports' and len(f) >= 4:
		rows.append(f + [''] * (5 - len(f)))

todo = [r for r in rows if r[4] != 'built' and r[0] not in anyPorts]
known = [r for r in todo if r[0] in times]
unknown = [r[0] for r in todo if r[0] not in times]
x86 = sum(times[r[0]][0] for r in known)
print(f'ports: {len(rows)}, built: {sum(r[4] == "built" for r in rows)}, '
	f'any (reused): {sum(r[0] in anyPorts for r in rows)}, to build: {len(todo)}')
print(f'x86_64 buildmaster time for {len(known)} of them: {x86 / 3600:.1f} h; '
	f'arm64 TCG estimate at {factor:g}x: {x86 * factor / 3600:.0f} h')
print('no x86_64 time:', ' '.join(sorted(unknown)))
print('\nport\tx86_64 s\tarm64 est h\tbuilder\tpulled in by')
for r in sorted(known, key=lambda r: -times[r[0]][0]):
	s, v, b = times[r[0]]
	print(f'{r[0]}\t{s}\t{s * factor / 3600:.1f}\t{b}\t{r[3]}')
