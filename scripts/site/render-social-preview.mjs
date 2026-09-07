#!/usr/bin/env node
// Run from any directory: node scripts/site/render-social-preview.mjs
// Requires FFmpeg on PATH. Uses the actual desktop demo, without redrawing the UI.
import { mkdir, stat } from 'node:fs/promises';
import { spawnSync } from 'node:child_process';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = resolve(dirname(fileURLToPath(import.meta.url)), '../..');
const output = resolve(root, 'docs/site/assets/social-preview-desktop-dark.png');

await mkdir(dirname(output), { recursive: true });
const result = spawnSync('ffmpeg', [
  '-hide_banner', '-loglevel', 'error', '-nostdin', '-y',
  // The checklist is complete and dark mode has settled near the end of the demo.
  '-ss', '28.5',
  '-i', resolve(root, 'docs/assets/demo.mp4'),
  '-frames:v', '1',
  // Keep the title, window controls, and full checklist. The pointer is below
  // this crop. Its 40:21 aspect ratio scales exactly to the social card size.
  '-vf', 'crop=1560:819:24:24:exact=1,scale=1200:630:flags=lanczos,setsar=1',
  '-map_metadata', '-1', '-compression_level', '9', '-update', '1',
  output,
], { stdio: 'inherit' });
if (result.error) throw result.error;
if (result.status !== 0) throw new Error(`FFmpeg exited with status ${result.status}`);
console.log(`${output} (${(await stat(output)).size.toLocaleString()} bytes, 1200 × 630)`);
