// Inline the small assets needed for the first paint. No npm dependencies.
import { readFile, writeFile } from 'node:fs/promises';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = resolve(dirname(fileURLToPath(import.meta.url)), '../..');
const source = resolve(root, 'docs/site');
let page = await readFile(resolve(source, 'index.html'), 'utf8');
for (const [path, type] of [
  ['assets/drift-title.woff2', 'font/woff2'],
  ['assets/chris-avatar.webp', 'image/webp'],
]) {
  if (!page.includes(path)) throw new Error(`Missing inline asset reference: ${path}`);
  const bytes = await readFile(resolve(source, path));
  page = page.replaceAll(path, `data:${type};base64,${bytes.toString('base64')}`);
}
await writeFile(resolve(root, 'dist/site/index.html'), page);
