#!/bin/bash
set -e
DERIVED_DATA_PATH="$PWD/.build/DerivedData"
APP_PATH="$DERIVED_DATA_PATH/Build/Products/Debug/NotchApp.app"

xcodebuild \
  -project NotchApp.xcodeproj \
  -scheme NotchApp \
  -configuration Debug \
  -derivedDataPath "$DERIVED_DATA_PATH" \
  build 2>&1 | grep -E "(error:|warning:|BUILD)" | tail -10

OLD_PIDS=$(pgrep -x NotchApp 2>/dev/null || true)
if [ -n "$OLD_PIDS" ]; then
  pkill -x NotchApp 2>/dev/null || true

  for pid in $OLD_PIDS; do
    while kill -0 "$pid" 2>/dev/null; do
      sleep 0.5
    done
  done
fi

open "$APP_PATH"
echo "Running. Logs: tail -f notchapp.log"
