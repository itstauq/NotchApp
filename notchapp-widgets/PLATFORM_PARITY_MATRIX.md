# Widget Mock Parity Matrix

This document treats the mock widgets from commit `88688469eb510fa87ff8b238c2babe349fa84595` as the visual and functional source of truth for v1.

The working requirement is stricter than the earlier planning stubs:

- the real widgets should match the mock widgets visually
- all visible controls should function
- widgets remain self-contained
- no shell or process spawning is available to widget code
- the host provides only generic runtime and native capability APIs

## Capability Matrix

| Widget | Mock features that must work | Generic host APIs needed | Renderer / UI primitives needed | Can stay generic without shell? | Biggest platform gaps today |
| --- | --- | --- | --- | --- | --- |
| Capture | Input row, mic affordance, checklist rows, complete toggle, strikethrough, delete | `storage`, `logger`, `environment` | `Input`, `Row` or `ListItem`, `Checkbox`, `IconButton`, `Spacer`, text styling | Yes | Styling flexibility and row composition polish |
| Notes | Scrollable note cards, timestamps, multiline previews | `storage`, `logger`, `environment` | `ScrollView`, card/container styling, multiline `Text` | Yes | Real scroll container and card styling control |
| Pomodoro | Live countdown, cycle dots, primary CTA, reset/settings controls | `storage`, `timer`, `logger`, `environment` | `Button`, `IconButton`, dot indicators or `Progress`, large text styling | Yes | Timer/update model and richer button sizing/styling |
| Ambient Sounds | Two-by-three sound tiles, selected states, level bars, per-source controls | `audio`, `storage`, `logger`, `environment` | Tile/grid layout, `Icon`, `Text`, mini bar graph or `Progress`, selectable container styling | Yes | Generic audio API, tile/grid primitive, visual control fidelity |
| Calendar | Scrollable agenda, event color bars, time column, metadata, bottom fade mask | `calendar` or `fetch`, `storage`, `openURL`, `logger`, `environment` | `ScrollView`, `Divider`, colored bar primitive, fade mask support, row layout | Yes | Scroll + mask/fade support and data refresh model |
| Music | Artwork area, title, transport controls, live playback state | `media`, `logger`, `environment` | `Image`, `Button` / `IconButton`, optional `Progress`, artwork container styling | Yes | Generic media session API, image support, live updates |
| Linear | Scrollable issue list, priority bars, status pill affordance | `fetch`, `preferences`, `storage`, `openURL`, `logger`, `environment` | `ScrollView`, `Badge` / pill, mini bar indicator, row layout, fade mask | Yes | Auth/preferences model, richer badges/pills, scroll + mask |
| Gmail | Unread header, compose affordance, sender avatars, unread dots, message rows | `fetch`, `preferences`, `storage`, `openURL`, `logger`, `environment` | `ScrollView`, `Image` or avatar primitive, unread indicator, row layout, fade mask | Yes | Auth/preferences model, avatar/image support, scroll + mask |
| Camera Preview | Large live preview surface, overlay controls in corners | `camera`, `logger`, `environment` | `Image` or preview surface, overlay positioning, control badges | Yes, with native capability | Generic camera API and live frame delivery |

## Minimum Generic Capability Set

These are the smallest reusable platform capabilities that cover the full mock set without widget-specific host logic.

### Runtime APIs

- `storage`
- `preferences`
- `logger`
- `environment`
- `openURL`
- `fetch`
- `timer`
- `audio`
- `media`
- `camera`

### Renderer / UI primitives

- `Stack`
- `Inline`
- `Spacer`
- `Text`
- `Input`
- `Button`
- `IconButton`
- `Checkbox` or `Toggle`
- `ScrollView`
- `Divider`
- `Image`
- `Badge`
- `Progress`
- styled `Row` or `ListItem`
- overlay positioning support
- mask and fade support
- richer container styling for cards, pills, and tiles

## Current Runtime Coverage

The current runtime surface already supports:

- `Stack`
- `Inline`
- `Spacer`
- `Text`
- `Input`
- `Button`
- `Icon`
- `IconButton`
- `Checkbox`
- `Row`

That means the current runtime is closest to supporting:

- Capture
- parts of Notes
- parts of Pomodoro

## Biggest Platform Gaps

Grouped by area:

### Data and device capabilities

- `timer` for Pomodoro
- `fetch` plus `preferences` for Linear, Gmail, and one Calendar path
- `audio` for Ambient Sounds
- `media` for Music
- `camera` for Camera Preview

