# Notes

## Purpose

Provide lightweight working notes and session-adjacent memory inside the notch.

## Why It Fits NotchApp

Notes complements Capture without duplicating it. Capture is fast dump-in; Notes is for active thought continuation and quick review of current context.

## Target v1 Scope

- Match the mock widget visually and functionally in commit `88688469eb510fa87ff8b238c2babe349fa84595`
- Scrollable stack of note cards
- Multiline note previews with timestamps
- Quick review of recent notes with local persistence

## Likely UI Shape

- Vertical scroll surface with stacked cards
- Each card shows a multiline preview and a timestamp
- Bottom fade treatment as content scrolls out

The mock notes widget in commit `88688469eb510fa87ff8b238c2babe349fa84595` should be treated as the parity target.

## Needed Generic Host APIs

- `storage`
- `environment`
- `logger`

Likely host UI primitives:

- `ScrollView`
- styled card/container support
- `Text`
- fade mask support

## Current Feasibility / Open Questions

Feasible without shell access.

This widget can be fully self-contained using local React state plus widget-scoped storage. It is one of the strongest early parity targets.

Open questions:

- Whether the first real version is read-mostly like the mock or also supports inline editing immediately
- Whether multiline editing needs a richer text input primitive than the current runtime surface
