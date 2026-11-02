const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');

const template = fs.readFileSync('BetterCallBliss/HTML/EN/plugins/BetterCallBliss/index.html', 'utf8');
const match = template.match(/<script>\s*(\(function \(\) \{\s*var jobId = '[\s\S]*?)<\/script>/);
assert.ok(match, 'live-preview script exists');
const script = match[1].replace(/\[%[\s\S]*?%\]/g, '');

function setup() {
  const elements = {};
  function element(id) {
    return elements[id] ||= {
      textContent: '', innerHTML: '', disabled: false, open: false,
      classList: { values: new Set(), add(x) { this.values.add(x); }, remove(...x) { x.forEach(v => this.values.delete(v)); }, toggle(x, on) { if (on) this.values.add(x); else this.values.delete(x); } },
      setAttribute() {}, removeAttribute() {}, getAttribute() { return null; },
      querySelector() { return id === 'bea-live-status-banner' ? elements.title : null; },
      querySelectorAll() { return []; },
      addEventListener(name, fn) { this[name] = fn; },
    };
  }
  elements.title = { textContent: 'Optimization is running.' };
  for (const id of ['bea-live-status-banner', 'bea-live-status-text', 'bea-live-status-elapsed',
    'bea-starting-status', 'bea-starting-cancel', 'bea-job-overview',
    'bea-running-jobs-list', 'bea-recent-jobs-list', 'bea-start-recovery-controls',
    'bea-check-start-status', 'bea-retry-start']) element(id);
  elements['bea-start-recovery-controls'].classList.add('bea-hidden');
  const timers = new Map(); let nextTimer = 1;
  const window = {
    location: { hostname: 'localhost', href: 'http://localhost/', replace() {} },
    sessionStorage: { getItem() { return null; }, removeItem() {} },
    BetterCallBlissPreviewPreparation: { stopTimer() {} },
    setTimeout(fn, delay) { const id = nextTimer++; timers.set(id, { fn, delay }); return id; },
    clearTimeout(id) { timers.delete(id); }, console: { warn() {} }, confirm() { return false; },
  };
  let responses = []; const requests = [];
  const buttons = ['run_preview', 'run_route_to_track_preview'].map(name => ({
    name, disabled: true, clicks: 0, removeAttribute() {}, getAttribute() { return null; }, click() { this.clicks++; },
  }));
  const document = { getElementById: element, querySelectorAll(selector) { return selector.includes('input[type="submit"]') ? buttons : []; } };
  const fetch = (url, options) => {
    requests.push({ url, body: JSON.parse(options.body) });
    const response = responses.shift();
    return response instanceof Error ? Promise.reject(response)
      : response && typeof response.then === 'function' ? response
      : Promise.resolve({ ok: true, json: () => Promise.resolve(response || { result: { state: 'not_found' } }) });
  };
  vm.runInNewContext(script, { window, document, fetch, URL, Date, JSON, setTimeout: window.setTimeout });
  const flush = () => new Promise(resolve => setImmediate(resolve));
  return { elements, window, timers, buttons, requests, flush, respond(x) { responses.push(x); },
    fire(delay) { const found = [...timers].find(([, t]) => t.delay === delay); assert.ok(found, 'timer exists'); timers.delete(found[0]); found[1].fn(); } };
}

async function run() {
  {
    const t = setup();
    t.window.BetterCallBlissPreviewStatus.follow('preview-123-webabcdef', true);
    await t.flush();
    t.window.BetterCallBlissPreviewStatus.submissionFailed('preview-123-webabcdef', 'NetworkError');
    assert.match(t.elements['bea-live-status-text'].textContent, /checking/i, 'network failure enters reconciliation');
    assert.match(t.elements.title.textContent, /check/i, 'banner no longer claims optimization is running');
    await t.flush();
    t.respond({ result: { job: { id: 'preview-123-webabcdef', state: 'running', status: 'Optimizing' }, running_jobs: [], recent_jobs: [] } });
    t.fire(1500); await t.flush();
    assert.equal(t.elements['bea-live-status-text'].textContent, 'Optimizing', 'registered job resumes live tracking');
    assert.ok(t.requests.every(request => request.body.params[1][3] === 'job_id:preview-123-webabcdef'), 'reconciliation checks the original job ID');
    assert.ok(t.requests.every(request => request.body.params[1][2] === 'status'), 'reconciliation never sends a second start command');
    assert.match(t.elements.title.textContent, /running/i, 'confirmed job restores running banner');
    assert.equal(t.elements['bea-running-jobs-heading'].textContent, 'Running', 'confirmed jobs restore the running section title');
  }
  {
    const t = setup();
    t.window.BetterCallBlissPreviewStatus.follow('preview-123-webabcdef', true);
    await t.flush();
    t.window.BetterCallBlissPreviewStatus.submissionFailed('preview-123-webabcdef', 'NetworkError');
    t.fire(15000);
    assert.match(t.elements['bea-live-status-text'].textContent, /could not confirm/i, 'unresolved startup is reported as uncertain');
    assert.match(t.elements.title.textContent, /unconfirmed/i, 'timed-out state does not claim that checking continues');
    assert.equal(t.elements['bea-start-recovery-controls'].classList.values.has('bea-hidden'), false, 'recovery choices are visible');
    assert.ok(t.elements['bea-check-start-status'].click, 'user can check again');
    assert.ok(t.elements['bea-retry-start'].click, 'user can explicitly retry');
    t.elements['bea-check-start-status'].click();
    assert.match(t.elements['bea-live-status-text'].textContent, /checking/i, 'manual check resumes reconciliation');
  }
  {
    const t = setup();
    t.respond({ result: { job: { id: 'preview-123-webabcdef', state: 'running', status: 'Optimizing' }, running_jobs: [], recent_jobs: [] } });
    t.window.BetterCallBlissPreviewStatus.follow('preview-123-webabcdef', true);
    await t.flush();
    t.window.BetterCallBlissPreviewStatus.submissionFailed('preview-123-webabcdef', 'NetworkError');
    assert.equal(t.elements['bea-live-status-text'].textContent, 'Optimizing', 'late start response failure does not hide an already confirmed job');
  }
  {
    const t = setup(); let resolveRequest;
    t.respond(new Promise(resolve => { resolveRequest = resolve; }));
    t.window.BetterCallBlissPreviewStatus.follow('preview-123-webabcdef', true);
    t.window.BetterCallBlissPreviewStatus.submissionFailed('preview-123-webabcdef', 'NetworkError');
    t.fire(15000);
    resolveRequest({ ok: true, json: () => Promise.resolve({ result: { state: 'not_found' } }) });
    await t.flush();
    assert.equal([...t.timers.values()].some(timer => timer.delay === 1500), false, 'a late status response does not restart exhausted polling');
  }
  {
    const t = setup();
    t.window.BetterCallBlissPreviewStatus.follow('preview-123-webabcdef', true, 'run_route_to_track_preview');
    await t.flush();
    t.window.BetterCallBlissPreviewStatus.submissionFailed('preview-123-webabcdef', 'NetworkError');
    t.fire(15000);
    assert.equal(t.buttons[1].clicks, 0, 'an uncertain start does not automatically submit again');
    t.window.confirm = () => true;
    t.elements['bea-retry-start'].click();
    assert.equal(t.buttons[0].clicks, 0, 'retry does not change the requested action');
    assert.equal(t.buttons[1].clicks, 1, 'explicit retry repeats the original action');
  }
  {
    const t = setup();
    t.window.BetterCallBlissPreviewStatus.follow('preview-123-webabcdef', true);
    await t.flush();
    t.window.BetterCallBlissPreviewStatus.submissionFailed('preview-123-webabcdef', 'NetworkError');
    t.fire(15000);
    t.window.BetterCallBlissPreviewStatus.follow('preview-124-webabcdef', true);
    assert.match(t.elements.title.textContent, /running/i, 'a new preview restores the normal banner');
  }
  console.log('preview start recovery behavior: ok');
}
run().catch(error => { console.error(error); process.exitCode = 1; });
