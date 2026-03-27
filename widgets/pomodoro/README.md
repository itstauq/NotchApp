# Pomodoro

## Purpose

Support focused work sessions with a highly glanceable timer and lightweight controls.

## Why It Fits NotchApp

Pomodoro is naturally span-responsive, easy to understand at a glance, and makes the layout feel alive without requiring heavy interaction.

## Target v1 Scope

- Match the mock widget visually and functionally in commit `88688469eb510fa87ff8b238c2babe349fa84595`
- Live countdown timer
- Cycle label and dot indicators
- Large primary start action
- Reset and settings controls
- Persistence of active session state across remounts where practical

## Likely UI Shape

- Centered timer display
- Compact cycle label with dot progress above
- Pill-shaped primary button and two smaller secondary controls below

The mock in commit `88688469eb510fa87ff8b238c2babe349fa84595` should be treated as the parity target.

## Needed Generic Host APIs

- `storage`
- `environment`
- `logger`
- Generic timer or interval support

Likely host UI primitives:

- `Text`
- `Button`
- `IconButton`
- dot indicator support through shapes or `Progress`
- `Badge`
- `Stack`
- `Inline`

## Current Feasibility / Open Questions

Feasible without shell access if the runtime supports timer updates or a host-managed interval capability.

This widget should stay self-contained and should not require host-specific Pomodoro logic.

Open questions:

- Whether timer progression is driven by React effects alone or by an explicit host timing API
- Whether the settings control is active in the first parity pass or present-but-inert until a broader preferences flow exists
