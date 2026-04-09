# Camera Preview

Live camera widget for Skylane.

It uses the host-provided `Camera` primitive from `@skylane/api`, so the
widget itself only defines presentation:

- rounded live preview surface
- subtle glare overlay
- top-right and bottom corner action badges

The actual camera access, permission flow, and native rendering are handled by
the Skylane host.

## Notes

- The first time you use it, the widget shows a permission prompt instead of
  opening the system camera dialog immediately.
- If camera access is denied, the widget keeps an actionable fallback so the
  user can jump to System Settings and re-enable it.
- This widget is bundled with the app and seeded into the default Home layout
  for fresh installs.
