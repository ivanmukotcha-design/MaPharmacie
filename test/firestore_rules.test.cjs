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
async function account(label, verified = true) {
  const email = `${label}-${Date.now()}@example.test`;
  const response = await fetch(`http://${authHost}/identitytoolkit.googleapis.com/v1/accounts:signUp?key=demo-key`, {
    method: 'POST', headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ email, password: 'Test-password-123!', returnSecureToken: true }),
  });
  const data = await response.json();
  assert.equal(response.status, 200, JSON.stringify(data));
  const result = { uid: data.localId, token: data.idToken, email };
  if (verified) result.token = await verifyAccount(result);
  return result;
}
async function verifyAccount(user) {
  const update = await fetch(`http://${authHost}/identitytoolkit.googleapis.com/v1/accounts:update?key=demo-key`, {
    method: 'POST', headers: { 'Content-Type': 'application/json', Authorization: 'Bearer owner' },
    body: JSON.stringify({ localId: user.uid, emailVerified: true }),
  });
  assert.equal(update.status, 200, await update.text());
  const response = await fetch(`http://${authHost}/identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key=demo-key`, {
    method: 'POST', headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ email: user.email, password: 'Test-password-123!', returnSecureToken: true }),
  });
  const data = await response.json();
  assert.equal(response.status, 200, JSON.stringify(data));
  return data.idToken;
}

test('Email non confirmé : profil, données et administration refusés même avec un compte actif', async () => {
  const user = await account('unverified', false);
  for (const credentials of [
    { email: user.email, password: 'incorrect' },
    { email: `absent-${Date.now()}@example.test`, password: 'Test-password-123!' },
  ]) {
    const response = await fetch(`http://${authHost}/identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key=demo-key`, {
      method: 'POST', headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ ...credentials, returnSecureToken: true }),
    });
    assert.equal(response.status, 400);
  }
  const path = `pharmacies/${user.uid}`;
  await allowed(write(path, { nom: 'Pharmacie privée', access_status: 'active' }, 'owner'));
  await allowed(write(`${path}/medicaments/secret`, { nom: 'Privé' }, 'owner'));
  await allowed(write(`${path}/notifications/secret`, { lu: false }, 'owner'));
  await allowed(write(`clients/${user.uid}`, { nom: 'Annuaire privé' }, 'owner'));
  await allowed(write(`account_admins/${user.uid}`, { enabled: true }, 'owner'));
  for (const target of [path, `${path}/medicaments/secret`, `${path}/notifications/secret`, `clients/${user.uid}`, `account_admins/${user.uid}`]) {
    await denied(read(target, user.token));
    await denied(write(target, { email_verified: true }, user.token));
  }
  const freshToken = await verifyAccount(user);
  await denied(read(path, user.token));
  await allowed(read(path, freshToken));
  await allowed(read(`${path}/medicaments/secret`, freshToken));
  const pending = await account('unverified-signup', false);
  await denied(write(`pharmacies/${pending.uid}`, {
    code: `PHR-${pending.uid}`, nom: 'Test', email: pending.email, tarifs_gros_actifs: false, access_status: 'pending',
  }, pending.token, ['created_at']));
});
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

function decodeValue(entry) {
  if ('nullValue' in entry) return null;
  if ('stringValue' in entry) return entry.stringValue;
  if ('integerValue' in entry) return Number(entry.integerValue);
  if ('timestampValue' in entry) return new Date(entry.timestampValue);
  if ('booleanValue' in entry) return entry.booleanValue;
  throw new Error('Unsupported test value');
}

