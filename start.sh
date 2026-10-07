#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"
/usr/bin/time -p pwd
PROJECT_ROOT="$(pwd)"
PORT="${PORT:-3000}"
DIST_DIR="$PROJECT_ROOT/dist"
WEB_DIR="${OPENCODE_WEB_DIR:-/home/runner/work/_temp/omgithub-web}"
/usr/bin/time -p mkdir -p "$DIST_DIR"
/usr/bin/time -p mkdir -p "$WEB_DIR"
/usr/bin/time -p test -f "$DIST_DIR/index.html"
/usr/bin/time -p ls -l "$DIST_DIR/index.html"
if /usr/bin/time -p test -f "$PROJECT_ROOT/package.json"; then
  if /usr/bin/time -p test -f "$PROJECT_ROOT/package-lock.json"; then
    /usr/bin/time -p npm ci --no-audit --no-fund
  else
    /usr/bin/time -p npm install --no-audit --no-fund
  fi
  if /usr/bin/time -p npm run --silent build --if-present; then
    /usr/bin/time -p test -f "$DIST_DIR/index.html"
  fi
else
  /usr/bin/time -p echo "no package.json: static dist, skipping install/build"
fi
/usr/bin/time -p bash -c "printf '%s' \"$PROJECT_ROOT\" | grep -q '^/home/runner/work/PlayGround/PlayGround'"
DEPLOY_JSON="{\"project\":\"$PROJECT_ROOT\",\"directory\":\"$DIST_DIR\"}"
/usr/bin/time -p bash -c "printf '%s' '$DEPLOY_JSON' > \"$WEB_DIR/deployment-output.json\""
/usr/bin/time -p cat "$WEB_DIR/deployment-output.json"
/usr/bin/time -p echo "serving $DIST_DIR on PORT=$PORT project=$PROJECT_ROOT"
/usr/bin/time -p python3 --version
exec /usr/bin/time -p python3 -m http.server "$PORT" --directory "$DIST_DIR" --bind 0.0.0.0
