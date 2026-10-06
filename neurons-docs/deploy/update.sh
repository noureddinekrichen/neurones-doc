#!/usr/bin/env bash
# Pull the latest documentation, build it with Hugo and publish it.
# Run on the server as root:   /var/www/neurones-doc/neurons-docs/deploy/update.sh
#
# The build happens in a temporary directory; the live site is only replaced
# if the build succeeds.
set -euo pipefail

REPO="${REPO:-/var/www/neurones-doc}"        # git clone of the repository
SITE_SRC="$REPO/neurons-docs"                # Hugo project inside the repository
WEB_ROOT="${WEB_ROOT:-/var/www/neurons-docs}" # directory served by nginx at /neurons/

command -v hugo  >/dev/null || { echo "hugo not found: run deploy/install-hugo.sh first" >&2; exit 1; }
command -v rsync >/dev/null || { echo "rsync not found: dnf install -y rsync" >&2; exit 1; }

echo "==> Pulling $REPO"
git -C "$REPO" pull --ff-only

echo "==> Building"
BUILD="$(mktemp -d)"
trap 'rm -rf "$BUILD"' EXIT
hugo --source "$SITE_SRC" --destination "$BUILD" --minify --cleanDestinationDir

echo "==> Publishing to $WEB_ROOT"
mkdir -p "$WEB_ROOT"
rsync -a --delete "$BUILD/" "$WEB_ROOT/"
chown -R root:root "$WEB_ROOT"
find "$WEB_ROOT" -type d -exec chmod 755 {} +
find "$WEB_ROOT" -type f -exec chmod 644 {} +
if command -v restorecon >/dev/null && [ "$(getenforce 2>/dev/null)" != "Disabled" ]; then
  restorecon -R "$WEB_ROOT"
fi

echo "==> Done: $(git -C "$REPO" log -1 --format='%h %s')"
