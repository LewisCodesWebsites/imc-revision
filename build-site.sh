#!/usr/bin/env bash
# Assembles the web page into _site/ (used by the Pages and iOS workflows).
set -euo pipefail
cd "$(dirname "$0")"
rm -rf _site && mkdir -p _site
cat web/head.html web/page.html web/foot.html > _site/index.html
cp web/manifest.webmanifest web/*.png _site/
touch _site/.nojekyll
echo "Built _site/index.html"
