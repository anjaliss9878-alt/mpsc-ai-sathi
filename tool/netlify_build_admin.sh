#!/usr/bin/env bash
# Netlify build: Flutter web Admin Panel.
# Does NOT pass AI_API_KEY / VERTEX_* into dart-define
# (those belong on Student Netlify Functions only).
#
# Flutter outputs to build/web3 (separate from the Student build/web).
# RAG_BACKEND_URL (preferred) / CLASSROOM_VIDEO_WORKER point Admin /ai/*
# and /rag/* at the Student Netlify site that already hosts those functions.
# Never dart-define AI_API_KEY / GEMINI / VERTEX secrets into the Admin bundle.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "${ROOT}"

FLUTTER_VERSION="${FLUTTER_VERSION:-3.44.4}"
CACHE_DIR="${NETLIFY_CACHE_DIR:-$HOME/cache}"
FLUTTER_DIR="${CACHE_DIR}/flutter"
WORKER="${RAG_BACKEND_URL:-${CLASSROOM_VIDEO_WORKER:-https://mpscaisathi.co.in}}"
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
  --dart-define="RAG_BACKEND_URL=${WORKER}"
  --dart-define="CLASSROOM_VIDEO_WORKER=${WORKER}"
)
if [ -n "${AI_MODEL:-}" ]; then
  DEFINES+=(--dart-define="AI_MODEL=${AI_MODEL}")
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
