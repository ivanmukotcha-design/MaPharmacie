import { test } from 'node:test';
import assert from 'node:assert/strict';
import { filterClients, summarize, transitions, validateDecision } from '../admin/public/access.mjs';

test('Transitions explicites et motif obligatoire', () => {
  assert.deepEqual(transitions('pending'), ['active']);
  assert.deepEqual(transitions('active'), ['suspended']);
  assert.deepEqual(transitions('suspended'), ['active']);
  assert.deepEqual(transitions('unknown'), []);
  assert.throws(() => validateDecision('pending', 'suspended', 'raison valable'));
  assert.throws(() => validateDecision('active', 'active', 'raison valable'));
  assert.throws(() => validateDecision('pending', 'active', '    '));
  assert.throws(() => validateDecision('pending', 'active', 'a'.repeat(501)));
  assert.equal(validateDecision('pending', 'active', ' Vente confirmée '), 'Vente confirmée');
});
test('Recherche, filtres et compteurs sur les fiches chargées', () => {
  const clients = [
    { nom: 'Pharmacie Soleil', ville: 'Kinshasa', telephone: '123', access_status: 'pending' },
    { nom: 'Autre', email: 'contact@example.com', access_status: 'active' },
    { nom: 'Troisième', proprietaire_nom: 'Jean', access_status: 'suspended' },
  ];
  assert.equal(filterClients(clients, ' KINSHASA ', 'all').length, 1);
  assert.equal(filterClients(clients, '123', 'active').length, 0);
  assert.equal(filterClients(clients, 'CONTACT@', 'active').length, 1);
  assert.equal(filterClients(clients, 'jean', 'suspended').length, 1);
  assert.deepEqual(summarize(clients), { total: 3, pending: 1, active: 1, suspended: 1 });
});
