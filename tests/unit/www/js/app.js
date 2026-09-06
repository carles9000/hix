// HIX Test Master — client

const outputs     = {};
const results     = {};
let   running       = false;
let   doneReceived  = false;
let   currentAbort  = null;   // AbortController for active fetch stream
let   watchdogTimer = null;
let   done         = 0;
let   total        = 0;
let   logInterval  = null;
let   detailOn     = true;
let   srvLogCursor = 0;

const WATCHDOG_MS = 30000;

const globalStats = { assertions: 0, passed: 0, failed: 0, ms: 0 };
const groupStats  = {};   // groupName → { total, passed, failed, ms }
const testStart   = {};   // testName  → performance.now() when it started

function groupStat(name) {
  if (!groupStats[name]) groupStats[name] = { total: 0, passed: 0, failed: 0, ms: 0 };
  return groupStats[name];
}

// Elapsed time measured on the client — fallback when the server sends no "ms".
function elapsedSince(testName) {
  const t0 = testStart[testName];
  return t0 == null ? null : Math.round(performance.now() - t0);
}

// 842 → "842 ms" · 3120 → "3.12 s"
function fmtMs(ms) {
  return ms < 1000 ? ms + ' ms' : (ms / 1000).toFixed(2) + ' s';
}

// ── Init ──────────────────────────────────────────────────────────
document.addEventListener('DOMContentLoaded', () => {
  initTheme();
  loadTests();
  loadInfo();
  startLogPolling();
  startActivityStream();

  const consoleCollapse = document.getElementById('collapse-console');
  const consoleChev     = document.getElementById('chev-console');
  if (consoleCollapse && consoleChev) {
    consoleCollapse.addEventListener('hide.bs.collapse', () => {
      consoleChev.className = 'bi bi-chevron-down';
    });
    consoleCollapse.addEventListener('show.bs.collapse', () => {
      consoleChev.className = 'bi bi-chevron-up';
    });
  }
});

function loadTests() {
  fetch('/api/tests')
    .then(r => r.json())
    .then(renderGroups)
    .catch(e => showError('Could not reach /api/tests: ' + e));
}

function loadInfo() {
  fetch('/api/info', { cache: 'no-store' })
    .then(r => r.json())
    .then(info => {
      const badge = document.getElementById('nav-os');
      if (!badge) return;
      badge.textContent = info.compiler || 'n/a';
      badge.title       = (info.compiler || '') + '  |  ' + (info.os || '');
    })
    .catch(() => {
      const badge = document.getElementById('nav-os');
      if (badge) { badge.textContent = 'n/a'; badge.title = 'no /api/info'; }
    });
}

// ── Theme (dark / light) ──────────────────────────────────────────
const THEME_KEY = 'hix-theme';

function currentTheme() {
  return document.documentElement.getAttribute('data-bs-theme') === 'dark' ? 'dark' : 'light';
}

function applyTheme(theme) {
  document.documentElement.setAttribute('data-bs-theme', theme);
  const icon = document.getElementById('icon-theme');
  const btn  = document.getElementById('btn-theme');
  if (icon) icon.className = theme === 'dark' ? 'bi bi-sun-fill' : 'bi bi-moon-stars-fill';
  if (btn)  btn.title = theme === 'dark' ? 'Switch to light mode' : 'Switch to dark mode';
}

function initTheme() {
  applyTheme(localStorage.getItem(THEME_KEY) || 'dark');
}

function toggleTheme() {
  const next = currentTheme() === 'dark' ? 'light' : 'dark';
  localStorage.setItem(THEME_KEY, next);
  applyTheme(next);
}

// ── Render groups ─────────────────────────────────────────────────
function renderGroups(groups) {
  const container = document.getElementById('groups');
  container.innerHTML = '';
  groups.forEach(g => {
    const col = document.createElement('div');
    col.className = 'col-12 col-md-6 col-xl-4';
    col.innerHTML = groupCard(g);
    container.appendChild(col);

    const gid        = safeId(g.name);
    const collapseEl = col.querySelector(`#collapse-${gid}`);
    const chevEl     = col.querySelector(`#chev-${gid}`);
    if (collapseEl && chevEl) {
      collapseEl.addEventListener('hide.bs.collapse', () => chevEl.className = 'bi bi-chevron-down');
      collapseEl.addEventListener('show.bs.collapse', () => chevEl.className = 'bi bi-chevron-up');
    }
  });
}

