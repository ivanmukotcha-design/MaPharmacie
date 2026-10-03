import { initializeApp } from 'https://www.gstatic.com/firebasejs/12.19.0/firebase-app.js';
import { getAuth, onAuthStateChanged, signInWithEmailAndPassword, signOut, setPersistence, browserSessionPersistence, sendPasswordResetEmail, connectAuthEmulator } from 'https://www.gstatic.com/firebasejs/12.19.0/firebase-auth.js';
import { getFirestore, collection, doc, getDocFromServer, getDocsFromServer, query, orderBy, limit, startAfter, where, runTransaction, serverTimestamp, onSnapshot, connectFirestoreEmulator } from 'https://www.gstatic.com/firebasejs/12.19.0/firebase-firestore.js';
import { labels, transitions, validateDecision, filterClients, summarize } from './access.mjs';

const element = id => document.getElementById(id);
const message = text => { element('message').textContent = text; };
const date = value => value?.toDate ? value.toDate().toLocaleString('fr-FR') : 'Non renseignée';
const local = ['127.0.0.1', 'localhost'].includes(location.hostname) && new URLSearchParams(location.search).get('emulators') === '1';
let auth, database, clients = [], cursor = null, more = false, selected = null, epoch = 0, authorized = false, roleSubscription = null;
let listBusy = false, actionBusy = false;

function node(tag, text, className) {
  const result = document.createElement(tag);
  if (text !== undefined) result.textContent = text;
  if (className) result.className = className;
  return result;
}

function describeError(error) {
  if (error.code?.includes('permission-denied')) return 'Accès refusé. Vérifiez vos droits administrateur et les règles Firebase publiées.';
  if (error.code?.includes('failed-precondition')) return 'Configuration incomplète : vérifiez les index Firestore indiqués dans le guide de déploiement.';
  if (error.code?.startsWith('auth/')) return 'Connexion impossible. Vérifiez vos identifiants et votre connexion, puis réessayez.';
  if (error.code) return 'Opération impossible pour le moment. Vérifiez votre connexion puis actualisez avant de réessayer.';
  return error.message || 'Opération impossible.';
}

function clearWorkspace() {
  authorized = false;
  clients = [];
  selected = null;
  cursor = null;
  more = false;
  listBusy = false;
  actionBusy = false;
  element('close-detail').disabled = false;
  element('detail').close();
  for (const id of ['clients', 'stats', 'history', 'detail-content']) element(id).replaceChildren();
  element('reason').value = '';
  element('search').value = '';
  element('status').value = 'all';
  element('detail-title').textContent = 'Fiche client';
  for (const id of ['coverage', 'results', 'signed-in', 'detail-message']) element(id).textContent = '';
  element('workspace').hidden = true;
}

function renderClients() {
  const counts = summarize(clients);
  element('stats').replaceChildren(...['total', 'pending', 'active', 'suspended'].map(status => {
    const card = node('div', undefined, 'stat');
    card.append(node('span', status === 'total' ? 'Pharmacies chargées' : labels[status]), node('strong', counts[status]));
    return card;
  }));
  element('coverage').textContent = `${clients.length} fiche(s) chargée(s). ${more ? 'Les compteurs et la recherche portent sur ces fiches ; chargez la suite pour élargir les résultats.' : 'Toutes les fiches de l’annuaire ont été chargées.'} Les anciens comptes apparaissent après leur connexion avec l’application mise à jour.`;
  const matches = filterClients(clients, element('search').value, element('status').value);
  element('results').textContent = `${matches.length} résultat(s)`;
  element('clients').replaceChildren(...matches.map(client => {
    const card = node('article', undefined, 'client');
    const info = node('div', undefined, 'client-info');
    info.append(node('h2', client.nom || 'Pharmacie sans nom'), node('p', `${client.ville || 'Ville non renseignée'} · ${client.telephone || 'Téléphone non renseigné'}`), node('p', client.email), node('span', labels[client.access_status] || 'Statut inconnu', `badge ${Object.hasOwn(labels, client.access_status) ? client.access_status : ''}`));
    const button = node('button', 'Ouvrir la fiche', 'secondary');
    button.addEventListener('click', () => openClient(client));
    card.append(info, button);
    return card;
  }));
  if (!matches.length) element('clients').append(node('p', 'Aucune pharmacie ne correspond à cette sélection.'));
  element('load-more').hidden = !more;
}

