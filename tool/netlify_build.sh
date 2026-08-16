#!/usr/bin/env bash
# Netlify build: Flutter web student app.
# Does NOT pass AI_API_KEY / ELEVENLABS_API_KEY into dart-define
# (those belong on Netlify Functions only).
set -euo pipefail

FLUTTER_VERSION="${FLUTTER_VERSION:-3.44.4}"
CACHE_DIR="${NETLIFY_CACHE_DIR:-$HOME/cache}"
FLUTTER_DIR="${CACHE_DIR}/flutter"

if [ ! -x "${FLUTTER_DIR}/bin/flutter" ]; then
  rm -rf "${FLUTTER_DIR}"
  git clone https://github.com/flutter/flutter.git \
    --branch "${FLUTTER_VERSION}" \
    --depth 1 \
    "${FLUTTER_DIR}"
fi

export PATH="${FLUTTER_DIR}/bin:${PATH}"
flutter config --enable-web --no-analytics
flutter --version
flutter pub get

DEFINES=()
if [ -n "${AI_MODEL:-}" ]; then
  DEFINES+=(--dart-define="AI_MODEL=${AI_MODEL}")
fi
if [ -n "${ELEVENLABS_MODEL:-}" ]; then
  DEFINES+=(--dart-define="ELEVENLABS_MODEL=${ELEVENLABS_MODEL}")
fi

flutter build web \
  -t lib/main.dart \
  --release \
  --no-web-resources-cdn \
  --no-tree-shake-icons \
  "${DEFINES[@]+"${DEFINES[@]}"}"
