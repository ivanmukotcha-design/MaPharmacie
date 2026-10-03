import { defineConfig } from '@playwright/test';

export default defineConfig({
  testDir: './tests',
  timeout: 120000,
  expect: { timeout: 20000 },
  workers: 1,
  reporter: 'list',
  use: { browserName: 'chromium', channel: 'msedge', headless: true, baseURL: 'http://127.0.0.1:4173', screenshot: 'only-on-failure' },
  webServer: { command: 'node serve.mjs', url: 'http://127.0.0.1:4173', reuseExistingServer: false, timeout: 30000 },
});
