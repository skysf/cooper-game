import {execFileSync} from 'node:child_process';
import {appendFileSync, readFileSync} from 'node:fs';
import {pathToFileURL} from 'node:url';

const sha = /^[0-9a-f]{40}$/i;
const git = (...args) => execFileSync('git', args, {encoding: 'utf8'}).trimEnd();

export function documentationOnly(paths) {
  return paths.length > 0 && paths.every(path => path === 'README.md' || path === 'AGENTS.md' ||
    (path.startsWith('docs/') && path.endsWith('.md')) ||
    (path.startsWith('evidence/') && /\.(?:png|jpe?g|webp)$/i.test(path)));
}

export function proofName(number, tree, reference) {
  return `cooper-visual-pr-${number}-${tree}-${reference}`;
}

// A successful check on a branch head alone does not identify the merged tree
// or the reference it was compared with. A completed four-scene run records both.
export async function verifiedPullRun({repository, commit, branch, tree, reference}, get) {
  const pulls = await get(`commits/${commit}/pulls`);
  const pull = pulls.find(pr => pr.merged_at && pr.merge_commit_sha === commit &&
    pr.base.repo.full_name === repository && pr.base.ref === branch && sha.test(pr.head.sha));
  if (!pull) return null;
  const query = new URLSearchParams({event: 'pull_request', status: 'success', head_sha: pull.head.sha, per_page: '20'});
  const {workflow_runs: runs} = await get('actions/workflows/coop-render.yml/runs?' + query);
  const marker = proofName(pull.number, tree, reference);
  for (const run of runs) {
    if (run.event !== 'pull_request' || run.conclusion !== 'success' || run.head_sha !== pull.head.sha ||
        run.head_repository?.full_name !== pull.head.repo?.full_name) continue;
    const {artifacts} = await get(`actions/runs/${run.id}/artifacts?per_page=100`);
    if (artifacts.some(artifact => artifact.name === marker && !artifact.expired && artifact.size_in_bytes > 0)) return run;
  }
  return null;
}

async function main() {
  const env = process.env;
  const event = JSON.parse(readFileSync(env.GITHUB_EVENT_PATH, 'utf8'));
  const commit = env.GITHUB_SHA;
  let reference = env.REQUESTED_REFERENCE || event.pull_request?.base.sha || event.before;
  if (!reference || /^0{40}$/.test(reference)) reference = git('rev-parse', 'HEAD^');
  if (!sha.test(reference) || reference === commit) throw Error('Choose a distinct reference commit');
  const tree = git('rev-parse', 'HEAD^{tree}');
  let mode = env.HARDWARE === 'true' ? 'hardware' : 'full';
  let source = '';
  if (mode === 'full' && env.GITHUB_EVENT_NAME === 'push') {
    try {
      const get = path => JSON.parse(execFileSync('gh', ['api', `repos/${env.GITHUB_REPOSITORY}/${path}`], {encoding:'utf8'}));
      const run = await verifiedPullRun({repository:env.GITHUB_REPOSITORY, commit, branch:env.GITHUB_REF_NAME, tree, reference}, get);
      if (run) { mode = 'reuse'; source = run.html_url; }
    } catch (error) {
      console.log('Could not verify an earlier run. Performing the full comparison.', error.message);
    }
  }
  if (mode === 'full' && env.GITHUB_EVENT_NAME !== 'workflow_dispatch') {
    // An older pinned reference may be outside the shallow checkout. Compare it
    // in the build jobs in that case, without assuming this only changes docs.
    try {
      const names = execFileSync('git', ['diff', '--no-renames', '--name-only', '-z', reference, 'HEAD'], {encoding:'utf8'});
      if (documentationOnly(names.split('\0').filter(Boolean))) mode = 'docs';
    } catch { /* The full comparison is already selected. */ }
  }
  const proof = event.pull_request ? proofName(event.number, tree, reference) : '';
  appendFileSync(env.GITHUB_OUTPUT, `mode=${mode}\nreference=${reference}\ntree=${tree}\nproof=${proof}\nsource=${source}\n`);
  console.log(`Render mode ${mode}, tree ${tree}, reference ${reference}`);
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) await main();
