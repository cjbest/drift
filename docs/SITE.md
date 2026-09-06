# Landing page

The public landing page is served by GitHub Pages at
https://cjbest.github.io/drift/. Its source is `docs/site/index.html`.
It is a static page with no analytics, cookies, or external font requests.
A small script controls the looping demo and respects reduced-motion settings.
The iPhone section comes first on mobile; desktop shows both apps side by side.

Build and preview from the repository root:

```sh
./scripts/build-site.sh
python3 -m http.server 4173 --bind 127.0.0.1 --directory dist/site
```

Open http://127.0.0.1:4173/. The build assembles only the page and its selected
assets in the ignored `dist/site` directory. It does not publish the rest of
`docs` or require npm dependencies.

`.github/workflows/pages.yml` deploys changes to the site and its inputs on
`main`. GitHub Pages must use **GitHub Actions** as its publishing source.
The workflow can also be run manually. See
[GitHub's Pages workflow guide](https://docs.github.com/en/pages/getting-started-with-github-pages/using-custom-workflows-with-github-pages).

The Mac demo uses Chris's September 6, 2026, 12:43 PM recording, showing the
whole window and desktop background during the opening drag. The video then
smoothly zooms to 117% from 4.2 to 5.5 seconds, around the paste, and holds that
framing for the remaining demo. The whole window stays visible, with an even
24-pixel wallpaper border after the zoom.
`docs/assets/demo.mp4` preserves the 29-second performance at
1870 × 1474, encoded as H.264 at 30 fps (CRF 20, slow preset, YUV 4:2:0,
fast start), with audio and recording metadata removed. The centered zoom uses
a cubic smoothstep and 2× intermediate scaling to keep movement smooth.
The final crop is 1870 × 1474 at (40, 4) in the 1990 × 1502 zoomed frame.
`desktop-demo.jpg` is the clean light-mode frame at 14.5 seconds from this cut.
To replace the recording, update the video, poster, and video's intrinsic
dimensions and aspect-ratio calculation in the page. The README links to this
same MP4 and displays a 1200-pixel-wide, 15 fps GIF derived from it in
`docs/assets/demo.gif` (global palette, Bayer dithering, optimized with
Gifsicle). Keep the GIF in sync when changing the demo; its image URL includes a version query
to avoid serving an older cached recording on GitHub.
The iPhone image is shared with the README; the font and its license are copied
from the Mac app. `assets/chris.jpg` is the profile photo from
[Chris's Substack profile](https://substack.com/@cb), stored locally so visitors
do not contact Substack just to load the page.

## Enable downloads

Until the install links have been verified, each download is a disabled button
with a visible “Coming soon” label. Do not send visitors to nonexistent release
assets, the source repository, or a development-signed app under a download label.

After completing the checks in [RELEASING.md](RELEASING.md), replace the relevant
`button.download` in `docs/site/index.html` with an `a.download` whose `href` is
the verified Mac DMG or iPhone TestFlight/App Store URL. Remove `disabled`,
`type`, and `aria-describedby`, and update its availability text. For Mac, show
the version, Apple silicon requirement, and minimum macOS version.
