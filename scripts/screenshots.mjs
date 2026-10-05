// UI review harness. Captures full-page screenshots of the application at a
// desktop and a phone width so the layout can be compared against the reference
// structure by eye, and reports the measured document width of every page so an
// overflowing page is caught as a number rather than by squinting at a picture.
//
// Playwright rather than the project's Selenium setup, because Firefox headless
// clamps its window to roughly 450px wide: Selenium's resize_to(375, 800) lands
// on 450, and -width/-height/--window-size are all ignored at launch, so every
// "phone" screenshot came out a desktop layout. Playwright's viewport is exact.
// The specs keep using Selenium; this is only a review tool.
//
// Usage, from the devcontainer with the app booted:
//
//   yarn screenshots                       # against http://localhost:3000
//   BASE_URL=https://staging.example yarn screenshots
//   OUT_DIR=tmp/ui-review yarn screenshots
//
// Output lands in tmp/ui-review, which is gitignored.

import { chromium } from 'playwright';
import { mkdir, writeFile } from 'node:fs/promises';

const BASE = (process.env.BASE_URL ?? 'http://localhost:3000').replace(/\/$/, '');
const OUT = process.env.OUT_DIR ?? 'tmp/ui-review';
const EDITOR_EMAIL = process.env.EDITOR_EMAIL ?? 'editor@example.com';

// A phone and a laptop. The review turns on these two widths.
const WIDTHS = { desktop: 1280, mobile: 375 };

// Rack::Attack throttles to 5 requests per IP per 2 seconds
// (config/initializers/rack_attack.rb:38). This matters more than it looks: the
// listings page pulls seven subresources (HTML, CSS, JS, the asterisk icon, the
// map icon, and two font files), so one page view can exhaust the budget on its
// own and leave the tail of them 429. A 429 has a blank body, so the page still
// screenshots "successfully" - it just has a broken image in it, which is
// indistinguishable from a real layout bug unless you check the response codes.
// So: record every non-200 subresource, and pace the page loads to stay under.
const THROTTLE_MS = 700;
// The map page needs a few seconds for tiles, markers and the auto-opened info
// window; every other page is static and settled long before this.
const SETTLE_MS = Number(process.env.SETTLE_MS ?? 5000);

const PUBLIC_PAGES = {
  listings: '/',
  occasional: '/occasional',
  about: '/about',
  listings_policy: '/listings_policy',
  privacy: '/privacy',
  login: '/login',
  name_clash: '/name_clash',
  map_socials: '/map/socials'
};

// Editor pages. These need a signed-in session; SKIP_LOGIN=true in development
// means posting the seeded address signs straight in.
const CMS_PATHS = [
  'events',
  'events/new',
  'venues',
  'venues/new',
  'venues/1',
  'organisers',
  'organisers/new',
  'account',
  'admin/users',
  'admin/audit_log'
];

const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));

const rows = [];

// Collect the codes of every subresource a page asked for. A broken <img> in a
// screenshot is otherwise indistinguishable from a styling bug.
function watchResponses(page) {
  const bad = [];
  page.on('response', (response) => {
    if (response.status() >= 400) bad.push(`${response.status()} ${new URL(response.url()).pathname}`);
  });
  page.on('requestfailed', (request) => {
    bad.push(`FAILED ${new URL(request.url()).pathname} ${request.failure()?.errorText ?? ''}`);
  });
  return bad;
}

async function settle(page) {
  // Wait for the document and its subresources, then for webfonts. Do NOT use
  // waitUntil: 'networkidle': the Google map keeps requests in flight
  // indefinitely (tile prefetch), so the map page never reaches networkidle and
  // the capture times out instead of being written.
  await page.waitForLoadState('load');
  try {
    await page.evaluate(() => document.fonts.ready);
  } catch {
    // fonts.ready rejects on some pages; the load state above is enough.
  }
  await sleep(SETTLE_MS);
}

