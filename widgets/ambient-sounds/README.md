# Ambient Sounds

## Purpose

Offer compact ambience controls that support focus without expanding into a full audio mixing surface.

## Why It Fits NotchApp

Ambient Sounds is a strong focus-oriented widget category. It can make views feel distinct while staying compact and low-friction.

## Target v1 Scope

- Match the mock widget visually and functionally in commit `88688469eb510fa87ff8b238c2babe349fa84595`
- Two-by-three grid of ambience tiles
- Selectable ambience sources
- Per-source selected state and level visualization
- Basic playback and intensity behavior
- Remember last-used settings

## Likely UI Shape

- Two rows of three compact tiles
- Icon, label, and mini level bars inside each tile
- Selected and unselected visual states

The mock in commit `88688469eb510fa87ff8b238c2babe349fa84595` should be treated as the parity target.

## Needed Generic Host APIs

- `storage`
- `environment`
- `logger`
- Generic `audio` capability

Likely host UI primitives:

- selectable tile/container support
- `Icon`
- `Text`
- mini bar graph or `Progress`
- grid or equivalent tile layout support

## Current Feasibility / Open Questions

Feasible without shell access if the platform exposes a generic audio capability rather than widget-specific playback hooks.

This widget should own its UI logic and source selection while the host provides only reusable audio primitives.

Open questions:

- Whether v1 audio support is limited to bundled ambience sources or can support external sources later
- Whether tile layout is implemented as a dedicated grid primitive or a composition pattern over existing layout primitives
