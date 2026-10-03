import('./app.mjs').catch(() => {
  document.getElementById('message').textContent = 'Chargement impossible. Vérifiez votre connexion Internet puis rechargez cette page.';
});