### Rendering primitives

- `ScrollView`
- `Divider`
- `Image`
- `Badge`
- `Progress`

### Styling and layout fidelity

- richer card, tile, and pill styling
- overlay positioning for camera and media controls
- mask and fade support for scroll endings
- per-element sizing variants for buttons and icons
- colored accent bars and tiny chart-like indicators

## Prioritized Platform Roadmap

This roadmap is optimized for the two questions:

1. Which generic capabilities unlock the most mock widgets fastest?
2. Which capabilities are mandatory before exact parity is even possible?

### Phase 1: Highest leverage unlocks

These unlock the most widgets with the least new platform breadth.

- Add `ScrollView`
- Add `Divider`
- Add richer row and container styling support
- Add `Badge`
- Add `Progress`
- Add `fetch`
- Add `preferences`
- Add `storage` parity with the intended spec
- Add a generic `timer` capability

Why this phase first:

- It unlocks strong versions of Capture, Notes, Pomodoro, Calendar, Linear, and Gmail
- It covers the majority of the mock list before media/device work
- It reduces the largest gap between the current runtime and the mock UIs

Widgets meaningfully unlocked in this phase:

- Capture: near-complete
- Notes: near-complete
- Pomodoro: functionally complete, pending visual polish
- Calendar: structurally complete, pending chosen data source
- Linear: structurally complete, pending auth and styling polish
- Gmail: structurally complete, pending auth and avatar/image support

### Phase 2: Visual/media parity layer

- Add `Image`
- Add overlay positioning support
- Add mask and fade support
- Add improved sizing/style variants for buttons and icons
- Add mini indicator support through either richer `Progress` variants or simple shaped primitives

Why this phase second:

- It closes most remaining visual fidelity gaps for Calendar, Notes, Linear, Gmail, Music, and Camera Preview
- It lets widget authors reproduce the mock surfaces more closely before adding deeper native integrations

Widgets meaningfully advanced in this phase:

- Notes
- Calendar
- Linear
- Gmail
- Music
- Camera Preview

### Phase 3: Native generic capability APIs

- Add generic `audio`
- Add generic `media`
- Add generic `camera`

Why this phase third:

- These are narrower but deeper capabilities
- They are required for exact functional parity in Ambient Sounds, Music, and Camera Preview
- They should stay capability-level and reusable rather than widget-specific

Widgets meaningfully unlocked in this phase:

- Ambient Sounds
- Music
- Camera Preview

## Mandatory Capabilities Before Exact Parity Is Possible

These are non-negotiable blockers if the requirement is exact visual and functional parity with the mocks.

### Mandatory for broad parity across most widgets

- `ScrollView`
- `Divider`
- richer row/card/tile styling
- `storage`
- `fetch`
- `preferences`
- `timer`
- mask and fade support

Without these, exact parity is not possible for:

- Notes
- Pomodoro
- Calendar
- Linear
- Gmail

### Mandatory for media and device parity

- `Image`
- `audio`
- `media`
- `camera`
- overlay positioning support

Without these, exact parity is not possible for:

- Ambient Sounds
- Music
- Camera Preview

## Widget-by-Widget Generic Implementation Notes

### Capture

- Own item list and mutations in local state
- Persist through `storage`
- Render input plus checklist rows
- Treat the mic affordance as decorative until a generic audio/input capability exists, unless that capability is added intentionally

### Notes

- Own notes list and active editing state
- Persist through `storage`
- Render scrollable note cards with timestamp metadata

### Pomodoro

- Own session state
- Use `timer` to drive rerenders or expose elapsed time
- Render cycle dots, large timer text, and transport controls

### Ambient Sounds

- Own selection state and preset logic
- Use `audio` for play, pause, source selection, and intensity
- Render tiles as generic selectable containers

### Calendar

- Fetch agenda items through `calendar` or `fetch`
- Cache lightweight data in `storage`
- Render agenda rows with colored event bars and jump-out links through `openURL`

### Music

- Subscribe to or poll `media`
- Render artwork, title, transport controls, and progress

### Linear

- Fetch issues through `fetch`
- Read token and config through `preferences`
- Cache summaries through `storage`
- Use `openURL` for issue navigation

### Gmail

- Fetch message summaries through `fetch`
- Read auth/config through `preferences`
- Cache summaries through `storage`
- Use `openURL` for compose and message navigation

### Camera Preview

- Request frames or snapshot updates from `camera`
- Render into an image or preview surface
- Use overlay controls as generic positioned buttons
