#!/usr/bin/env python3
# Resolves the ports needed to build a set of packages natively, from the JSON
# that eval-recipes.py writes. Follows runtime REQUIRES of every package and the
# BUILD_REQUIRES and BUILD_PREREQUIRES of every port that has to be built.
# Ports named in $CUT (a file) are left out, with everything only they pull in.
# Usage: resolve.py <recipes.json> <arch> <seeds.txt> [<built.txt>] > report
import json, os, re, sys
from collections import defaultdict

recipes, arch, seedFile = sys.argv[1:4]
built = set(open(sys.argv[4]).read().split()) if len(sys.argv) > 4 else set()
cut = set(open(os.environ['CUT']).read().split()) if os.environ.get('CUT') else set()
cutHits = defaultdict(set)

def vkey(v):
	return [(0, int(t), '') if t.isdigit() else (1, 0, t) for t in re.findall(r'\d+|[a-z]+', v.lower())]

def status(archs):
	tokens = archs.lower().split()
	if '!' + arch in tokens:
		return 'broken'
	if arch in tokens or 'all' in tokens or 'any' in tokens:
		return 'stable'
	if '?' + arch in tokens or '?all' in tokens:
		return 'untested'
	return 'unsupported'

def entities(text):
	out = []
	for line in (text or '').splitlines():
		line = line.split('#')[0].strip()
		if not line:
			continue
		name = line.split()[0].strip('"')
		out.append(re.split(r'[<>=]', name)[0].lower())
	return out

# Pick each port's newest recipe that builds on this architecture.
byPort = defaultdict(list)
for r in json.load(open(recipes)):
	if 'attrs' in r:
		r['status'] = status(r['attrs'].get('ARCHITECTURES', ''))
		byPort[r['port']].append(r)
ports = {}
for name, rs in byPort.items():
	# Like HaikuPorter without ALLOW_UNTESTED: a stable recipe wins over a newer untested one.
	usable = ([r for r in rs if r['status'] == 'stable']
		or [r for r in rs if r['status'] == 'untested'] or rs)
	ports[name] = max(usable, key=lambda r: vkey(r['version']))

# Every package each port makes, and what each package provides.
packages = {}		# package name -> (port, requires)
providers = defaultdict(set)
for name, r in ports.items():
	a = r['attrs']
	suffixes = [''] + [k[len('PROVIDES_'):] for k in a if k.startswith('PROVIDES_')]
	for s in suffixes:
		pkg = a.get('PACKAGE_NAME_' + s) if s else name
		pkg = pkg or name + '_' + s
		packages[pkg] = (name, entities(a.get('REQUIRES' + ('_' + s if s else ''))))
		providers[pkg.lower()].add(pkg)
		for e in entities(a.get('PROVIDES' + ('_' + s if s else ''))):
			providers[e].add(pkg)

# The haiku and haiku_devel system packages (src/data/package_infos/generic).
system = set('''haiku haiku_devel haiku_loader makefile_engine lib:libgcc_s lib:libstdc++ lib:libsupc++
	cmd:arp cmd:chop cmd:clear cmd:df cmd:ftpd cmd:hd cmd:hey cmd:login cmd:more cmd:passwd
	cmd:pidof cmd:ping cmd:prio cmd:ps cmd:renice cmd:resattr cmd:su cmd:telnet cmd:telnetd
	cmd:top cmd:traceroute cmd:trash cmd:unchop cmd:useradd cmd:watch cmd:xres'''.split())

chosen = {}
ambiguous = {}
def provider(e):
	if e in chosen:
		return chosen[e]
	cands = providers.get(e, set())
	if not cands:
		return None
	plain = e.split(':', 1)[-1]
	def rank(p):
		port = ports[packages[p][0]]
		return (p.lower() in (e, plain), p in needPkgs, port['status'] == 'stable',
			not p.endswith('_bootstrap'), p)
	best = max(cands, key=rank)
	if len(cands) > 1:
		ambiguous[e] = sorted(cands)
	chosen[e] = best
	return best

needPkgs, needPorts, why, unresolved = set(), set(), {}, defaultdict(set)
queue = [(s, 'seed') for s in open(seedFile).read().split()]
while queue:
	e, parent = queue.pop()
	if e in system:
		continue
	p = provider(e)
	if p is None:
		unresolved[e].add(parent)
		continue
	if p in needPkgs:
		continue
	port, reqs = packages[p]
	if port in cut:
		cutHits[port].add(parent)
		continue
	needPkgs.add(p)
	queue += [(x, p) for x in reqs]
	if port not in needPorts:
		needPorts.add(port)
		why[port] = parent
		a = ports[port]['attrs']
		queue += [(x, port + ' (build)') for x in
			entities(a.get('BUILD_REQUIRES')) + entities(a.get('BUILD_PREREQUIRES'))]

print(f'ports needed: {len(needPorts)}, packages: {len(needPkgs)}, already built: {len(needPorts & built)}')
print('\n## ports (status, recipe, pulled in by)')
for port in sorted(needPorts):
	r = ports[port]
	print(f"{port}\t{r['status']}\t{r['path']}\t{why[port]}\t{'built' if port in built else ''}")
print('\n## cut (wanted by)')
for port, ps in sorted(cutHits.items()):
	print(port, '<-', ' '.join(sorted(ps)[:6]))
print('\n## unresolved')
for e, ps in sorted(unresolved.items()):
	print(e, '<-', ' '.join(sorted(ps)[:5]))
print('\n## ambiguous providers (chosen first)')
for e, cs in sorted(ambiguous.items()):
	if any(packages[c][0] in needPorts for c in cs):
		print(e, '->', chosen[e], '|', ' '.join(c for c in cs if c != chosen[e]))
