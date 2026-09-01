#!/usr/bin/env bash
# Netlify build: Flutter web Admin Panel.
# Does NOT pass AI_API_KEY / ELEVENLABS_API_KEY / VERTEX_* into dart-define
# (those belong on Student Netlify Functions only).
#
# Flutter outputs to build/web3 (separate from the Student build/web).
# CLASSROOM_VIDEO_WORKER points Admin /ai/* and /rag/* at the Student site.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "${ROOT}"

FLUTTER_VERSION="${FLUTTER_VERSION:-3.44.4}"
CACHE_DIR="${NETLIFY_CACHE_DIR:-$HOME/cache}"
FLUTTER_DIR="${CACHE_DIR}/flutter"
WORKER="${CLASSROOM_VIDEO_WORKER:-https://mpscaisathi.co.in}"
OUT_DIR="${ROOT}/build/web3"

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

DEFINES=(
  --dart-define="CLASSROOM_VIDEO_WORKER=${WORKER}"
)
if [ -n "${AI_MODEL:-}" ]; then
  DEFINES+=(--dart-define="AI_MODEL=${AI_MODEL}")
fi
if [ -n "${ELEVENLABS_MODEL:-}" ]; then
  DEFINES+=(--dart-define="ELEVENLABS_MODEL=${ELEVENLABS_MODEL}")
fi

flutter build web \
  -t lib/admin_main.dart \
  --release \
  --no-web-resources-cdn \
  --no-tree-shake-icons \
  --output="${OUT_DIR}" \
  "${DEFINES[@]+"${DEFINES[@]}"}"

# SPA fallback for the Admin host (not shipped in the Student web/ folder).
printf '%s\n' '/*    /index.html   200' > "${OUT_DIR}/_redirects"
