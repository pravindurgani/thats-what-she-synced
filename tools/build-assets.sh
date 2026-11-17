#!/usr/bin/env bash
# Regenerates the site's binary assets. Optional: the committed files are the build output.
#
#   tools/build-assets.sh fonts <dir-with-source-ttfs>
#   tools/build-assets.sh og
#
# Font sources (SIL OFL 1.1, from github.com/google/fonts):
#   ofl/archivo/Archivo[wdth,wght].ttf
#   ofl/courierprime/CourierPrime-Regular.ttf, CourierPrime-Bold.ttf
# Needs fonttools with brotli (pip install fonttools brotli), and Google Chrome for "og".
set -euo pipefail
here="$(cd "$(dirname "$0")/.." && pwd)"
latin="U+0000-00FF,U+0131,U+0152-0153,U+02BB-02BC,U+02C6,U+02DA,U+02DC,U+0304,U+0308,U+0329,U+2000-206F,U+20AC,U+2122,U+2190-2193,U+2212,U+2215,U+FEFF,U+FFFD"
features="kern,liga,calt,ccmp,locl,mark,mkmk"

fonts() {
  src="$1"; tmp="$(mktemp -d)"
  # Headlines and labels: width 62-87 %, weight 700-900. Body: width 100 %, weight 400.
  fonttools varLib.instancer "$src/Archivo[wdth,wght].ttf" wght=700:900 wdth=62:87 -q -o "$tmp/display.ttf"
  fonttools varLib.instancer "$src/Archivo[wdth,wght].ttf" wght=400 wdth=100 -q -o "$tmp/text.ttf"
  sub() { pyftsubset "$1" --unicodes="$latin" --layout-features="$features" --flavor=woff2 --no-hinting --output-file="$2"; }
  sub "$tmp/display.ttf" "$here/fonts/archivo-display.woff2"
  sub "$tmp/text.ttf" "$here/fonts/archivo-text.woff2"
  sub "$src/CourierPrime-Regular.ttf" "$here/fonts/courier-prime-400.woff2"
  sub "$src/CourierPrime-Bold.ttf" "$here/fonts/courier-prime-700.woff2"
  rm -rf "$tmp"
}

og() {
  # The social card is drawn with the site's own CSS from this template, then saved as a JPEG.
  chrome="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
  tmp="$(mktemp -d)"
  sed "s#__SITE__#$here#g" > "$tmp/og.html" <<'HTML'
<!doctype html>
<html lang="en-GB">
<head>
<meta charset="utf-8">
<meta name="robots" content="noindex">
<title>Social card source</title>
<link rel="stylesheet" href="file://__SITE__/assets/site.css">
<style>
  body { width: 1200px; height: 630px; overflow: hidden; }
  .card { box-sizing: border-box; width: 1200px; height: 630px; padding: 52px 56px 40px; display: flex; flex-direction: column; }
  .card h1 { margin: 0; font-family: var(--display); font-weight: 900; font-stretch: 62%; text-transform: uppercase; color: var(--navy); font-size: 112px; line-height: .9; letter-spacing: -.005em; }
  .card .stage { --z: 2.6; margin-top: 30px; height: 350px; }
  .card .lower { left: 26px; bottom: 26px; }
  .card .foot { margin: auto 0 0; font-family: var(--mono); font-size: 17px; color: var(--muted); }
</style>
</head>
<body>
<div class="card">
  <h1>That’s what she synced.</h1>
  <div class="stage"><div class="screen">
    <div class="shot">
      <div class="menubar"></div>
      <div class="rigc"><div class="rig">
        <div class="isl" data-scene="idle">
          <div class="notch">
            <span class="pad l"></span><span class="pad r"></span>
            <span class="cam"><span class="lens"></span></span>
            <span class="glow l g-idle pal-scarn"></span><span class="glow r g-idle pal-scarn"></span>
            <div class="slot l s-idle"><span class="mem m-scarn pal-scarn idle"><svg viewBox="0 0 24 24" aria-hidden="true"><g class="hop"><g class="sq"><g class="tilt"><circle class="hand-l" cx="3.9" cy="17" r="1.35"/><circle class="hand-r" cx="20.1" cy="17" r="1.35"/><circle cx="12" cy="8.4" r="6.1" fill="#E9E1D0"/><path d="M4.6 22V16.6C4.6 13.7 7 12.3 9.4 12.3H14.6C17 12.3 19.4 13.7 19.4 16.6V22Z" fill="#1B1B1F"/><path d="M4.6 21.6V16.6C4.6 13.7 7 12.3 9.4 12.3M14.6 12.3C17 12.3 19.4 13.7 19.4 16.6V21.6" fill="none" stroke="#4A4A58" stroke-width=".55" stroke-linecap="round"/><path d="M9 12.3H15L12 18.4Z" fill="#F4F1E8"/><path d="M9 12.3L12 18.4L15 12.3" fill="none" stroke="#4A4A58" stroke-width=".55" stroke-linejoin="round"/><path d="M11.35 13.2H12.65L13 18.3L12 19.7L11 18.3Z" fill="#D2343F"/><g class="eyes"><ellipse class="ink" cx="9.8" cy="8.8" rx=".9" ry="1.15"/><ellipse class="ink" cx="14.2" cy="8.8" rx=".9" ry="1.15"/></g></g></g></g></svg></span></div>
          </div>
        </div>
      </div></div>
    </div>
    <div class="lower"><span class="bar"><span class="nm">The Notch</span></span><span class="bar"><span class="rl">Assistant to the Regional Menu Bar</span></span></div>
  </div></div>
  <p class="foot">Unofficial fan homage. Not affiliated with or endorsed by NBCUniversal, or by the Vorssaint project.</p>
</div>
</body>
</html>
HTML
  "$chrome" --headless=new --disable-gpu --hide-scrollbars --force-device-scale-factor=1 \
    --window-size=1200,630 --virtual-time-budget=3000 --allow-file-access-from-files \
    --screenshot="$tmp/og.png" "file://$tmp/og.html"
  sips -s format jpeg -s formatOptions 84 "$tmp/og.png" --out "$here/assets/og.jpg" >/dev/null
  rm -rf "$tmp"
}

case "${1:-}" in
  fonts) fonts "${2:?source font directory}" ;;
  og) og ;;
  *) echo "usage: $0 fonts <dir> | og" >&2; exit 2 ;;
esac
