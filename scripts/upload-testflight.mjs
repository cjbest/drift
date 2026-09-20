#!/usr/bin/env node
// Upload an already validated, personal-team Drift archive using Apple's API key.
import { spawnSync } from 'node:child_process';
import { access, mkdtemp, rm, writeFile } from 'node:fs/promises';
import { constants } from 'node:fs';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { loadConfig } from './app-store-connect.mjs';

const teamId = 'F486BUQ5G3';
const bundleId = 'best.christopher.drift';
const args = process.argv.slice(2);
if (!args.length || args.includes('--help')) {
  console.log('Usage: node scripts/upload-testflight.mjs <Drift.xcarchive> [--dry-run]\n\nUploads a validated Drift archive to App Store Connect. Does not assign it to\na tester group or submit it for review. --dry-run verifies the archive and\nprints the upload plan without contacting Apple. Uses the same credentials\nas scripts/app-store-connect.mjs.');
} else {
  try {
    const dryRun = args.includes('--dry-run');
    const positional = args.filter(arg => arg !== '--dry-run');
    if (positional.length !== 1 || positional[0].startsWith('-')) throw new Error('Provide one .xcarchive path and optionally --dry-run.');
    const archivePath = path.resolve(positional[0]);
    if (!archivePath.endsWith('.xcarchive')) throw new Error('Expected a .xcarchive directory.');
    const config = await loadConfig();
    const readPlist = (file, key) => {
      // Archive-level metadata contains CreationDate, which JSON cannot represent.
      const operation = key ? ['-extract', key, 'json'] : ['-convert', 'json'];
      const result = spawnSync('/usr/bin/plutil', [...operation, '-o', '-', file], { encoding: 'utf8' });
      if (result.status !== 0) throw new Error(`Cannot read archive metadata: ${file}`);
      return JSON.parse(result.stdout);
    };
    const archive = readPlist(path.join(archivePath, 'Info.plist'), 'ApplicationProperties');
    const relativeApp = archive.ApplicationPath;
    if (!relativeApp) throw new Error('Archive has no application product.');
    const products = path.join(archivePath, 'Products');
    const appPath = path.resolve(products, relativeApp);
    if (!appPath.startsWith(products + path.sep)) throw new Error('Archive application is outside Products.');
    const app = readPlist(path.join(appPath, 'Info.plist'));
    if (app.CFBundleIdentifier !== bundleId) throw new Error(`Expected normal Drift (${bundleId}); archive contains ${app.CFBundleIdentifier}.`);
    const signature = spawnSync('/usr/bin/codesign', ['-d', '--verbose=4', appPath], { encoding: 'utf8' });
    if (signature.status !== 0 || !signature.stderr.split('\n').includes(`TeamIdentifier=${teamId}`)) {
      throw new Error(`Archive must be signed by Drift's personal Apple team ${teamId}.`);
    }
    const integrity = spawnSync('/usr/bin/codesign', ['--verify', '--deep', '--strict', appPath], { encoding: 'utf8' });
    if (integrity.status !== 0) throw new Error('Archive code-signature verification failed.');
    console.log(JSON.stringify({ archivePath, bundleId, teamId, version: app.CFBundleShortVersionString, build: app.CFBundleVersion, destination: 'App Store Connect', distributeToTesters: false, dryRun }, null, 2));
    if (!dryRun) {
      await access(config.privateKeyPath, constants.R_OK);
      const workDir = await mkdtemp(path.join(tmpdir(), 'drift-api-upload-'));
      try {
        const optionsPath = path.join(workDir, 'ExportOptions.plist');
        await writeFile(optionsPath, `<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>method</key><string>app-store-connect</string>
<key>destination</key><string>upload</string>
<key>teamID</key><string>${teamId}</string>
<key>signingStyle</key><string>automatic</string>
<key>manageAppVersionAndBuildNumber</key><false/>
<key>uploadSymbols</key><true/>
</dict></plist>\n`, { mode: 0o600 });
        const result = spawnSync('/usr/bin/xcodebuild', [
          '-exportArchive', '-archivePath', archivePath, '-exportPath', path.join(workDir, 'export'),
          '-exportOptionsPlist', optionsPath, '-allowProvisioningUpdates',
          '-authenticationKeyPath', config.privateKeyPath,
          '-authenticationKeyID', config.keyId,
          '-authenticationKeyIssuerID', config.issuerId,
        ], { stdio: 'inherit' });
        if (result.error) throw result.error;
        if (result.status !== 0) throw new Error(`Xcode upload failed (${result.status ?? result.signal}).`);
        console.log('Upload accepted. Check processing and group availability with app-store-connect.mjs status.');
      } finally {
        await rm(workDir, { recursive: true, force: true });
      }
    }
  } catch (error) {
    console.error(`TestFlight upload: ${error.message}`);
    process.exitCode = 1;
  }
}
