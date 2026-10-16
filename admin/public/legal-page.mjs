import { publicationProblems, deletionEmail } from './legal.mjs';

const element = id => document.getElementById(id);
const node = (tag, text) => {
  const result = document.createElement(tag);
  result.textContent = text;
  return result;
};

try {
  const response = await fetch('./legal.json', { cache: 'no-store' });
  if (!response.ok) throw new Error('Informations indisponibles. Réessayez plus tard.');
  const information = await response.json();
  const problems = publicationProblems(information);
  element('app-name').textContent = information.appName;
  if (problems.length) {
    element('legal-status').textContent = 'Version de préparation : les coordonnées et la politique ne sont pas encore validées. Cette page ne doit pas être publiée en l’état.';
  } else {
    element('publisher').textContent = `Éditeur : ${information.publisherName} · Mise à jour : ${information.effectiveDate}`;
    element('contact').textContent = information.supportEmail;
    element('legal-status').textContent = '';
  }
  if (document.body.dataset.page === 'privacy') {
    for (const section of information.sections) {
      const article = document.createElement('section');
      article.append(node('h2', section.title), node('p', section.body));
      element('legal-content').append(article);
    }
  } else {
    element('legal-content').append(node('p', information.deletion.warning));
    const steps = document.createElement('ol');
    steps.append(...information.deletion.steps.map(step => node('li', step)));
    element('legal-content').append(steps);
    if (!problems.length) {
      element('request-options').hidden = false;
      element('email-request').href = deletionEmail(information);
      element('confirm-owner').addEventListener('change', event => {
        element('email-request').hidden = !event.target.checked;
      });
    }
  }
} catch {
  element('legal-status').textContent = 'Informations indisponibles. Vérifiez votre connexion puis rechargez cette page.';
}
