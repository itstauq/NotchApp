# Widget Development

Build Skylane widgets with `skylane` and `@skylane/api`.

This guide is organized around the way most widgets are actually built:

1. create a widget package
2. run the hot-reload workflow
3. build UI with the component-first SDK
4. choose the right state model
5. add host-managed features such as preferences and notifications

If you are new to Skylane, read this file top to bottom once. After that, it works well as a reference.

## Quick Start

Install the SDK in your widget package:

```bash
npm install --save-dev skylane
npm install @skylane/api
```

Recommended package layout:

```text
my-widget/
  package.json
  assets/
  src/
    index.tsx
```

Example `package.json`:

```json
{
  "name": "@acme/skylane-widget-hello",
  "private": true,
  "scripts": {
    "dev": "skylane dev",
    "build": "skylane build",
    "lint": "skylane lint"
  },
  "devDependencies": {
    "skylane": "^0.1.0"
  },
  "dependencies": {
    "@skylane/api": "^0.1.0"
  },
  "skylane": {
    "id": "com.acme.hello",
    "title": "Hello",
    "icon": "sparkles",
    "minSpan": 3,
    "maxSpan": 6,
    "entry": "src/index.tsx"
  }
}
```

Start the development loop inside the widget directory:

```bash
npx skylane dev
```

Or:

```bash
npm run dev
```

`skylane dev`:

- builds your widget into `.skylane/build/index.cjs`
- copies package-local assets into `.skylane/build/assets`
- registers the local widget with Skylane for development
- watches `package.json`, `src/`, and `assets/`
- rebuilds and reloads the widget whenever you save

Create a production build with:

```bash
npx skylane build
```

Validate the manifest and entry file with:

```bash
npx skylane lint
```

## Build Your First Widget

Each widget needs:

- a `default` export that renders the widget
- a `skylane` manifest in `package.json`
- any state it needs through React hooks or `@skylane/api`

The recommended authoring style is component-first. Reach for `Card`, `Field`, `List`, `EmptyState`, `Toolbar`, and `DropdownMenu` first. Use low-level primitives such as `RoundedRect`, `Circle`, `Stack`, and `Inline` only when you intentionally need bespoke layout or presentation.

Example:

```tsx
import {
  Button,
  Card,
  CardContent,
  CardDescription,
  CardTitle,
  Field,
  Input,
  Section,
  useLocalStorage,
} from "@skylane/api";

export default function Widget({ environment }) {
  const [draft, setDraft] = useLocalStorage("draft", "");

  return (
    <Section spacing="md">
      <Card>
        <CardContent>
          <CardTitle>Hello from Skylane</CardTitle>
          <CardDescription>{`Span ${environment.span} • Draft ${draft.length}`}</CardDescription>
        </CardContent>
      </Card>

      <Field>
        <Input
          value={draft}
          placeholder="Capture a note"
          onValueChange={setDraft}
        />
      </Field>

      <Button title="Clear" variant="secondary" onClick={() => setDraft("")} />
    </Section>
  );
}
```

The render function receives `environment`. In practice, `environment.span` is the most useful field because it lets the widget adapt to narrow and wide layouts.

Standard components already resolve against the widget theme. Use `useTheme()` when you need advanced customization or when you are intentionally building something bespoke.

## Event And Callback Style

Widget callbacks can use the low-level host event names:

- `Button`, `Row`, `Checkbox`, and `IconButton` use `onPress`
- `Input` uses `onChange` and `onSubmit`, which receive `{ value }`
- `DropdownMenuItem` and `DropdownMenuCheckboxItem` also use `onPress`

For normal widget code, prefer the React-style aliases:

- `onClick` for buttons, rows, list items, icon buttons, and menu items
- `onCheckedChange` for `Checkbox` and `DropdownMenuCheckboxItem`
- `onValueChange` and `onSubmitValue` for `Input`

## Choose The Right State Model

Skylane widgets usually use four different kinds of state. Picking the right one early keeps the widget simple.

### React State

Use normal React state for transient UI values:

- open menus
- temporary input drafts
- in-memory loading states
- optimistic UI that does not need to survive reloads

### LocalStorage

Use `useLocalStorage()` for widget-owned persisted state:

- counters
- recent widget data
- dismissed UI state
- timer state that belongs to the widget itself

Example:

```tsx
import { Button, Description, Section, useLocalStorage } from "@skylane/api";

export default function Widget() {
  const [count, setCount] = useLocalStorage("count", 0);

  return (
    <Section spacing="md">
      <Description tone="secondary">{`Count: ${count}`}</Description>
      <Button title="Increment" onClick={() => setCount((current) => current + 1)} />
    </Section>
  );
}
```