async function changeAccess(clientId, actor, target, options = {}) {
  const response = await read(`clients/${clientId}`, actor.token);
  assert.equal(response.status, 200);
  const current = Object.fromEntries(Object.entries((await response.json()).fields).map(([key, entry]) => [key, decodeValue(entry)]));
  const eventId = `event-${Date.now()}-${Math.random().toString(36).slice(2)}`;
  const update = { access_status: target, access_revision: current.access_revision + 1,
    last_access_event: eventId, activated_at: current.activated_at };
  const transforms = [{ fieldPath: 'access_updated_at', setToServerValue: 'REQUEST_TIME' }];
  if (target === 'active' && current.activated_at === null) transforms.push({ fieldPath: 'activated_at', setToServerValue: 'REQUEST_TIME' });
  const writes = [{ update: { name: `${database}/clients/${clientId}`, fields: fields({ ...current, ...update }) }, updateTransforms: transforms }];
  if (options.profile !== false) writes.push({
    update: { name: `${database}/pharmacies/${clientId}`, fields: fields(update) },
    updateMask: { fieldPaths: Object.keys(update) }, updateTransforms: transforms,
  });
  if (options.audit !== false) writes.push({ update: { name: `${database}/account_events/${eventId}`, fields: fields({
    client_id: clientId, actor_uid: options.actor || actor.uid, from_status: current.access_status,
    to_status: target, reason: options.reason ?? 'Vente vérifiée par administrateur', revision: update.access_revision,
  }) }, updateTransforms: [{ fieldPath: 'created_at', setToServerValue: 'REQUEST_TIME' }] });
  return fetch(`${endpoint}:commit`, { method: 'POST', headers: {
    'Content-Type': 'application/json', Authorization: `Bearer ${actor.token}`,
  }, body: JSON.stringify({ writes }) });
}

test('Activation commerciale : séparation des rôles et historique atomique', async (suite) => {
  const client = await account('activation-client');
  const operator = await account('activation-admin');
  const stranger = await account('activation-stranger');
  const path = `pharmacies/${client.uid}`;
  const contact = { nom: 'Pharmacie à activer', email: client.email, telephone: '123', adresse: 'Rue',
    ville: 'Ville', pays: 'Pays', proprietaire_nom: 'Responsable' };
  const profile = { ...contact, code: `PHR-${client.uid}`, username: '', tarifs_gros_actifs: false, access_status: 'pending' };
  await allowed(write(`account_admins/${operator.uid}`, { enabled: true }, 'owner'));
  await suite.test('Aucun utilisateur ne peut s’attribuer un rôle ou activer son propre compte', async () => {
    await denied(write(`account_admins/${client.uid}`, { enabled: true }, client.token));
    await denied(write(`account_admins/${stranger.uid}`, { enabled: true }, operator.token));
    await denied(write(path, { ...profile, access_status: 'active' }, client.token, ['created_at']));
    const { access_status, ...oldClient } = profile;
    await denied(write(path, oldClient, client.token, ['created_at']));
    await allowed(write(path, profile, client.token, ['created_at']));
  });
  const snapshot = await (await read(path, client.token)).json();
  const created = new Date(snapshot.fields.created_at.timestampValue);
  const directory = { ...contact, created_at: created, access_status: 'pending', access_revision: 0, last_access_event: '', activated_at: null };
  const medicinePath = `${path}/medicaments/existing`;
  const medicine = { pharmacie_id: client.uid, nom: 'Stock privé', prix_detail: 10, prix_grossiste: null, prix_achat: 5,
    unite_prix: 'boite', seuil_alerte: 1, est_actif: true, revision: 1,
    unites: { cartons: 0, boites: 10, plaquettes: 0, comprimes: 0, flacons: 0, cartons_par_boite: 20, boites_par_plaquette: 10, plaquettes_par_comprime: 10 } };
  await allowed(write(medicinePath, medicine, 'owner'));
  await suite.test('Annuaire limité aux coordonnées vérifiées et compte en attente bloqué', async () => {
    await denied(write(`clients/${client.uid}`, { ...directory, access_status: 'active' }, client.token));
    await denied(write(`clients/${client.uid}`, { ...directory, nom: 'Fausse fiche' }, client.token));
    await denied(write(`clients/${client.uid}`, { ...directory, ventes: [] }, client.token));
    await allowed(write(`clients/${client.uid}`, directory, client.token));
    await denied(read(medicinePath, client.token));
    await denied(write(`${path}/medicaments/new`, medicine, client.token));
    await allowed(read(`clients/${client.uid}`, operator.token));
    await denied(read(`clients/${client.uid}`, stranger.token));
    await denied(read(path, operator.token));
    await denied(read(medicinePath, operator.token));
    await denied(write(`${path}/medicaments/new`, medicine, operator.token));
    await denied(write(`clients/${client.uid}`, { ...directory, access_status: 'active' }, client.token));
  });
  await suite.test('Activation exige une transaction complète et un motif horodaté', async () => {
    await denied(changeAccess(client.uid, operator, 'active', { audit: false }));
    await denied(changeAccess(client.uid, operator, 'active', { profile: false }));
    await denied(changeAccess(client.uid, operator, 'active', { reason: 'x' }));
    await denied(changeAccess(client.uid, operator, 'active', { actor: stranger.uid }));
    await allowed(changeAccess(client.uid, operator, 'active'));
    await allowed(read(medicinePath, client.token));
    await allowed(write(`${path}/medicaments/new`, medicine, client.token));
    await denied(changeAccess(client.uid, operator, 'active'));
    const current = await (await read(`clients/${client.uid}`, operator.token)).json();
    const eventPath = `account_events/${current.fields.last_access_event.stringValue}`;
    await allowed(read(eventPath, operator.token));
    await denied(read(eventPath, client.token));
    await denied(write(eventPath, { reason: 'Historique réécrit' }, operator.token));
    await denied(read(medicinePath, operator.token));
  });
  await suite.test('Suspension conserve la lecture et refuse toute nouvelle vente ou modification', async () => {
    await allowed(changeAccess(client.uid, operator, 'suspended'));
    await allowed(read(medicinePath, client.token));
    await denied(write(medicinePath, { ...medicine, revision: 2 }, client.token));
    await denied(write(`${path}/ventes/new`, { pharmacie_id: client.uid }, client.token));
    await allowed(changeAccess(client.uid, operator, 'active'));
    await allowed(write(medicinePath, { ...medicine, revision: 2 }, client.token));
  });
  await suite.test('Révocation administrateur immédiate côté serveur', async () => {
    await allowed(write(`account_admins/${operator.uid}`, { enabled: false }, 'owner'));
    await denied(read(`clients/${client.uid}`, operator.token));
    await denied(write(path, { access_status: 'suspended' }, operator.token));
    await allowed(read(medicinePath, client.token));
  });
});

