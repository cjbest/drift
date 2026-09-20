#!/usr/bin/env node
// Local and CI access to Apple's API. Credentials stay outside the repository.
import { createPrivateKey, sign } from 'node:crypto';
import { readFile } from 'node:fs/promises';
import { homedir } from 'node:os';
import { resolve } from 'node:path';
import { pathToFileURL } from 'node:url';

const ORIGIN = 'https://api.appstoreconnect.apple.com';
const CONFIG_PATH = resolve(homedir(), '.config/drift/app-store-connect/config.json');
const HELP = `Usage: node scripts/app-store-connect.mjs COMMAND

  status                  App, ten newest builds, beta state, and beta groups
  feedback                All tester screenshot and crash submissions (JSON)
  crash-log ID            Crash log for a feedback submission (JSON)
  api METHOD /v1/path [--body file.json]
                          Call an API endpoint; write methods change the account
  --help                  Show this help without loading credentials

Configuration: ~/.config/drift/app-store-connect/config.json
Fields: keyId, issuerId, privateKeyPath, appId, bundleId
Overrides: ASC_KEY_ID, ASC_ISSUER_ID, ASC_PRIVATE_KEY_PATH, ASC_APP_ID
Requires Node.js 20 or newer. Output is JSON; redirects are never followed.
`;

export async function loadConfig({ env = process.env, configPath = CONFIG_PATH } = {}) {
  let saved = {};
  try {
    saved = JSON.parse(await readFile(configPath, 'utf8'));
    if (!saved || typeof saved !== 'object' || Array.isArray(saved)) throw new Error('format');
  } catch (error) {
    if (error.code !== 'ENOENT') throw new Error(`Cannot read configuration at ${configPath}; check its JSON and permissions.`);
  }
  const config = {
    keyId: env.ASC_KEY_ID ?? saved.keyId,
    issuerId: env.ASC_ISSUER_ID ?? saved.issuerId,
    privateKeyPath: env.ASC_PRIVATE_KEY_PATH ?? saved.privateKeyPath,
    appId: env.ASC_APP_ID ?? saved.appId ?? '6809245122',
    bundleId: saved.bundleId ?? 'best.christopher.drift',
  };
  for (const field of ['keyId', 'issuerId', 'privateKeyPath', 'appId']) {
    if (typeof config[field] !== 'string' || !config[field].trim()) {
      throw new Error(`Missing ${field}; configure ${configPath} or the corresponding ASC_ environment variable.`);
    }
  }
  if (config.privateKeyPath.startsWith('~/')) {
    config.privateKeyPath = resolve(homedir(), config.privateKeyPath.slice(2));
  }
  config.privateKeyPath = resolve(config.privateKeyPath);
  return config;
}

export function createToken(config, privateKey, now = Date.now()) {
  const issuedAt = Math.floor(now / 1000);
  const encode = value => Buffer.from(JSON.stringify(value)).toString('base64url');
  const header = encode({ alg: 'ES256', kid: config.keyId, typ: 'JWT' });
  const claims = encode({ iss: config.issuerId, iat: issuedAt, exp: issuedAt + 600, aud: 'appstoreconnect-v1' });
  const message = `${header}.${claims}`;
  const signature = sign('sha256', Buffer.from(message), { key: privateKey, dsaEncoding: 'ieee-p1363' });
  return `${message}.${signature.toString('base64url')}`;
}

export function apiUrl(endpoint) {
  let url;
  try {
    if (typeof endpoint !== 'string' || !endpoint) throw new Error('missing');
    url = new URL(endpoint, ORIGIN);
  } catch {
    throw new Error('Supply an App Store Connect API path such as /v1/apps.');
  }
  if (url.origin !== ORIGIN || url.username || url.password || url.hash || !/^\/v\d+\//.test(url.pathname)) {
    throw new Error(`Refusing API destination; only ${ORIGIN}/v*/ paths are allowed.`);
  }
  return url;
}

