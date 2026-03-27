#!/bin/bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")" && pwd)"
RUNTIME_ROOT="$REPO_ROOT/runtime"
WIDGETS_ROOT="$REPO_ROOT/widgets"
DEST_ROOT="${1:-}"

if [ -z "$DEST_ROOT" ]; then
  if [ -z "${TARGET_BUILD_DIR:-}" ] || [ -z "${UNLOCALIZED_RESOURCES_FOLDER_PATH:-}" ]; then
    echo "Usage: prebuild.sh <destination-root>" >&2
    exit 1
  fi
  DEST_ROOT="$TARGET_BUILD_DIR/$UNLOCALIZED_RESOURCES_FOLDER_PATH/WidgetRuntime"
fi

rm -rf "$DEST_ROOT"
mkdir -p "$DEST_ROOT/scripts" "$DEST_ROOT/widgets" "$DEST_ROOT/node/bin"

cp "$RUNTIME_ROOT/runtime-worker.mjs" "$DEST_ROOT/scripts/runtime-worker.mjs"
cp "$RUNTIME_ROOT/.build/tools/node/bin/node" "$DEST_ROOT/node/bin/node"

if [ -d "$WIDGETS_ROOT" ]; then
  for widget_dir in "$WIDGETS_ROOT"/*; do
    if [ ! -d "$widget_dir" ]; then
      continue
    fi

    if [ ! -f "$widget_dir/package.json" ]; then
      continue
    fi

    (
      cd "$widget_dir"
      "$RUNTIME_ROOT/runtime-launcher" build
    )

    widget_name="$(basename "$widget_dir")"
    cp -R "$widget_dir" "$DEST_ROOT/widgets/$widget_name"
  done
fi
