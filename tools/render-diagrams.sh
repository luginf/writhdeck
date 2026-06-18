#!/bin/sh
# Render every Mermaid source (media/*.mmd) to a PNG next to it.
#
# Requires mermaid-cli (mmdc) and a Chromium/Chrome for its headless renderer.
# Defaults to the install copied to /opt/mermaid-cli and the system google-chrome
# (see tools/puppeteer-chrome.json). Override with MMDC / PUPPETEER_CFG env vars.
#
#   sh tools/render-diagrams.sh        # or: make diagrams
set -e

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
MMDC=${MMDC:-/opt/mermaid-cli/node_modules/.bin/mmdc}
PUPPETEER_CFG=${PUPPETEER_CFG:-"$ROOT/tools/puppeteer-chrome.json"}

if [ ! -x "$MMDC" ]; then
    echo "mmdc not found at $MMDC (set MMDC=/path/to/mmdc)" >&2
    exit 1
fi

for src in "$ROOT"/media/*.mmd; do
    [ -e "$src" ] || continue
    out="${src%.mmd}.png"
    echo "Rendering $(basename "$src") -> $(basename "$out")"
    "$MMDC" -i "$src" -o "$out" -p "$PUPPETEER_CFG" -b white -s 2
done

echo "Done."
