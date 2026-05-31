#!/usr/bin/env node
/*
 * Playwright testing agent for collaborator relevance.
 *
 * Usage:
 *   node tools/testing/collab-relevance-agent.mjs --record-auth
 *   node tools/testing/collab-relevance-agent.mjs --channelKey youtube_UCBJycsmduvYEL83R_U4JriQ
 *
 * Env options:
 *   APP_BASE_URL=https://tandem-ce3fd.web.app
 *   SOURCE_TERMS=tech,smartphone,review,gadget
 *   BLOCKED_TERMS=nursery,rhyme,kids,song,cartoon
 */

import fs from 'node:fs';
import path from 'node:path';
import { chromium } from 'playwright';

const args = new Set(process.argv.slice(2));
const appBaseUrl = process.env.APP_BASE_URL ?? 'https://tandem-ce3fd.web.app';
const channelKeyArg = process.argv.find((v) => v.startsWith('--channelKey='));
const channelKey = channelKeyArg?.split('=')[1] ?? process.env.CHANNEL_KEY;
const sourceTerms = splitCsv(process.env.SOURCE_TERMS ?? 'tech,smartphone,review,gadget,ai');
const blockedTerms = splitCsv(process.env.BLOCKED_TERMS ?? 'nursery,rhyme,kids song,kids,cartoon');

const authDir = path.join(process.cwd(), 'tools', 'testing', '.auth');
const authPath = path.join(authDir, 'user.json');

await fs.promises.mkdir(authDir, { recursive: true });

if (args.has('--record-auth')) {
  await recordAuth();
  process.exit(0);
}

if (!channelKey) {
  console.error('Missing channel key. Use --channelKey=<key> or CHANNEL_KEY env var.');
  process.exit(1);
}

if (!fs.existsSync(authPath)) {
  console.error('Auth state not found. Run: node tools/testing/collab-relevance-agent.mjs --record-auth');
  process.exit(1);
}

await runRelevanceCheck(channelKey);

async function recordAuth() {
  const browser = await chromium.launch({ headless: false });
  const context = await browser.newContext();
  const page = await context.newPage();

  console.log('Opening sign-in page for manual authentication...');
  await page.goto(`${appBaseUrl}/#/signin`, { waitUntil: 'domcontentloaded' });
  console.log('Complete login in the opened browser window.');
  console.log('Press Enter here when login is done and app is past sign-in.');

  await waitForEnter();
  await context.storageState({ path: authPath });
  await browser.close();
  console.log(`Saved auth state to ${authPath}`);
}

async function runRelevanceCheck(key) {
  const browser = await chromium.launch({ headless: true });
  const context = await browser.newContext({ storageState: authPath });
  const page = await context.newPage();

  await page.goto(`${appBaseUrl}/#/profile/${key}`, { waitUntil: 'domcontentloaded' });

  const collaboratorButton = page.getByRole('button', { name: /find collaborators/i });
  if (await collaboratorButton.count()) {
    await collaboratorButton.first().click();
  } else {
    await page.goto(`${appBaseUrl}/#/matches/${key}`, { waitUntil: 'domcontentloaded' });
  }

  await page.waitForTimeout(6000);

  const cards = page.locator('text=Draft Outreach').locator('xpath=ancestor::div[contains(@class,"Card") or self::div][1]');
  const fallbackCards = page.locator('button:has-text("Draft Outreach")').locator('xpath=ancestor::*[self::div or self::article][1]');

  let texts = [];
  try {
    const count = await cards.count();
    if (count > 0) {
      for (let i = 0; i < count; i += 1) {
        texts.push((await cards.nth(i).innerText()).toLowerCase());
      }
    }
  } catch {
    // fall back below
  }

  if (texts.length === 0) {
    const count = await fallbackCards.count();
    for (let i = 0; i < count; i += 1) {
      texts.push((await fallbackCards.nth(i).innerText()).toLowerCase());
    }
  }

  if (texts.length === 0) {
    const pageText = (await page.locator('body').innerText()).toLowerCase();
    if (pageText.includes('no collaborators found')) {
      console.log('No collaborators returned; relevance check passed by absence of bad matches.');
      await browser.close();
      return;
    }
    console.error('Could not detect collaborator cards. Check selector or app state.');
    await browser.close();
    process.exit(1);
  }

  const violations = [];

  for (const cardText of texts) {
    const hasBlocked = blockedTerms.some((t) => cardText.includes(t));
    const hasSourceSignal = sourceTerms.some((t) => cardText.includes(t));
    if (hasBlocked && !hasSourceSignal) {
      violations.push(cardText.slice(0, 240));
    }
  }

  if (violations.length > 0) {
    console.error('Relevance check failed. Off-niche candidates detected:');
    for (const v of violations) {
      console.error(`- ${v.replace(/\s+/g, ' ')}`);
    }
    await browser.close();
    process.exit(2);
  }

  console.log(`Relevance check passed. Reviewed ${texts.length} collaborator cards.`);
  await browser.close();
}

function splitCsv(value) {
  return value
    .split(',')
    .map((s) => s.trim().toLowerCase())
    .filter(Boolean);
}

function waitForEnter() {
  return new Promise((resolve) => {
    process.stdin.resume();
    process.stdin.once('data', () => {
      process.stdin.pause();
      resolve();
    });
  });
}
