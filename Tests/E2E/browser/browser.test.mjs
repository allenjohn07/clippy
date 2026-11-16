// Browser end-to-end checks. Playwright opens a real browser window with text inputs and
// reads back their values; the keystrokes and clicks are real OS events sent by e2ectl,
// because Playwright's own key presses never leave the browser (Clippy wouldn't see them).
//
//   node browser.test.mjs <path to e2ectl> <clippy pid>
import { chromium } from 'playwright';
import { execFileSync } from 'node:child_process';

const [ctl, clippyPid] = process.argv.slice(2);
const run = (...a) => execFileSync(ctl, a, { encoding: 'utf8' }).trim();
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

let passed = 0, failed = 0;
const check = (name, ok, detail = '') => {
  if (ok) { passed++; console.log(`  ✔ ${name}`); }
  else { failed++; console.log(`  ✘ ${name}  ${detail}`); }
};
async function waitFor(fn, timeout = 3000) {
  const end = Date.now() + timeout;
  while (Date.now() < end) { if (await fn()) return true; await sleep(50); }
  return !!(await fn());
}
const popup = () => {
  const s = run('popup', clippyPid);
  if (s === 'none') return null;
  const [x, y, w, h] = s.split(' ').map(Number);
  return { x, y, w, h };
};

/** Safety: only send keys while the browser is the frontmost app. */
function key(spec) {
  const front = run('front');
  if (!/chrom/i.test(front)) {
    console.log(`  ✘ ABORT: browser is not frontmost (front app: "${front}"); not sending keys`);
    process.exit(3);
  }
  run('key', spec);
}

const PAGE = `<!doctype html><title>Clippy E2E</title>
<style>body{font:14px system-ui;margin:0;height:100vh}
#a{position:absolute;top:30px;left:30px;width:360px;font-size:16px}
#b{position:absolute;bottom:20px;left:30px;width:360px;height:60px}</style>
<input id="a" placeholder="top input"><textarea id="b" placeholder="bottom textarea"></textarea>`;

/** Element rect in screen points (CG coordinates: top-left origin). */
const screenRect = (page, sel) => page.evaluate((sel) => {
  const r = document.querySelector(sel).getBoundingClientRect();
  const chromeTop = window.outerHeight - window.innerHeight;
  return { x: window.screenX + r.left, y: window.screenY + chromeTop + r.top, w: r.width, h: r.height };
}, sel);

const noOverlap = (p, r) => p.y >= r.y + r.h || p.y + p.h <= r.y;
const gap = (p, r) => (p.y >= r.y + r.h ? p.y - (r.y + r.h) : r.y - (p.y + p.h));

async function testBrowser(label, launchOpts) {
  let browser;
  try {
    browser = await chromium.launch({
      headless: false, ...launchOpts,
      args: ['--window-position=160,80', '--window-size=900,820'],
    });
  } catch (e) {
    console.log(`\n${label}: skipped (${e.message.split('\n')[0]})`);
    return;
  }
  console.log(`\n${label}`);
  const page = await (await browser.newContext({ viewport: null })).newPage();
  await page.setContent(PAGE);
  await sleep(800);

  const word = `web-${label.toLowerCase().replace(/\W+/g, '')}`;
  run('copy', word);
  await sleep(1000);

  // Top input
  const a = await screenRect(page, '#a');
  run('click', String(a.x + a.w / 2), String(a.y + a.h / 2));
  await waitFor(() => page.evaluate(() => document.activeElement?.id === 'a'));

  key('cmd+v');
  check('⌘V pastes normally', await waitFor(async () => (await page.inputValue('#a')) === word),
        `value=${await page.inputValue('#a')}`);
  await sleep(300);
  check('⌘V does not open the popup', popup() === null);

  await page.evaluate(() => { document.querySelector('#a').value = ''; });
  key('cmd+shift+v');
  const opened = await waitFor(() => popup() !== null);
  check('⌘⇧V opens the popup in a web text input', opened);
  if (opened) {
    const p = popup();
    check('popup does not cover the input', noOverlap(p, a), `popup=${JSON.stringify(p)} input=${JSON.stringify(a)}`);
    check('popup is right next to the input', gap(p, a) < 30, `gap=${gap(p, a)}`);
    key('1');
    check('pressing 1 pastes into the web input',
          await waitFor(async () => (await page.inputValue('#a')) === word),
          `value=${await page.inputValue('#a')}`);
    check('popup closes', await waitFor(() => popup() === null));
  }

  // Bottom textarea
  const b = await screenRect(page, '#b');
  run('click', String(b.x + b.w / 2), String(b.y + b.h / 2));
  await waitFor(() => page.evaluate(() => document.activeElement?.id === 'b'));
  key('cmd+shift+v');
  const opened2 = await waitFor(() => popup() !== null);
  check('⌘⇧V opens the popup in a web textarea', opened2);
  if (opened2) {
    const p = popup();
    check('popup does not cover the textarea', noOverlap(p, b), `popup=${JSON.stringify(p)} textarea=${JSON.stringify(b)}`);
    key('esc');
    check('Esc closes the popup', await waitFor(() => popup() === null));
    await sleep(200);
    check('Esc pastes nothing', (await page.inputValue('#b')) === '', `value=${await page.inputValue('#b')}`);
  }

  await browser.close();
}

await testBrowser('Chromium (Playwright)', {});
await testBrowser('Google Chrome', { channel: 'chrome' });

console.log(`\n${passed} passed, ${failed} failed (browser)`);
process.exit(failed === 0 ? 0 : 1);