`LocalStorage` is private to widget code. It is not the same thing as manifest preferences.

### Preferences

Use manifest preferences for user configuration values that Skylane should own:

- API tokens
- account identifiers
- display modes
- labels and default choices the user expects to edit in Settings

Preferences are:

- declared under `skylane.preferences`
- read with `usePreference("name")`
- resolved before widget code sees them
- stored per widget instance
- separate from `LocalStorage`

Preference values resolve in this order:

1. saved value for this widget instance
2. manifest `default`
3. `undefined`

Example:

```tsx
import { Description, Image, Section, usePreference } from "@skylane/api";

export default function Widget() {
  const [imageUrl] = usePreference("imageUrl");
  const [caption] = usePreference("caption");

  return (
    <Section spacing="sm">
      <Image src={imageUrl} contentMode="fit" />
      <Description tone="secondary">{caption ?? "Remote image"}</Description>
    </Section>
  );
}
```

If a preference has `required: true` and still resolves to no usable value:

- the widget does not render normally in the compact surface
- Skylane shows a host `Configuration Required` state
- the user can open that widget instance's settings from there

For required text-like fields, empty strings count as missing.

### Notifications

Use widget notifications when the host should deliver a macOS alert on the widget's behalf. Typical examples:

- Pomodoro completion reminders
- countdown or deadline alerts
- "come back to this" reminders for a workflow widget

Notifications are host-managed, not widget-managed. The widget requests schedule and cancel actions, while Skylane owns:

- permission prompts
- system notification delivery
- foreground suppression when the widget is already visible
- click routing back into Skylane
- global and per-instance notification settings

To opt in, declare notification support in the manifest:

```json
{
  "skylane": {
    "id": "com.acme.pomodoro",
    "title": "Pomodoro",
    "icon": "timer",
    "minSpan": 3,
    "maxSpan": 6,
    "entry": "src/index.tsx",
    "capabilities": {
      "notifications": {}
    }
  }
}
```

`capabilities.notifications` is optional. If it is missing, the widget cannot schedule notifications.

In widget code, use `scheduleNotification()` and `cancelNotification()`:

```tsx
import {
  Button,
  Description,
  Section,
  cancelNotification,
  scheduleNotification,
} from "@skylane/api";

const COMPLETION_NOTIFICATION_ID = "session-complete";

export default function Widget() {
  async function startTimer() {
    await scheduleNotification(COMPLETION_NOTIFICATION_ID, {
      title: "Focus complete",
      body: "Time for a short break.",
      deliverAtMs: Date.now() + 25 * 60 * 1000,
    });
  }

  async function resetTimer() {
    await cancelNotification(COMPLETION_NOTIFICATION_ID);
  }

  return (
    <Section spacing="md">
      <Description tone="secondary">
        Schedule one stable notification id per reminder you want to manage.
      </Description>
      <Button title="Start focus session" onClick={startTimer} />
      <Button title="Reset" variant="secondary" onClick={resetTimer} />
    </Section>
  );
}
```

Important behavior:

- notification ids are scoped to the widget instance
- scheduling the same id again replaces the earlier pending request for that widget instance
- Skylane asks for notification permission lazily on the first delivery attempt
- notifications are silent by default
- clicking a notification opens Skylane to the relevant widget when possible
- if Skylane is active and the widget is already visible, the host suppresses the system banner

Best practices:

- use stable ids such as `"session-complete"` instead of generating random ids
- schedule again when the delivery time or message changes
- cancel when the underlying reminder is no longer relevant
- keep titles short and bodies optional

Users control notifications in two places:

- General settings contains the global widget notifications switch
- Widget settings contains the per-instance notification switch for widgets that declare support

### Events

Use widget events when the host should read calendar data on the widget's behalf through EventKit. Typical examples:

- compact agenda widgets
- "next meeting" widgets
- planning widgets that filter by calendar

Events are host-managed and query-based, not widget-managed. The widget requests normalized calendar metadata or event occurrences, while Skylane owns:

- EventKit permission handling
- loading and normalizing calendar metadata
- fetching event occurrences within a time window
- invalidating stale data when the system calendar database changes
- opening Calendar or jumping to the relevant event time

To opt in, declare events support in the manifest:

```json
{
  "skylane": {
    "id": "com.acme.agenda",
    "title": "Agenda",
    "icon": "calendar",
    "minSpan": 3,
    "maxSpan": 6,
    "entry": "src/index.tsx",
    "capabilities": {
      "events": {
        "access": "fullAccess"
      }
    }
  }
}
```

`capabilities.events` is optional. If it is missing, the widget cannot call the host events RPCs.

In widget code, use `useEvents()` and `useEventCalendars()`:

