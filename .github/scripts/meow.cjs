// The meow easter egg for issues and pull requests, switched by release/events.json (see scripts/core/easter_eggs.gd).
// While it is on, an issue or PR opened on the egg's date (Beijing time) gets 喵 before every punctuation mark in its
// title and body. Code blocks, inline code, links and HTML comments are left alone, and the original text is kept in a
// hidden marker so restore() puts it back once the egg is switched off or has expired. Bot-authored issues are skipped:
// the card validation workflow finds its own issues by their exact title.
const {readFileSync} = require('node:fs');

const PUNCTUATION = new Set([...'，。！？、；：…—（）《》【】「」『』“”‘’,.!?;:()[]~～']);
const MARKER = /\n*<!-- meow-original:([A-Za-z0-9+/=]+) -->\s*$/;
const BEIJING = 8 * 3600 * 1000;

function config(path = 'release/events.json', now = Date.now()) {
  try {
    const meow = JSON.parse(readFileSync(path, 'utf8')).meow;
    if (!meow || typeof meow.enabled !== 'boolean' || !/^\d{4}-\d{2}-\d{2}$/.test(meow.date ?? '') || !Number.isFinite(meow.until_unix)) return null;
    return {...meow, active: meow.enabled && now < meow.until_unix * 1000};
  } catch { return null; }
}

const beijingDate = iso => new Date(Date.parse(iso) + BEIJING).toISOString().slice(0, 10);

function meowText(text) {
  let result = '';
  for (let i = 0; i < text.length; i++) {
    const c = text[i];
    const decimal = c === '.' && /\d/.test(text[i - 1] ?? '') && /\d/.test(text[i + 1] ?? '');
    if (PUNCTUATION.has(c) && !decimal && text[i - 1] !== '喵') result += '喵';
    result += c;
  }
  return result;
}

// Markdown: only prose is changed; fenced code, inline code, links, autolinks, URLs and HTML comments stay as written.
function meowMarkdown(markdown) {
  const protectedPart = /```[\s\S]*?```|~~~[\s\S]*?~~~|`[^`\n]*`|<!--[\s\S]*?-->|\]\([^)]*\)|<https?:[^>]*>|https?:\/\/\S+/g;
  let result = '', last = 0;
  for (const match of markdown.matchAll(protectedPart)) {
    result += meowText(markdown.slice(last, match.index)) + match[0];
    last = match.index + match[0].length;
  }
  return result + meowText(markdown.slice(last));
}

const encode = value => Buffer.from(JSON.stringify(value), 'utf8').toString('base64');
const decode = value => JSON.parse(Buffer.from(value, 'base64').toString('utf8'));

async function update(github, {owner, repo}, item, fields) {
  if (item.pull_request || item.head) await github.rest.pulls.update({owner, repo, pull_number: item.number, ...fields});
  else await github.rest.issues.update({owner, repo, issue_number: item.number, ...fields});
}

async function apply({github, context, core}, item) {
  const egg = config();
  if (!egg?.active || !item || item.user?.type === 'Bot') return;
  if (beijingDate(item.created_at) !== egg.date || MARKER.test(item.body ?? '')) return;
  const original = {title: item.title, body: item.body ?? ''};
  const body = `${meowMarkdown(original.body)}\n\n<!-- meow-original:${encode(original)} -->`;
  await update(github, context.repo, item, {title: meowText(original.title), body});
  core.info(`喵 #${item.number}`);
}

async function restore({github, context, core}, force = false) {
  const egg = config();
  if (egg?.active && !force) return;
  if (!egg) return;
  for (const item of await sameDay({github, context}, egg)) {
    const match = MARKER.exec(item.body ?? '');
    if (!match) continue;
    const original = decode(match[1]);
    await update(github, context.repo, item, {title: original.title, body: original.body});
    core.info(`复原 #${item.number}`);
  }
}

// Issues and PRs opened on the egg's date (Beijing time); the marker itself is not searchable.
async function sameDay({github, context}, egg) {
  const {owner, repo} = context.repo;
  const from = Date.parse(`${egg.date}T00:00:00+08:00`);
  const stamp = ms => new Date(ms).toISOString().slice(0, 19) + 'Z';
  return github.paginate(github.rest.search.issuesAndPullRequests, {q: `repo:${owner}/${repo} created:${stamp(from)}..${stamp(from + 86400000)}`, per_page: 100});
}

// workflow_dispatch "apply": the egg's date has passed before this workflow existed, so meow everything opened that day.
async function backfill({github, context, core}) {
  const egg = config();
  if (!egg?.active) return;
  for (const item of await sameDay({github, context}, egg)) await apply({github, context, core}, item);
}

async function run({github, context, core}) {
  const name = context.eventName;
  if (name === 'issues') return apply({github, context, core}, context.payload.issue);
  if (name === 'pull_request_target') return apply({github, context, core}, context.payload.pull_request);
  if (name === 'workflow_dispatch' && context.payload.inputs?.mode === 'apply') return backfill({github, context, core});
  if (name === 'workflow_dispatch' && context.payload.inputs?.mode === 'restore') return restore({github, context, core}, true);
  return restore({github, context, core});
}

module.exports = Object.assign(run, {meowText, meowMarkdown, beijingDate, config, MARKER, encode, decode});
