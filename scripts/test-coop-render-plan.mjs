import assert from 'node:assert/strict';
import test from 'node:test';
import {documentationOnly, proofName, verifiedPullRun} from './coop-render-plan.mjs';

const context = {repository:'sky/cooper', commit:'a'.repeat(40), tree:'b'.repeat(40), reference:'c'.repeat(40), branch:'main'};
const head = 'd'.repeat(40);
const pull = {number:7, merged_at:'2026-11-23', merge_commit_sha:context.commit,
  base:{ref:'main', repo:{full_name:context.repository}}, head:{sha:head, repo:{full_name:context.repository}}};
const run = {id:123, event:'pull_request', conclusion:'success', head_sha:head, head_repository:pull.head.repo};
const proof = {name:proofName(7, context.tree, context.reference), size_in_bytes:180, expired:false};

const replies = (prs, runs, artifacts) => async path => {
  if (path === `commits/${context.commit}/pulls`) return prs;
  if (path.startsWith('actions/workflows/coop-render.yml/runs?')) return {workflow_runs:runs};
  if (path === 'actions/runs/123/artifacts?per_page=100') return {artifacts};
  throw Error('Unexpected request ' + path);
};

test('only documentation and evidence images qualify for the documentation shortcut', () => {
  assert.ok(documentationOnly(['README.md','docs/play.md','evidence/flight/edge.png']));
  for (const paths of [[], ['coop/coast/tide.png'], ['docs/new-tool.py'], ['evidence/result.json'],
    ['README.md','.github/workflows/coop-render.yml'], ['scripts/coop-render-benchmark.mjs']]) {
    assert.equal(documentationOnly(paths), false);
  }
});

test('a successful comparison belongs to this merge, repository, tree and baseline', async () => {
  assert.equal(await verifiedPullRun(context, replies([pull],[run],[proof])), run);
  for (const evidence of [
    replies([], [run], [proof]),
    replies([{...pull,merge_commit_sha:head}], [run], [proof]),
    replies([pull], [{...run,head_repository:{full_name:'elsewhere/cooper'}}], [proof]),
    replies([pull], [{...run,conclusion:'failure'}], [proof]),
    replies([pull], [run], [{...proof, expired:true}]),
    replies([pull], [run], [{...proof, name:proofName(8,context.tree,context.reference)}]),
    replies([pull], [run], [{...proof, name:proofName(7,head,context.reference)}]),
    replies([pull], [run], [{...proof, name:proofName(7,context.tree,head)}]),
  ]) assert.equal(await verifiedPullRun(context, evidence), null);
});
