#!/usr/bin/env bash
# Install (or upgrade to) the Hugo version this project is built with, on Linux x86_64.
# Run as root:   /var/www/neurones-doc/neurons-docs/deploy/install-hugo.sh
# The download is verified against the official checksum file before installing.
set -euo pipefail

HUGO_VERSION="${HUGO_VERSION:-0.167.0}"
ASSET="hugo_${HUGO_VERSION}_linux-amd64.tar.gz"
BASE="https://github.com/gohugoio/hugo/releases/download/v${HUGO_VERSION}"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
cd "$TMP"

echo "==> Downloading Hugo ${HUGO_VERSION}"
curl -fsSLO "$BASE/$ASSET"
curl -fsSL "$BASE/hugo_${HUGO_VERSION}_checksums.txt" | grep " ${ASSET}\$" > checksum.txt
sha256sum -c checksum.txt

tar -xzf "$ASSET" hugo
install -m 755 hugo /usr/local/bin/hugo
echo "==> Installed: $(/usr/local/bin/hugo version)"
