#!/usr/bin/env bash
# Assembles the web page and the question engine into _site/.
# Used by the Pages workflow and by the iOS workflow (which bundles engine.js as an offline copy).
set -euo pipefail
cd "$(dirname "$0")"
rm -rf _site && mkdir -p _site
cat web/head.html web/page.html web/foot.html > _site/index.html
# engine.js = the question generators from page.html (between the GEN markers) + the app API.
python3 - <<'PY'
src = open('web/page.html', encoding='utf-8').read()
gen = src.split('/*GEN-START*/', 1)[1].split('/*GEN-END*/', 1)[0]
api = open('tools/engine-api.js', encoding='utf-8').read()
open('_site/engine.js', 'w', encoding='utf-8').write('"use strict";\n' + gen + api)
PY
cp web/manifest.webmanifest web/papers.json web/*.png _site/
touch _site/.nojekyll
echo "Built _site/index.html and _site/engine.js"
