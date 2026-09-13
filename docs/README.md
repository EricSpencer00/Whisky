# Docs

**Playing a game: [foss-bundle-usage.md](foss-bundle-usage.md).** Install,
verify, and how to tell which layer is at fault. Everything else here is
background or record.

## Current

| file | what it is |
|---|---|
| [foss-bundle-usage.md](foss-bundle-usage.md) | install, verify, run apps, known limitations |
| [app-triage.md](app-triage.md) | how to find where an app breaks, the capability map, what works today |
| [open-source-roadmap.md](open-source-roadmap.md) | the full record, newest sections last |
| [upstream-status.md](upstream-status.md) | the syscall-argument bug, and why it is not filed upstream |

## What runs today

BeamNG.drive plays. Steam's store and library work. The Rockstar Games Launcher
reaches its sign-in screen. Cave Story, OpenTTD, SuperTuxKart and GZDoom all
run. D3D9, D3D11 and D3D12 each create a device and present the colour asked
for, in both word sizes. [app-triage.md](app-triage.md) has the measurements and
the failures.

Also `.claude/skills/wine-app-triage/` — read it before debugging an app that
will not start.

## Superseded, kept for the record

| file | why it is here |
|---|---|
| [beamng-runbook.md](beamng-runbook.md) | Apr 2026. Recommends CrossOver. Not needed any more. |
| [beamng-sikarugir-recipe.md](beamng-sikarugir-recipe.md) | Apr 2026. Sikarugir + DXMT 0.74, superseded by this fork's own bundle. |
| [gptk-3-swap-experiment.md](gptk-3-swap-experiment.md) | Apr 2026. Apple GPTK / D3DMetal, not redistributable, replaced by DXMT. |

## Reading the roadmap

It is chronological and includes the wrong turns, because the corrections are
usually the more useful half. Several early conclusions were later disproved.
If you only read part of it, read the end.

The short version:

- **Direct3D 11 is solved.** DXMT gives feature level 11_1 with the real Apple
  GPU as the adapter. DXVK and wined3d cannot: both go through Vulkan, and
  MoltenVK has no geometry shaders.
- **The bug that blocked BeamNG was ours, not the game's.** A `BOOLEAN` syscall
  argument was written one byte wide by the PE compiler and read four bytes wide
  by the unix side, so `GetLogicalDrives()` looped forever while holding the
  loader lock. See `Scripts/patches/ntdll-boolean-syscall-arg-abi.patch`.
- **Direct3D 12 is not supported** and is the main gap. MoltenVK already meets
  vkd3d-proton's descriptor-indexing requirements everywhere except samplers,
  which Metal caps at 1024.
- **Rosetta 2 is being removed** in macOS 28. Everything here is x86_64. Issue #20.
