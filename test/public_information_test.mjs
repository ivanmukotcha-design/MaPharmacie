import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { deletionEmail, publicationProblems } from '../admin/public/legal.mjs';

const source = JSON.parse(await readFile(new URL('../admin/public/legal.json', import.meta.url), 'utf8'));
const valid = { ...source, publisherName: 'Éditeur de test', supportEmail: 'support@example.test', effectiveDate: '2026-10-16', approvedForPublication: true };

test('Le contrôle de publication refuse les coordonnées ou la validation manquantes', () => {
  assert.deepEqual(publicationProblems(valid), []);
  for (const overrides of [
    { publisherName: '' }, { supportEmail: '' }, { supportEmail: 'invalide' },
    { effectiveDate: '' }, { approvedForPublication: false }, { website: 'http://example.test' },
    { sections: [] }, { deletion: {} },
    { effectiveDate: '2026-02-30' },
  ]) {
    const invalid = { ...valid, ...overrides };
    assert.ok(publicationProblems(invalid).length);
    assert.throws(() => deletionEmail(invalid));
  }
});

test('Les sauvegardes système excluent les bases et les sessions sans retirer les exports manuels', async () => {
  const base = new URL('../android/app/src/main/', import.meta.url);
  const manifest = await readFile(new URL('AndroidManifest.xml', base), 'utf8');
  assert.match(manifest, /android:allowBackup="false"/);
  assert.match(manifest, /android:dataExtractionRules="@xml\/data_extraction_rules"/);
  const legacy = await readFile(new URL('res/xml/backup_rules.xml', base), 'utf8');
  const modern = await readFile(new URL('res/xml/data_extraction_rules.xml', base), 'utf8');
  for (const domain of ['root', 'file', 'database', 'sharedpref', 'external', 'device_root', 'device_file', 'device_database', 'device_sharedpref']) {
    const expression = new RegExp(`<exclude domain="${domain}" path="\\."`, 'g');
    assert.equal([...legacy.matchAll(expression)].length, 1);
    assert.equal([...modern.matchAll(expression)].length, 2);
  }
});

test('Le lien encode correctement le texte et ne transmet aucune demande automatiquement', () => {
  const information = { ...valid, deletion: { ...valid.deletion, subject: 'Compte & pharmacie ?', body: 'Email :\nQuestion & réponse + caractères accentués' } };
  const uri = new URL(deletionEmail(information));
  assert.equal(uri.protocol, 'mailto:');
  assert.equal(decodeURIComponent(uri.pathname), information.supportEmail);
  assert.equal(uri.searchParams.get('subject'), information.deletion.subject);
  assert.equal(uri.searchParams.get('body'), information.deletion.body);
});

test('Le manifeste ne force pas le portrait ni les permissions inutilisées', async () => {
  const manifest = await readFile(new URL('../android/app/src/main/AndroidManifest.xml', import.meta.url), 'utf8');
  assert.ok(!manifest.includes('screenOrientation="portrait"'));
  for (const permission of ['READ_EXTERNAL_STORAGE', 'WRITE_EXTERNAL_STORAGE', 'CALL_PHONE', 'USE_BIOMETRIC', 'USE_FINGERPRINT']) {
    assert.match(manifest, new RegExp(`<uses-permission[^>]+android.permission.${permission}[^>]+tools:node="remove"`));
  }
});
