// Smoke-test an exported directory with a static server and Chromium, without Rails.
// Run in the devcontainer: node scripts/check-static-site.mjs tmp/static-poc-1
import { createServer } from 'node:http';
import { readFile, stat } from 'node:fs/promises';
import { resolve, extname } from 'node:path';
import assert from 'node:assert/strict';
import { chromium } from 'playwright';

const root = resolve(process.argv[2]);
const manifest = JSON.parse(await readFile(resolve(root, 'export-manifest.json')));
const types = { '.html': 'text/html', '.js': 'text/javascript', '.css': 'text/css', '.json': 'application/json', '.png': 'image/png', '.svg': 'image/svg+xml' };
const server = createServer(async (request, response) => {
  try {
    const url = new URL(request.url, 'http://localhost');
    if (url.pathname === '/map') {
      response.writeHead(302, { Location: '/map/socials' }).end();
      return;
    }
    let path = resolve(root, '.' + decodeURIComponent(url.pathname));
    if (!path.startsWith(root + '/') && path !== root) throw new Error('Outside export');
    // Matches how a static host resolves a request, in this order: an exact
    // file, then the same path with .html appended, then a directory's
    // index.html. The middle step is what serves "/about" from "about.html"
    // without a redirect, and it wins over the directory step: "/map/classes"
    // is served from "map/classes.html" even though "map/classes/" also
    // exists, which is what Cloudflare Pages does (measured against a live
    // deployment, 2026-10-19). Resolve to a file (or null) before writing any
    // headers, so a missing path is a 404 rather than a half-sent response.
    const resolveFile = async (path) => {
      const stats = await stat(path).catch(() => null);
      if (stats?.isFile()) { return path }
      const withExtension = await stat(`${path}.html`).then(found => found.isFile() ? `${path}.html` : null).catch(() => null);
      if (withExtension) { return withExtension }
      if (stats?.isDirectory()) { return resolve(path, 'index.html') }
      return null;
    };
    const file = await resolveFile(path);
    if (file === null) {
      response.writeHead(404).end('Not found');
      return;
    }
    const body = await readFile(file);
    response.writeHead(200, { 'Content-Type': types[extname(file)] ?? 'application/octet-stream' });
    response.end(body);
  } catch {
    response.writeHead(404).end('Not found');
  }
});
await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
const base = `http://127.0.0.1:${server.address().port}`;
let browser;
try {
  for (const path of [...manifest.pages, ...manifest.map_data, ...manifest.assets, '/robots.txt', '/sitemap.xml']) {
    assert.equal((await fetch(base + path)).status, 200, path);
  }
  assert.equal((await fetch(base + '/login')).status, 404);
  browser = await chromium.launch({ headless: true, args: ['--no-sandbox'] });
  const page = await browser.newPage({ viewport: { width: 375, height: 800 } });
  const failures = [];
  page.on('response', response => {
    if (response.url().startsWith(base) && response.status() >= 400) failures.push(response.url());
  });
  await page.goto(base, { waitUntil: 'load' });
  assert.equal(await page.locator('meta[name="csrf-token"]').count(), 0);
  assert.ok(await page.locator('h1').innerText());
  assert.ok(await page.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth));
  await page.getByRole('link', { name: 'About', exact: true }).first().click();
  await page.waitForURL(/\/about\/?$/);
  await page.goto(base + '/map/classes?venue_id=1', { waitUntil: 'domcontentloaded' });
  assert.equal(await page.locator('[data-map-static-value="true"]').count(), 1);
  const controls = await page.locator('[data-url]').evaluateAll(nodes => nodes.map(node => node.dataset.url));
  for (const path of controls) {
    const response = await fetch(base + path);
    assert.equal(response.status, 200, path);
    assert.ok(Array.isArray((await response.json()).markers));
  }
  assert.deepEqual(failures, []);
  console.log(`PASS: ${manifest.pages.length} pages, ${manifest.map_data.length} map datasets, ${manifest.assets.length} assets; mobile layout, navigation, private-page exclusion and map controls.`);
  console.log('Google Maps external rendering and domain restrictions still require a deployed-domain check.');
} finally {
  if (browser) await browser.close();
  server.close();
}
