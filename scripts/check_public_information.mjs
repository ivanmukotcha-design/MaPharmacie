import { readFile } from 'node:fs/promises';
import { publicationProblems } from '../admin/public/legal.mjs';

try {
  const information = JSON.parse(await readFile(new URL('../admin/public/legal.json', import.meta.url), 'utf8'));
  const problems = publicationProblems(information);
  if (problems.length) {
    process.stderr.write(`Publication bloquée :\n${problems.map(problem => `- ${problem}`).join('\n')}\n`);
    process.exitCode = 1;
  } else {
    process.stdout.write('Informations publiques complètes. La conformité et la procédure de traitement restent à valider par le responsable.\n');
  }
} catch {
  process.stderr.write('Impossible de vérifier les informations publiques. Publication bloquée.\n');
  process.exitCode = 1;
}
