// SPDX-License-Identifier: AGPL-3.0-or-later

import { spawn } from 'node:child_process';
import { createRequire } from 'node:module';
import { existsSync } from 'node:fs';
import { createServer } from 'node:net';
import path from 'node:path';

const require = createRequire(import.meta.url);
const root = path.resolve(path.dirname(new URL(import.meta.url).pathname), '..');
const timeoutMs = 10000;
const viewports = [
  { name: 'desktop', width: 1280, height: 900 },
  { name: 'mobile', width: 390, height: 844 },
];
let port = process.env.PORT ? Number(process.env.PORT) : null;
let baseUrl = null;

function loadPlaywright() {
  const explicitPath = process.env.PLAYWRIGHT_CORE_PATH;
  if (explicitPath) {
    return require(explicitPath);
  }

  try {
    return require('playwright-core');
  } catch (error) {
    throw new Error(
      'playwright-core is required. Run through `nix develop` or set PLAYWRIGHT_CORE_PATH.',
      { cause: error },
    );
  }
}

function browserExecutablePath() {
  const explicitPath = process.env.BROWSER || process.env.CHROME_PATH;
  if (explicitPath) {
    return explicitPath;
  }

  if (process.env.PLAYWRIGHT_BROWSERS_PATH) {
    return undefined;
  }

  const candidates = [
    '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome',
    '/Applications/Chromium.app/Contents/MacOS/Chromium',
    '/Applications/Brave Browser.app/Contents/MacOS/Brave Browser',
    '/Applications/Microsoft Edge.app/Contents/MacOS/Microsoft Edge',
  ];

  return candidates.find((candidate) => existsSync(candidate));
}

