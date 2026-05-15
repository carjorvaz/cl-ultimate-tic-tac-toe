// SPDX-License-Identifier: AGPL-3.0-or-later

import { spawn } from 'node:child_process';
import { createRequire } from 'node:module';
import { existsSync } from 'node:fs';
import { mkdir, writeFile } from 'node:fs/promises';
import { createServer } from 'node:net';
import path from 'node:path';

const require = createRequire(import.meta.url);
const root = path.resolve(path.dirname(new URL(import.meta.url).pathname), '..');
const timeoutMs = 10000;
const updateScreenshots = process.env.UPDATE_SCREENSHOTS === '1';
const screenshotDir = path.join(root, 'docs', 'assets', 'screenshots');
const viewports = [
  { name: 'desktop', width: 1280, height: 900 },
  { name: 'mobile', width: 390, height: 844 },
];
const xGlobalWinMoves = [
  [0, 0], [0, 1], [1, 2], [2, 0], [0, 3], [3, 4],
  [4, 5], [5, 0], [0, 6], [6, 1], [1, 0], [4, 1],
  [1, 3], [3, 1], [1, 6], [6, 2], [2, 3], [3, 2],
  [2, 4], [4, 2], [2, 5],
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

  const pathCandidate = findExecutableOnPath([
    'chromium',
    'chromium-browser',
    'google-chrome',
    'google-chrome-stable',
    'brave',
    'microsoft-edge',
  ]);
  if (pathCandidate) {
    return pathCandidate;
  }

  const candidates = [
    '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome',
    '/Applications/Chromium.app/Contents/MacOS/Chromium',
    '/Applications/Brave Browser.app/Contents/MacOS/Brave Browser',
    '/Applications/Microsoft Edge.app/Contents/MacOS/Microsoft Edge',
  ];

  return candidates.find((candidate) => existsSync(candidate));
}

