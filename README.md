# IMC Daily

Daily practice for the UKMT Intermediate Maths Challenge (27 January 2027).

- **Practice page:** https://lewiscodeswebsites.github.io/imc-revision/
- **iPhone app:** download the latest unsigned IPA from
  https://github.com/LewisCodesWebsites/imc-revision/releases/latest/download/IMCDaily.ipa
  and sign it with Feather.

The app loads the live page, so new topics appear without reinstalling. With no
internet it falls back to the copy bundled at build time.

## How it fits together

| Path | What it is |
| --- | --- |
| `web/page.html` | The practice page and all question generators |
| `web/head.html`, `web/foot.html` | Wrapper added around the page for hosting |
| `build-site.sh` | Assembles `_site/` |
| `ios/` | SwiftUI + WKWebView wrapper, generated with XcodeGen |
| `.github/workflows/pages.yml` | Publishes the page to GitHub Pages |
| `.github/workflows/ipa.yml` | Builds an unsigned IPA on a macOS runner and attaches it to a release |
