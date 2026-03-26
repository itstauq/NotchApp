# Gmail

## Purpose

Surface the latest important email context with unread visibility and quick jump-out actions.

## Why It Fits NotchApp

Gmail is a useful later integration widget because it can provide meaningful awareness in a small footprint, but it should stay lightweight and avoid becoming an inbox client.

## Target v1 Scope

- Match the mock widget visually and functionally in commit `88688469eb510fa87ff8b238c2babe349fa84595`
- Unread summary header
- Compose affordance
- Recent or important message rows
- Sender avatars and unread markers
- Quick jump-out to open or compose
- Simple cached summaries for responsiveness

## Likely UI Shape

- Compact header with unread count and compose affordance
- Scrollable list of message rows
- Avatar, sender, unread dot, and one-line subject per row
- Bottom fade treatment as content scrolls out

The mock in commit `88688469eb510fa87ff8b238c2babe349fa84595` should be treated as the parity target.

## Needed Generic Host APIs

- `fetch`
- `preferences` for configuration or auth inputs
- `storage`
- `openURL`
- `environment`
- `logger`

Likely host UI primitives:

- `ScrollView`
- styled `Row`
- `Text`
- `Image` for avatars if supported
- unread indicator support
- `IconButton`
- fade mask support

## Current Feasibility / Open Questions

Feasible without shell access.

This widget can be self-contained if it handles its own API integration through generic fetch and managed configuration, without host-specific Gmail behavior.

Open questions:

- Whether v1 should prioritize unread summaries only or include compose/open affordances immediately
- Whether avatar support is necessary in the first real version
