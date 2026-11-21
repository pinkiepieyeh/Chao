// One-off: gives catalog records without submitted_at the time of the commit that added their current revision,
// read from git history since --since (ISO date-time). Records already stamped are left alone. Idempotent.
// node tools/library/backfill_submitted_at.mjs --since 2026-11-20T00:00:00+08:00 [--dry-run]
import {execFileSync} from 'node:child_process';
import {loadCatalog, saveCatalog, ROOT} from './catalog_io.mjs';

const args = process.argv.slice(2);
const since = args[args.indexOf('--since') + 1];
if (!since || args.indexOf('--since') < 0) { console.error('需要 --since <ISO 时间>。'); process.exit(1); }
const git = (...parts) => execFileSync('git', parts, {cwd: ROOT, encoding: 'utf8', maxBuffer: 256 * 1024 * 1024});

const commits = git('log', '--reverse', '--format=%H %cI', `--since=${since}`, '--', 'data/catalog.json').trim().split('\n').filter(Boolean).map(line => line.split(' '));
const stamped = {};
let before = null;
try { before = JSON.parse(git('show', `${commits[0]?.[0]}~1:data/catalog.json`)); } catch { before = {cards: []}; }
let seen = Object.fromEntries(before.cards.map(card => [card.card_id, card.revision]));
for (const [hash, time] of commits) {
  const cards = JSON.parse(git('show', `${hash}:data/catalog.json`)).cards;
  for (const card of cards) if (seen[card.card_id] !== card.revision) stamped[`${card.card_id}@${card.revision}`] = new Date(time).toISOString();
  seen = Object.fromEntries(cards.map(card => [card.card_id, card.revision]));
}
const catalog = loadCatalog();
const changed = [];
const cards = catalog.cards.map(card => {
  const time = stamped[`${card.card_id}@${card.revision}`];
  if (!time || card.submitted_at) return card;
  changed.push({name: card.definition.name, revision: card.revision, submitted_at: time});
  return {...card, submitted_at: time};
});
console.log(JSON.stringify(changed, null, 1));
if (!args.includes('--dry-run') && changed.length) console.log(`卡库版本：${saveCatalog({...catalog, cards}).catalog_version}`);
