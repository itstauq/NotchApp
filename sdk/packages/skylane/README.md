# skylane

CLI for developing and building Skylane widgets.

## Install

```bash
npm install --save-dev skylane
npm install @skylane/api
```

## Usage

Inside a widget package:

```bash
npx skylane dev
```

This starts the hot-reload workflow:

- builds the widget into `.skylane/build/index.cjs`
- registers the local widget with Skylane for development
- rebuilds when `package.json`, `src/`, or `assets/` change
- tells Skylane to reload the widget after each successful build

Other commands:

```bash
npx skylane build
npx skylane lint
```

## Widget Shape

A widget package needs:

- `package.json`
- `src/index.tsx`
- a `skylane` manifest in `package.json`

Example:

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

Skylane itself currently runs on macOS. The SDK source and examples live in the main repository:

<https://github.com/itstauq/Skylane>
