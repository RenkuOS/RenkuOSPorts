# Sizing the arm64 nightly

These scripts count the ports an arm64 `@nightly-mmc` build needs and estimate how long they
take to build. They run on the build host. Nothing here needs the guest.

| File | What it does |
|---|---|
| `eval-recipes.py` | Sources every recipe in the tree for one architecture, the way HaikuPorter does, and writes the attributes as JSON. |
| `resolve.py` | Follows runtime and build requirements from a seed list, and reports the ports needed, the ones already built, and whatever is left unresolved. Ports named in the `CUT` file are left out. |
| `bm-times.py` | Reads HaikuPorts buildmaster `master.log` files and prints the latest successful build time of each port. |
| `estimate.py` | Joins a `resolve.py` report with those times and a TCG factor. |
| `seeds-arm64.txt` | What jam asks for: the image packages, the build-feature packages, and the current arm64 package set. |
| `cut-arm64.txt` | Ports left out of the first arm64 nightly. |

```sh
./eval-recipes.py ../../../.. arm64 recipes-arm64.json
CUT=cut-arm64.txt ./resolve.py recipes-arm64.json arm64 seeds-arm64.txt built.txt > report.txt
mkdir -p logs
B=https://build.haiku-os.org/buildmaster/master/x86_64/buildruns
curl -fsS $B/buildruns.txt | tail -4000 | xargs -P4 -I{} curl -fsS -o logs/{}.log $B/{}/master.log
./bm-times.py logs/*.log > times.tsv
./estimate.py report.txt times.tsv recipes-arm64.json 3.5
```

`built.txt` lists the package names already built, one per line. The resolver uses the
newest stable recipe of each port, as HaikuPorter does without `ALLOW_UNTESTED`. Where
several packages provide the same name, it prefers the one already chosen, then the one
named after it.