function groupCard(g) {
  const gid  = safeId(g.name);
  const rows = g.tests.map(t => testRow(t)).join('');
  return `
    <div class="card shadow-sm">
      <div class="card-header bg-dark text-white d-flex justify-content-between align-items-center py-2">
        <span class="fw-semibold"><i class="bi bi-folder2 me-1"></i>${g.name}</span>
        <div class="d-flex align-items-center gap-2">
          <span id="grp-badge-${gid}"  class="badge bg-secondary small">—</span>
          <span id="grp-assert-${gid}" class="badge bg-info small text-dark" style="display:none"></span>
          <span id="grp-time-${gid}"   class="badge bg-secondary small font-monospace"
                title="Group elapsed time" style="display:none"></span>
          <button class="btn btn-sm btn-outline-light py-0 px-2 btn-group-run"
                  onclick="runGroup('${g.name}')" title="Run ${g.name}">
            <i class="bi bi-play-fill"></i>
          </button>
          <button class="btn btn-sm btn-outline-light py-0 px-2"
                  data-bs-toggle="collapse" data-bs-target="#collapse-${gid}"
                  title="Collapse/Expand">
            <i class="bi bi-chevron-down" id="chev-${gid}"></i>
          </button>
        </div>
      </div>
      <div class="collapse" id="collapse-${gid}">
        <div class="card-body p-0">
          <table class="table table-sm table-hover mb-0">
            <thead>
              <tr>
                <th class="ps-3">Test</th>
                <th class="text-center" style="width:48px">Tot</th>
                <th class="text-center" style="width:48px">OK</th>
                <th class="text-center" style="width:48px">KO</th>
                <th class="text-end" style="width:72px">Lap.</th>
                <th style="width:76px">Status</th>
              </tr>
            </thead>
            <tbody id="tbody-${gid}">${rows}</tbody>
          </table>
        </div>
      </div>
    </div>`;
}

function testRow(t) {
  const tid   = safeId(t.name);
  const badge = t.exists
    ? `<span class="badge bg-secondary badge-status" id="st-${tid}">pending</span>`
    : `<span class="badge bg-warning  badge-status text-dark" id="st-${tid}">no exe</span>`;
  return `
    <tr id="row-${tid}">
      <td class="ps-3">
        <button class="test-name-btn" onclick="showAssertions('${t.name}')">${t.name}</button>
      </td>
      <td class="text-center text-muted"    id="tot-${tid}">—</td>
      <td class="text-center text-success fw-semibold" id="ok-${tid}">—</td>
      <td class="text-center text-danger  fw-semibold" id="ko-${tid}">—</td>
      <td class="text-end text-muted font-monospace" id="lap-${tid}">—</td>
      <td>${badge}</td>
    </tr>`;
}

// ── Run ───────────────────────────────────────────────────────────
function handleRunBtn() {
  if (running) abortRun();
  else runGroup('all');
}

async function runGroup(group) {
  if (running) return;
  resetAll();          // clears the activity panel, so log after it
  clearRunError();
  appendActivity(group === 'all' ? 'Init Run All...' : 'Init ' + group + '...', 'start');
  setRunning(true);
  doneReceived = false;
  resetWatchdog();

  currentAbort = new AbortController();

  try {
    const resp = await fetch('/api/run?group=' + encodeURIComponent(group), {
      signal: currentAbort.signal
    });
    if (!resp.ok) {
      throw new Error('HTTP ' + resp.status + ' — server busy, try again.');
    }

    const reader  = resp.body.getReader();
    const decoder = new TextDecoder();
    let   buf     = '';

    while (true) {
      const { done: eof, value } = await reader.read();
      if (eof) break;
      buf += decoder.decode(value, { stream: true });

      let sep;
      while ((sep = buf.indexOf('\n\n')) !== -1) {
        const msg = buf.slice(0, sep);
        buf = buf.slice(sep + 2);
        if (!msg.startsWith('data: ')) continue;
        resetWatchdog();
        let evt;
        try { evt = JSON.parse(msg.slice(6)); } catch(ex) {
          logConsole('[JS ERROR] ' + ex + ' | raw: ' + msg);
          continue;
        }
        handleEvent(evt);
        if (evt.type === 'done') {
          doneReceived = true;
          clearTimeout(watchdogTimer); watchdogTimer = null;
          setRunning(false);
          return;
        }
      }
    }

    // Stream closed by server without 'done' — treat as complete if all results arrived
    if (running) {
      if (total > 0 && done >= total) {
        setRunning(false);
      } else {
        logConsole('[SSE] Stream closed without done event');
        showRunError('Connection lost — press Run again.');
        abortRun();
      }
    }
  } catch(ex) {
    if (ex.name === 'AbortError') return;
    logConsole('[SSE ERROR] ' + ex.message);
    showRunError(ex.message);
    abortRun();
  } finally {
    currentAbort = null;
  }
}

