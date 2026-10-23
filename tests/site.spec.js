const { test, expect } = require('@playwright/test');

const WGET_COMMAND = 'bash <(wget -q -O - https://wireguard.sh/wireguard.sh)';
const CURL_COMMAND = 'bash <(curl -s https://wireguard.sh/wireguard.sh)';
const SOURCE_BLOB = 'https://github.com/jnnngs/wireguard.sh/blob/main/wireguard.sh';

test.describe('without JavaScript', () => {
  test.use({ javaScriptEnabled: false });

  test('renders the headline and both commands', async ({ page }) => {
    await page.goto('/');
    await expect(page.getByRole('heading', { level: 1 })).toContainText(
      'Install a WireGuard VPN server',
    );
    await expect(page.locator('#cmd-wget')).toHaveText(WGET_COMMAND);
    await expect(page.locator('#cmd-curl')).toHaveText(CURL_COMMAND);
    await expect(page.locator('button.copy').first()).toBeHidden();
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
});

test('source links open the rendered installer instead of the .sh download', async ({ page }) => {
  await page.goto('/');

  await expect(page.locator('a[href="wireguard.sh"]')).toHaveCount(0);
  await expect(page.locator(`a[href="${SOURCE_BLOB}"]`).first()).toBeVisible();
});

test('reduced motion disables the cursor blink', async ({ page }) => {
  await page.emulateMedia({ reducedMotion: 'reduce' });
  await page.goto('/');

  await expect(page.locator('.cursor')).toHaveCSS('animation-name', 'none');
});