function delay(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

async function findOpenPort() {
  return new Promise((resolve, reject) => {
    const probe = createServer();
    probe.once('error', reject);
    probe.listen(0, '127.0.0.1', () => {
      const address = probe.address();
      const selectedPort = address.port;
      probe.close(() => resolve(selectedPort));
    });
  });
}

function startServer() {
  const server = spawn('sbcl', ['--script', 'scripts/run.lisp'], {
    cwd: root,
    env: { ...process.env, PORT: String(port) },
    stdio: ['ignore', 'pipe', 'pipe'],
  });
  const logs = [];
  const record = (chunk) => {
    logs.push(chunk.toString());
    while (logs.length > 30) {
      logs.shift();
    }
  };
  server.stdout.on('data', record);
  server.stderr.on('data', record);
  server.on('exit', (code, signal) => {
    if (code !== 0 && signal !== 'SIGTERM') {
      logs.push(`server exited with code ${code ?? 'null'} signal ${signal ?? 'null'}\n`);
    }
  });
  return { server, logs };
}

async function waitForServer() {
  const deadline = Date.now() + timeoutMs;
  while (Date.now() < deadline) {
    try {
      const response = await fetch(baseUrl);
      if (response.ok) {
        return;
      }
    } catch {
      // Keep polling until the server accepts connections.
    }
    await delay(100);
  }
  throw new Error(`Timed out waiting for ${baseUrl}`);
}

async function stopServer(server) {
  if (server.exitCode !== null || server.signalCode !== null) {
    return;
  }

  server.kill('SIGTERM');
  await Promise.race([
    new Promise((resolve) => server.once('exit', resolve)),
    delay(2000).then(() => {
      if (server.exitCode === null && server.signalCode === null) {
        server.kill('SIGKILL');
      }
    }),
  ]);
}

function assert(condition, message) {
  if (!condition) {
    throw new Error(message);
  }
}

async function waitForText(page, text) {
  await page.waitForFunction(
    (expected) => document.body?.innerText.includes(expected),
    text,
    { timeout: timeoutMs },
  );
}

async function assertNoHorizontalOverflow(page, label) {
  const overflow = await page.evaluate(() => {
    const width = window.innerWidth;
    const offenders = [...document.body.querySelectorAll('*')]
      .map((element) => {
        const rect = element.getBoundingClientRect();
        return {
          tag: element.tagName.toLowerCase(),
          className: element.className || '',
          left: rect.left,
          right: rect.right,
          width: rect.width,
        };
      })
      .filter((rect) => rect.width > 0 && (rect.left < -1 || rect.right > width + 1))
      .slice(0, 5);

    return {
      documentWidth: document.documentElement.scrollWidth,
      viewportWidth: width,
      offenders,
    };
  });

  assert(
    overflow.documentWidth <= overflow.viewportWidth + 1,
    `${label} has horizontal document overflow: ${JSON.stringify(overflow)}`,
  );
  assert(
    overflow.offenders.length === 0,
    `${label} has overflowing elements: ${JSON.stringify(overflow.offenders)}`,
  );
}

async function assertVisibleGame(page, label) {
  const gameBox = await page.locator('#game').boundingBox();
  assert(gameBox, `${label} did not render #game`);
  assert(gameBox.width > 200 && gameBox.height > 200, `${label} rendered a tiny game shell`);

  const screenshot = await page.screenshot({ fullPage: false });
  assert(screenshot.length > 15000, `${label} screenshot looks unexpectedly small`);
}

async function assertAccessibleControls(page, label) {
  const unlabeledCells = await page.$$eval('.cell-button', (buttons) =>
    buttons.filter((button) => !button.getAttribute('aria-label')?.trim()).length,
  );
  const formsWithoutCsrf = await page.$$eval('form[method="post"]', (forms) =>
    forms.filter((form) => !form.querySelector('input[name="csrf-token"]')).length,
  );

  assert(unlabeledCells === 0, `${label} has ${unlabeledCells} playable cells without labels`);
  assert(formsWithoutCsrf === 0, `${label} has ${formsWithoutCsrf} POST forms without CSRF tokens`);
}

async function smokeViewport(browser, viewport) {
  const context = await browser.newContext({
    viewport: { width: viewport.width, height: viewport.height },
    deviceScaleFactor: 1,
  });
  const page = await context.newPage();
  const failures = [];

  page.on('pageerror', (error) => failures.push(`page error: ${error.message}`));
  page.on('console', (message) => {
    if (message.type() === 'error') {
      failures.push(`console error: ${message.text()}`);
    }
  });
  page.on('requestfailed', (request) => {
    if (request.url().startsWith(baseUrl)) {
      failures.push(`request failed: ${request.url()} ${request.failure()?.errorText ?? ''}`);
    }
  });
  page.on('request', (request) => {
    const url = request.url();
    if (/^https?:\/\//.test(url) && !url.startsWith(baseUrl)) {
      failures.push(`unexpected external request: ${url}`);
    }
  });

  await page.goto(baseUrl, { waitUntil: 'commit' });
  await page.waitForSelector('#game', { timeout: timeoutMs });
  await waitForText(page, 'X to move');
  assert((await page.locator('.cell-button').count()) === 81, `${viewport.name} did not render 81 playable cells`);
  await assertAccessibleControls(page, viewport.name);
  await assertVisibleGame(page, viewport.name);
  await assertNoHorizontalOverflow(page, viewport.name);

  await page.fill('input[name="player-x"]', 'Ada');
  await page.fill('input[name="player-o"]', 'Bea');
  await page.check('input[name="first-player"][value="o"]', { force: true });
  await page.click('.players-button');
  await waitForText(page, 'Bea to move');
  await assertAccessibleControls(page, `${viewport.name} after settings`);

  await page.click('.cell-button');
  await waitForText(page, 'Ada to move');
  assert((await page.locator('.mark').count()) === 1, `${viewport.name} did not render the first mark`);
  assert((await page.locator('.cell-button').count()) === 8, `${viewport.name} did not target the next board`);
  await assertNoHorizontalOverflow(page, `${viewport.name} after move`);

  await context.close();
  assert(failures.length === 0, `${viewport.name} browser failures:\n${failures.join('\n')}`);
}

async function main() {
  port = port ?? await findOpenPort();
  baseUrl = `http://127.0.0.1:${port}/`;

  const { chromium } = loadPlaywright();
  const executablePath = browserExecutablePath();
  const { server, logs } = startServer();

  let browser;
  try {
    await waitForServer();
    browser = await chromium.launch({
      headless: true,
      executablePath,
      args: ['--no-sandbox'],
    });

    for (const viewport of viewports) {
      await smokeViewport(browser, viewport);
    }

    console.log(`Browser smoke passed for ${viewports.map((viewport) => viewport.name).join(', ')}.`);
  } catch (error) {
    if (logs.length > 0) {
      console.error('Recent server output:');
      console.error(logs.join('').trim());
    }
    throw error;
  } finally {
    if (browser) {
      await browser.close();
    }
    await stopServer(server);
  }
}

main().catch((error) => {
  console.error(error.stack || error.message || error);
  process.exit(1);
});