```tsx
import { Button, Text, useEventCalendars, useEvents } from "@skylane/api";

export default function Widget() {
  const events = useEvents({
    startMs: Date.now(),
    endMs: Date.now() + 6 * 60 * 60 * 1000,
    includeAllDay: true,
    limit: 5,
  });
  const calendars = useEventCalendars();

  if (events.authorizationStatus === "notDetermined") {
    return <Button title="Connect Calendar" onClick={() => events.requestAccess()} />;
  }

  return (
    <>
      <Text variant="body">{events.items[0]?.title ?? "No upcoming events"}</Text>
      <Text variant="caption">{`Calendars: ${calendars.items.length}`}</Text>
    </>
  );
}
```

Important behavior:

- v1 is read-only; widgets can read event data but not create or edit events
- `fullAccess` is required to read events and calendars
- `writeOnly` is modeled for future compatibility but does not unlock readable event data
- rendering a widget never auto-prompts for calendar permission
- call `requestAccess()` from a user-visible CTA such as "Connect Calendar"
- `useEvents()` refetches the current query after the host invalidates event data
- `useEventCalendars()` returns normalized calendar metadata for filters, legends, and settings UIs

### Audio

Use widget audio when the host should play bundled local sound assets on the widget's behalf. Typical examples:

- ambient loop mixers
- focus timers with short bundled chimes
- utility widgets with subtle local sound beds

Audio playback is host-managed, not widget-managed. The widget requests per-player playback actions, while Skylane owns:

- loading bundled asset files from the widget build output
- concurrent playback for multiple named players in one widget instance
- loop behavior
- pause, resume, stop, and per-player volume changes

To opt in, declare audio support in the manifest:

```json
{
  "skylane": {
    "id": "com.acme.ambient",
    "title": "Ambient",
    "icon": "speaker.wave.2.fill",
    "minSpan": 4,
    "maxSpan": 4,
    "entry": "src/index.tsx",
    "capabilities": {
      "audio": {}
    }
  }
}
```

`capabilities.audio` is optional. If it is missing, the widget cannot call the host audio RPCs.

In widget code, use `useAudio()`:

```tsx
import { Button, Text, useAudio } from "@skylane/api";

export default function Widget() {
  const audio = useAudio();

  return (
    <>
      <Text variant="body">{audio.playbackState}</Text>
      <Button
        title="Rain"
        onClick={() =>
          audio.play({
            playerId: "rain",
            src: "assets/rain.wav",
            loop: true,
            volume: 0.6,
          })
        }
      />
      <Button title="Pause All" variant="secondary" onClick={() => audio.pauseAll()} />
    </>
  );
}
```

Important behavior:

- audio player ids are scoped to the widget instance
- `play()` creates or reuses one named player per `playerId`
- sources must be widget-relative bundled asset paths such as `assets/rain.wav`
- only bundled local assets are supported in v1, not remote URLs
- `pauseAll()` and `resumeAll()` preserve the current player set and per-player volumes
- `stop()` removes one player and `stopAll()` clears the widget instance's entire audio session

## Manifest

Each widget declares a `skylane` block in `package.json`.

Required fields:

- `id`
- `title`
- `icon`
- `minSpan`
- `maxSpan`

Optional fields:

- `description`
- `theme`
- `entry`
- `preferences`
- `capabilities`

`entry` defaults to `src/index.tsx`.

`theme` lets a widget opt into a curated platform theme. The resolved theme is exposed through `useTheme()`. Supported values today:

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
- `pink`

`capabilities` is where a widget declares access to host-managed APIs. Current capability keys:

- `audio`
- `notifications`
- `events`

Example manifest with preferences plus audio and notifications:

```json
{
  "name": "@acme/skylane-widget-focus",
  "private": true,
  "scripts": {
    "dev": "skylane dev",
    "build": "skylane build",
    "lint": "skylane lint"
  },
  "devDependencies": {
    "skylane": "^0.1.0"
  },
  "dependencies": {
    "@skylane/api": "^0.1.0"
  },
  "skylane": {
    "id": "com.acme.focus",
    "title": "Focus",
    "description": "A configurable focus timer",
    "icon": "timer",
    "theme": "orange",
    "minSpan": 3,
    "maxSpan": 6,
    "entry": "src/index.tsx",
    "capabilities": {
      "audio": {},
      "notifications": {}
    },
    "preferences": [
      {
        "name": "durationMinutes",
        "title": "Duration",
        "description": "Length of one focus session in minutes.",
        "type": "textfield",
        "default": "25"
      },
      {
        "name": "autoStartBreak",
        "title": "Auto-start break",
        "label": "Start the break timer automatically",
        "type": "checkbox",
        "default": true
      }
    ]
  }
}
```

