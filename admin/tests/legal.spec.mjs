import { test, expect } from '@playwright/test';
import { readFile } from 'node:fs/promises';

const source = JSON.parse(await readFile(new URL('../public/legal.json', import.meta.url), 'utf8'));
const valid = { ...source, publisherName: 'Éditeur fictif', supportEmail: 'support@example.test', effectiveDate: '2026-10-16', approvedForPublication: true };

test('Les pages publiques fonctionnent sans Firebase et sans authentification', async ({ page }) => {
  await page.route('**/legal.json', route => route.fulfill({ json: valid }));
  await page.route('https://www.gstatic.com/**', route => route.abort());
  await page.setViewportSize({ width: 320, height: 568 });
  await page.goto('/confidentialite.html');
  await expect(page.getByRole('heading', { name: 'Politique de confidentialité' })).toBeVisible();
  await expect(page.locator('#contact')).toHaveText(valid.supportEmail);
  await expect(page.locator('#legal-content')).toContainText('SQLite');
  await page.getByRole('link', { name: 'Demander la suppression du compte' }).click();
  await expect(page.locator('#request-options')).toBeVisible();
  await expect(page.locator('#email-request')).toBeHidden();
  await page.locator('#confirm-owner').check();
  await expect(page.locator('#email-request')).toHaveAttribute('href', /^mailto:/);
  await expect(page.locator('#request-options')).toContainText('Aucune demande n’est envoyée automatiquement');
  expect(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth)).toBe(true);
});

test('Une configuration non validée ne propose pas un faux envoi', async ({ page }) => {
  await page.route('**/legal.json', route => route.fulfill({ json: { ...valid, approvedForPublication: false } }));
  await page.goto('/suppression-compte.html');
  await expect(page.locator('#legal-status')).toContainText('Version de préparation');
  await expect(page.locator('#request-options')).toBeHidden();
});

test('Une panne de chargement donne une explication', async ({ page }) => {
  await page.route('**/legal.json', route => route.abort());
  await page.goto('/suppression-compte.html');
  await expect(page.locator('#legal-status')).toContainText('Informations indisponibles');
  await expect(page.locator('#request-options')).toBeHidden();
});