function resetWatchdog() {
  clearTimeout(watchdogTimer);
  watchdogTimer = setTimeout(() => {
    if (running) {
      showRunError('No SSE activity for ' + (WATCHDOG_MS / 1000) + 's — test hung.');
      abortRun();
    }
  }, WATCHDOG_MS);
}

function abortRun() {
  if (currentAbort) { currentAbort.abort(); currentAbort = null; }
  clearTimeout(watchdogTimer); watchdogTimer = null;
  fetch('/api/reset').catch(() => {});
  setRunning(false);
  logConsole('[ABORT] Run aborted');
}

function showRunError(msg) {
  const el = document.getElementById('run-error');
  if (!el) return;
  el.textContent = '⚠ ' + msg;
  el.style.display = '';
}

function clearRunError() {
  const el = document.getElementById('run-error');
  if (el) el.style.display = 'none';
}

function handleEvent(evt) {
  switch (evt.type) {

    case 'init':
      total = evt.count;
      done  = 0;
      setProgress(0);
      logConsole('[RUN] Starting ' + evt.count + ' tests from ' + (evt.testsDir || '?'));
      break;

    case 'running': {
      const tid = safeId(evt.test);
      const gid = safeId(evt.group);
      const colEl = document.getElementById(`collapse-${gid}`);
      if (colEl && !colEl.classList.contains('show'))
        bootstrap.Collapse.getOrCreateInstance(colEl).show();
      setStatus(tid, 'running');
      setText(`tot-${tid}`, '…');
      setText(`ok-${tid}`,  '…');
      setText(`ko-${tid}`,  '…');
      setText(`lap-${tid}`, '…');
      testStart[evt.test] = performance.now();
      logConsole('[RUN] > ' + evt.test);
      if (detailOn) _addDetailLine(
        document.getElementById('detail-panel'),
        '▶ ' + evt.test, 'dl-test'
      );
      break;
    }

    case 'line':
      if (detailOn) _colorDetailLine(evt.line || '');
      break;

    case 'result': {
      const tid = safeId(evt.test);
      results[evt.test] = evt;
      outputs[evt.test] = evt.output || '';

      // Server-side elapsed time; fall back to the client stopwatch if absent.
      const lap = evt.ms != null ? evt.ms : elapsedSince(evt.test);
      delete testStart[evt.test];

      setText(`tot-${tid}`, evt.total  != null ? evt.total  : '—');
      setText(`ok-${tid}`,  evt.passed != null ? evt.passed : '—');
      setText(`ko-${tid}`,  evt.failed != null ? evt.failed : '—');
      setText(`lap-${tid}`, lap != null ? fmtMs(lap) : '—');
      setStatus(tid, evt.status);

      const gs = groupStat(evt.group);
      if (lap != null) {
        globalStats.ms += lap;
        gs.ms          += lap;
      }
      if (evt.status === 'ok' || evt.status === 'fail') {
        globalStats.assertions += evt.total;
        globalStats.passed     += evt.passed;
        globalStats.failed     += evt.failed;
        gs.total  += evt.total;
        gs.passed += evt.passed;
        gs.failed += evt.failed;
      }

      const icon = evt.status === 'ok' ? '✓' : (evt.status === 'noexe' ? '⚠' : '✗');
      logConsole(`[RES] ${icon} ${evt.test} — ${evt.total} total / ${evt.passed} ok / ${evt.failed} fail  (exit=${evt.exit})`);

      if (detailOn) {
        const icon = evt.status === 'ok' ? '✓' : (evt.status === 'noexe' ? '⚠' : '✗');
        _addDetailLine(
          document.getElementById('detail-panel'),
          `${icon} ${evt.total} total / ${evt.passed} ok / ${evt.failed} fail` +
          (lap != null ? `  —  ${fmtMs(lap)}` : ''), 'dl-summary'
        );
      }

      done++;
      setProgress(total > 0 ? Math.round((done / total) * 100) : 0);
      updateGroupBadge(evt.group);
      updateNavBadges();
      break;
    }

    case 'done':
      setProgress(100, '100% done');
      logConsole('[DONE] Run finished');
      break;

    case 'ping':
      logConsole('[SSE] ping ' + evt.i);
      break;
  }
}

