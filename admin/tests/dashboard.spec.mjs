import { test, expect } from '@playwright/test';

const project = 'demo-pharmaflow-tests';
const root = `projects/${project}/databases/(default)/documents`;
const endpoint = `http://127.0.0.1:8080/v1/${root}`;
const password = 'Emulator-test-password-123!';
if (process.env.FIRESTORE_EMULATOR_HOST !== '127.0.0.1:8080' || process.env.FIREBASE_AUTH_EMULATOR_HOST !== '127.0.0.1:9099') {
  throw new Error('Browser tests require the local Firebase emulators only.');
}

function fields(data) {
  return Object.fromEntries(Object.entries(data).map(([key, value]) => [key,
    value === null ? { nullValue: null } : typeof value === 'boolean' ? { booleanValue: value }
      : typeof value === 'number' ? { integerValue: String(value) }
        : value instanceof Date ? { timestampValue: value.toISOString() } : { stringValue: value }]));
}

async function write(path, data) {
  const response = await fetch(`${endpoint}/${path}`, {
    method: 'PATCH', headers: { 'Content-Type': 'application/json', Authorization: 'Bearer owner' }, body: JSON.stringify({ fields: fields(data) }),
  });
  expect(response.status).toBe(200);
}

async function account(prefix, verified = true) {
  const email = `${prefix}-${Date.now()}-${Math.random().toString(36).slice(2)}@example.test`;
  const response = await fetch('http://127.0.0.1:9099/identitytoolkit.googleapis.com/v1/accounts:signUp?key=demo-key', {
    method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ email, password, returnSecureToken: true }),
  });
  expect(response.status).toBe(200);
  const user = { ...(await response.json()), email };
  if (verified) {
    const update = await fetch('http://127.0.0.1:9099/identitytoolkit.googleapis.com/v1/accounts:update?key=demo-key', {
      method: 'POST', headers: { 'Content-Type': 'application/json', Authorization: 'Bearer owner' },
      body: JSON.stringify({ localId: user.localId, emailVerified: true }),
    });
    expect(update.status).toBe(200);
  }
  return user;
}

test('Un administrateur doit confirmer son email avant tout accès aux fiches', async ({ page }) => {
  const user = await account('admin-unverified', false);
  await write(`account_admins/${user.localId}`, { enabled: true });
  await page.setViewportSize({ width: 320, height: 568 });
  await login(page, user);
  await expect(page.locator('#verification')).toBeVisible();
  await expect(page.locator('#workspace')).toBeHidden();
  await expect(page.locator('#clients')).toBeEmpty();
  await page.locator('#check-verification').click();
  await expect(page.locator('#message')).toContainText('pas encore confirmée');
  await page.locator('#send-verification').click();
  await expect(page.locator('#message')).toContainText('Lien envoyé');
  await expect(page.locator('#send-verification')).toBeDisabled();
  const response = await fetch(`http://127.0.0.1:9099/emulator/v1/projects/${project}/oobCodes`);
  const codes = (await response.json()).oobCodes;
  const code = codes.find(entry => entry.email === user.email && entry.requestType === 'VERIFY_EMAIL');
  expect(code).toBeTruthy();
  const verified = await fetch('http://127.0.0.1:9099/identitytoolkit.googleapis.com/v1/accounts:update?key=demo-key', {
    method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ oobCode: code.oobCode }),
  });
  expect(verified.status).toBe(200);
  await page.locator('#check-verification').click();
  await expect(page.locator('#workspace')).toBeVisible();
  await expect(page.locator('#verification')).toBeHidden();
  expect(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth)).toBe(true);
});

async function login(page, user) {
  await page.goto('/?emulators=1');
  await page.getByLabel('Email administrateur').fill(user.email);
  await page.getByLabel('Mot de passe', { exact: true }).fill(password);
  await page.getByRole('button', { name: 'Se connecter', exact: true }).click();
}

