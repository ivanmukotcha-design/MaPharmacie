export const labels = Object.freeze({ pending: 'En attente', active: 'Actif', suspended: 'Suspendu' });

export function transitions(status) {
  if (status === 'pending' || status === 'suspended') return ['active'];
  if (status === 'active') return ['suspended'];
  return [];
}

export function validateDecision(current, target, reason) {
  if (!transitions(current).includes(target)) throw new Error('Cette transition de statut est interdite.');
  const trimmed = reason.trim();
  if (trimmed.length < 5 || trimmed.length > 500) throw new Error('Indiquez un motif de 5 à 500 caractères.');
  return trimmed;
}

export function filterClients(clients, query, status) {
  const normalized = query.trim().toLocaleLowerCase('fr');
  return clients.filter(client => (status === 'all' || client.access_status === status) &&
    ['nom', 'email', 'telephone', 'ville', 'proprietaire_nom'].some(field =>
      String(client[field] ?? '').toLocaleLowerCase('fr').includes(normalized)));
}

export function summarize(clients) {
  const counts = { total: clients.length, pending: 0, active: 0, suspended: 0 };
  for (const client of clients) {
    if (Object.hasOwn(labels, client.access_status)) counts[client.access_status]++;
  }
  return counts;
}