Current validation rules:

- `id` and `title` must be non-empty
- `minSpan` and `maxSpan` must be integers
- `minSpan` must be greater than `0`
- `maxSpan` must be greater than or equal to `minSpan`
- the entry file must exist
- the host currently supports up to `12` columns

### Supported Preference Fields

Use these field names exactly:

- `name`
- `title`
- `description`
- `type`
- `required`
- `placeholder`
- `default`
- `label` for `checkbox`
- `data` for `dropdown`

Supported preference `type` values today:

- `textfield`
- `password`
- `checkbox`
- `dropdown`
- `camera`

## UI System

The primary UI surface in `@skylane/api` is organized around product components:

- cards: `Card`, `CardHeader`, `CardTitle`, `CardDescription`, `CardContent`, `CardFooter`
- sections: `Section`, `SectionHeader`, `SectionTitle`, `SectionDescription`
- lists: `List`, `ListItem`, `ListItemTitle`, `ListItemDescription`, `ListItemAction`
- forms: `Field`, `Label`, `Description`, `Input`, `Checkbox`
- utility UI: `EmptyState`, `Badge`, `Toolbar`, `ToolbarButton`
- menus: `DropdownMenu`, `DropdownMenuTriggerButton`, `DropdownMenuItem`, `DropdownMenuCheckboxItem`, `DropdownMenuLoadingItem`, `DropdownMenuErrorItem`, `DropdownMenuSeparator`

Text uses `variant` instead of `role`. Supported variants are:

- `title`
- `subtitle`
- `body`
- `caption`
- `label`
- `placeholder`

Use `tone` for semantic meaning only:

- `primary`
- `secondary`
- `tertiary`
- `accent`
- `success`
- `warning`
- `destructive`
- `onAccent`

Variants on standard controls are intentionally opinionated:

- `Button`: `default`, `secondary`, `outline`, `ghost`, `destructive`
- `IconButton`: `default`, `secondary`, `ghost`, `destructive`
- `Card`: `default`, `secondary`, `accent`, `ghost`

When you need bespoke composition, use `useTheme().colors` as a small semantic palette instead of introducing widget-local color constants.

The canonical token list, component mapping, and mock-widget theme family mapping live in [widget-theme-mapping.md](./widget-theme-mapping.md).

Examples:

- [list-form](../examples/list-form)
- [media-player](../examples/media-player)
- [settings-menu](../examples/settings-menu)
- [widget-ui.md](./widget-ui.md)
- [widget-theme-mapping.md](./widget-theme-mapping.md)

## Images And Host APIs

`Image` supports both package-local assets and remote `https://` URLs.

For local images, place files under `assets/` and reference them with package-relative paths such as `src="assets/cover.png"`.

`skylane build` and `skylane dev` copy `assets/` into `.skylane/build/assets`, so the same path works in development and packaged installs.

Remote image URLs are fetched by the host image pipeline, not by widget code:

- only `https://` is supported
- requests are anonymous
- custom headers, cookies, and auth are not supported yet

Other host-backed APIs available through `@skylane/api`:

- `useCameras()` for camera selection
- `useAudio()` for bundled local audio playback
- `useMedia()` for now-playing data and transport controls
- `useEvents()` for query-based calendar event occurrences
- `useEventCalendars()` for calendar metadata and filter UIs
- `useFetch()` and `usePromise()` for advanced async flows
- `openURL()` for opening external links

## Configure In Skylane

Widget preferences and per-instance notification settings are edited inside Skylane:

1. open Settings
2. go to `Widgets`
3. select the widget instance from the mirrored panel preview
4. update the instance-specific settings

Text and password fields save on Enter or when focus leaves the field. Toggles and dropdowns save immediately.

## Troubleshooting

If the widget shows `Configuration Required`:

- make sure all required preferences are filled in
- for required text or password fields, an empty string still counts as missing
- check that dropdown defaults or saved values exist in the declared `data`

If notifications do not fire:

- make sure the widget declares `skylane.capabilities.notifications`
- make sure widget notifications are enabled globally in General settings
- make sure notifications are enabled for that widget instance in Widget settings

If bundled audio does not play:

- make sure the widget declares `skylane.capabilities.audio`
- make sure the files live under `assets/`
- make sure the widget uses widget-relative asset paths such as `assets/rain.wav`
- make sure Skylane has notification permission in macOS System Settings
- make sure the widget uses a stable id and a future `deliverAtMs`

If a remote image does not load:

- make sure the URL is `https://`
- make sure the response is actually an image

If `skylane lint` fails:

- verify the `skylane` manifest block exists
- verify `entry` points to a real file
- verify preference definitions use supported field names and types
