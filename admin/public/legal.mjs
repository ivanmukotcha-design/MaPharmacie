export function publicationProblems(information) {
  const problems = [];
  if (information.approvedForPublication !== true) problems.push('La politique doit être validée par le responsable avant publication.');
  if (!information.appName?.trim()) problems.push('Le nom de l’application est manquant.');
  if (!information.publisherName?.trim()) problems.push('Le nom public du développeur ou de l’entreprise est manquant.');
  if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(information.supportEmail || '')) problems.push('Une adresse de support publique valide est nécessaire.');
  const parsedDate = Date.parse(information.effectiveDate);
  if (!/^\d{4}-\d{2}-\d{2}$/.test(information.effectiveDate || '') || !Number.isFinite(parsedDate) || new Date(parsedDate).toISOString().slice(0, 10) !== information.effectiveDate) problems.push('La date de la politique doit être renseignée et valide.');
  try {
    if (new URL(information.website).protocol !== 'https:') throw new Error();
  } catch { problems.push('Le site public doit utiliser HTTPS.'); }
  if (!Array.isArray(information.sections) || !information.sections.length || information.sections.some(section => !section.title?.trim() || !section.body?.trim())) problems.push('La politique de confidentialité est incomplète.');
  if (!information.deletion?.warning?.trim() || !Array.isArray(information.deletion?.steps) || !information.deletion.steps.length || information.deletion.steps.some(step => !step?.trim()) || !information.deletion?.subject?.trim() || !information.deletion?.body?.trim()) problems.push('La procédure de suppression est incomplète.');
  return problems;
}

export function deletionEmail(information) {
  if (publicationProblems(information).length) throw new Error('Informations publiques non validées');
  return `mailto:${encodeURIComponent(information.supportEmail)}?subject=${encodeURIComponent(information.deletion.subject)}&body=${encodeURIComponent(information.deletion.body)}`;
}
