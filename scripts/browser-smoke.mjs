// SPDX-License-Identifier: AGPL-3.0-or-later

import { spawn } from 'node:child_process';
import { createRequire } from 'node:module';
import { existsSync } from 'node:fs';
import { mkdir, readFile, writeFile } from 'node:fs/promises';
import { createServer } from 'node:net';
import path from 'node:path';
import { inflateSync } from 'node:zlib';

const require = createRequire(import.meta.url);
const root = path.resolve(path.dirname(new URL(import.meta.url).pathname), '..');
const timeoutMs = 30000;
const updateScreenshots = process.env.UPDATE_SCREENSHOTS === '1';
const screenshotDir = path.join(root, 'docs', 'assets', 'screenshots');
const screenshotDiffPixelLimit = 0.18;
const screenshotDiffChannelLimit = 8.5;
const screenshotSignificantChannelDelta = 24;
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

function paethPredictor(left, up, upLeft) {
  const estimate = left + up - upLeft;
  const leftDistance = Math.abs(estimate - left);
  const upDistance = Math.abs(estimate - up);
  const upLeftDistance = Math.abs(estimate - upLeft);

  if (leftDistance <= upDistance && leftDistance <= upLeftDistance) {
    return left;
  }
  if (upDistance <= upLeftDistance) {
    return up;
  }
  return upLeft;
}

function decodePng(buffer) {
  const signature = Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]);
  assert(buffer.subarray(0, signature.length).equals(signature), 'screenshot baseline is not a PNG');

  let offset = signature.length;
  let width = null;
  let height = null;
  let bitDepth = null;
  let colorType = null;
  let interlaceMethod = null;
  const idatChunks = [];

  while (offset < buffer.length) {
    const length = buffer.readUInt32BE(offset);
    const type = buffer.toString('ascii', offset + 4, offset + 8);
    const dataStart = offset + 8;
    const dataEnd = dataStart + length;
    const data = buffer.subarray(dataStart, dataEnd);

    if (type === 'IHDR') {
      width = data.readUInt32BE(0);
      height = data.readUInt32BE(4);
      bitDepth = data[8];
      colorType = data[9];
      interlaceMethod = data[12];
    } else if (type === 'IDAT') {
      idatChunks.push(data);
    } else if (type === 'IEND') {
      break;
    }

    offset = dataEnd + 4;
  }

  assert(width && height, 'screenshot baseline PNG is missing IHDR');
  assert(bitDepth === 8, `unsupported screenshot PNG bit depth ${bitDepth}`);
  assert(colorType === 2 || colorType === 6, `unsupported screenshot PNG color type ${colorType}`);
  assert(interlaceMethod === 0, 'interlaced screenshot PNGs are not supported');

  const channels = colorType === 6 ? 4 : 3;
  const bytesPerPixel = channels;
  const rowLength = width * channels;
  const inflated = inflateSync(Buffer.concat(idatChunks));
  const pixels = Buffer.alloc(width * height * 4);
  const previousRow = Buffer.alloc(rowLength);
  let inputOffset = 0;

  for (let y = 0; y < height; y += 1) {
    const filter = inflated[inputOffset];
    inputOffset += 1;
    const row = Buffer.from(inflated.subarray(inputOffset, inputOffset + rowLength));
    inputOffset += rowLength;

    for (let x = 0; x < rowLength; x += 1) {
      const left = x >= bytesPerPixel ? row[x - bytesPerPixel] : 0;
      const up = previousRow[x];
      const upLeft = x >= bytesPerPixel ? previousRow[x - bytesPerPixel] : 0;
      let predictor = 0;

      if (filter === 1) {
        predictor = left;
      } else if (filter === 2) {
        predictor = up;
      } else if (filter === 3) {
        predictor = Math.floor((left + up) / 2);
      } else if (filter === 4) {
        predictor = paethPredictor(left, up, upLeft);
      } else {
        assert(filter === 0, `unsupported screenshot PNG filter ${filter}`);
      }

      row[x] = (row[x] + predictor) & 0xff;
    }

    for (let x = 0; x < width; x += 1) {
      const sourceOffset = x * channels;
      const targetOffset = ((y * width) + x) * 4;
      pixels[targetOffset] = row[sourceOffset];
      pixels[targetOffset + 1] = row[sourceOffset + 1];
      pixels[targetOffset + 2] = row[sourceOffset + 2];
      pixels[targetOffset + 3] = colorType === 6 ? row[sourceOffset + 3] : 255;
    }

    previousRow.set(row);
  }

  return { width, height, pixels };
}

