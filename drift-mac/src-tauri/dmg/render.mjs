// Regenerate the checked-in Finder background with the desktop test tools:
// node drift-mac/src-tauri/dmg/render.mjs
import { readFile } from 'node:fs/promises';
import { execFileSync } from 'node:child_process';
import { createRequire } from 'node:module';
import { fileURLToPath } from 'node:url';

const require = createRequire(new URL('../../package.json', import.meta.url));
const { chromium } = require('@playwright/test');
const output = fileURLToPath(new URL('background.png', import.meta.url));
const browser = await chromium.launch();
try {
  const page = await browser.newPage({ viewport: { width: 660, height: 400 }, deviceScaleFactor: 2 });
  const svg = await readFile(new URL('background.svg', import.meta.url), 'utf8');
  const font = await readFile(new URL('../../public/fonts/Newsreader-Italic.ttf', import.meta.url));
  await page.setContent(`<style>@font-face{font-family:Newsreader;src:url(data:font/ttf;base64,${font.toString('base64')});font-style:italic;font-weight:200 800}html,body{margin:0}svg{display:block}</style>${svg}`);
  await page.evaluate(() => document.fonts.ready);
  await page.screenshot({ path: output });
} finally {
  await browser.close();
}
// Finder reads 1320 x 800 pixels at 144 DPI as 660 x 400 logical points.
execFileSync('/usr/bin/sips', ['-s', 'dpiWidth', '144', '-s', 'dpiHeight', '144', output], { stdio: 'ignore' });