function findExecutableOnPath(names) {
  const searchPaths = (process.env.PATH || '').split(path.delimiter).filter(Boolean);
  for (const directory of searchPaths) {
    for (const name of names) {
      const candidate = path.join(directory, name);
      if (existsSync(candidate)) {
        return candidate;
      }
    }
  }
  return undefined;
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

function captureBrowserFailures(page, failures) {
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

async function maybeWriteScreenshot(page, fileName) {
  if (!updateScreenshots) {
    return;
  }

  await mkdir(screenshotDir, { recursive: true });
  await writeFile(
    path.join(screenshotDir, fileName),
    await page.screenshot({ fullPage: false }),
  );
}

async function assertAccessibleControls(page, label) {
  const unlabeledCells = await page.$$eval('.cell-button', (buttons) =>
    buttons.filter((button) => !button.getAttribute('aria-label')?.trim()).length,
  );
  const unlabeledButtons = await page.$$eval('button', (buttons) =>
    buttons.filter((button) => {
      const explicitLabel = button.getAttribute('aria-label')?.trim();
      return !explicitLabel && !button.textContent.trim();
    }).length,
  );
  const unlabeledInputs = await page.$$eval('input:not([type="hidden"])', (inputs) =>
    inputs.filter((input) => {
      const explicitLabel = input.getAttribute('aria-label')?.trim();
      const labelledBy = input.getAttribute('aria-labelledby')?.trim();
      return !explicitLabel && !labelledBy && input.labels.length === 0;
    }).length,
  );
  const formsWithoutCsrf = await page.$$eval('form[method="post"]', (forms) =>
    forms.filter((form) => !form.querySelector('input[name="csrf-token"]')).length,
  );

  assert(unlabeledCells === 0, `${label} has ${unlabeledCells} playable cells without labels`);
  assert(unlabeledButtons === 0, `${label} has ${unlabeledButtons} buttons without accessible names`);
  assert(unlabeledInputs === 0, `${label} has ${unlabeledInputs} inputs without labels`);
  assert(formsWithoutCsrf === 0, `${label} has ${formsWithoutCsrf} POST forms without CSRF tokens`);
}

async function assertKeyboardStartupFlow(page, label) {
  const expectedFocus = [
    ['.reset-button', 'topbar new game button'],
    ['#player-x-name', 'X player name'],
    ['#player-o-name', 'O player name'],
    ['input[name="opponent"][value="human"]', 'human opponent option'],
    ['input[name="first-player"][value="x"]', 'X first-player option'],
    ['.players-button', 'start button'],
  ];

  await page.evaluate(() => {
    document.activeElement?.blur();
  });

  for (const [selector, description] of expectedFocus) {
    await page.keyboard.press('Tab');
    const matched = await page.evaluate((focusSelector) =>
      document.activeElement?.matches(focusSelector),
    selector);
    assert(matched, `${label} tab order did not reach ${description}`);
  }
}

async function waitForHtmx(page) {
  await page.waitForFunction(() => window.htmx, { timeout: timeoutMs });
}

async function playMove(page, board, cell, moveNumber) {
  const button = page.locator(
    `form.cell-form:has(input[name="board"][value="${board}"]):has(input[name="cell"][value="${cell}"]) button`,
  );
  await button.click();
  await page.waitForFunction(
    (expectedMarks) => document.querySelectorAll('.mark').length >= expectedMarks
      || document.querySelector('.game-over-modal'),
    moveNumber,
    { timeout: timeoutMs },
  );
}

async function smokeViewport(browser, viewport) {
  const context = await browser.newContext({
    viewport: { width: viewport.width, height: viewport.height },
    deviceScaleFactor: 1,
  });
  const page = await context.newPage();
  const failures = [];
  captureBrowserFailures(page, failures);

  await page.goto(baseUrl, { waitUntil: 'commit' });
  await page.waitForSelector('#game', { timeout: timeoutMs });
  await waitForHtmx(page);
  await waitForText(page, 'X to move');
  assert((await page.locator('.cell-button').count()) === 81, `${viewport.name} did not render 81 playable cells`);
  assert((await page.locator('.opponent-choice').count()) === 2, `${viewport.name} did not render opponent choices`);
  await assertAccessibleControls(page, viewport.name);
  await assertKeyboardStartupFlow(page, viewport.name);
  await assertVisibleGame(page, viewport.name);
  await assertNoHorizontalOverflow(page, viewport.name);
  if (viewport.name === 'desktop') {
    await maybeWriteScreenshot(page, 'game-start.png');
  }

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
  if (viewport.name === 'desktop') {
    await maybeWriteScreenshot(page, 'game-in-progress.png');
  }

  await context.close();
  assert(failures.length === 0, `${viewport.name} browser failures:\n${failures.join('\n')}`);
}

async function smokeComputerOpponent(browser) {
  const context = await browser.newContext({
    viewport: { width: 1280, height: 900 },
    deviceScaleFactor: 1,
  });
  const page = await context.newPage();
  const failures = [];
  captureBrowserFailures(page, failures);

  await page.goto(baseUrl, { waitUntil: 'commit' });
  await page.waitForSelector('#game', { timeout: timeoutMs });
  await waitForHtmx(page);

  await page.fill('input[name="player-x"]', 'Ada');
  await page.fill('input[name="player-o"]', 'CPU');
  await page.check('input[name="opponent"][value="computer"]', { force: true });
  await page.check('input[name="first-player"][value="o"]', { force: true });
  await page.click('.players-button');

  await waitForText(page, 'Ada to move');
  await waitForText(page, 'Center board');
  assert((await page.locator('.players-form').count()) === 0, 'computer-start flow kept setup form visible');
  assert((await page.locator('.player-strip').count()) === 1, 'computer-start flow did not show player summary');
  assert((await page.locator('.chip-kind').innerText()) === 'CPU', 'computer player was not labeled in the summary');
  assert((await page.locator('.mark').count()) === 1, 'computer-start flow did not place the opening move');
  assert((await page.locator('.mark.mark-o').count()) === 1, 'computer-start flow did not place O first');
  assert((await page.locator('.cell-button').count()) === 9, 'computer-start flow did not target the center board');
  await assertAccessibleControls(page, 'computer-start flow');
  await assertNoHorizontalOverflow(page, 'computer-start flow');

  await playMove(page, 4, 4, 2);
  await waitForText(page, 'Ada to move');
  assert((await page.locator('.mark').count()) === 3, 'computer opponent did not reply after the human move');
  assert((await page.locator('.mark.mark-x').count()) === 1, 'human move did not render as X');
  assert((await page.locator('.mark.mark-o').count()) === 2, 'computer reply did not render as O');
  await assertAccessibleControls(page, 'computer reply flow');
  await assertNoHorizontalOverflow(page, 'computer reply flow');

  await context.close();
  assert(failures.length === 0, `computer opponent browser failures:\n${failures.join('\n')}`);
}

async function smokeGameOverDialog(browser) {
  const context = await browser.newContext({
    viewport: { width: 1280, height: 900 },
    deviceScaleFactor: 1,
  });
  const page = await context.newPage();
  const failures = [];
  captureBrowserFailures(page, failures);

  await page.goto(baseUrl, { waitUntil: 'commit' });
  await page.waitForSelector('#game', { timeout: timeoutMs });
  await waitForHtmx(page);

  for (let index = 0; index < xGlobalWinMoves.length; index += 1) {
    const [board, cell] = xGlobalWinMoves[index];
    await playMove(page, board, cell, index + 1);
  }

  await page.waitForSelector(
    '.game-over-modal[role="dialog"][aria-modal="true"][aria-labelledby="game-over-title"][aria-describedby="game-over-detail"]',
    { timeout: timeoutMs },
  );
  await waitForText(page, 'X wins!');
  assert((await page.locator('#game-over-title').innerText()).includes('X wins!'), 'game-over dialog title is wrong');
  assert((await page.locator('#game-over-detail').innerText()).includes('played X'), 'game-over dialog detail is missing');
  assert(await page.locator('.reset-button').evaluate((button) => button.tabIndex === -1), 'background reset button stayed in tab order');

  await page.waitForFunction(() =>
    document.activeElement?.matches('.game-over-modal .dialog-button'),
    null,
    { timeout: timeoutMs },
  );
  await page.keyboard.press('Tab');
  const forwardTrap = await page.evaluate(() =>
    document.activeElement?.matches('.game-over-modal .dialog-button'),
  );
  await page.keyboard.press('Shift+Tab');
  const backwardTrap = await page.evaluate(() =>
    document.activeElement?.matches('.game-over-modal .dialog-button'),
  );
  assert(forwardTrap && backwardTrap, 'game-over dialog did not retain keyboard focus');

  await page.keyboard.press('Enter');
  await waitForText(page, 'X to move');
  assert((await page.locator('.game-over-modal').count()) === 0, 'game-over dialog did not close after new game');
  assert((await page.locator('.cell-button').count()) === 81, 'new game did not restore playable cells');
  await assertNoHorizontalOverflow(page, 'game-over reset flow');

  await context.close();
  assert(failures.length === 0, `game-over browser failures:\n${failures.join('\n')}`);
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
    await smokeComputerOpponent(browser);
    await smokeGameOverDialog(browser);

    console.log(`Browser smoke passed for ${viewports.map((viewport) => viewport.name).join(', ')}, computer opponent, and game-over dialog.`);
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