function screenshotDiff(actualBuffer, expectedBuffer) {
  const actual = decodePng(actualBuffer);
  const expected = decodePng(expectedBuffer);
  assert(
    actual.width === expected.width && actual.height === expected.height,
    `screenshot dimensions changed from ${expected.width}x${expected.height} to ${actual.width}x${actual.height}`,
  );

  let changedPixels = 0;
  let channelDelta = 0;
  const pixelCount = actual.width * actual.height;

  for (let offset = 0; offset < actual.pixels.length; offset += 4) {
    const redDelta = Math.abs(actual.pixels[offset] - expected.pixels[offset]);
    const greenDelta = Math.abs(actual.pixels[offset + 1] - expected.pixels[offset + 1]);
    const blueDelta = Math.abs(actual.pixels[offset + 2] - expected.pixels[offset + 2]);
    const maxDelta = Math.max(redDelta, greenDelta, blueDelta);

    channelDelta += redDelta + greenDelta + blueDelta;
    if (maxDelta > screenshotSignificantChannelDelta) {
      changedPixels += 1;
    }
  }

  return {
    changedRatio: changedPixels / pixelCount,
    averageChannelDelta: channelDelta / (pixelCount * 3),
  };
}

async function assertScreenshotBaseline(page, fileName, label) {
  const screenshot = await page.screenshot({ fullPage: false });
  const screenshotPath = path.join(screenshotDir, fileName);

  if (updateScreenshots) {
    await mkdir(screenshotDir, { recursive: true });
    await writeFile(screenshotPath, screenshot);
    return;
  }

  const baseline = await readFile(screenshotPath);
  const diff = screenshotDiff(screenshot, baseline);
  assert(
    diff.changedRatio <= screenshotDiffPixelLimit
      && diff.averageChannelDelta <= screenshotDiffChannelLimit,
    `${label} screenshot differs from ${fileName}: ${(diff.changedRatio * 100).toFixed(3)}% changed pixels, ${diff.averageChannelDelta.toFixed(3)} average channel delta. Run UPDATE_SCREENSHOTS=1 if the new rendering is intentional.`,
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

async function assertAccessibilityStructure(page, label) {
  const report = await page.evaluate(() => {
    const describe = (element) => {
      const tag = element.tagName.toLowerCase();
      const id = element.id ? `#${element.id}` : '';
      const classText = typeof element.className === 'string' ? element.className : '';
      const className = classText.trim().split(/\s+/).filter(Boolean).slice(0, 2).join('.');
      return `${tag}${id}${className ? `.${className}` : ''}`;
    };
    const firstChildLegend = (fieldset) =>
      [...fieldset.children].find((child) => child.tagName.toLowerCase() === 'legend');
    const isFocusable = (element) =>
      !element.disabled
        && element.type !== 'hidden'
        && element.tabIndex >= 0
        && element.getClientRects().length > 0;

    const idCounts = [...document.querySelectorAll('[id]')].reduce((counts, element) => {
      counts[element.id] = (counts[element.id] || 0) + 1;
      return counts;
    }, {});
    const duplicateIds = Object.entries(idCounts)
      .filter(([, count]) => count > 1)
      .map(([id, count]) => `${id} (${count})`);

    const ariaReferenceAttributes = [
      'aria-activedescendant',
      'aria-controls',
      'aria-describedby',
      'aria-labelledby',
      'aria-owns',
    ];
    const missingAriaReferences = [];
    for (const attribute of ariaReferenceAttributes) {
      for (const element of document.querySelectorAll(`[${attribute}]`)) {
        const value = element.getAttribute(attribute)?.trim() || '';
        if (!value) {
          missingAriaReferences.push(`${describe(element)} ${attribute} is empty`);
          continue;
        }

        for (const id of value.split(/\s+/)) {
          if (!document.getElementById(id)) {
            missingAriaReferences.push(`${describe(element)} ${attribute} -> ${id}`);
          }
        }
      }
    }

    const brokenLabelTargets = [...document.querySelectorAll('label[for]')]
      .filter((label) => !label.htmlFor || !document.getElementById(label.htmlFor))
      .map((label) => `${describe(label)} -> ${label.htmlFor || '(empty)'}`);
    const imagesWithoutAlt = [...document.querySelectorAll('img:not([alt])')]
      .map(describe);
    const focusablesInAriaHidden = [...document.querySelectorAll('a[href], button, input, select, textarea, [tabindex]')]
      .filter((element) => isFocusable(element) && element.closest('[aria-hidden="true"]'))
      .map(describe);
    const fieldsetsWithoutLegend = [...document.querySelectorAll('fieldset')]
      .filter((fieldset) => !firstChildLegend(fieldset)?.textContent.trim())
      .map(describe);
    const radioInputsWithoutLegend = [...document.querySelectorAll('input[type="radio"]')]
      .filter((input) => {
        const fieldset = input.closest('fieldset');
        return !fieldset || !firstChildLegend(fieldset)?.textContent.trim();
      })
      .map(describe);

    return {
      duplicateIds,
      missingAriaReferences,
      brokenLabelTargets,
      imagesWithoutAlt,
      focusablesInAriaHidden,
      fieldsetsWithoutLegend,
      radioInputsWithoutLegend,
      mainCount: document.querySelectorAll('main').length,
      h1Count: document.querySelectorAll('h1').length,
      documentTitle: document.title.trim(),
      htmlLang: document.documentElement.lang.trim(),
    };
  });

  const problems = [];
  if (report.duplicateIds.length > 0) {
    problems.push(`duplicate ids: ${report.duplicateIds.join(', ')}`);
  }
  if (report.missingAriaReferences.length > 0) {
    problems.push(`broken ARIA references: ${report.missingAriaReferences.join(', ')}`);
  }
  if (report.brokenLabelTargets.length > 0) {
    problems.push(`broken label targets: ${report.brokenLabelTargets.join(', ')}`);
  }
  if (report.imagesWithoutAlt.length > 0) {
    problems.push(`images without alt: ${report.imagesWithoutAlt.join(', ')}`);
  }
  if (report.focusablesInAriaHidden.length > 0) {
    problems.push(`focusable controls inside aria-hidden content: ${report.focusablesInAriaHidden.join(', ')}`);
  }
  if (report.fieldsetsWithoutLegend.length > 0) {
    problems.push(`fieldsets without legends: ${report.fieldsetsWithoutLegend.join(', ')}`);
  }
  if (report.radioInputsWithoutLegend.length > 0) {
    problems.push(`radio inputs without fieldset legends: ${report.radioInputsWithoutLegend.join(', ')}`);
  }
  if (report.mainCount !== 1) {
    problems.push(`expected one main landmark, found ${report.mainCount}`);
  }
  if (report.h1Count !== 1) {
    problems.push(`expected one h1, found ${report.h1Count}`);
  }
  if (!report.documentTitle) {
    problems.push('document title is empty');
  }
  if (!report.htmlLang) {
    problems.push('html lang is empty');
  }

  assert(problems.length === 0, `${label} accessibility structure issues:\n${problems.join('\n')}`);
}

async function assertKeyboardStartupFlow(page, label) {
  async function assertFocused(selector, description) {
    const matched = await page.evaluate((focusSelector) =>
      document.activeElement?.matches(focusSelector),
    selector);
    assert(matched, `${label} keyboard flow did not reach ${description}`);
  }
  async function assertChecked(selector, description) {
    const checked = await page.evaluate((inputSelector) =>
      document.querySelector(inputSelector)?.checked === true,
    selector);
    assert(checked, `${label} keyboard flow did not select ${description}`);
  }

  await page.evaluate(() => {
    document.activeElement?.blur();
  });

  await page.keyboard.press('Tab');
  await assertFocused('.reset-button', 'topbar new game button');
  await page.keyboard.press('Tab');
  await assertFocused('#player-x-name', 'X player name');
  await page.keyboard.press('Tab');
  await assertFocused('#player-o-name', 'O player name');
  await page.keyboard.press('Tab');
  await assertFocused('input[name="opponent"][value="human"]', 'human opponent option');

  await page.keyboard.press('ArrowRight');
  await assertChecked('input[name="opponent"][value="easy"]', 'easy opponent option');
  await page.keyboard.press('ArrowRight');
  await assertChecked('input[name="opponent"][value="normal"]', 'normal opponent option');
  await page.keyboard.press('ArrowLeft');
  await assertChecked('input[name="opponent"][value="easy"]', 'easy opponent option');
  await page.keyboard.press('ArrowLeft');
  await assertChecked('input[name="opponent"][value="human"]', 'human opponent option');

  await page.keyboard.press('Tab');
  await assertFocused('input[name="first-player"][value="x"]', 'X first-player option');
  await page.keyboard.press('Tab');
  await assertFocused('.players-button', 'start button');

  await page.check('input[name="opponent"][value="human"]', { force: true });
}

async function assertStartupNameFields(page, label) {
  const fields = await page.$$eval('.player-field input', (inputs) =>
    inputs.map((input) => ({
      id: input.id,
      value: input.value,
      placeholder: input.getAttribute('placeholder') || '',
    })),
  );

  assert(fields.length === 2, `${label} did not render both player name fields`);
  for (const field of fields) {
    assert(field.value === '', `${label} ${field.id} should start blank, not "${field.value}"`);
    assert(field.placeholder === 'Name', `${label} ${field.id} should have a name placeholder`);
  }
}

async function gameLayoutSnapshot(page) {
  return page.evaluate(() => {
    const box = (selector) => {
      const element = document.querySelector(selector);
      if (!element) {
        return null;
      }

      const rect = element.getBoundingClientRect();
      return {
        top: rect.top,
        left: rect.left,
        width: rect.width,
        height: rect.height,
      };
    };

    return {
      board: box('.macro-board'),
      playerRow: box('.players-form, .player-strip'),
    };
  });
}

function assertFirstMoveLayoutStable(before, after, label) {
  assert(before.board && after.board, `${label} could not measure the macro board`);
  assert(before.playerRow && after.playerRow, `${label} could not measure the player row`);

  const tolerance = 6;
  const checks = [
    ['board top', before.board.top, after.board.top],
    ['board left', before.board.left, after.board.left],
    ['board width', before.board.width, after.board.width],
    ['board height', before.board.height, after.board.height],
    ['player row height', before.playerRow.height, after.playerRow.height],
  ];

  for (const [name, expected, actual] of checks) {
    const delta = Math.abs(actual - expected);
    assert(
      delta <= tolerance,
      `${label} shifted ${name} by ${delta.toFixed(1)}px after the first move`,
    );
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
  assert((await page.locator('.opponent-choice').count()) === 3, `${viewport.name} did not render opponent choices`);
  await assertAccessibleControls(page, viewport.name);
  await assertAccessibilityStructure(page, viewport.name);
  await assertKeyboardStartupFlow(page, viewport.name);
  await assertStartupNameFields(page, viewport.name);
  await assertVisibleGame(page, viewport.name);
  await assertNoHorizontalOverflow(page, viewport.name);
  if (viewport.name === 'desktop') {
    await assertScreenshotBaseline(page, 'game-start.png', 'desktop start');
  }

  await page.fill('input[name="player-x"]', 'Ada');
  await page.fill('input[name="player-o"]', 'Bea');
  await page.check('input[name="first-player"][value="o"]', { force: true });
  await page.click('.players-button');
  await waitForText(page, 'Bea to move');
  await assertAccessibleControls(page, `${viewport.name} after settings`);
  await assertAccessibilityStructure(page, `${viewport.name} after settings`);
  const beforeFirstMoveLayout = await gameLayoutSnapshot(page);

  await page.click('.cell-button');
  await waitForText(page, 'Ada to move');
  assert((await page.locator('.mark').count()) === 1, `${viewport.name} did not render the first mark`);
  assert((await page.locator('.cell-button').count()) === 8, `${viewport.name} did not target the next board`);
  await assertAccessibilityStructure(page, `${viewport.name} after move`);
  assertFirstMoveLayoutStable(
    beforeFirstMoveLayout,
    await gameLayoutSnapshot(page),
    `${viewport.name} first move`,
  );
  await assertNoHorizontalOverflow(page, `${viewport.name} after move`);
  if (viewport.name === 'desktop') {
    await assertScreenshotBaseline(page, 'game-in-progress.png', 'desktop in-progress');
  }

  await context.close();
  assert(failures.length === 0, `${viewport.name} browser failures:\n${failures.join('\n')}`);
}

async function smokeLegalNotices(browser, viewport) {
  const context = await browser.newContext({
    viewport: { width: viewport.width, height: viewport.height },
    deviceScaleFactor: 1,
  });
  const page = await context.newPage();
  const failures = [];
  const label = `${viewport.name} legal notices`;
  captureBrowserFailures(page, failures);

  await page.goto(baseUrl, { waitUntil: 'commit' });
  await page.waitForSelector('#game', { timeout: timeoutMs });
  await assertNoHorizontalOverflow(page, `${label} entry`);

  await page.click('#site-footer a[href="/legal"]');
  await page.waitForURL(/\/legal$/, { timeout: timeoutMs });
  await waitForText(page, 'Legal Notices');
  await waitForText(page, 'GNU Affero General Public License');
  await waitForText(page, 'without warranty');
  assert((await page.locator('.legal-shell').count()) === 1, `${label} did not render the legal shell`);
  assert((await page.locator('.legal-shell a[href="/"]').count()) === 1, `${label} did not render a back-to-game link`);
  assert((await page.locator('.legal-shell a[rel="license"]').count()) === 1, `${label} did not render a license link`);
  assert((await page.locator('#site-footer a[href="/legal"]').count()) === 1, `${label} did not render the footer legal link`);
  await assertAccessibilityStructure(page, label);
  await assertNoHorizontalOverflow(page, label);

  await page.click('.legal-shell a[href="/"]');
  await page.waitForURL(baseUrl, { timeout: timeoutMs });
  await page.waitForSelector('#game', { timeout: timeoutMs });
  await waitForText(page, 'X to move');
  await assertNoHorizontalOverflow(page, `${label} return`);

  await context.close();
  assert(failures.length === 0, `${label} browser failures:\n${failures.join('\n')}`);
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
  await page.check('input[name="opponent"][value="normal"]', { force: true });
  await page.check('input[name="first-player"][value="o"]', { force: true });
  await page.click('.players-button');

  await waitForText(page, 'Ada to move');
  await waitForText(page, 'Center board');
  assert((await page.locator('.players-form').count()) === 0, 'computer-start flow kept setup form visible');
  assert((await page.locator('.player-strip').count()) === 1, 'computer-start flow did not show player summary');
  assert((await page.locator('.chip-kind').innerText()) === 'Normal CPU', 'computer player was not labeled with difficulty');
  assert((await page.locator('.mark').count()) === 1, 'computer-start flow did not place the opening move');
  assert((await page.locator('.mark.mark-o').count()) === 1, 'computer-start flow did not place O first');
  assert((await page.locator('.cell-button').count()) === 9, 'computer-start flow did not target the center board');
  await assertAccessibleControls(page, 'computer-start flow');
  await assertAccessibilityStructure(page, 'computer-start flow');
  await assertNoHorizontalOverflow(page, 'computer-start flow');

  await playMove(page, 4, 4, 2);
  await waitForText(page, 'Ada to move');
  assert((await page.locator('.mark').count()) === 3, 'computer opponent did not reply after the human move');
  assert((await page.locator('.mark.mark-x').count()) === 1, 'human move did not render as X');
  assert((await page.locator('.mark.mark-o').count()) === 2, 'computer reply did not render as O');
  await assertAccessibleControls(page, 'computer reply flow');
  await assertAccessibilityStructure(page, 'computer reply flow');
  await assertNoHorizontalOverflow(page, 'computer reply flow');

  await context.close();
  assert(failures.length === 0, `computer opponent browser failures:\n${failures.join('\n')}`);
}

async function smokeEasyComputerOpponent(browser) {
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
  await page.check('input[name="opponent"][value="easy"]', { force: true });
  await page.click('.players-button');

  await waitForText(page, 'Ada to move');
  await page.click('.cell-button');
  await waitForText(page, 'Ada to move');
  await waitForText(page, 'Top board');
  assert((await page.locator('.chip-kind').innerText()) === 'Easy CPU', 'easy computer player was not labeled with difficulty');
  assert((await page.locator('.mark.mark-x').count()) === 1, 'easy flow did not render the human X move');
  assert((await page.locator('.mark.mark-o').count()) === 1, 'easy flow did not render the computer O reply');
  assert((await page.locator('.cell-button').count()) === 9, 'easy flow did not route play to the top board');
  await assertAccessibleControls(page, 'easy computer flow');
  await assertAccessibilityStructure(page, 'easy computer flow');
  await assertNoHorizontalOverflow(page, 'easy computer flow');

  await context.close();
  assert(failures.length === 0, `easy computer browser failures:\n${failures.join('\n')}`);
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
  await assertAccessibilityStructure(page, 'game-over dialog');

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
  await assertAccessibilityStructure(page, 'game-over reset flow');
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
      await smokeLegalNotices(browser, viewport);
    }
    await smokeComputerOpponent(browser);
    await smokeEasyComputerOpponent(browser);
    await smokeGameOverDialog(browser);

    console.log(`Browser smoke passed for ${viewports.map((viewport) => viewport.name).join(', ')}, legal notices, computer opponents, and game-over dialog.`);
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
