# IMC Daily

Daily practice for the UKMT Intermediate Maths Challenge (27 January 2027).

- **Practice page:** https://lewiscodeswebsites.github.io/imc-revision/
- **iPhone app:** download the latest unsigned IPA from
  https://github.com/LewisCodesWebsites/imc-revision/releases/latest/download/IMCDaily.ipa
  and sign it with Feather.

The iPhone app is native SwiftUI. Questions come from `engine.js`, which the app
downloads from GitHub Pages and runs with JavaScriptCore (no web view). New topics
and question types arrive without reinstalling. The last downloaded engine is kept
for offline use, and a copy is bundled in the app as a fallback.

## How it fits together

| Path | What it is |
| --- | --- |
| `web/page.html` | The web practice page and all question generators (between the GEN markers) |
| `tools/engine-api.js` | JSON API added to the generators to make `engine.js` for the app |
| `web/head.html`, `web/foot.html` | Wrapper added around the page for hosting |
| `build-site.sh` | Assembles `_site/` |
| `ios/` | Native SwiftUI app, generated with XcodeGen |
| `.github/workflows/pages.yml` | Publishes the page to GitHub Pages |
| `.github/workflows/ipa.yml` | Builds an unsigned IPA on a macOS runner and attaches it to a release |
