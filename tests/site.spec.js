const { test, expect } = require('@playwright/test');
const fs = require('fs');
const path = require('path');

const WGET_COMMAND = 'bash <(wget -q -O - https://wireguard.sh/wireguard.sh)';
const CURL_COMMAND = 'bash <(curl -s https://wireguard.sh/wireguard.sh)';
const SOURCE_BLOB = 'https://github.com/eyupio/wireguard.sh/blob/main/wireguard.sh';
const RELEASE_API = 'https://api.github.com/repos/eyupio/wireguard.sh/releases/latest';
const INSTALLER = fs.readFileSync(path.join(__dirname, '..', 'wireguard.sh'), 'utf8');
const EXPECTED_VERSION = INSTALLER.match(/^APP_VERSION="([^"]+)"/m)[1];

test.beforeEach(async ({ page }) => {
  await page.route(RELEASE_API, (route) => route.abort());
});

test.describe('without JavaScript', () => {
  test.use({ javaScriptEnabled: false });

  test('renders the headline, commands, TUI and credits', async ({ page }) => {
    await page.goto('/');
    await expect(page.getByRole('heading', { level: 1 })).toContainText(
      'Install a WireGuard VPN server',
    );
    await expect(page.locator('#cmd-wget')).toHaveText(WGET_COMMAND);
    await expect(page.locator('#cmd-curl')).toHaveText(CURL_COMMAND);
    await expect(page.locator('button.copy').first()).toBeHidden();
    await expect(page.locator('#tui')).toBeVisible();
    await expect(page.locator('.tui-card')).toHaveCount(3);
    await expect(page.locator('.credits')).toContainText('Jason A. Donenfeld');
    await expect(page.locator('.credits')).toContainText("Nyr's");
    expect(await page.locator('body').innerText()).toContain('JavaScript is off');
  });
});

test('copy buttons write the exact command to the clipboard', async ({ page, context }) => {
  const pageErrors = [];
  page.on('pageerror', (error) => pageErrors.push(error.message));

  await context.grantPermissions(['clipboard-read', 'clipboard-write']);
  await page.goto('/');

  for (const [id, command] of [
    ['cmd-wget', WGET_COMMAND],
    ['cmd-curl', CURL_COMMAND],
  ]) {
    const button = page.locator(`button[data-copy="${id}"]`);

    await button.click();
    await expect(button.locator('.copy__label')).toHaveText('Copied');
    await expect(page.locator('#copy-status')).toHaveText('Command copied to clipboard.');
    await expect
      .poll(() => page.evaluate(() => navigator.clipboard.readText()))
      .toBe(command);

    await expect(button.locator('.copy__label')).toHaveText('Copy', { timeout: 5000 });
  }

  expect(pageErrors).toEqual([]);
});

test('the 375px layout does not overflow or clip the commands', async ({ page }) => {
  await page.setViewportSize({ width: 375, height: 812 });
  await page.goto('/');

  const overflow = await page.evaluate(
    () => document.documentElement.scrollWidth - document.documentElement.clientWidth,
  );
  expect(overflow).toBeLessThanOrEqual(0);

  const clipped = await page.evaluate(() =>
    [...document.querySelectorAll('.command__code')].some(
      (code) => code.scrollWidth > code.clientWidth + 1,
    ),
  );
  expect(clipped).toBe(false);

  await expect(page.locator('button[data-copy="cmd-wget"]')).toBeVisible();
  await expect(page.locator('.banner')).toBeHidden();
  await expect(page.locator('.tui-card')).toHaveCount(3);
});

test('source links open the rendered installer instead of the .sh download', async ({ page }) => {
  await page.goto('/');

  await expect(page.locator('a[href="wireguard.sh"]')).toHaveCount(0);
  await expect(page.locator(`a[href="${SOURCE_BLOB}"]`).first()).toBeVisible();
  await expect(page.locator('a[href="https://github.com/Nyr/wireguard-install"]').first()).toBeVisible();
});

test('the footer links to EyUp.io like the Zoomies footer', async ({ page }) => {
  await page.goto('/');

  const credit = page.locator('.site-footer__credit a[href="https://eyup.io"]');
  await expect(credit).toBeVisible();
  await expect(credit).toHaveText('EyUp.io');
  await expect(credit).toHaveAttribute('target', '_blank');
  await expect(credit).toHaveAttribute('rel', 'noopener noreferrer');
});

test('the release badge follows the latest GitHub release', async ({ page }) => {
  await page.route(RELEASE_API, (route) =>
    route.fulfill({
      status: 200,
      contentType: 'application/json',
      headers: { 'access-control-allow-origin': '*' },
      body: JSON.stringify({
        tag_name: 'v9.9',
        html_url: 'https://github.com/eyupio/wireguard.sh/releases/tag/v9.9',
      }),
    }),
  );

  await page.goto('/');

  await expect(page.locator('[data-release-version]').first()).toHaveText('v9.9');
  await expect(page.locator('[data-release-link]').first()).toHaveAttribute(
    'href',
    'https://github.com/eyupio/wireguard.sh/releases/tag/v9.9',
  );
});

test('the static release fallback remains when GitHub is unavailable', async ({ page }) => {
  const pageErrors = [];
  page.on('pageerror', (error) => pageErrors.push(error.message));
  await page.route(RELEASE_API, (route) => route.abort());

  await page.goto('/');

  await expect(page.locator('[data-release-version]').first()).toHaveText(`v${EXPECTED_VERSION}`);
  await expect(page.locator('[data-release-link]').first()).toHaveAttribute(
    'href',
    `https://github.com/eyupio/wireguard.sh/releases/tag/v${EXPECTED_VERSION}`,
  );
  expect(pageErrors).toEqual([]);
});

test('the TUI previews and dashboard explanation are present', async ({ page }) => {
  await page.goto('/');

  await expect(page.locator('#tui-title')).toHaveText('A terminal UI that shows its working.');
  await expect(page.locator('.tui-card').nth(0)).toContainText('Welcome');
  await expect(page.locator('.tui-card').nth(1)).toContainText('Review your setup');
  await expect(page.locator('.tui-card').nth(2)).toContainText('Dashboard');
  await expect(page.locator('.tui-aside')).toContainText('Service, endpoint, clients.');
  await expect(page.locator('.tui-screen-wrap').first()).toHaveAttribute('role', 'group');
  await expect(page.locator('.credits')).toContainText('not affiliated with');
});

test('reduced motion disables the cursor blink', async ({ page }) => {
  await page.emulateMedia({ reducedMotion: 'reduce' });
  await page.goto('/');

  await expect(page.locator('.cursor')).toHaveCSS('animation-name', 'none');
});
