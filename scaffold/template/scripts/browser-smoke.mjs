#!/usr/bin/env node
// SPDX-License-Identifier: AGPL-3.0-or-later

import { spawn } from 'node:child_process';
import { createRequire } from 'node:module';

const require = createRequire(import.meta.url);

const timeoutMs = Number.parseInt(process.env.BROWSER_SMOKE_TIMEOUT_MS || '15000', 10);
const port = 43000 + Math.floor(Math.random() * 1000);
const baseUrl = `http://127.0.0.1:${port}`;

function loadPlaywright() {
  const explicitPath = process.env.PLAYWRIGHT_CORE_PATH;
  if (explicitPath) return require(explicitPath);

  try {
    return require('playwright-core');
  } catch (_coreError) {
    return require('playwright');
  }
}

const { chromium } = loadPlaywright();

function wait(ms) { return new Promise((resolve) => setTimeout(resolve, ms)); }

function startServer() {
  const child = spawn('sbcl', ['--script', 'scripts/run.lisp'], {
    env: { ...process.env, PORT: String(port), SERVER: 'hunchentoot' },
    stdio: ['ignore', 'pipe', 'pipe'],
  });
  let output = '';
  child.stdout.on('data', (chunk) => { output += chunk; });
  child.stderr.on('data', (chunk) => { output += chunk; });
  return { child, output: () => output };
}

async function waitForHealth() {
  const deadline = Date.now() + timeoutMs;
  while (Date.now() < deadline) {
    try {
      const response = await fetch(`${baseUrl}/health`);
      if (response.ok && (await response.text()).trim() === 'ok') return;
    } catch (_error) {}
    await wait(250);
  }
  throw new Error('Timed out waiting for /health');
}

async function main() {
  const server = startServer();
  let browser;
  try {
    await waitForHealth();
    browser = await chromium.launch({ headless: true });
    const page = await browser.newPage({ viewport: { width: 1024, height: 768 } });
    const unexpected = [];
    page.on('request', (request) => {
      if (!request.url().startsWith(baseUrl)) unexpected.push(request.url());
    });
    await page.goto(baseUrl, { waitUntil: 'networkidle' });
    await page.getByRole('heading', { name: 'Common Lisp Web App' }).waitFor({ timeout: timeoutMs });
    await page.getByRole('link', { name: 'Health' }).waitFor({ timeout: timeoutMs });
    await page.getByRole('link', { name: 'Version' }).waitFor({ timeout: timeoutMs });
    const box = await page.locator('.shell').boundingBox();
    if (!box || box.width < 300 || box.height < 180) throw new Error(`Shell rendered too small: ${JSON.stringify(box)}`);
    if (unexpected.length > 0) throw new Error(`Unexpected external requests: ${unexpected.join(', ')}`);
    console.log('Browser smoke passed.');
  } catch (error) {
    console.error(`Recent server output:\n${server.output()}`);
    throw error;
  } finally {
    if (browser) await browser.close();
    server.child.kill('SIGTERM');
  }
}

main().catch((error) => { console.error(error); process.exit(1); });
