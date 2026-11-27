#!/usr/bin/env python3
# Evaluates every recipe in a HaikuPorts tree for one target architecture, the
# way HaikuPorter does (bash sources the recipe, then prints its attributes),
# and writes the result as JSON. Usage: eval-recipes.py <tree> <arch> <out.json>
import json, os, re, subprocess, sys
from concurrent.futures import ThreadPoolExecutor

tree, arch, out = sys.argv[1:4]
tree = os.path.abspath(tree)

# The parts of HaikuPorter's commonRecipeScriptHead that recipes call at the top level.
HEAD = r'''
defineDebugInfoPackage() {
	[ "$1" = --directory ] && shift 2
	PROVIDES_debuginfo="${1}_debuginfo = $portVersion"
	REQUIRES_debuginfo="$1 == $portVersion base"
}
getPackagePrefix() { echo /packages/x/.self; }
updateRevisionVariables() { :; }
'''
KEYS = 'ARCHITECTURES|PROVIDES|REQUIRES|BUILD_REQUIRES|BUILD_PREREQUIRES|SECONDARY_ARCHITECTURES|PACKAGE_NAME|DISABLED'
TAIL = r'''
for key in $(set | grep -E -o "^(''' + KEYS + r''')(_[0-9a-zA-Z_]+)?=" | cut -d= -f1); do
	value=${!key}
	printf '%s=%s\n' "$key" "${value//$'\n'/\\n}"
done
'''

def evaluate(path):
	base = os.path.basename(path)[:-len('.recipe')]
	m = re.match(r'(.+?)-(\d.*)$', base)
	if not m:
		return None
	name, version = m.groups()
	env = {
		'PATH': '/usr/bin:/bin',
		'portName': name, 'portBaseName': name, 'portVersion': version,
		'portVersionedName': base, 'portRevision': '1', 'portFullVersion': version + '-1',
		'portRevisionedName': base + '-1', 'portDir': os.path.dirname(path),
		'portBaseDir': os.path.dirname(path),
		'targetArchitecture': arch, 'effectiveTargetArchitecture': arch,
		'buildArchitecture': arch, 'secondaryArchSuffix': '', 'secondaryArchSubDir': '',
		'effectiveTargetMachineTriple': arch + '-unknown-haiku',
		'effectiveTargetMachineTripleAsName': arch + '_unknown_haiku',
	}
	script = HEAD + '. "$recipe" > /dev/null 2>&1 || true\n' + TAIL
	env['recipe'] = path
	try:
		r = subprocess.run(['bash', '-c', script], env=env, capture_output=True,
			text=True, timeout=30, cwd=os.path.dirname(path))
	except subprocess.TimeoutExpired:
		return {'port': name, 'version': version, 'path': path, 'error': 'timeout'}
	attrs = {}
	for line in r.stdout.splitlines():
		k, _, v = line.partition('=')
		attrs[k] = v.replace('\\n', '\n')
	return {'port': name, 'version': version, 'path': os.path.relpath(path, tree), 'attrs': attrs}

recipes = []
for root, dirs, files in os.walk(tree):
	dirs[:] = [d for d in dirs if not d.startswith('.') and d not in ('renkuos', 'repository')]
	recipes += [os.path.join(root, f) for f in files if f.endswith('.recipe')]
with ThreadPoolExecutor(os.cpu_count()) as pool:
	results = [r for r in pool.map(evaluate, recipes) if r]
json.dump(results, open(out, 'w'), indent=0)
print(len(results), 'recipes evaluated', file=sys.stderr)