async function loadClients(reset = false) {
  if (!authorized || listBusy) return;
  const ticket = epoch;
  listBusy = true;
  element('refresh').disabled = element('load-more').disabled = true;
  message('Chargement des fiches clients…');
  try {
    const constraints = [orderBy('__name__'), limit(100)];
    if (!reset && cursor) constraints.push(startAfter(cursor));
    const snapshot = await getDocsFromServer(query(collection(database, 'clients'), ...constraints));
    if (ticket !== epoch || !authorized) return;
    const entries = snapshot.docs.map(record => ({ ...record.data(), id: record.id }));
    clients = reset ? entries : [...clients, ...entries];
    cursor = snapshot.docs.at(-1) || null;
    more = snapshot.size === 100;
    renderClients();
    message('');
  } catch (error) {
    if (ticket === epoch) message(describeError(error));
  } finally {
    if (ticket === epoch) {
      listBusy = false;
      element('refresh').disabled = element('load-more').disabled = false;
    }
  }
}

async function openClient(client) {
  if (!authorized) return;
  selected = client;
  element('detail-title').textContent = client.nom || 'Fiche client';
  const description = node('dl');
  for (const [label, value] of [
    ['Responsable', client.proprietaire_nom], ['Email', client.email], ['Téléphone', client.telephone],
    ['Adresse', client.adresse], ['Ville / pays', `${client.ville} / ${client.pays}`],
    ['Statut', labels[client.access_status] || 'Inconnu'], ['Inscription', date(client.created_at)],
    ['Activation', date(client.activated_at)], ['Identifiant', client.id],
  ]) description.append(node('dt', label), node('dd', value || 'Non renseigné'));
  element('detail-content').replaceChildren(description);
  element('action-form').reset();
  const decisions = transitions(client.access_status);
  element('decision').replaceChildren(...decisions.map(status => {
    const option = node('option', status === 'active' ? (client.access_status === 'pending' ? 'Activer après la vente' : 'Réactiver le compte') : 'Suspendre le compte');
    option.value = status;
    return option;
  }));
  element('apply').disabled = !decisions.length;
  element('confirmation-label').textContent = client.access_status === 'pending'
    ? 'J’ai vérifié la vente et je confirme l’activation de cette pharmacie.'
    : client.access_status === 'active' ? 'Je confirme la suspension des opérations de cette pharmacie, sans suppression de ses données.' : 'Je confirme la réactivation de cette pharmacie.';
  element('detail-message').textContent = '';
  element('history').replaceChildren(node('li', 'Chargement…'));
  if (!element('detail').open) element('detail').showModal();
  const ticket = epoch;
  try {
    const snapshot = await getDocsFromServer(query(collection(database, 'account_events'), where('client_id', '==', client.id), orderBy('revision', 'desc'), limit(30)));
    if (ticket !== epoch || selected?.id !== client.id || !authorized) return;
    element('history').replaceChildren(...snapshot.docs.map(record => {
      const event = record.data();
      return node('li', `${date(event.created_at)} — ${labels[event.from_status]} → ${labels[event.to_status]}\n${event.reason}\nAdministrateur : ${event.actor_uid}`);
    }));
    if (snapshot.empty) element('history').append(node('li', 'Aucune intervention enregistrée.'));
  } catch (error) {
    if (ticket === epoch && selected?.id === client.id) element('history').replaceChildren(node('li', describeError(error)));
  }
}

element('action-form').addEventListener('submit', async event => {
  event.preventDefault();
  if (!authorized || !selected || actionBusy || !element('confirmation').checked) return;
  const client = selected;
  const target = element('decision').value;
  const ticket = epoch;
  const actor = auth.currentUser.uid;
  actionBusy = true;
  element('apply').disabled = true;
  element('close-detail').disabled = true;
  element('detail-message').textContent = 'Enregistrement sécurisé de la décision…';
  try {
    const reason = validateDecision(client.access_status, target, element('reason').value);
    const reference = doc(database, 'clients', client.id);
    const audit = doc(collection(database, 'account_events'));
    await runTransaction(database, async transaction => {
      const snapshot = await transaction.get(reference);
      if (!snapshot.exists()) throw new Error('Cette fiche n’existe plus. Actualisez la liste.');
      const current = snapshot.data();
      if (current.access_revision !== client.access_revision || current.access_status !== client.access_status) throw new Error('Le compte a changé depuis son affichage. Fermez la fiche et actualisez avant de recommencer.');
      if (!authorized || ticket !== epoch || auth.currentUser?.uid !== actor) throw new Error('La session a changé. Reconnectez-vous.');
      validateDecision(current.access_status, target, reason);
      const update = { access_status: target, access_revision: current.access_revision + 1,
        last_access_event: audit.id, access_updated_at: serverTimestamp(),
        activated_at: current.activated_at ?? (target === 'active' ? serverTimestamp() : null) };
      transaction.update(reference, update);
      transaction.update(doc(database, 'pharmacies', client.id), update);
      transaction.set(audit, { client_id: client.id, actor_uid: actor, from_status: current.access_status,
        to_status: target, reason, revision: update.access_revision, created_at: serverTimestamp() });
    });
    if (ticket !== epoch || !authorized) return;
    element('detail').close();
    selected = null;
    await loadClients(true);
    message('Décision enregistrée et historisée. Les appareils déconnectés recevront le nouveau statut à leur reconnexion.');
  } catch (error) {
    if (ticket === epoch) element('detail-message').textContent = describeError(error);
  } finally {
    if (ticket === epoch) {
      actionBusy = false;
      element('apply').disabled = false;
      element('close-detail').disabled = false;
    }
  }
});

