# Widget Theme Mapping

This is the canonical reference for the widget theme system.

This document tracks three things:

- the public semantic theme tokens exposed through `useTheme()`
- how the runtime and SDK map those tokens onto components
- how the old mock widget palettes map onto the current theme families

The goal is a smaller, more opinionated theme API for widget authors, closer to shadcn-ui, Radix, and Tailwind semantics:

- pick a theme family
- use semantic components first
- when you need bespoke composition, use a small semantic palette instead of many near-duplicate renderer tokens

## Public Theme Tokens

`useTheme().colors` now exposes this palette:

- `background`
- `foreground`
- `card`
- `cardForeground`
- `popover`
- `popoverForeground`
- `primary`
- `primaryForeground`
- `secondary`
- `secondaryForeground`
- `muted`
- `mutedForeground`
- `accent`
- `accentForeground`
- `success`
- `warning`
- `destructive`
- `destructiveForeground`
- `border`
- `input`
- `ring`

Intended roles:

- `primary`: solid accent call-to-action color
- `accent`: soft accent-tinted surface
- `secondary`: neutral translucent control surface
- `muted`: the faintest neutral surface
- `foreground` / `mutedForeground`: content hierarchy
- `card` / `popover`: container surfaces
- `border` / `input` / `ring`: structural chrome

## Runtime Mapping

Current runtime and SDK usage maps cleanly onto those tokens:

- `Card`
  - default: `card` + `border`
  - secondary: `secondary` + `border`
  - accent: `accent` + `ring`
  - ghost: transparent + `border`
- `Button`
  - primary: `primary` + `primaryForeground`
  - secondary: `secondary` + `secondaryForeground`
  - outline: transparent + `border` + `foreground`
  - ghost: transparent + `foreground`
  - destructive: `destructive` + `destructiveForeground`
- `Row`
  - default: `secondary`
  - accent: `accent`
  - ghost: transparent
- `IconButton`
  - primary: `primary` + `primaryForeground`
  - secondary: `secondary` + `secondaryForeground`
  - subtle: `accent` + `accentForeground`
  - ghost: transparent
  - destructive: `destructive` + `destructiveForeground`
- `Checkbox`
  - checked: `primary` + `ring` + `primaryForeground`
  - unchecked: transparent + `border`
- `Input`
  - background: `card`
  - border: `input`
  - trailing accessory plate: `muted`
  - text: `foreground`
- `Badge`
  - default: `accent` + `ring` + `accentForeground`
  - secondary: `secondary` + `border` + `secondaryForeground`
  - outline: transparent + `border` + `secondaryForeground`
- `DropdownMenuTriggerButton` overlay appearance
  - `popover` + `popoverForeground`
- `Camera`
  - `background`

Text and icon tones remain intentionally narrow:

- `primary`
- `secondary`
- `tertiary`
- `accent`
- `success`
- `warning`
- `destructive`
- `onAccent`

`onAccent` remains as the tone name for compatibility, but it resolves from `primaryForeground`.

## Old To New Token Mapping

This is the migration path from the older wide theme object to the current smaller one:

| Old token | New token |
| --- | --- |
| `surfaceCanvas` | `background` |
| `surfacePrimary` | `card` |
| `surfaceSecondary` | `secondary` |
| `surfaceControlSecondary` | `secondary` |
| `surfaceTertiary` | `muted` |
| `surfaceAccent` | `accent` |
| `surfaceOverlay` | `popover` |
| `borderPrimary` | `border` |
| `borderSecondary` | `border` |
| `borderAccent` | `ring` |
| `textEmphasis` | `foreground` |
| `textPrimary` | `foreground` / `cardForeground` by context |
| `textSecondary` | `mutedForeground` |
| `textTertiary` | `mutedForeground` with lower opacity |
| `textPlaceholder` | `mutedForeground` with lower opacity |
| `textOnAccent` | `primaryForeground` |
| `iconPrimary` | `foreground` / `popoverForeground` by context |
| `iconSecondary` | `secondaryForeground` or `mutedForeground` by context |
| `iconTertiary` | `mutedForeground` with lower opacity |
| `iconControlSecondary` | `secondaryForeground` |
| `iconOnAccent` | `primaryForeground` |

## Mock Widget Palette Lineage

### Initial placeholder mock widgets

Commit `137cba3` used placeholder families before the final named widgets:

| Mock | Accent |
| --- | --- |
| `mockAlpha` | `#75ADFA` |
| `mockBeta` | `#FCA360` |
| `mockGamma` | `#B894FA` |
| `mockDelta` | `#5EDBB8` |
| `mockEpsilon` | `#F5C759` |
| `mockPhi` | `#FA80A1` |
| `mockGammaAlt` | `#85E0F5` |

### Final named mock widgets

Commits `de68196`, `8b64713`, and `88688469eb510fa87ff8b238c2babe349fa84595` converge on this named palette:

| Widget | Mock accent | Theme family |
| --- | --- | --- |
| Capture / Inbox | `#FA757A` | `pink` |
| Pomodoro | `#FCAD59` | `amber` |
| Calendar | `#63ADFA` | `blue` |
| Camera Preview | `#8FADF5` | `periwinkle` |
| Ambient Sounds | `#75D1B8` | `green` |
| Music | `#B08AFA` | `indigo` |
| Notes | `#8AC2FA` | `cyan` |
| Linear | `#B894FA` | `violet` |
| Gmail | `#F5757A` | `pink` |

## Implemented Theme Families

The runtime now supports all previously-available theme names plus the extra mock families:

- `neutral`
- `amber`
- `blue`
- `cyan`
- `emerald`
- `fuchsia`
- `green`
- `indigo`
- `lime`
- `orange`
- `periwinkle`
- `pink`
- `violet`

Notes:

- `pink`, `amber`, `blue`, `green`, `indigo`, and `cyan` already cover most of the named mocks exactly
- `periwinkle` and `violet` were added specifically so Camera Preview and Linear can land pixel-perfect instead of being approximated
- `lime` now remains a distinct family instead of sharing the same accent as `emerald`

## Visual Pattern From The Mock Widgets

Across the named mock widgets, the palette logic is consistent:

- near-black canvas background
- bright white primary content
- softer white supporting copy
- translucent white secondary controls
- one strong theme-specific CTA color
- one softer accent-tinted surface derived from that CTA color

That means the right abstraction is not widget-specific color slots. It is:

1. a small semantic palette
2. a good theme family choice
3. semantic components first
4. bespoke low-level composition only when the layout itself is unique

## Recommendation

When implementing the remaining mock widgets:

1. choose the closest theme family first
2. use semantic components and variants before raw primitives
3. if a custom layout still needs low-level color access, stay inside the public palette above
4. only add a new theme family when the mock accent itself is materially different, not when a single widget needs custom layout
