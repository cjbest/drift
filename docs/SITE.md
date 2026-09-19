# Landing page

The public landing page is served by GitHub Pages at
https://drift.christopher.best/. Its source is `docs/site/index.html`.
It is a static page with no analytics, cookies, or external font requests.
A small script controls the looping demo and respects reduced-motion settings.
The iPhone section comes first on mobile; desktop shows both apps side by side.

Build and preview from the repository root:

```sh
./scripts/build-site.sh
python3 -m http.server 4173 --bind 127.0.0.1 --directory dist/site
```

Open http://127.0.0.1:4173/. The build assembles only the page and its selected
assets in the ignored `dist/site` directory. It requires Node.js, using only
its standard library; no npm dependencies are needed. It does not publish the
rest of `docs`.

`.github/workflows/pages.yml` deploys changes to the site and its inputs on
`main`. GitHub Pages must use **GitHub Actions** as its publishing source.
The workflow can also be run manually. See
[GitHub's Pages workflow guide](https://docs.github.com/en/pages/getting-started-with-github-pages/using-custom-workflows-with-github-pages).

The Pages custom domain is `drift.christopher.best`. In Name.com's DNS settings
for `christopher.best`, the `drift` host must have a `CNAME` record pointing to
`cjbest.github.io`. Configure the custom domain in the repository's Pages
settings and enable **Enforce HTTPS** after GitHub provisions the certificate.
This Actions-based deployment does not use a `CNAME` file. The original
https://cjbest.github.io/drift/ address redirects to the custom domain.

The Mac demo uses Chris's September 6, 2026, 12:43 PM recording, showing the
whole window and desktop background during the opening drag. The video then
smoothly zooms to 117% from 4.2 to 5.5 seconds, around the paste, and holds that
framing for the remaining demo. The whole window stays visible, with an even
24-pixel wallpaper border after the zoom.
`docs/assets/demo.mp4` preserves the 29-second performance at
1870 × 1474, encoded as H.264 at 30 fps (CRF 20, slow preset, YUV 4:2:0,
fast start), with audio and recording metadata removed. The centered zoom uses
a cubic smoothstep and 2× intermediate scaling to keep movement smooth.
The H.264 stream and MP4 container explicitly identify BT.709 primaries and
matrix, limited range, and the sRGB transfer function. Leaving the transfer
function unspecified made Safari brighten the video relative to the still
poster. These tags were added without re-encoding or changing any frames.
The final crop is 1870 × 1474 at (40, 4) in the 1990 × 1502 zoomed frame.
`desktop-demo-first-frame.mp4` contains only the first frame, copied without
re-encoding. This paused preview preloads immediately and uses the same native
video renderer as the full demo. Safari otherwise samples a JPEG and video
slightly differently, making the picture shift by a fraction of a pixel.
The preview remains still while the demo loads, when reduced motion is
requested, or when autoplay is unavailable. Once the full video's decoded frame
is ready, the preview is hidden in the same update that reveals the video,
without a fade. This also prevents doubled antialiasing at the rounded corners.
`desktop-demo.jpg` is the first-frame fallback if the preview fails or JavaScript
is disabled. Regenerate the paused preview when changing the demo:

```sh
ffmpeg -i docs/assets/demo.mp4 -map 0:v:0 -frames:v 1 -c:v copy -movflags +faststart docs/site/assets/desktop-demo-first-frame.mp4
```

The demo's 1870:1474 aspect ratio is reserved before its media loads, with the video
positioned inside it so intrinsic media sizing cannot move the page. Native
controls are absent from the initial markup to prevent a Safari loading-overlay
flash. Frame callbacks are backed by a loaded-frame check because some browsers
skip compositor callbacks while a video is fully transparent. Without
JavaScript, the still links directly to the demo.
To replace the recording, update the video, both previews, and video's intrinsic
dimensions and aspect-ratio calculation in the page. The README links to this
same MP4 and displays a 1200-pixel-wide, 15 fps GIF derived from it in
`docs/assets/desktop-demo.gif` (global palette, Bayer dithering, optimized with
Gifsicle). Keep the GIF in sync when changing the demo. Use a new GIF
filename when replacing it to avoid GitHub serving an older cached recording.
The iPhone source is shared with the README. The page preloads responsive 800-
and 1200-pixel lossless WebP derivatives (106 and 172 KiB, versus the original
1.7 MiB PNG). An explicit aspect ratio keeps their rounded raster dimensions
from changing the layout. `assets/chris.jpg` is the original photo from
[Chris's Substack profile](https://substack.com/@cb); the visible 56-pixel avatar
uses a 168-pixel WebP derivative with the original color profile (7 KiB, versus
812 KiB). All assets stay local to the site.

`scripts/site/build-page.mjs` embeds that small avatar and `drift-title.woff2`
directly in the built HTML, so neither waits for another network request.
The title font contains only the glyphs needed for “Drift”, preserving the
original Newsreader weight and optical-size axes. `font-display: block` avoids
briefly showing a substitute font while the embedded bytes decode. The full
font and OFL license are also copied from the Mac app. Keep the embedded font
out of preload links: Safari rejects its data URL when preloaded with CORS.
Regenerate the subset with FontTools and Brotli installed:

```sh
pyftsubset drift-mac/public/fonts/Newsreader-Italic.ttf --text=Drift --flavor=woff2 --output-file=docs/site/assets/drift-title.woff2 --no-recalc-timestamp
```

## Search and sharing

The page includes a descriptive title and summary, a canonical HTTPS URL,
Open Graph and X link previews, and basic structured data identifying Drift
and Chris. `robots.txt` allows crawling and points to the one-page sitemap.
There are no invented ratings, app-store offers, or tracking integrations.

The 1200 × 630 social preview is a wide crop of the actual dark-mode desktop
editor at 28.5 seconds in `docs/assets/demo.mp4`. It keeps the window controls,
title, and completed checklist, with the mouse pointer below the crop. The
generator crops 1560 × 819 pixels at (24, 24), then scales to the card size.
Regenerate it after changing the demo (requires Node and FFmpeg on PATH):

```sh
node scripts/site/render-social-preview.mjs
```

`social-preview-desktop-dark.png` has a new URL for refreshed image caches.
The earlier `social-preview.png` remains available for cached page metadata.

The favicon is the Mac app's 512-pixel icon. The 180-pixel Apple touch icon is
derived from the opaque iOS app icon. To refresh it on a Mac:

```sh
sips -z 180 180 drift-ios/Drift/Assets.xcassets/AppIcon.appiconset/AppIcon.png --out docs/site/assets/apple-touch-icon.png
```

The build copies all metadata files and assets into the deployed site. Keep
canonical, social, structured-data, and sitemap URLs in sync if the domain
changes. Search engines and social crawlers need working HTTPS to fetch them.

## Enable downloads

The iPhone button links to the public TestFlight beta at
<https://testflight.apple.com/join/YfEQ1TSH>, enabled and verified on
September 16, 2026. Keep this invitation current when managing beta access.

Until the install links have been verified, each download is a disabled button
with a visible “Coming soon” label. Do not send visitors to nonexistent release
assets, the source repository, or a development-signed app under a download label.

After completing the checks in [RELEASING.md](RELEASING.md), replace the relevant
`button.download` in `docs/site/index.html` with an `a.download` whose `href` is
the verified Mac DMG or iPhone TestFlight/App Store URL. Remove `disabled`,
`type`, and `aria-describedby`, and update its availability text. For Mac, show
the version, Apple silicon requirement, and minimum macOS version.
Update all three description tags in the page head when iPhone downloads go
live so search and sharing previews no longer say “coming soon.”

Keep the filled button for the Mac in the desktop layout and for the iPhone in
the mobile layout. The other download stays outlined even when both are live.
An unavailable download stays outlined and disabled.
