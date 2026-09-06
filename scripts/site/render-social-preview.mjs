#!/usr/bin/env node
// Run from any directory: node scripts/site/render-social-preview.mjs
// Requires the Mac app's Playwright dependencies and installed Chromium browser.
import { readFile, mkdir, stat } from 'node:fs/promises';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { chromium } from '../../drift-mac/node_modules/playwright-core/index.mjs';

const root = resolve(dirname(fileURLToPath(import.meta.url)), '../..');
const output = resolve(root, 'docs/site/assets/social-preview.png');
const dataURL = async (path, type) => `data:${type};base64,${(await readFile(resolve(root, path))).toString('base64')}`;
const [font, mac, iphone] = await Promise.all([
  dataURL('drift-mac/public/fonts/Newsreader-Italic.ttf', 'font/ttf'),
  dataURL('docs/site/assets/desktop-demo.jpg', 'image/jpeg'),
  dataURL('docs/assets/iphone.png', 'image/png'),
]);

const html = `<!doctype html>
<html lang="en"><head><meta charset="utf-8"><style>
  @font-face { font-family: Newsreader; src: url("${font}") format("truetype"); font-style: italic; font-weight: 200 800; }
  * { box-sizing: border-box; }
  html, body { margin: 0; width: 1200px; height: 630px; overflow: hidden; }
  body { background: #faf7f0; color: #302b25; -webkit-font-smoothing: antialiased; }
  header { position: absolute; top: 35px; left: 0; width: 1200px; text-align: center; }
  h1 { margin: 0; font: italic 400 92px/1.08 Newsreader, Georgia, serif; }
  p { margin: 11px 0 0; font: 400 25px/1.4 -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif; letter-spacing: -.2px; }
  .screens { position: absolute; top: 201px; left: 0; width: 1200px; height: 392px; display: flex; justify-content: center; align-items: center; gap: 76px; }
  img { display: block; width: auto; height: 392px; flex: none; }
  .mac { border-radius: 10px; box-shadow: 0 12px 30px #302b251c; }
  .iphone { filter: drop-shadow(0 10px 12px #302b2510); }
</style></head><body>
  <header><h1>Drift</h1><p>A quiet place for your notes.</p></header>
  <div class="screens">
    <img class="mac" src="${mac}" width="1870" height="1474" alt="Drift's Mac window with a Markdown checklist">
    <img class="iphone" src="${iphone}" width="1600" height="1583" alt="Drift on iPhone in light and dark mode">
  </div>
</body></html>`;

const browser = await chromium.launch({ headless: true });
try {
  const page = await browser.newPage({ viewport: { width: 1200, height: 630 }, deviceScaleFactor: 1, colorScheme: 'light' });
  await page.setContent(html, { waitUntil: 'load' });
  await page.evaluate(async () => {
    await document.fonts.ready;
    await Promise.all([...document.images].map(image => image.decode()));
    await new Promise(requestAnimationFrame);
    await new Promise(requestAnimationFrame);
    if (!document.fonts.check('italic 92px Newsreader')) throw new Error('The wordmark font did not load.');
    for (const element of document.querySelectorAll('h1, p, img')) {
      const { x, y, right, bottom } = element.getBoundingClientRect();
      if (x < 0 || y < 0 || right > 1200 || bottom > 630) throw new Error('Social artwork clips an element.');
    }
  });
  await mkdir(dirname(output), { recursive: true });
  await page.screenshot({ path: output, type: 'png', animations: 'disabled' });
} finally {
  await browser.close();
}
console.log(`${output} (${(await stat(output)).size.toLocaleString()} bytes, 1200 × 630)`);
