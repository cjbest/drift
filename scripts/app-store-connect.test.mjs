import assert from 'node:assert/strict';
import { generateKeyPairSync, verify } from 'node:crypto';
import { mkdtemp, rm, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { after, test } from 'node:test';
import { apiUrl, createClient, createToken, loadConfig, runCommand } from './app-store-connect.mjs';

const { privateKey, publicKey } = generateKeyPairSync('ec', { namedCurve: 'prime256v1' });
const directory = await mkdtemp(join(tmpdir(), 'drift-asc-test-'));
const privateKeyPath = join(directory, 'test.p8');
await writeFile(privateKeyPath, privateKey.export({ type: 'pkcs8', format: 'pem' }), { mode: 0o600 });
const config = { keyId: 'TESTKEY123', issuerId: 'test-issuer', privateKeyPath, appId: '123' };
after(() => rm(directory, { recursive: true, force: true }));

test('JWT has a verifiable ES256 signature, correct audience, and ten-minute lifetime', () => {
  const [header, payload, signature] = createToken(config, privateKey, 1_800_000_000_000).split('.');
  assert.deepEqual(JSON.parse(Buffer.from(header, 'base64url')), { alg: 'ES256', kid: config.keyId, typ: 'JWT' });
  assert.deepEqual(JSON.parse(Buffer.from(payload, 'base64url')), {
    iss: config.issuerId, iat: 1_800_000_000, exp: 1_800_000_600, aud: 'appstoreconnect-v1',
  });
  assert.equal(Buffer.from(signature, 'base64url').length, 64);
  assert.equal(verify('sha256', Buffer.from(`${header}.${payload}`), { key: publicKey, dsaEncoding: 'ieee-p1363' }, Buffer.from(signature, 'base64url')), true);
});

test('configuration supports CI environment overrides without a configuration file', async () => {
  const result = await loadConfig({ configPath: join(directory, 'missing.json'), env: {
    ASC_KEY_ID: config.keyId, ASC_ISSUER_ID: config.issuerId, ASC_PRIVATE_KEY_PATH: privateKeyPath, ASC_APP_ID: '456',
  } });
  assert.equal(result.appId, '456');
  assert.equal(result.privateKeyPath, privateKeyPath);
  assert.equal(result.keyId, config.keyId);
  await assert.rejects(loadConfig({ configPath: join(directory, 'missing.json'), env: {} }), /Missing keyId/);
});

test('configuration merges saved defaults and overrides and rejects malformed JSON', async () => {
  const configPath = join(directory, 'config.json');
  await writeFile(configPath, JSON.stringify(config));
  assert.equal((await loadConfig({ configPath, env: { ASC_APP_ID: '789' } })).appId, '789');
  await writeFile(configPath, 'not JSON');
  await assert.rejects(loadConfig({ configPath, env: {} }), /check its JSON/);
});

test('only the exact HTTPS Apple API origin is allowed, including pagination URLs', () => {
  assert.equal(apiUrl('/v1/apps?limit=1').origin, 'https://api.appstoreconnect.apple.com');
  for (const endpoint of [
    'https://example.com/v1/apps', '//example.com/v1/apps',
    'http://api.appstoreconnect.apple.com/v1/apps',
    'https://api.appstoreconnect.apple.com.example.com/v1/apps',
    'https://user:pass@api.appstoreconnect.apple.com/v1/apps',
    'https://api.appstoreconnect.apple.com:444/v1/apps', '/v1/apps#fragment', '/not-an-api',
  ]) assert.throws(() => apiUrl(endpoint), /Refusing API destination/);
});

test('requests authenticate, prohibit redirects, and serialize JSON mutation bodies', async () => {
  const client = await createClient(config, { fetchImpl: async (url, options) => {
    assert.equal(url.href, 'https://api.appstoreconnect.apple.com/v1/betaGroups');
    assert.equal(options.method, 'POST');
    assert.equal(options.redirect, 'error');
    assert.ok(options.signal instanceof AbortSignal);
    assert.match(options.headers.Authorization, /^Bearer [\w-]+\.[\w-]+\.[\w-]+$/);
    assert.equal(options.headers['Content-Type'], 'application/json');
    assert.deepEqual(JSON.parse(options.body), { data: { type: 'betaGroups' } });
    return new Response(JSON.stringify({ data: { id: 'group-1' } }));
  } });
  assert.deepEqual(await client.request('POST', '/v1/betaGroups', { data: { type: 'betaGroups' } }), { data: { id: 'group-1' } });
  await assert.rejects(client.request('GET', '/v1/apps', {}), /cannot have a body/);
});

test('HTTP failure explains missing access and never prints the bearer token', async () => {
  let token;
  const client = await createClient(config, { fetchImpl: async (_url, options) => {
    token = options.headers.Authorization.slice(7);
    return new Response(JSON.stringify({ errors: [{ code: 'NOT_AUTHORIZED', title: 'Invalid credentials', detail: token }] }), { status: 401 });
  } });
  await assert.rejects(client.request('GET', '/v1/apps'), error => {
    assert.match(error.message, /401.*NOT_AUTHORIZED/);
    assert.match(error.message, /system clock/);
    assert.ok(!error.message.includes(token));
    return true;
  });
});

test('non-JSON HTTP failures and network failures have actionable errors', async () => {
  const failed = await createClient(config, { fetchImpl: async () => new Response('<html>Unavailable</html>', { status: 503, statusText: 'Service Unavailable' }) });
  await assert.rejects(failed.request('GET', '/v1/apps'), /503.*Service Unavailable/);
  const offline = await createClient(config, { fetchImpl: async () => { throw new Error('network detail with secrets'); } });
  await assert.rejects(offline.request('GET', '/v1/apps'), error => {
    assert.match(error.message, /check your connection/);
    assert.ok(!error.message.includes('secrets'));
    return true;
  });
});

test('pagination retains feedback and assets, deduplicates related resources, and fetches every page', async () => {
  let count = 0;
  const screenshot = { type: 'betaFeedbackScreenshotSubmissions', id: '1', attributes: { comment: 'Example', screenshots: [{ url: 'https://assets.example/screenshot.png' }] } };
  const tester = { type: 'betaTesters', id: 'tester-1', attributes: { firstName: 'Tester' } };
  const client = await createClient(config, { fetchImpl: async url => {
    count += 1;
    if (count === 1) return Response.json({ data: [screenshot], included: [tester], links: { next: 'https://api.appstoreconnect.apple.com/v1/feedback?cursor=2' } });
    assert.equal(url.searchParams.get('cursor'), '2');
    return Response.json({ data: [{ type: 'betaFeedbackScreenshotSubmissions', id: '2' }], included: [tester], links: { next: null } });
  } });
  const result = await client.paginate('/v1/feedback');
  assert.equal(count, 2);
  assert.equal(result.data.length, 2);
  assert.deepEqual(result.data[0], screenshot);
  assert.deepEqual(result.included, [tester]);
  assert.equal(result.meta.pagesFetched, 2);
  assert.equal(result.links.next, null);
});

test('cross-origin pagination stops before a credential can be sent off-host', async () => {
  let count = 0;
  const client = await createClient(config, { fetchImpl: async () => {
    count += 1;
    return Response.json({ data: [], links: { next: 'https://example.com/v1/feedback' } });
  } });
  await assert.rejects(client.paginate('/v1/feedback'), /Refusing API destination/);
  assert.equal(count, 1);
});

test('pagination rejects repeated next links', async () => {
  const client = await createClient(config, { fetchImpl: async () => Response.json({ data: [], links: { next: '/v1/feedback' } }) });
  await assert.rejects(client.paginate('/v1/feedback'), /repeated pagination link/);
});

test('feedback commands use app-scoped endpoints and retain complete responses', async () => {
  const paths = [];
  const client = { paginate: async endpoint => { paths.push(endpoint); return { data: [{ id: endpoint }] }; } };
  const result = await runCommand(['feedback'], config, client);
  assert.equal(paths.length, 2);
  assert.ok(paths.some(path => path.startsWith('/v1/apps/123/betaFeedbackScreenshotSubmissions?')));
  assert.ok(paths.some(path => path.startsWith('/v1/apps/123/betaFeedbackCrashSubmissions?')));
  assert.equal(result.crashes.data.length, 1);
  assert.equal(result.screenshots.data.length, 1);
});
