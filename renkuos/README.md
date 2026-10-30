# RenkuOSPorts

RenkuOSPorts is the RenkuOS fork of [HaikuPorts](https://github.com/haikuports/haikuports).
It is a full fork: the recipe tree at the top level is HaikuPorts with our own commits on
top, and HaikuPorter uses it directly. This `renkuos/` directory holds what is ours and not a
recipe. HaikuPorter ignores it because it contains no recipes.

## Tracking upstream

- `main` started at HaikuPorts `46b2f4b3e13f` (2026-10-21), the commit the first arm64
  bootstrap image was built from.
- Upstream is merged in on a schedule, the same way RenkuOS/Source tracks Haiku. Add the
  remote with `git remote add upstream https://github.com/haikuports/haikuports.git`.
- HaikuPorts does not take our changes, so fixes live here for good. Keep each one a
  separate commit that says why it is needed, so a later upstream merge shows clearly when
  it conflicts or is no longer needed.

## Layout

| Path | What it is |
|---|---|
| `bootstrap/arm64/` | Scripts that build arm64 packages natively on arm64 Haiku under QEMU. See its README. |

Changes that are only needed while bootstrapping a new architecture, such as recipe edits
that break dependency cycles, go on a `bootstrap/<arch>` branch and not on `main`.