// ── Activity polling (independent from the run stream) ────────────
let activitySeq = 0;

let _actIntervalId = null;
let _actStopped = false;
let _actBuf = [];
let _actMaxPolls = 400;
let _pollTick = 0;
let _actFirstPoll = true;

function _actLog(line) {
  const stamp = new Date().toISOString().substr(11, 12);
  const full = '[JS] ' + stamp + ' ' + line;
  console.log(full);
  _actBuf.push(full);
}

async function _actFlush(final) {
  if (_actBuf.length === 0 && !final) return;
  const dump = _actBuf.join('\n') + '\n';
  _actBuf = [];
  try {
    await fetch('/api/tracedump', { method: 'POST', body: dump, cache: 'no-store' });
  } catch (e) { /* silent */ }
}

function _actStop(reason) {
  if (_actStopped) return;
  _actStopped = true;
  if (_actIntervalId) { clearInterval(_actIntervalId); _actIntervalId = null; }
  _actBuf.push('[JS] --- STOPPED reason=' + reason + ' ---');
  _actFlush(true);
}

function startActivityStream() {
  pollActivity();
  _actIntervalId = setInterval(pollActivity, 400);
}

async function pollActivity() {
  if (_actStopped) return;
  const tick = ++_pollTick;
  const t0 = performance.now();
  try {
    const url = '/api/activity?from=' + activitySeq;
    const resp = await fetch(url, { cache: 'no-store' });
    if (!resp.ok) {
      _actLog('[ACT#' + tick + '] HTTP ' + resp.status + ' url=' + url);
      return;
    }
    const data = await resp.json();
    const dt = Math.round(performance.now() - t0);
    _actLog('[ACT#' + tick + '] from=' + activitySeq + ' last=' + data.last +
            ' notes=' + (data.notes ? data.notes.length : 0) + ' dt=' + dt + 'ms');

    // First poll: just capture the cursor, don't repaint leftover history.
    if (_actFirstPoll) {
      _actFirstPoll = false;
      activitySeq = data.last || 0;
      _actLog('[ACT#' + tick + '] first poll — cursor set to ' + activitySeq);
      return;
    }

    if (data.last != null && data.last < activitySeq) {
      _actLog('[ACT#' + tick + '] RESET cursor (last<from)');
      activitySeq = 0;
    }
    if (Array.isArray(data.notes)) {
      for (const n of data.notes) {
        _actLog('[ACT#' + tick + '] note seq=' + n.seq + ' kind=' + n.kind + ' label=' + n.label);
        if (n.seq > activitySeq) activitySeq = n.seq;
        setActivityBadge(n.label || '', n.kind || 'info');
        appendActivity(n.label || '', n.kind || 'info');
      }
    }
  } catch (e) {
    _actLog('[ACT#' + tick + '] fetch FAILED: ' + (e && e.message ? e.message : e));
  }

  // Flush every 5 polls (~2 s) to keep the trace file up to date.
  if (tick % 5 === 0) _actFlush(false);

  if (tick >= _actMaxPolls) _actStop('cap ' + _actMaxPolls);
}

// ── Activity badge ────────────────────────────────────────────────
const ACTIVITY_KIND_CLASS = {
  start: 'bg-warning text-dark',
  on:    'bg-success',
  stop:  'bg-warning text-dark',
  off:   'bg-secondary',
  wait:  'bg-info text-dark',
  test:  'bg-primary',
  warn:  'bg-danger',
  info:  'bg-primary'
};

let activityTimer = null;

function setActivityBadge(label, kind) {
  const el = document.getElementById('nav-activity');
  if (!el) return;

  if (activityTimer) { clearTimeout(activityTimer); activityTimer = null; }

  if (!label) {
    el.className = 'badge bg-secondary mt-1';
    el.textContent = '—';
    return;
  }

  const cls = ACTIVITY_KIND_CLASS[kind] || ACTIVITY_KIND_CLASS.info;
  el.className = 'badge mt-1 ' + cls;
  el.textContent = label;

  // "on"/"off" states stay until the next change. So does "warn":
  // a warning that clears itself after 4 s is a warning nobody reads.
  // Transient states auto-clear after 4 s.
  if (kind !== 'on' && kind !== 'off' && kind !== 'warn') {
    activityTimer = setTimeout(() => setActivityBadge('', 'info'), 4000);
  }
}

