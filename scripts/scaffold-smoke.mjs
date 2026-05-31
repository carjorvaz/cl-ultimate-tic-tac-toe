#!/usr/bin/env node
// SPDX-License-Identifier: AGPL-3.0-or-later

import { mkdtemp, cp, rm, chmod, lstat, readdir } from 'node:fs/promises';
import { existsSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join, resolve } from 'node:path';
import { spawn } from 'node:child_process';

const repoRoot = resolve(new URL('..', import.meta.url).pathname);
const templateRoot = join(repoRoot, 'scaffold', 'template');

const requiredFiles = [
  '.envrc',
  'flake.nix',
  'app.asd',
  'README.md',
  'AGENTS.md',
  'assets/style.lass',
  'docs/README.md',
  'docs/ARCHITECTURE.md',
  'docs/HARNESS.md',
  'docs/PRODUCT.md',
  'docs/RELIABILITY.md',
  'docs/QUALITY.md',
  'docs/PLANS.md',
  'docs/technical-debt.md',
  'scripts/run.lisp',
  'scripts/test.lisp',
  'scripts/build-assets.lisp',
  'scripts/validate-assets.lisp',
  'scripts/validate-architecture.lisp',
  'scripts/validate-docs.lisp',
  'scripts/browser-smoke.mjs',
  'src/package.lisp',
  'src/domain.lisp',
  'src/web.lisp',
  'static/app.js',
  'static/htmx.min.js',
  'static/style.css',
  't/package.lisp',
  't/domain-tests.lisp',
  't/web-tests.lisp',
];

function run(command, args, cwd) {
  return new Promise((resolvePromise, reject) => {
    const child = spawn(command, args, {
      cwd,
      env: { ...process.env, HOME: process.env.HOME || tmpdir() },
      stdio: ['ignore', 'pipe', 'pipe'],
    });
    let stdout = '';
    let stderr = '';
    child.stdout.on('data', (chunk) => { stdout += chunk; });
    child.stderr.on('data', (chunk) => { stderr += chunk; });
    child.on('error', reject);
    child.on('close', (code) => {
      if (code === 0) {
        resolvePromise({ stdout, stderr });
      } else {
        const error = new Error(`${command} ${args.join(' ')} failed with ${code}\n${stdout}\n${stderr}`);
        error.stdout = stdout;
        error.stderr = stderr;
        reject(error);
      }
    });
  });
}

async function makeWritable(path) {
  const info = await lstat(path);
  if (info.isDirectory()) {
    await chmod(path, 0o700);
    const entries = await readdir(path);
    await Promise.all(entries.map((entry) => makeWritable(join(path, entry))));
  } else {
    await chmod(path, 0o600);
  }
}

async function main() {
  const missing = requiredFiles.filter((relativePath) => !existsSync(join(templateRoot, relativePath)));
  if (missing.length > 0) {
    throw new Error(`Scaffold template is missing required files:\n- ${missing.join('\n- ')}`);
  }

  const workspace = await mkdtemp(join(tmpdir(), 'cl-web-template-'));
  try {
    await cp(templateRoot, workspace, { recursive: true });
    const commands = [
      ['nix', ['develop', '-c', 'sbcl', '--script', 'scripts/validate-docs.lisp']],
      ['nix', ['develop', '-c', 'sbcl', '--script', 'scripts/validate-assets.lisp']],
      ['nix', ['develop', '-c', 'sbcl', '--script', 'scripts/test.lisp']],
      ['nix', ['develop', '-c', 'sbcl', '--script', 'scripts/validate-architecture.lisp']],
    ];
    for (const [command, args] of commands) {
      await run(command, args, workspace);
    }
    console.log(`Scaffold smoke passed in ${workspace}`);
  } finally {
    if (!process.env.SCAFFOLD_SMOKE_KEEP_TMP) {
      await makeWritable(workspace).catch(() => {});
      await rm(workspace, { recursive: true, force: true });
    }
  }
}

main().catch((error) => {
  console.error(error.message);
  process.exit(1);
});
