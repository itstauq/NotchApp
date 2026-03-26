# Camera Preview

## Purpose

Offer a differentiated notch-native widget that makes the surface feel playful, visual, and uniquely tied to the hardware context.

## Why It Fits NotchApp

Camera Preview is one of the most distinct ideas in the planned set. It is visually memorable and especially well matched to the notch, even though it is less important than the core productivity widgets for validating the platform.

## Target v1 Scope

- Match the mock widget visually and functionally in commit `88688469eb510fa87ff8b238c2babe349fa84595`
- Live or near-live camera preview
- Large preview-first surface
- Overlay controls in the card corners
- Minimal quick actions related to the preview surface

## Likely UI Shape

- Large preview surface with rounded corners
- Small overlay control badges in the corners
- Minimal chrome so the preview remains primary

The mock in commit `88688469eb510fa87ff8b238c2babe349fa84595` should be treated as the parity target.

## Needed Generic Host APIs

- `environment`
- `logger`
- Generic `camera` capability

Likely host UI primitives:

- `Image`
- `Button`
- `Icon`
- `Stack`
- `Inline`
- overlay positioning support
- control badge/container styling

## Current Feasibility / Open Questions

Feasible without shell access only if the platform exposes a generic camera capability and image rendering support.

This widget should still be self-contained at the product level, but it depends on a reusable native capability that other widgets could also rely on later.

Open questions:

- Whether v1 should target a true live preview stream or a snapshot-based approximation
- What the minimal generic camera API should look like for permission handling and frame delivery