// ── DOM helpers ───────────────────────────────────────────────────
function setStatus(tid, status) {
  const el = document.getElementById(`st-${tid}`);
  if (!el) { logConsole('[WARN] element not found: st-' + tid); return; }
  const map = {
    pending: ['bg-secondary', 'pending'],
    running: ['bg-primary',   '<span class="spinner-border spinner-xs"></span>'],
    ok:      ['bg-success',   '<i class="bi bi-check-lg"></i> ok'],
    fail:    ['bg-danger',    '<i class="bi bi-x-lg"></i> fail'],
    noexe:   ['bg-warning text-dark', '⚠ no exe'],
  };
  const [cls, label] = map[status] || ['bg-secondary', status];
  el.className = `badge badge-status ${cls}`;
  el.innerHTML = label;
}

function setText(id, val) {
  const el = document.getElementById(id);
  if (el) el.textContent = val;
}

function updateGroupBadge(groupName) {
  const gid   = safeId(groupName);
  const tbody = document.getElementById(`tbody-${gid}`);
  if (!tbody) return;
  let ok = 0, fail = 0;
  tbody.querySelectorAll('[id^="st-"]').forEach(el => {
    if (el.classList.contains('bg-success')) ok++;
    else if (el.classList.contains('bg-danger')) fail++;
  });
  const badge = document.getElementById(`grp-badge-${gid}`);
  if (!badge) return;
  if (fail > 0) {
    badge.className   = 'badge bg-danger small';
    badge.textContent = `${ok}✓ ${fail}✗`;
  } else if (ok > 0) {
    badge.className   = 'badge bg-success small';
    badge.textContent = `${ok}✓`;
  }

  const gs = groupStats[groupName];
  const assertBadge = document.getElementById(`grp-assert-${gid}`);
  if (assertBadge && gs && gs.total > 0) {
    assertBadge.style.display = '';
    assertBadge.textContent   = gs.failed > 0
      ? `${gs.passed}/${gs.total}`
      : `${gs.total}`;
    assertBadge.className = gs.failed > 0
      ? 'badge bg-warning small text-dark'
      : 'badge bg-info small text-dark';
  }

  const timeBadge = document.getElementById(`grp-time-${gid}`);
  if (timeBadge && gs && gs.ms > 0) {
    timeBadge.style.display = '';
    timeBadge.textContent   = fmtMs(gs.ms);
  }
}

function updateNavBadges() {
  setText('nav-total', globalStats.assertions);
  setText('nav-pass',  globalStats.passed);
  setText('nav-fail',  globalStats.failed);
  setText('nav-info',  `${done}/${total}`);
  setText('nav-lap',   globalStats.ms > 0 ? fmtMs(globalStats.ms) : '—');
}

// The label defaults to "NN% process..."; pass an explicit one for the final state.
function setProgress(pct, label) {
  document.getElementById('progress-bar').style.width = pct + '%';
  setText('progress-label', label != null ? label : pct + '% process...');
}

function setRunning(state) {
  running = state;
  const btn = document.getElementById('btn-run-all');
  btn.disabled = false;
  if (state) {
    btn.className = 'btn btn-danger btn-sm';
    btn.innerHTML = '<span class="spinner-border spinner-border-sm"></span> Running… <i class="bi bi-stop-fill ms-1"></i>';
  } else {
    btn.className = 'btn btn-primary btn-sm';
    btn.innerHTML = '<i class="bi bi-play-fill"></i> Run All';
    clearTimeout(watchdogTimer);
    watchdogTimer = null;
  }
  document.querySelectorAll('.btn-group-run').forEach(b => { b.disabled = state; });
}

