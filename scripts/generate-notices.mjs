#!/usr/bin/env node
// Regenerate from installed, locked dependencies. No license is assigned to Drift.
import fs from 'node:fs';
import path from 'node:path';
import os from 'node:os';
import crypto from 'node:crypto';
import { execFileSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';

const desktop = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../drift-mac');
const output = path.join(desktop, 'src-tauri/notices');
const sha256 = value => crypto.createHash('sha256').update(value).digest('hex');
const run = (command, args) => execFileSync(command, args, { cwd: desktop, encoding: 'utf8', maxBuffer: 32 * 1024 * 1024 });
const sourceNotices = {};
for (const [directory, matches] of [
  ['public/fonts', name => /ofl|license/i.test(name)],
  ['licenses/upstream', name => name.endsWith('.txt')],
]) {
  for (const name of fs.readdirSync(path.join(desktop, directory)).filter(matches).sort()) {
    const relative = `${directory}/${name}`;
    sourceNotices[relative] = sha256(fs.readFileSync(path.join(desktop, relative)));
  }
}
const inputs = {
  npmLock: sha256(fs.readFileSync(path.join(desktop, 'package-lock.json'))),
  cargoLock: sha256(fs.readFileSync(path.join(desktop, 'src-tauri/Cargo.lock'))),
  cargoManifest: sha256(fs.readFileSync(path.join(desktop, 'src-tauri/Cargo.toml'))),
  licenseConfig: sha256(fs.readFileSync(path.join(desktop, 'licenses/about.toml'))),
  upstreamNotices: sha256(fs.readFileSync(path.join(desktop, 'licenses/upstream.json'))),
  sourceNotices: sha256(JSON.stringify(sourceNotices)),
  generator: sha256(fs.readFileSync(fileURLToPath(import.meta.url))),
  rustc: run('rustc', ['--version']).trim(),
};
if (process.argv[2] === '--check') {
  const manifest = JSON.parse(fs.readFileSync(path.join(output, 'manifest.json'), 'utf8'));
  for (const [key, value] of Object.entries(inputs)) {
    if (manifest.inputs[key] !== value) throw new Error(`${key} changed; regenerate third-party notices before releasing.`);
  }
  for (const [name, hash] of Object.entries(manifest.files)) {
    if (sha256(fs.readFileSync(path.join(output, name))) !== hash) throw new Error(`Missing or changed bundled notice: ${name}`);
  }
  console.log('Bundled notices match both lockfiles, the Rust toolchain, and generated files.');
  process.exit(0);
}
if (process.argv.length > 2) throw new Error('Usage: node scripts/generate-notices.mjs [--check]');

const cargoAbout = process.env.CARGO_ABOUT || 'cargo-about';
const cargoAboutVersion = run(cargoAbout, ['--version']).trim();
if (cargoAboutVersion !== 'cargo-about 0.9.2') throw new Error('Use cargo-about 0.9.2; see docs/RELEASING.md.');
const temporary = fs.mkdtempSync(path.join(os.tmpdir(), 'drift-notices-'));
try {
  const cargoOutput = path.join(temporary, 'cargo.json');
  execFileSync(cargoAbout, ['generate', '--manifest-path', 'src-tauri/Cargo.toml', '--config', 'licenses/about.toml', '--locked', '--fail', '--format', 'json', '--output-file', cargoOutput], { cwd: desktop, stdio: 'inherit' });
  const cargo = JSON.parse(fs.readFileSync(cargoOutput, 'utf8'));
  const upstream = JSON.parse(fs.readFileSync(path.join(desktop, 'licenses/upstream.json'), 'utf8'));
  const sections = [
    'DRIFT — THIRD-PARTY NOTICES',
    'This distribution includes the components listed below. License texts and copyright notices come from the locked packages and their upstream repositories. Standard SPDX terms are supplied where a package declares a license but does not include its complete text; package attribution is preserved separately. These notices do not assign a license to Drift itself.',
    'Unmodified Rust dependency source is available at the versioned crates.io source links below. The Rust standard library has additional notices in RUST-STANDARD-LIBRARY.html.',
    'JAVASCRIPT DEPENDENCIES',
  ];
  const npmPaths = run('npm', ['ls', '--omit=dev', '--all', '--parseable']).trim().split('\n').filter(p => path.resolve(p) !== desktop);
  const npm = npmPaths.map(directory => ({ directory, pkg: JSON.parse(fs.readFileSync(path.join(directory, 'package.json'), 'utf8')) })).sort((a, b) => a.pkg.name.localeCompare(b.pkg.name));
  for (const { directory, pkg } of npm) {
    const licenses = fs.readdirSync(directory).filter(name => /^(licen[sc]e|copying|notice)([._-]|$)/i.test(name) && fs.statSync(path.join(directory, name)).isFile()).sort();
    if (!licenses.length) throw new Error(`No license file in ${pkg.name}@${pkg.version}`);
    const repository = typeof pkg.repository === 'string' ? pkg.repository : pkg.repository?.url;
    sections.push(`${pkg.name} ${pkg.version}\nLicense: ${pkg.license || 'See included license'}\nSource: ${repository || `https://www.npmjs.com/package/${pkg.name}/v/${pkg.version}`}`);
    for (const name of licenses) sections.push(`${name}\n\n${fs.readFileSync(path.join(directory, name), 'utf8').trim()}`);
  }
  sections.push('RUST DEPENDENCIES');
  const crateCount = new Set();
  const supplementary = new Map();
  for (const { package: crate } of cargo.crates) {
    if (fs.readdirSync(path.dirname(crate.manifest_path)).some(name => /^notice([._-]|$)/i.test(name))) {
      supplementary.set(`${crate.name}@${crate.version}`, crate);
    }
  }
  for (const license of cargo.licenses) {
    if (!license.text?.trim()) throw new Error(`Missing Rust license text for ${license.id}`);
    const usedBy = license.used_by.map(({ crate }) => {
      crateCount.add(`${crate.name}@${crate.version}`);
      if (!license.source_path) supplementary.set(`${crate.name}@${crate.version}`, crate);
      return `${crate.name} ${crate.version}\nSource: https://crates.io/api/v1/crates/${crate.name}/${crate.version}/download\n${crate.repository || ''}`.trim();
    }).sort().join('\n\n');
    // SPDX's fallback MIT/BSD templates contain placeholder copyright holders.
    // Never ship invented holders: retain the actual package attribution below.
    const terms = license.text.replace(/^Copyright \(c\) <year> <(?:copyright holders|owner)>\.? *\r?\n/gm, '').trim();
    sections.push(`${license.name} (${license.id})\n\n${usedBy}\n\n${terms}`);
  }
  sections.push('ADDITIONAL RUST COPYRIGHT AND LICENSE NOTICES');
  // These published versions have no standalone license in their package or
  // upstream snapshot. Retain their explicit SPDX declaration and authors from
  // Cargo.toml alongside the standard terms above; do not invent copyrights.
  const metadataOnly = new Set(['convert_case@0.4.0', 'dispatch@0.2.0', 'fxhash@0.2.1', 'mac@0.1.1', 'sigchld@0.2.4']);
  for (const [key, crate] of [...supplementary].sort(([a], [b]) => a.localeCompare(b))) {
    const directory = path.dirname(crate.manifest_path);
    const localFiles = fs.readdirSync(directory).filter(name => /^(licen[sc]e|copying|notice)([._-]|$)/i.test(name) && fs.statSync(path.join(directory, name)).isFile()).sort();
    const parts = [`${crate.name} ${crate.version}\nDeclared license: ${crate.license}\nPackage authors: ${crate.authors.join('; ')}\nSource: https://crates.io/api/v1/crates/${crate.name}/${crate.version}/download`];
    for (const name of localFiles) parts.push(`${name}\n\n${fs.readFileSync(path.join(directory, name), 'utf8').trim()}`);
    for (const file of upstream[key]?.files || []) {
      const bytes = fs.readFileSync(path.join(desktop, 'licenses/upstream', file.file));
      if (sha256(bytes) !== file.sha256) throw new Error(`Upstream license checksum changed: ${key} ${file.path}`);
      parts.push(`${file.path}\nSource: ${file.source}\n\n${bytes.toString().trim()}`);
    }
    if (parts.length === 1 && !metadataOnly.has(key)) throw new Error(`Review missing concrete attribution for ${key} before generating notices.`);
    sections.push(parts.join('\n\n'));
  }
  sections.push('FONTS');
  const fontsDirectory = path.join(desktop, 'public/fonts');
  const fonts = fs.readdirSync(fontsDirectory).filter(name => /ofl|license/i.test(name)).sort();
  if (!fonts.length) throw new Error('Font notices are missing.');
  for (const font of fonts) sections.push(`${font}\n\n${fs.readFileSync(path.join(fontsDirectory, font), 'utf8').trim()}`);
  const rustDocs = path.join(run('rustc', ['--print', 'sysroot']).trim(), 'share/doc/rust');
  const rustCopyright = fs.readFileSync(path.join(rustDocs, 'COPYRIGHT-library.html'));
  const rustLicenseNames = [...new Set([...rustCopyright.toString().matchAll(/href="licenses\/([^"]+)"/g)].map(match => match[1]))].sort();
  fs.mkdirSync(path.join(temporary, 'notices/licenses'), { recursive: true });
  fs.writeFileSync(path.join(temporary, 'notices/THIRD-PARTY-NOTICES.txt'), `${sections.join('\n\n' + '='.repeat(78) + '\n\n')}\n`);
  fs.writeFileSync(path.join(temporary, 'notices/RUST-STANDARD-LIBRARY.html'), rustCopyright);
  for (const name of rustLicenseNames) {
    if (path.basename(name) !== name) throw new Error('Unexpected Rust license path.');
    fs.copyFileSync(path.join(rustDocs, 'licenses', name), path.join(temporary, 'notices/licenses', name));
  }
  const files = {};
  const listFiles = (directory, prefix = '') => {
    for (const entry of fs.readdirSync(directory, { withFileTypes: true })) {
      const name = `${prefix}${entry.name}`;
      if (entry.isDirectory()) listFiles(path.join(directory, entry.name), `${name}/`);
      else files[name] = sha256(fs.readFileSync(path.join(directory, entry.name)));
    }
  };
  listFiles(path.join(temporary, 'notices'));
  fs.writeFileSync(path.join(temporary, 'notices/manifest.json'), `${JSON.stringify({ generator: cargoAboutVersion, target: 'aarch64-apple-darwin', inputs, npmPackages: npm.length, rustCrates: crateCount.size, files }, null, 2)}\n`);
  fs.mkdirSync(output, { recursive: true });
  fs.cpSync(path.join(temporary, 'notices'), output, { recursive: true });
  console.log(`Generated notices for ${npm.length} npm packages and ${crateCount.size} Rust crates, plus fonts and the Rust standard library.`);
} finally {
  fs.rmSync(temporary, { recursive: true, force: true });
}
