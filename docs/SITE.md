# Landing page

The public landing page is served by GitHub Pages at
https://cjbest.github.io/drift/. Its source is `docs/site/index.html`.
It is a static page with no JavaScript, analytics, cookies, or external font
requests. The iPhone section comes first on mobile; desktop shows both apps
side by side.

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

The Mac still is the 18.5-second frame from the approved human recording in
`docs/assets/demo.mp4`. CSS clips the surrounding desktop wallpaper, preserving
the whole window. The README's video and GIF are unchanged. The iPhone image is
shared with the README; the font and its license are copied from the Mac app.

## Enable downloads

Until the install links have been verified, each download is a disabled button
with a visible “Coming soon” label. Do not send visitors to nonexistent release
assets, the source repository, or a development-signed app under a download label.

After completing the checks in [RELEASING.md](RELEASING.md), replace the relevant
`button.download` in `docs/site/index.html` with an `a.download` whose `href` is
the verified Mac DMG or iPhone TestFlight/App Store URL. Remove `disabled`,
`type`, and `aria-describedby`, and update its availability text. For Mac, show
the version, Apple silicon requirement, and minimum macOS version.
