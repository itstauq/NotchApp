# NotchApp

NotchApp is a productivity app that turns your MacBook notch into an always-available widget hub.

## Features

- expand the notch into a larger interactive surface
- create multiple views and organize widgets across them
- choose from a carefully crafted set of built-in widgets
- build your own using a Raycast-inspired extensions API (coming soon)

## Requirements

- macOS 14+
- Xcode 15+

## Run

```bash
./run.sh
```

This script builds the app in Debug and launches `NotchApp`.

You can also open [NotchApp.xcodeproj](/Users/tauquir/Projects/NotchApp2/NotchApp.xcodeproj) in Xcode and run the `NotchApp` scheme directly.

## Project Structure

- [NotchApp/NotchAppApp.swift](/Users/tauquir/Projects/NotchApp2/NotchApp/NotchAppApp.swift): app entry point and notch/window lifecycle
- [NotchApp/NotchContentView.swift](/Users/tauquir/Projects/NotchApp2/NotchApp/NotchContentView.swift): expanded notch UI
- [NotchApp/ViewSwitcher.swift](/Users/tauquir/Projects/NotchApp2/NotchApp/ViewSwitcher.swift): tab strip, selection, and reordering
- [NotchApp/SavedViews.swift](/Users/tauquir/Projects/NotchApp2/NotchApp/SavedViews.swift): saved view model and ordering logic
- [NotchApp/NotchPanel.swift](/Users/tauquir/Projects/NotchApp2/NotchApp/NotchPanel.swift): panel behavior
- [NotchApp/NotchViewModel.swift](/Users/tauquir/Projects/NotchApp2/NotchApp/NotchViewModel.swift): hover, expansion, and pinned state

## License

Apache 2.0. See [LICENSE](/Users/tauquir/Projects/NotchApp2/LICENSE).