export async function createClient(config, { fetchImpl = globalThis.fetch, now = Date.now } = {}) {
  let privateKey;
  try {
    privateKey = createPrivateKey(await readFile(config.privateKeyPath));
    if (privateKey.asymmetricKeyType !== 'ec' || privateKey.asymmetricKeyDetails?.namedCurve !== 'prime256v1') {
      throw new Error('wrong key type');
    }
  } catch {
    throw new Error(`Cannot load an ES256 private key from ${config.privateKeyPath}; check the .p8 file and permissions.`);
  }

  async function request(method, endpoint, body) {
    const url = apiUrl(endpoint);
    const verb = method.toUpperCase();
    if (!['GET', 'POST', 'PATCH', 'DELETE', 'PUT'].includes(verb)) throw new Error(`Unsupported HTTP method: ${verb}`);
    if (verb === 'GET' && body !== undefined) throw new Error('GET requests cannot have a body.');
    const token = createToken(config, privateKey, now());
    let response;
    let raw;
    try {
      response = await fetchImpl(url, {
        method: verb,
        headers: { Authorization: `Bearer ${token}`, Accept: 'application/json', ...(body === undefined ? {} : { 'Content-Type': 'application/json' }) },
        ...(body === undefined ? {} : { body: JSON.stringify(body) }),
        redirect: 'error',
        signal: AbortSignal.timeout(30_000),
      });
      raw = await response.text();
    } catch {
      throw new Error(`Could not reach Apple's API for ${verb} ${url.pathname}; check your connection and retry. Redirects are blocked.`);
    }
    let result;
    try {
      result = raw ? JSON.parse(raw) : null;
    } catch {
      if (response.ok) throw new Error(`Apple returned a non-JSON response for ${url.pathname}.`);
    }
    if (!response.ok) {
      const detail = Array.isArray(result?.errors)
        ? result.errors.map(error => [error.code, error.title, error.detail].filter(Boolean).join(': ')).join('; ')
        : response.statusText;
      const hint = response.status === 401 ? ' Check the key ID, issuer ID, private key, and system clock.'
        : response.status === 403 ? ' Check the API key role and app access.'
          : response.status === 429 ? ' Apple rate-limited the request; wait before retrying.' : '';
      throw new Error(`Apple API ${response.status} for ${verb} ${url.pathname}: ${String(detail).replaceAll(token, '[redacted]').slice(0, 2000)}.${hint}`);
    }
    return result;
  }

  async function paginate(endpoint) {
    let next = endpoint;
    let first;
    const data = [];
    const included = new Map();
    const visited = new Set();
    while (next) {
      const url = apiUrl(next).href;
      if (visited.has(url)) throw new Error('Apple returned a repeated pagination link; stopped to avoid a loop.');
      visited.add(url);
      const page = await request('GET', url);
      if (!Array.isArray(page?.data)) throw new Error('Expected a collection response from Apple.');
      first ??= page;
      data.push(...page.data);
      for (const resource of page.included ?? []) included.set(`${resource.type}:${resource.id}`, resource);
      next = page.links?.next;
    }
    return {
      ...first,
      data,
      ...(included.size ? { included: [...included.values()] } : {}),
      links: { ...first?.links, next: null },
      meta: { ...first?.meta, pagesFetched: visited.size },
    };
  }
  return { request, paginate };
}

export async function runCommand(args, config, client) {
  const [command, ...rest] = args;
  const app = encodeURIComponent(config.appId);
  if (command === 'status' && !rest.length) {
    const buildsQuery = new URLSearchParams({ 'filter[app]': config.appId, sort: '-uploadedDate', limit: '10', include: 'preReleaseVersion,buildBetaDetail' });
    const groupsQuery = new URLSearchParams({ 'filter[app]': config.appId, limit: '200' });
    const [appInfo, builds, betaGroups] = await Promise.all([
      client.request('GET', `/v1/apps/${app}`),
      client.request('GET', `/v1/builds?${buildsQuery}`),
      client.paginate(`/v1/betaGroups?${groupsQuery}`),
    ]);
    return { app: appInfo, builds, betaGroups };
  }
  if (command === 'feedback' && !rest.length) {
    const query = new URLSearchParams({ limit: '200', sort: '-createdDate', include: 'build,tester' });
    const [screenshots, crashes] = await Promise.all([
      client.paginate(`/v1/apps/${app}/betaFeedbackScreenshotSubmissions?${query}`),
      client.paginate(`/v1/apps/${app}/betaFeedbackCrashSubmissions?${query}`),
    ]);
    return { screenshots, crashes };
  }
  if (command === 'crash-log' && rest.length === 1 && rest[0] && !rest[0].startsWith('-')) {
    return client.request('GET', `/v1/betaFeedbackCrashSubmissions/${encodeURIComponent(rest[0])}/crashLog`);
  }
  if (command === 'api' && (rest.length === 2 || (rest.length === 4 && rest[2] === '--body'))) {
    let body;
    if (rest.length === 4) {
      try {
        body = JSON.parse(await readFile(rest[3], 'utf8'));
      } catch {
        throw new Error(`Cannot read JSON request body from ${rest[3]}.`);
      }
    }
    return client.request(rest[0], rest[1], body);
  }
  throw new Error('Unknown command or arguments. Run with --help for usage.');
}

async function main(args) {
  if (!args.length || (args.length === 1 && ['--help', '-h', 'help'].includes(args[0]))) {
    process.stdout.write(HELP);
    return;
  }
  const config = await loadConfig();
  const client = await createClient(config);
  const result = await runCommand(args, config, client);
  process.stdout.write(`${JSON.stringify(result, null, 2)}\n`);
}

if (process.argv[1] && import.meta.url === pathToFileURL(resolve(process.argv[1])).href) {
  main(process.argv.slice(2)).catch(error => {
    process.stderr.write(`Error: ${error.message}\n`);
    process.exitCode = 1;
  });
}