function resetAll() {
  clearRunError();
  globalStats.assertions = 0;
  globalStats.passed     = 0;
  globalStats.failed     = 0;
  globalStats.ms         = 0;
  done = 0; total = 0;
  clearDetail();
  clearActivity();
  updateNavBadges();
  setActivityBadge('', 'info');
  document.querySelectorAll('[id^="st-"]').forEach(el => {
    if (!el.classList.contains('bg-warning')) {
      el.className  = 'badge bg-secondary badge-status';
      el.textContent = 'pending';
    }
  });
  ['tot-', 'ok-', 'ko-', 'lap-'].forEach(pfx =>
    document.querySelectorAll(`[id^="${pfx}"]`).forEach(el => el.textContent = '—')
  );
  document.querySelectorAll('[id^="grp-badge-"]').forEach(el => {
    el.className  = 'badge bg-secondary small';
    el.textContent = '—';
  });
  document.querySelectorAll('[id^="grp-assert-"], [id^="grp-time-"]').forEach(el => {
    el.style.display = 'none';
    el.textContent   = '';
  });
  Object.keys(groupStats).forEach(k => delete groupStats[k]);
  Object.keys(testStart).forEach(k => delete testStart[k]);
}

// ── Assertions detail modal ───────────────────────────────────────
function parseAssertions(output) {
  const lines = (output || '').split('\n');
  const items = [];
  let n = 0, cur = null;
  for (const raw of lines) {
    const line = raw.replace(/\r$/, '');
    const mHead = line.match(/^\[(PASS|FAIL)\]\s(.*?)(?:\s+\((\d+)ms\))?\s*$/);
    if (mHead) {
      n++;
      cur = {
        n,
        desc: mHead[2].trim(),
        expected: '',
        got: '',
        pass: mHead[1] === 'PASS',
        ms: mHead[3] ? parseInt(mHead[3], 10) : null,
      };
      items.push(cur);
    } else if (cur) {
      const m = line.match(/Expected:\s*(.*?)\s{2,}Got:\s*(.*)/);
      if (m) { cur.expected = m[1].trim(); cur.got = m[2].trim(); }
    }
  }
  return items;
}

function showAssertions(name) {
  const output = outputs[name];
  if (!output) { showOutput(name); return; }
  const items = parseAssertions(output);
  if (!items.length) { showOutput(name); return; }

  document.getElementById('modal-assert-title').textContent = name;
  const result = results[name] || {};
  const tbody = document.getElementById('modal-assert-body');
  tbody.innerHTML = items.map(it => {
    const bg    = it.pass ? '' : 'table-danger';
    const badge = it.pass
      ? '<span class="badge bg-success badge-status">PASS</span>'
      : '<span class="badge bg-danger  badge-status">FAIL</span>';
    return `<tr class="${bg}">
      <td class="text-center text-muted ps-2">${it.n}</td>
      <td>${escHtml(it.desc)}</td>
      <td class="font-monospace small">${escHtml(it.expected)}</td>
      <td class="font-monospace small">${it.pass ? '' : escHtml(it.got)}</td>
      <td class="text-end font-monospace small text-muted">${it.ms != null ? it.ms : ''}</td>
      <td class="text-center">${badge}</td>
    </tr>`;
  }).join('');
  bootstrap.Modal.getOrCreateInstance(document.getElementById('modal-assertions')).show();
}

function escHtml(s) {
  return (s || '').replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
}

// ── Output modal (raw) ────────────────────────────────────────────
function showOutput(name) {
  document.getElementById('modal-title').textContent = name;
  document.getElementById('modal-body').textContent  =
    outputs[name] || '(no output — run the test first)';
  bootstrap.Modal.getOrCreateInstance(document.getElementById('modal-output')).show();
}

// ── Console (server log) ──────────────────────────────────────────
function logConsole(msg) {
  const pre = document.getElementById('console');
  pre.textContent += msg + '\n';
  pre.scrollTop = pre.scrollHeight;
}

function refreshLog() {
  fetch('/api/log?from=' + srvLogCursor)
    .then(r => r.json())
    .then(data => {
      setText('log-file', data.file || '');
      const lines = (data.lines || []).filter(l => l.trim());
      if (lines.length > 0) {
        const pre = document.getElementById('console');
        lines.forEach(l => { pre.textContent += '[SRV] ' + l + '\n'; });
        pre.scrollTop = pre.scrollHeight;
      }
      srvLogCursor = data.total || srvLogCursor;
    })
    .catch(e => logConsole('[LOG ERROR] ' + e));
}

function clearLog() {
  document.getElementById('console').textContent = '';
}

function startLogPolling() {
  refreshLog();
  logInterval = setInterval(refreshLog, 3000);
}