test('Inscription autonome, compte partagé et isolation Firestore', async (suite) => {
  const pharmacy = await account('pharmacy');
  const stranger = await account('stranger');
  const admin = await account('legacy-admin');
  const path = `pharmacies/${pharmacy.uid}`;
  const profile = { code: `PHR-${pharmacy.uid}`, nom: 'Pharmacie test', username: '',
    email: pharmacy.email, telephone: '123', adresse: 'Adresse', ville: 'Ville', pays: 'Pays',
    tarifs_gros_actifs: false, proprietaire_nom: 'Propriétaire', access_status: 'pending' };
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
    currentProfile = { ...profile, access_status: 'active', created_at: new Date() };
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
  await suite.test('Les anciens clients ne peuvent écraser le suivi par lots', async () => {
    const lotsPath = `${path}/medicaments/tracked`;
    const tracked = { ...medicine, suivi_lots: true, lot_revision: 1, lots: [{
      id: 'lot-1', numero: 'LOT-1', quantite_base: 1000, cout_base: 0.5,
      reception: new Date().toISOString(), expiration: '2030-01-01T00:00:00', fournisseur: '',
    }] };
    await allowed(write(lotsPath, tracked, pharmacy.token));
    await denied(write(lotsPath, { ...tracked, revision: 2 }, pharmacy.token));
    await denied(write(lotsPath, { ...tracked, revision: 2, suivi_lots: false }, pharmacy.token));
    await denied(write(lotsPath, { ...tracked, revision: 2, lot_revision: 2, unite_prix: 'comprimes' }, pharmacy.token));
    await denied(write(lotsPath, { ...tracked, revision: 2, lot_revision: 2, unites: { ...tracked.unites, cartons_par_boite: 10 } }, pharmacy.token));
    await allowed(write(lotsPath, { ...tracked, revision: 2, lot_revision: 2 }, pharmacy.token));
    await denied(read(lotsPath, stranger.token));
  });
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
    await allowed(write(`pharmacies/${stranger.uid}`, {
      ...profile, code: `PHR-${stranger.uid}`, email: stranger.email, access_status: 'active', created_at: new Date(),
    }, 'owner'));
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