element('detail').addEventListener('cancel', event => { if (actionBusy) event.preventDefault(); });
element('close-detail').addEventListener('click', () => { if (!actionBusy) { selected = null; element('detail').close(); } });
element('search').addEventListener('input', renderClients);
element('status').addEventListener('change', renderClients);
element('refresh').addEventListener('click', () => loadClients(true));
element('load-more').addEventListener('click', () => loadClients());
element('logout').addEventListener('click', async () => {
  ++epoch;
  clearWorkspace();
  try { await signOut(auth); } catch (error) { message(describeError(error)); }
});
element('login-form').addEventListener('submit', async event => {
  event.preventDefault();
  const button = event.submitter;
  button.disabled = true;
  message('Connexion en cours…');
  try { await signInWithEmailAndPassword(auth, element('email').value.trim(), element('password').value); }
  catch (error) { message(describeError(error)); }
  finally { element('password').value = ''; button.disabled = false; }
});
element('reset-password').addEventListener('click', async () => {
  if (!element('email').reportValidity()) return;
  try {
    await sendPasswordResetEmail(auth, element('email').value.trim());
    message('Si cette adresse correspond à un compte, consultez vos emails pour réinitialiser le mot de passe.');
  } catch (error) { message(describeError(error)); }
});

try {
  const response = local ? null : await fetch('/__/firebase/init.json', { cache: 'no-store' });
  if (!local && !response.ok) throw new Error('Ouvrez ce tableau de bord depuis Firebase Hosting. Consultez le guide de déploiement.');
  const config = local ? { projectId: 'demo-pharmaflow-tests', apiKey: 'demo-key', appId: 'demo-app', authDomain: 'localhost' } : await response.json();
  const app = initializeApp(config);
  auth = getAuth(app);
  database = getFirestore(app);
  if (local) { connectAuthEmulator(auth, 'http://127.0.0.1:9099', { disableWarnings: true }); connectFirestoreEmulator(database, '127.0.0.1', 8080); }
  await setPersistence(auth, browserSessionPersistence);
  onAuthStateChanged(auth, async user => {
    const ticket = ++epoch;
    roleSubscription?.();
    roleSubscription = null;
    clearWorkspace();
    element('logout').hidden = !user;
    element('login').hidden = Boolean(user);
    if (!user) { message(''); return; }
    message('Vérification des droits administrateur…');
    try {
      const reference = doc(database, 'account_admins', user.uid);
      const role = await getDocFromServer(reference);
      if (ticket !== epoch) return;
      if (role.data()?.enabled !== true) { message('Ce compte ne possède pas les droits administrateur. Déconnectez-vous ou contactez le propriétaire du projet.'); return; }
      authorized = true;
      element('workspace').hidden = false;
      element('signed-in').textContent = `Connecté : ${user.email}`;
      roleSubscription = onSnapshot(reference, snapshot => {
        if (ticket === epoch && snapshot.data()?.enabled !== true) { ++epoch; clearWorkspace(); message('Vos droits administrateur ont été retirés.'); }
      }, () => { if (ticket === epoch) { ++epoch; clearWorkspace(); message('Droits indisponibles. Reconnectez-vous pour les vérifier.'); } });
      await loadClients(true);
    } catch (error) { if (ticket === epoch) message(describeError(error)); }
  });
} catch (error) { message(describeError(error)); }
