const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const workflow = JSON.parse(fs.readFileSync('.github/workflows/ai-sdlc-maintain.yml', 'utf8'));
const script = workflow.jobs.repair.steps[0].with.script;
const execute = new (Object.getPrototypeOf(async function(){}).constructor)('github', 'context', 'core', script);
const sha = 'a'.repeat(40);
const owned = {number: 8, user: {login: 'github-actions[bot]'}, body: '<!-- ai-sdlc-current-main-repair -->\nold'};
async function scenario(change = {}, issues = [], current = sha, live = {}, observed = []) {
  const writes = [];
  const run = {id: 10, workflow_id: 5, event: 'push', head_branch: 'main',
    head_repository: {full_name: 'fol2/jev-playground'}, path: '.github/workflows/ai-sdlc.yml',
    head_sha: sha, status: 'completed', run_attempt: 1, conclusion: 'failure', ...change};
  const github = {rest: {
    actions: {getWorkflowRun: async () => { if (live.error) throw Error('unavailable'); return {data: {...run, ...live}}; }, getWorkflow: async () => ({data: {id: 5, path: '.github/workflows/ai-sdlc.yml'}})},
    repos: {getBranch: async () => ({data: {commit: {sha: current}}})},
    issues: {listForRepo: () => {}, create: async v => writes.push(['create', v]), update: async v => writes.push(['update', v])}
  }, paginate: async () => issues};
  await execute(github, {repo: {owner: 'fol2', repo: 'jev-playground'}, payload: {workflow_run: run}}, {info: message => observed.push(message)});
  return writes;
}
test('new failure records a source-only repair intent', async () => {
  const writes = await scenario();
  assert.equal(writes.length, 1); assert.equal(writes[0][0], 'create');
  assert.match(writes[0][1].body, /no live-machine effects/);
  assert.match(writes[0][1].body, /not a running AI worker/);
});
test('existing issue updates and identical event is idempotent', async () => {
  const first = await scenario({}, [owned]);
  assert.equal(first[0][0], 'update');
  assert.deepEqual(await scenario({}, [{...owned, body: first[0][1].body}]), []);
});
test('green current main closes only a bot-owned repair', async () => {
  const writes = await scenario({conclusion: 'success'}, [owned]);
  assert.equal(writes[0][1].state, 'closed');
  assert.deepEqual(await scenario({conclusion: 'success'}), []);
  assert.deepEqual(await scenario({conclusion: 'success'}, [{...owned, user: {login: 'someone'}}]), []);
});
test('stale run cannot open or close an incident', async () => {
  for (const conclusion of ['failure', 'success'])
    assert.deepEqual(await scenario({conclusion}, [owned], 'b'.repeat(40)), []);
});
test('foreign, malformed and non-main runs are ignored', async () => {
  for (const change of [{event: 'pull_request'}, {head_branch: 'topic'}, {workflow_id: 99},
    {head_repository: {full_name: 'attacker/repo'}}, {path: '.github/workflows/fake.yml'},
    {head_sha: 'payload'}, {id: '10'}, {conclusion: 'cancelled'}])
    assert.deepEqual(await scenario(change), []);
});
test('human-authored or PR lookalike is not overwritten', async () => {
  for (const issue of [{...owned, user: {login: 'human'}}, {...owned, pull_request: {url: 'x'}}])
    assert.equal((await scenario({}, [issue]))[0][0], 'create');
});
test('write-enabled workflow never checks out or executes source', () => {
  assert.deepEqual(workflow.permissions, {contents: 'read', issues: 'write', actions: 'read'});
  assert.equal(workflow.concurrency['cancel-in-progress'], false);
  for (const step of workflow.jobs.repair.steps) {
    assert.equal(step.run, undefined); assert.doesNotMatch(step.uses, /checkout/);
  }
});

test('late failure cannot reopen repair after a newer same-SHA rerun', async () => {
  assert.deepEqual(await scenario({}, [], sha, {run_attempt: 2, conclusion: 'success'}), []);
});
test('late green event cannot close a newer same-SHA failure', async () => {
  assert.deepEqual(await scenario({conclusion: 'success'}, [owned], sha,
    {run_attempt: 2, conclusion: 'failure'}), []);
});
test('live run identity and completed attempt must match', async () => {
  for (const live of [{status: 'in_progress'}, {head_sha: 'b'.repeat(40)},
    {workflow_id: 7}, {path: 'wrong'}, {event: 'workflow_dispatch'},
    {head_branch: 'topic'}, {head_repository: {full_name: 'other/repo'}}])
    assert.deepEqual(await scenario({}, [], sha, live), []);
});
test('unavailable native run evidence fails without an issue write', async () => {
  await assert.rejects(scenario({}, [], sha, {error: true}), /unavailable/);
});
test('outcome is observable even when no repair is needed', async () => {
  const observed = [];
  assert.deepEqual(await scenario({conclusion: 'success'}, [], sha, {}, observed), []);
  assert.ok(observed.some(message => message.includes('healthy-no-repair')));
});