async function capture(context, name, path) {
  const page = await context.newPage();
  const bad = watchResponses(page);
  const response = await page.goto(BASE + path, { waitUntil: 'load' });
  const status = response?.status() ?? 0;

  if (status !== 200) {
    rows.push({ name, path, width: page.viewportSize().width, status, note: `HTTP ${status}` });
    await page.close();
    await sleep(THROTTLE_MS);
    return;
  }

  await settle(page);

  const measured = await page.evaluate(() => ({
    scrollWidth: document.documentElement.scrollWidth,
    scrollHeight: document.documentElement.scrollHeight,
    viewportWidth: window.innerWidth,
    title: document.title.replace(/\s+/g, ' ').trim().slice(0, 60),
    // An image the browser could not decode renders as its alt text, which is a
    // broken-image icon in the capture rather than the picture.
    brokenImages: [...document.images]
      .filter((img) => !img.complete || img.naturalWidth === 0)
      .map((img) => img.alt || img.src)
  }));

  // fullPage widens the image to the document's scroll width, which is what we
  // want: a page that overflows a 375px viewport should produce a visibly wider
  // capture, and the row below says so in numbers.
  const file = `${OUT}/${name}-${measured.viewportWidth}w.png`;
  await page.screenshot({ path: file, fullPage: true });

  const notes = [];
  if (measured.scrollWidth > measured.viewportWidth) notes.push('HORIZONTAL OVERFLOW');
  if (measured.brokenImages.length) notes.push(`BROKEN IMAGE: ${measured.brokenImages.join(', ')}`);
  if (bad.length) notes.push(`SUBRESOURCE ${bad.join(' ')}`);
  if (!notes.length) notes.push(measured.title);

  rows.push({
    name,
    path,
    width: measured.viewportWidth,
    scrollWidth: measured.scrollWidth,
    height: measured.scrollHeight,
    status,
    note: notes.join(' | ')
  });

  await page.close();
  await sleep(THROTTLE_MS);
}

const browser = await chromium.launch({ args: ['--no-sandbox'] });

try {
  await mkdir(OUT, { recursive: true });

  for (const [label, width] of Object.entries(WIDTHS)) {
    const context = await browser.newContext({ viewport: { width, height: 900 } });

    await context.clearCookies();
    const login = await context.newPage();
    await login.goto(`${BASE}/login`, { waitUntil: 'networkidle' });
    await login.fill('input[name=email]', EDITOR_EMAIL);
    await login.click('input[type=submit]');
    await login.waitForLoadState('networkidle');
    const signedIn = login.url().includes('/events');
    await login.close();
    // Signing in costs eight requests, which is over the throttle budget on its
    // own. Let the window clear before the first capture, or the first page's
    // assets get 429 and the review starts from a false positive.
    await sleep(2500);

    if (!signedIn) {
      console.error(`Could not sign in as ${EDITOR_EMAIL}. Set SKIP_LOGIN=true, or EDITOR_EMAIL to an editor address.`);
      process.exitCode = 1;
      continue;
    }

    console.log(`\n== ${label} (${width}px wide) ==`);

    for (const [name, path] of Object.entries(PUBLIC_PAGES)) {
      await capture(context, name, path);
    }

    for (const path of CMS_PATHS) {
      await capture(context, `cms-${path.replaceAll('/', '-')}`, `/${path}`);
    }

    await context.close();
  }
} finally {
  await browser.close();
}

const report = rows.map((row) => ({
  ...row,
  scrollWidth: row.scrollWidth ?? '-',
  height: row.height ?? '-'
}));

await writeFile(`${OUT}/report.json`, `${JSON.stringify(report, null, 2)}\n`);

const pad = (value, width) => String(value).padEnd(width);
console.log(`\n${pad('page', 24)}${pad('width', 8)}${pad('scrollW', 10)}${pad('height', 9)}status  note`);
for (const row of report) {
  console.log(`${pad(row.name, 24)}${pad(row.width, 8)}${pad(row.scrollWidth, 10)}${pad(row.height, 9)}${pad(row.status, 7)}${row.note}`);
}

const overflows = report.filter((row) => row.note.includes('HORIZONTAL OVERFLOW'));
const broken = report.filter((row) => row.note.includes('BROKEN IMAGE'));
const failedSubresources = report.filter((row) => row.note.includes('SUBRESOURCE'));
const failures = report.filter((row) => row.status !== 200);

console.log(`\n${report.length} captures in ${OUT}`);

if (failures.length) {
  console.log(`${failures.length} page(s) did not return 200 - check for throttle or auth problems.`);
}
if (failedSubresources.length) {
  console.log(
    `${failedSubresources.length} page(s) had a failed subresource. Check the note column: a 429 is ` +
      `Rack::Attack throttling (5 requests per 2s, and one page view can exceed that), which leaves a ` +
      `page screenshotting a 429'd image - re-run after a pause. The map page failing is expected ` +
      `without GOOGLE_MAPS_JAVASCRIPT_API_KEY.`
  );
}
if (broken.length) {
  console.log(`${broken.length} page(s) contain an image the browser could not decode.`);
}
if (overflows.length) {
  console.log(`${overflows.length} page(s) overflow their viewport horizontally - see the note column.`);
}