for (const viewport of [{ width: 1280, height: 850 }, { width: 320, height: 568 }]) {
  test(`Activation, suspension et confidentialité à ${viewport.width}px`, async ({ page }, info) => {
    await page.setViewportSize(viewport);
    const errors = [];
    page.on('pageerror', error => errors.push(error.message));
    const operator = await account('admin-browser');
    const client = await account('client-browser');
    await write(`account_admins/${operator.localId}`, { enabled: true });
    const name = `Pharmacie ${client.localId}`;
    const contact = { nom: name, email: client.email, telephone: '+243123456789', adresse: 'Rue de démonstration', ville: 'Kinshasa', pays: 'CD', proprietaire_nom: 'Responsable de démonstration', created_at: new Date() };
    await write(`pharmacies/${client.localId}`, { ...contact, code: `PHR-${client.localId}`, username: '', tarifs_gros_actifs: false, access_status: 'pending' });
    await write(`clients/${client.localId}`, { ...contact, access_status: 'pending', access_revision: 0, activated_at: null, last_access_event: '' });
    await login(page, operator);
    await expect(page.getByRole('heading', { name: 'Vos pharmacies clientes' })).toBeVisible();
    await page.getByLabel('Rechercher dans les fiches chargées').fill(name);
    await expect(page.locator('.client')).toHaveCount(1);
    await expect(page.locator('.client .badge')).toHaveText('En attente');
    await page.getByRole('button', { name: 'Ouvrir la fiche' }).click();
    await expect(page.getByRole('dialog')).toBeVisible();
    await expect(page.getByText('Aucune intervention enregistrée.')).toBeVisible();
    await page.getByLabel('Motif ou référence de vente').fill('Vente test vérifiée et réglée');
    await page.locator('#confirmation').check();
    await page.getByRole('button', { name: 'Confirmer la décision' }).click();
    await expect(page.getByRole('dialog')).not.toBeVisible();
    await expect(page.locator('.client .badge')).toHaveText('Actif');
    await page.getByRole('button', { name: 'Ouvrir la fiche' }).click();
    await expect(page.locator('#history')).toContainText('Vente test vérifiée et réglée');
    await page.getByLabel('Motif ou référence de vente').fill('Suspension de test demandée');
    await page.locator('#confirmation').check();
    await page.getByRole('button', { name: 'Confirmer la décision' }).click();
    await expect(page.getByRole('dialog')).not.toBeVisible();
    await expect(page.locator('.client .badge')).toHaveText('Suspendu');
    await page.getByRole('button', { name: 'Ouvrir la fiche' }).click();
    await expect(page.locator('#history li')).toHaveCount(2);
    await expect(page.locator('#detail-content')).toContainText('Responsable de démonstration');
    await page.getByRole('button', { name: 'Fermer', exact: true }).click();
    expect(await page.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth)).toBe(true);
    await page.screenshot({ path: info.outputPath('dashboard.png'), fullPage: true });
    await page.getByRole('button', { name: 'Se déconnecter' }).click();
    await expect(page.getByRole('button', { name: 'Se connecter', exact: true })).toBeVisible();
    await expect(page.locator('#clients')).toBeEmpty();
    await expect(page.locator('#search')).toHaveValue('');
    await expect(page.locator('#detail-title')).toHaveText('Fiche client');
    expect(errors).toEqual([]);
  });
}

test('Un échec du chargement réseau affiche une explication', async ({ page }) => {
  await page.route('https://www.gstatic.com/firebasejs/**', route => route.abort());
  await page.goto('/?emulators=1');
  await expect(page.locator('#message')).toContainText('Chargement impossible');
  await expect(page.locator('#workspace')).not.toBeVisible();
});

test('Un compte client ne voit pas l’annuaire et une révocation ferme l’espace', async ({ page }) => {
  const user = await account('non-admin-browser');
  await login(page, user);
  await expect(page.locator('#message')).toContainText('ne possède pas les droits administrateur');
  await expect(page.locator('#workspace')).not.toBeVisible();
  await page.getByRole('button', { name: 'Se déconnecter' }).click();
  await write(`account_admins/${user.localId}`, { enabled: true });
  await login(page, user);
  await expect(page.locator('#workspace')).toBeVisible();
  await write(`account_admins/${user.localId}`, { enabled: false });
  await expect(page.locator('#workspace')).not.toBeVisible();
  await expect(page.locator('#clients')).toBeEmpty();
});
