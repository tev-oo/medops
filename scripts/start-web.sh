#!/bin/sh
set -eu

export PROMETHEUS_MULTIPROC_DIR=/tmp/medops-prometheus

mkdir -p "$PROMETHEUS_MULTIPROC_DIR"

# Clear previous Gunicorn-run metrics.
find "$PROMETHEUS_MULTIPROC_DIR" \
  -maxdepth 1 -type f -delete

exec gunicorn config.wsgi:application \
  --config gunicorn.conf.py \
  --bind "${GUNICORN_BIND:-0.0.0.0:8000}" \
  --workers 2 \
  --timeout 30 \
  --access-logfile - \
  --error-logfile -