// ── SSE diagnostic ────────────────────────────────────────────────
function testSSE() {
  logConsole('[SSE TEST] Connecting to /api/test-sse...');
  const es = new EventSource('/api/test-sse');
  es.onmessage = e => {
    const evt = JSON.parse(e.data);
    logConsole('[SSE TEST] received: ' + JSON.stringify(evt));
    if (evt.type === 'done') { es.close(); logConsole('[SSE TEST] OK — SSE works!'); }
  };
  es.onerror = () => {
    logConsole('[SSE TEST] ERROR — SSE not working');
    es.close();
  };
}

// ── Detail panel ─────────────────────────────────────────────────
function toggleDetail(on) {
  detailOn = on;
  const detCol = document.getElementById('detail-col');
  if (detCol) detCol.style.display = on ? '' : 'none';
}

function clearDetail() {
  document.getElementById('detail-panel').innerHTML = '';
}

// ── Activity panel ──────────────────────────────────────────────────
function clearActivity() {
  document.getElementById('activity-panel').innerHTML = '';
}

function appendActivity(label, kind) {
  const panel = document.getElementById('activity-panel');
  if (!panel || !label) return;
  const now = new Date();
  const hh = String(now.getHours()).padStart(2, '0');
  const mm = String(now.getMinutes()).padStart(2, '0');
  const ss = String(now.getSeconds()).padStart(2, '0');
  const line = document.createElement('span');
  line.className = 'al al-' + (kind || 'info');
  const t = document.createElement('span');
  t.className = 'al-time';
  t.textContent = hh + ':' + mm + ':' + ss + ' ';
  line.appendChild(t);
  line.appendChild(document.createTextNode(label));
  panel.appendChild(line);
  panel.scrollTop = panel.scrollHeight;

  while (panel.childNodes.length > 500) {
    panel.removeChild(panel.firstChild);
  }
}

function renderDetail(testName, output, status) {
  const panel = document.getElementById('detail-panel');
  const icon  = status === 'ok' ? '✓' : (status === 'noexe' ? '⚠' : '✗');

  _addDetailLine(panel, `${icon} ${testName}`, 'dl-test');

  (output || '').split('\n').forEach(raw => {
    const line = raw.replace(/\r$/, '');
    if (!line.trim()) return;

    if (line.startsWith('[PASS]'))
      _addDetailLine(panel, line, 'dl-pass');
    else if (line.startsWith('[FAIL]'))
      _addDetailLine(panel, line, 'dl-fail');
    else if (/^---/.test(line))
      _addDetailLine(panel, line, 'dl-header');
    else if (/Expected:|Got:/.test(line))
      _addDetailLine(panel, line, 'dl-detail');
    else if (/total.*passed.*failed/.test(line))
      _addDetailLine(panel, line, 'dl-summary');
    else
      _addDetailLine(panel, line, '');
  });

  panel.scrollTop = panel.scrollHeight;
}

function _colorDetailLine(line) {
  const panel = document.getElementById('detail-panel');
  let cls = '';
  if      (line.startsWith('[PASS]'))          cls = 'dl-pass';
  else if (line.startsWith('[FAIL]'))          cls = 'dl-fail';
  else if (/^---/.test(line))                  cls = 'dl-header';
  else if (/Expected:|Got:/.test(line))        cls = 'dl-detail';
  else if (/total.*passed.*failed/.test(line)) cls = 'dl-summary';
  if (line.trim()) _addDetailLine(panel, line, cls);
}

function _addDetailLine(panel, text, cls) {
  const span = document.createElement('span');
  span.className   = 'dl ' + cls;
  span.textContent = text;
  panel.appendChild(span);
  panel.scrollTop  = panel.scrollHeight;
}

// ── Toggle all group cards ────────────────────────────────────────
let groupsExpanded = false;

function toggleAllGroups() {
  groupsExpanded = !groupsExpanded;
  document.querySelectorAll('#groups .collapse').forEach(el => {
    bootstrap.Collapse.getOrCreateInstance(el)[groupsExpanded ? 'show' : 'hide']();
  });
  document.getElementById('icon-toggle-groups').className =
    groupsExpanded ? 'bi bi-chevron-bar-contract' : 'bi bi-chevron-bar-expand';
}

// ── Utils ─────────────────────────────────────────────────────────
function safeId(s) { return s.replace(/[^a-zA-Z0-9]/g, '_'); }
function showError(msg) {
  document.getElementById('groups').innerHTML =
    `<div class="col"><div class="alert alert-danger">${msg}</div></div>`;
}
