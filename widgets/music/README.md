# Music

## Purpose

Show now-playing context and basic playback controls in a compact utility widget.

## Why It Fits NotchApp

Music is a strong general-purpose utility category. It is highly glanceable, easy to understand, and works well as a lightweight control surface.

## Target v1 Scope

- Match the mock widget visually and functionally in commit `88688469eb510fa87ff8b238c2babe349fa84595`
- Now playing title
- Compact artwork or visual cover area
- Back, play/pause, and forward controls
- Live playback state

Avoid turning this into a full music browser in v1.

## Likely UI Shape

- Large top artwork or cover area
- Track title centered in that area
- Small transport controls below with emphasized center action

The mock in commit `88688469eb510fa87ff8b238c2babe349fa84595` should be treated as the parity target.

## Needed Generic Host APIs

- `environment`
- `logger`
- Generic `media` capability
- `storage` for lightweight local state if needed

Likely host UI primitives:

- `Image`
- `Text`
- `Button`
- `IconButton`
- `Stack`
- `Inline`
- richer circular control styling

## Current Feasibility / Open Questions

Feasible without shell access if the platform exposes generic media session APIs and live update support.

This widget should own presentation and interaction logic while relying on reusable media capabilities for playback state and actions.

Open questions:

- Whether v1 media support includes subscription-style updates or only explicit refresh
- Whether artwork is required for the first real version or can be deferred
