const { test } = require('node:test');
const assert = require('node:assert/strict');

const project = 'demo-pharmaflow-tests';
const firestoreHost = process.env.FIRESTORE_EMULATOR_HOST;
const authHost = process.env.FIREBASE_AUTH_EMULATOR_HOST;
if (firestoreHost !== '127.0.0.1:8080' || authHost !== '127.0.0.1:9099') {
  throw new Error('Exécuter exclusivement avec les émulateurs locaux via firebase emulators:exec');
}
const database = `projects/${project}/databases/(default)/documents`;
const endpoint = `http://${firestoreHost}/v1/${database}`;

function value(entry) {
  if (entry === null) return { nullValue: null };
  if (entry instanceof Date) return { timestampValue: entry.toISOString() };
  if (typeof entry === 'string') return { stringValue: entry };
  if (typeof entry === 'boolean') return { booleanValue: entry };
  if (typeof entry === 'number') return Number.isInteger(entry) ? { integerValue: String(entry) } : { doubleValue: entry };
  if (Array.isArray(entry)) return { arrayValue: { values: entry.map(value) } };
  return { mapValue: { fields: fields(entry) } };
}
function fields(data) {
  return Object.fromEntries(Object.entries(data).map(([key, entry]) => [key, value(entry)]));
}
async function account(label) {
  const email = `${label}-${Date.now()}@example.test`;
  const response = await fetch(`http://${authHost}/identitytoolkit.googleapis.com/v1/accounts:signUp?key=demo-key`, {
    method: 'POST', headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ email, password: 'Test-password-123!', returnSecureToken: true }),
  });
  const data = await response.json();
  assert.equal(response.status, 200, JSON.stringify(data));
  return { uid: data.localId, token: data.idToken, email };
}
function write(path, data, token, timestamps = []) {
  return fetch(`${endpoint}:commit`, {
    method: 'POST', headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${token}` },
    body: JSON.stringify({ writes: [{ update: { name: `${database}/${path}`, fields: fields(data) },
      updateTransforms: timestamps.map((fieldPath) => ({ fieldPath, setToServerValue: 'REQUEST_TIME' })) }] }),
  });
}
function read(path, token) {
  return fetch(`${endpoint}/${path}`, { headers: token ? { Authorization: `Bearer ${token}` } : {} });
}
async function allowed(responsePromise) {
  const response = await responsePromise;
  assert.equal(response.status, 200, await response.text());
}
async function denied(responsePromise) {
  const response = await responsePromise;
  assert.equal(response.status, 403, await response.text());
}

test('Inscription autonome, compte partagé et isolation Firestore', async (suite) => {
  const pharmacy = await account('pharmacy');
  const stranger = await account('stranger');
  const admin = await account('legacy-admin');
  const path = `pharmacies/${pharmacy.uid}`;
  const profile = { code: `PHR-${pharmacy.uid}`, nom: 'Pharmacie test', username: '',
    email: pharmacy.email, telephone: '123', adresse: 'Adresse', ville: 'Ville', pays: 'Pays',
    tarifs_gros_actifs: false, proprietaire_nom: 'Propriétaire' };
  let currentProfile;
  await suite.test('Aucune configuration préalable ou invitation nécessaire', async () => {
    assert.equal((await read(path, pharmacy.token)).status, 404);
    await denied(read(path));
    await denied(write(path, profile, stranger.token, ['created_at']));
    await denied(write('config/installation', { pharmacie_id: pharmacy.uid }, pharmacy.token));
  });
  await suite.test('Chaque utilisateur inscrit crée uniquement son propre profil', async () => {
    await denied(write(path, { ...profile, statut: 'actif' }, pharmacy.token, ['created_at']));
    await denied(write(path, { ...profile, tarifs_gros_actifs: true }, pharmacy.token, ['created_at']));
    await denied(write(path, { ...profile, email: stranger.email }, pharmacy.token, ['created_at']));
    await allowed(write(path, profile, pharmacy.token, ['created_at']));
    await denied(read(path));
    await denied(read(path, stranger.token));
    await allowed(read(path, pharmacy.token));
    await allowed(write('config/installation', { pharmacie_id: pharmacy.uid }, 'owner'));
    await allowed(write(`pharmacies/${stranger.uid}`,
      { ...profile, code: `PHR-${stranger.uid}`, email: stranger.email }, stranger.token, ['created_at']));
    await allowed(read(`pharmacies/${stranger.uid}`, stranger.token));
    await denied(read(`pharmacies/${stranger.uid}`, pharmacy.token));
    currentProfile = { ...profile, created_at: new Date() };
    await allowed(write(path, currentProfile, 'owner'));
  });
  await allowed(write(`admins/${admin.uid}`, { role: 'superadmin' }, 'owner'));
  await suite.test('Un ancien administrateur ne bénéficie plus de privilèges', async () => {
    await denied(read(path, admin.token));
    await denied(write(path, currentProfile, admin.token));
    await denied(read(`admins/${admin.uid}`, admin.token));
    await denied(write('config/installation', { pharmacie_id: admin.uid }, admin.token));
    await denied(read('pharmacies', pharmacy.token));
    await denied(read('config', pharmacy.token));
    await denied(read('config/installation', stranger.token));
  });
  const medicine = { pharmacie_id: pharmacy.uid, nom: 'Produit', est_actif: true,
    prix_detail: 100, prix_grossiste: null, prix_achat: 50, unite_prix: 'boite', revision: 1,
    seuil_alerte: 5, unites: { cartons: 0, boites: 10, plaquettes: 0, comprimes: 0, flacons: 0,
      cartons_par_boite: 20, boites_par_plaquette: 10, plaquettes_par_comprime: 10 } };
  const medicinePath = `${path}/medicaments/med-1`;
  await suite.test('Stock privé, prix de gros facultatif, révisions et quantités contrôlés', async () => {
    await denied(write(medicinePath, medicine, stranger.token));
    await allowed(write(medicinePath, medicine, pharmacy.token));
    await denied(write(medicinePath, medicine, pharmacy.token));
    await denied(write(medicinePath, { ...medicine, revision: 2, prix_grossiste: -1 }, pharmacy.token));
    await denied(write(medicinePath, { ...medicine, revision: 2, unites: { ...medicine.unites, boites: -1 } }, pharmacy.token));
    await denied(write(medicinePath, { ...medicine, revision: 2, pharmacie_id: stranger.uid }, pharmacy.token));
    await allowed(write(medicinePath, { ...medicine, revision: 2, prix_grossiste: 80 }, pharmacy.token));
    await denied(read(medicinePath, stranger.token));
    await denied(read(medicinePath, admin.token));
    const otherMedicine = `pharmacies/${stranger.uid}/medicaments/med-1`;
    await allowed(write(otherMedicine, { ...medicine, pharmacie_id: stranger.uid }, stranger.token));
    await denied(read(otherMedicine, pharmacy.token));
    await denied(write(`pharmacies/${admin.uid}/medicaments/med-1`, { ...medicine, pharmacie_id: admin.uid }, admin.token));
  });
  await suite.test('Les anciens champs abonnement ne bloquent plus lecture et écriture', async () => {
    currentProfile = { ...currentProfile, statut: 'suspendu', abonnement_fin: new Date(2020, 0, 1) };
    await allowed(write(path, currentProfile, 'owner'));
    await allowed(read(medicinePath, pharmacy.token));
    await allowed(write(medicinePath, { ...medicine, revision: 3 }, pharmacy.token));
  });
  await suite.test('Le réglage de gros est réservé au compte et exige un booléen', async () => {
    await denied(write(path, { ...currentProfile, tarifs_gros_actifs: true }, stranger.token));
    await denied(write(path, { ...currentProfile, tarifs_gros_actifs: 'oui' }, pharmacy.token));
    await allowed(write(path, { ...currentProfile, tarifs_gros_actifs: true }, pharmacy.token));
    await allowed(write(path, currentProfile, pharmacy.token));
    await denied(write(path, { ...currentProfile, email: stranger.email }, pharmacy.token));
  });
  await suite.test('Le même compte se connecte sur un deuxième appareil', async () => {
    const response = await fetch(`http://${authHost}/identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key=demo-key`, {
      method: 'POST', headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ email: pharmacy.email, password: 'Test-password-123!', returnSecureToken: true }),
    });
    const data = await response.json();
    assert.equal(response.status, 200);
    assert.equal(data.localId, pharmacy.uid);
    await allowed(read(medicinePath, data.idToken));
  });
  await suite.test('Les ventes sont immuables et une vente de gros déjà enregistrée peut se synchroniser', async () => {
    const sale = { pharmacie_id: pharmacy.uid, type_vente: 'gros', total_ht: 80,
      total_ttc: 80, benefice: 30, date: new Date(), items: [{ medicament_id: 'med-1', quantite: 1 }] };
    await allowed(write(`${path}/ventes/sale-1`, sale, pharmacy.token));
    await denied(write(`${path}/ventes/sale-1`, { ...sale, total_ttc: 0 }, pharmacy.token));
    await denied(write(`${path}/ventes/sale-2`, sale, stranger.token));
  });
  await suite.test('Paiements, abonnements et suppressions ne sont plus accessibles aux clients', async () => {
    await allowed(write('paiements/payment-1', { pharmacie_id: pharmacy.uid }, 'owner'));
    await allowed(write('abonnements/legacy', { pharmacie_id: pharmacy.uid }, 'owner'));
    for (const token of [pharmacy.token, stranger.token, admin.token]) {
      await denied(read('paiements/payment-1', token));
      await denied(read('abonnements/legacy', token));
      await denied(write('paiements/payment-2', { pharmacie_id: pharmacy.uid }, token));
      await denied(fetch(`${endpoint}/${path}`, { method: 'DELETE', headers: { Authorization: `Bearer ${token}` } }));
    }
  });
});
