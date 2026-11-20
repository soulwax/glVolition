/// Self-contained HTML/CSS/JS assets for the glVolition Studio GUI (`volition gui`).
///
/// Embedded directly in Dart so `volition gui` works identically whether invoked
/// via `dart run` or from a compiled native AOT `volition.exe` binary.
const String volitionGuiIndexHtml = r'''<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8"/>
<meta name="viewport" content="width=device-width, initial-scale=1"/>
<title>glVolition Studio</title>
<style>
  :root {
    --bg: #0d1117;
    --panel: #161b22;
    --panel-alt: #1c222b;
    --border: #30363d;
    --text: #e6edf3;
    --muted: #8b949e;
    --accent: #3b82f6;
    --accent-hover: #2563eb;
    --ok: #2ea043;
    --warn: #d29922;
    --err: #f85149;
    --mono: ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas, monospace;
    --sans: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif;
  }
  * { box-sizing: border-box; }
  html, body {
    margin: 0; padding: 0; height: 100%;
    background: var(--bg); color: var(--text);
    font-family: var(--sans); font-size: 14px;
  }
  .app {
    display: grid;
    grid-template-columns: 230px 1fr;
    grid-template-rows: 52px 1fr 240px;
    height: 100vh;
  }
  header {
    grid-column: 1 / -1;
    background: var(--panel);
    border-bottom: 1px solid var(--border);
    display: flex; align-items: center; justify-content: space-between;
    padding: 0 18px;
  }
  .brand { display: flex; align-items: center; gap: 10px; font-weight: 700; font-size: 15px; letter-spacing: 0.2px; }
  .badge {
    font-size: 11px; font-weight: 600; padding: 2px 8px; border-radius: 999px;
    background: rgba(59,130,246,0.16); color: #79c0ff; border: 1px solid rgba(59,130,246,0.35);
  }
  .conn { display: flex; align-items: center; gap: 8px; font-size: 12px; color: var(--muted); }
  .dot { width: 8px; height: 8px; border-radius: 50%; background: var(--warn); }
  .dot.ok { background: var(--ok); }
  .dot.err { background: var(--err); }

  nav {
    grid-row: 2 / 4;
    background: var(--panel);
    border-right: 1px solid var(--border);
    padding: 12px 10px;
    display: flex; flex-direction: column; gap: 4px;
  }
  .nav-btn {
    background: transparent; color: var(--muted); border: 1px solid transparent;
    border-radius: 6px; padding: 9px 12px; text-align: left;
    cursor: pointer; font-size: 13px; font-weight: 500;
    display: flex; align-items: center; justify-content: space-between;
  }
  .nav-btn:hover { background: var(--panel-alt); color: var(--text); }
  .nav-btn.active {
    background: rgba(59,130,246,0.14);
    color: #fff;
    border-color: rgba(59,130,246,0.4);
  }
  .nav-footer {
    margin-top: auto; padding-top: 12px; border-top: 1px solid var(--border);
    font-size: 11px; color: var(--muted); line-height: 1.5;
  }

  main {
    padding: 20px 24px;
    overflow-y: auto;
  }
  .view { display: none; max-width: 960px; }
  .view.active { display: block; }
  h2 { margin: 0 0 6px; font-size: 18px; }
  .subtitle { color: var(--muted); margin: 0 0 18px; font-size: 13px; }

  .card {
    background: var(--panel);
    border: 1px solid var(--border);
    border-radius: 8px;
    padding: 16px;
    margin-bottom: 14px;
  }
  .grid-2 { display: grid; grid-template-columns: repeat(auto-fit, minmax(260px, 1fr)); gap: 12px; }
  label { display: block; font-size: 12px; color: var(--muted); margin-bottom: 5px; font-weight: 500; }
  input, select {
    width: 100%; padding: 8px 10px; border-radius: 6px;
    border: 1px solid var(--border); background: var(--bg); color: var(--text);
    font-size: 13px; margin-bottom: 12px; font-family: var(--sans);
  }
  input[type="checkbox"] { width: auto; margin: 0 8px 0 0; }
  .check-row { display: flex; align-items: center; margin-bottom: 12px; font-size: 13px; cursor: pointer; }
  .row { display: flex; gap: 10px; flex-wrap: wrap; align-items: center; }

  button.primary {
    background: var(--accent); color: #fff; border: none; border-radius: 6px;
    padding: 8px 14px; font-size: 13px; font-weight: 600; cursor: pointer;
  }
  button.primary:hover { background: var(--accent-hover); }
  button.secondary {
    background: var(--panel-alt); color: var(--text); border: 1px solid var(--border);
    border-radius: 6px; padding: 8px 14px; font-size: 13px; font-weight: 500; cursor: pointer;
  }
  button.secondary:hover { border-color: #58a6ff; }
  button.danger {
    background: rgba(248,81,73,0.16); color: #ff7b72; border: 1px solid rgba(248,81,73,0.4);
    border-radius: 6px; padding: 6px 12px; font-size: 12px; font-weight: 600; cursor: pointer;
  }

  .doctor-item {
    display: flex; align-items: flex-start; justify-content: space-between;
    padding: 10px 12px; border-bottom: 1px solid var(--border);
  }
  .doctor-item:last-child { border-bottom: none; }
  .status-pill {
    font-size: 11px; font-weight: 700; padding: 2px 8px; border-radius: 999px; text-transform: uppercase;
  }
  .pill-ok { background: rgba(46,160,67,0.2); color: #56d364; }
  .pill-warning { background: rgba(210,153,34,0.2); color: #e3b341; }
  .pill-error { background: rgba(248,81,73,0.2); color: #ff7b72; }

  .console-pane {
    grid-column: 2 / -1;
    background: #090c10;
    border-top: 1px solid var(--border);
    display: flex; flex-direction: column;
  }
  .console-bar {
    display: flex; align-items: center; justify-content: space-between;
    padding: 6px 14px; background: var(--panel); border-bottom: 1px solid var(--border);
    gap: 10px;
  }
  .console-bar-left { display: flex; align-items: center; gap: 10px; font-size: 12px; font-weight: 600; }
  .console-bar-right { display: flex; align-items: center; gap: 8px; }
  .console-filter {
    width: 180px; margin: 0; padding: 4px 8px; font-size: 12px;
  }
  .console-output {
    flex: 1; overflow-y: auto; padding: 10px 14px;
    font-family: var(--mono); font-size: 12px; line-height: 1.45;
  }
  .log-line { white-space: pre-wrap; word-break: break-word; }
  .log-stderr { color: #ff7b72; }
  .log-info { color: #79c0ff; }
  .task-chip {
    display: inline-flex; align-items: center; gap: 6px;
    background: rgba(59,130,246,0.16); border: 1px solid rgba(59,130,246,0.4);
    color: #79c0ff; border-radius: 999px; padding: 2px 10px; font-size: 11px;
  }
  .serve-link { color: #58a6ff; text-decoration: none; font-family: var(--mono); font-size: 13px; }
  .serve-link:hover { text-decoration: underline; }
  .inspect-table { width: 100%; border-collapse: collapse; font-size: 12px; font-family: var(--mono); margin-top: 10px; }
  .inspect-table th, .inspect-table td { text-align: left; padding: 6px 8px; border-bottom: 1px solid var(--border); }
  .inspect-table th { color: var(--muted); font-family: var(--sans); font-weight: 600; }
</style>
</head>
<body>
<div class="app">
  <header>
    <div class="brand">
      <span>glVolition Studio</span>
      <span class="badge">Engine CLI GUI</span>
    </div>
    <div class="conn">
      <span id="connDot" class="dot"></span>
      <span id="connText">Connecting...</span>
    </div>
  </header>

  <nav>
    <button class="nav-btn active" data-view="doctor">Environment (Doctor)</button>
    <button class="nav-btn" data-view="create">New Project (Create)</button>
    <button class="nav-btn" data-view="build">Build &amp; Release</button>
    <button class="nav-btn" data-view="pack">Asset Packer</button>
    <button class="nav-btn" data-view="serve">Live Dev Server</button>
    <button class="nav-btn" data-view="inspector">Scene &amp; Pak Inspector</button>
    <button class="nav-btn" data-view="tests">Tests &amp; Quality Gates</button>
    <div class="nav-footer">
      <div>Workspace: <span id="wsPath" style="color:var(--text);word-break:break-all;">.</span></div>
    </div>
  </nav>

  <main>
    <!-- DOCTOR -->
    <section id="view-doctor" class="view active">
      <h2>Environment &amp; Toolchain Diagnostics</h2>
      <p class="subtitle">Verifies Dart SDK, WebGL browser, C/C++ compiler, SDL3 native libraries, and pixeldart shader pipeline.</p>
      <div class="row" style="margin-bottom:14px;">
        <button class="primary" onclick="runDoctor()">Re-run Doctor</button>
      </div>
      <div id="doctorList" class="card">Loading diagnostics...</div>
    </section>

    <!-- CREATE -->
    <section id="view-create" class="view">
      <h2>Create New Project</h2>
      <p class="subtitle">Scaffolds a starter glVolition project from official templates (`volition create`).</p>
      <div class="card">
        <div class="grid-2">
          <div>
            <label for="createName">Project Name</label>
            <input id="createName" value="my_volition_game" placeholder="my_game"/>
          </div>
          <div>
            <label for="createTemplate">Template</label>
            <select id="createTemplate">
              <option value="3d">3d (Forward+ Scene &amp; Camera)</option>
              <option value="2d">2d (2D Sprites &amp; Orthographic Camera)</option>
              <option value="multiplayer">multiplayer (NetworkManager &amp; Sync)</option>
            </select>
          </div>
        </div>
        <label for="createOut">Output Directory (optional)</label>
        <input id="createOut" placeholder="Leave empty to create in workspace root"/>
        <button class="primary" onclick="runCreate()">Create Project</button>
      </div>
    </section>

    <!-- BUILD & DIST -->
    <section id="view-build" class="view">
      <h2>Build &amp; Distribution Packaging</h2>
      <p class="subtitle">Compiles targets into `./dist/&lt;version&gt;/&lt;name&gt;/&lt;target&gt;/` (`volition build` / `volition dist`).</p>
      <div class="card">
        <label for="buildEntry">Entrypoint (.dart)</label>
        <div class="row" style="margin-bottom:12px;">
          <select id="buildEntrySelect" style="flex:1;margin:0;" onchange="document.getElementById('buildEntry').value=this.value"></select>
          <button class="secondary" onclick="refreshEntries()">Refresh</button>
        </div>
        <input id="buildEntry" value="example/island_3d/main.dart"/>

        <div class="grid-2">
          <div>
            <label for="buildTarget">Target</label>
            <select id="buildTarget">
              <option value="js">js (Web JavaScript)</option>
              <option value="wasm">wasm (WebAssembly)</option>
              <option value="windows">windows (Native AOT + SDL3)</option>
              <option value="linux">linux (Native AOT)</option>
              <option value="macos">macos (Native AOT)</option>
              <option value="server">server (Zero-GPU Headless)</option>
              <option value="webview">webview (.NET WebView2 Wrapper)</option>
              <option value="all">all (Dist Full Package)</option>
            </select>
          </div>
          <div>
            <label for="buildVersion">Version</label>
            <input id="buildVersion" value="0.1.0"/>
          </div>
        </div>

        <label for="buildName">Package Name (optional)</label>
        <input id="buildName" placeholder="Defaults to entrypoint parent folder"/>

        <label class="check-row">
          <input type="checkbox" id="buildDryRun"/> Dry Run (validate args without compiling)
        </label>

        <div class="row">
          <button class="primary" onclick="runBuild(false)">Run Build</button>
          <button class="secondary" onclick="runBuild(true)">Run Dist</button>
        </div>
      </div>
    </section>

    <!-- PACK -->
    <section id="view-pack" class="view">
      <h2>Asset Cooker &amp; .pak VFS</h2>
      <p class="subtitle">Cook Wavefront OBJ models, bake 3D LUTs, and bundle assets into compressed `.pak` archives (`volition pack`).</p>
      <div class="card">
        <label for="packMode">Operation</label>
        <select id="packMode">
          <option value="pack">pack (Bundle directory into .pak)</option>
          <option value="obj2qmesh">obj2qmesh (Cook OBJ + MTL to QMSH)</option>
          <option value="cube2lut">cube2lut (Bake .cube to 3D LUT)</option>
          <option value="validate">validate (Verify .pak integrity)</option>
        </select>

        <div class="grid-2">
          <div>
            <label for="packIn">Input Path (`--in`)</label>
            <input id="packIn" value="assets"/>
          </div>
          <div>
            <label for="packOut">Output Path (`--out`)</label>
            <input id="packOut" value="build/game.pak"/>
          </div>
        </div>

        <div class="grid-2">
          <div>
            <label for="packXor">XOR Key (optional int)</label>
            <input id="packXor" placeholder="Leave empty for none"/>
          </div>
          <div style="display:flex;align-items:center;padding-top:16px;">
            <label class="check-row" style="margin:0;">
              <input type="checkbox" id="packNoCompress"/> Disable Compression (`--no-compress`)
            </label>
          </div>
        </div>

        <button class="primary" onclick="runPack()">Run Asset Packer</button>
      </div>
    </section>

    <!-- SERVE -->
    <section id="view-serve" class="view">
      <h2>Live Development Server</h2>
      <p class="subtitle">Serves an app with live reload, hot state, and the F12 / Alt+I inspector (`volition serve`).</p>
      <div class="card">
        <div class="grid-2">
          <div>
            <label for="serveEntry">Entrypoint (.dart)</label>
            <input id="serveEntry" value="example/island_3d/main.dart"/>
          </div>
          <div>
            <label for="servePort">Port</label>
            <input id="servePort" type="number" value="8080"/>
          </div>
        </div>
        <div class="row" style="margin-bottom:12px;">
          <button class="primary" onclick="startServe()">Start Server</button>
          <button class="danger" onclick="stopServe()">Stop Server</button>
        </div>
        <div id="serveStatusText" style="color:var(--muted);font-size:13px;">Server stopped.</div>
      </div>
    </section>

    <!-- SCENE & PAK INSPECTOR -->
    <section id="view-inspector" class="view">
      <h2>Scene JSON &amp; `.pak` Archive Inspector</h2>
      <p class="subtitle">Inspect compressed VFS `.pak` tables (CRC32, raw vs stored bytes) or exported `scene.json` entity &amp; component histograms.</p>
      <div class="card">
        <label for="inspectFileSelect">Discovered Artifacts</label>
        <div class="row" style="margin-bottom:12px;">
          <select id="inspectFileSelect" style="flex:1;margin:0;" onchange="if(this.value)document.getElementById('inspectPath').value=this.value"></select>
          <button class="secondary" onclick="refreshInspectables()">Refresh Files</button>
        </div>
        <div class="grid-2">
          <div>
            <label for="inspectPath">Artifact Path (`.pak`, `*scene*.json`, or `*tape*.json`)</label>
            <input id="inspectPath" placeholder="e.g. build/game.pak, assets/scene.json, or smoke_tape.json"/>
          </div>
          <div>
            <label for="inspectXor">XOR Key (optional int for `.pak`)</label>
            <input id="inspectXor" placeholder="Leave empty if unmasked"/>
          </div>
        </div>
        <div class="row">
          <button class="primary" onclick="runInspect()">Inspect Artifact</button>
          <button class="secondary" onclick="runTapeVerify()">Verify Replay Tape</button>
        </div>
      </div>
      <div id="inspectorResult" class="card" style="color:var(--muted);">Select or enter a `.pak`, scene `.json`, or replay `*tape*.json` artifact to inspect or verify.</div>
    </section>

    <!-- TESTS & GATES -->
    <section id="view-tests" class="view">
      <h2>Tests &amp; Verification Gates</h2>
      <p class="subtitle">Run headless VM test suites, pure-Dart boundary checks, static analysis, and performance benchmarks.</p>
      <div class="card">
        <label for="testFilter">Test Path / Filter (optional)</label>
        <input id="testFilter" placeholder="e.g. test/engine/ or test/physics/ (empty = all tests)"/>
        <div class="row">
          <button class="primary" onclick="runTest()">Run dart test</button>
          <button class="secondary" onclick="runGate('boundaries')">Boundary Check</button>
          <button class="secondary" onclick="runGate('analyze')">Dart Analyze</button>
          <button class="secondary" onclick="runGate('bench')">Renderer Benchmark</button>
          <button class="secondary" onclick="runGate('verify')">Verify All (Fast)</button>
          <button class="secondary" onclick="runGate('verify_wasm')">Verify All + Wasm</button>
        </div>
      </div>
    </section>
  </main>

  <section class="console-pane">
    <div class="console-bar">
      <div class="console-bar-left">
        <span>Output Console</span>
        <div id="activeTasks" class="row"></div>
      </div>
      <div class="console-bar-right">
        <input id="logFilter" class="console-filter" placeholder="Filter logs..." oninput="renderFilteredLogs()"/>
        <button class="secondary" style="padding:4px 10px;font-size:12px;" onclick="clearLogs()">Clear</button>
      </div>
    </div>
    <div id="consoleOutput" class="console-output"></div>
  </section>
</div>

<script>
let ws = null;
let reqId = 1;
const logBuffer = [];
const activeTasks = new Map();

document.querySelectorAll('.nav-btn').forEach(btn => {
  btn.addEventListener('click', () => {
    document.querySelectorAll('.nav-btn').forEach(b => b.classList.remove('active'));
    document.querySelectorAll('.view').forEach(v => v.classList.remove('active'));
    btn.classList.add('active');
    document.getElementById('view-' + btn.dataset.view).classList.add('active');
  });
});

function connect() {
  const proto = location.protocol === 'https:' ? 'wss:' : 'ws:';
  ws = new WebSocket(proto + '//' + location.host + '/ws');
  const dot = document.getElementById('connDot');
  const txt = document.getElementById('connText');

  ws.onopen = () => {
    dot.className = 'dot ok';
    txt.textContent = 'Connected';
    sendRpc('init', {});
    runDoctor();
    refreshEntries();
    refreshInspectables();
  };
  ws.onclose = () => {
    dot.className = 'dot err';
    txt.textContent = 'Disconnected (retrying...)';
    setTimeout(connect, 1500);
  };
  ws.onmessage = (ev) => {
    const msg = JSON.parse(ev.data);
    handleServerMessage(msg);
  };
}

function sendRpc(method, params) {
  if (!ws || ws.readyState !== WebSocket.OPEN) return;
  ws.send(JSON.stringify({ id: reqId++, method, params }));
}

function handleServerMessage(msg) {
  if (msg.type === 'init') {
    document.getElementById('wsPath').textContent = msg.workingDirectory || '.';
    updateServeStatus(msg.serveStatus);
  } else if (msg.type === 'doctor.result') {
    renderDoctor(msg.report);
  } else if (msg.type === 'entries.result') {
    renderEntries(msg.entries || []);
  } else if (msg.type === 'inspector.list.result') {
    renderInspectables(msg.files || {});
  } else if (msg.type === 'inspector.inspect.result') {
    renderInspectReport(msg.report);
  } else if (msg.type === 'tape.verify.result') {
    renderTapeVerifyResult(msg.result);
  } else if (msg.type === 'task.update') {
    const t = msg.task;
    if (t.state === 'running') {
      activeTasks.set(t.taskId, t);
    } else {
      activeTasks.delete(t.taskId);
      appendLog('info', `[${t.label}] ${t.state} (exit=${t.exitCode ?? '-'}, ${t.durationMs}ms)`);
    }
    renderActiveTasks();
    if (msg.serveStatus) updateServeStatus(msg.serveStatus);
  } else if (msg.type === 'task.log') {
    appendLog(msg.event.stream, msg.event.line);
  } else if (msg.type === 'serve.status') {
    updateServeStatus(msg.serveStatus);
  } else if (msg.type === 'error') {
    appendLog('stderr', 'ERROR: ' + msg.message);
  }
}

function renderDoctor(report) {
  const el = document.getElementById('doctorList');
  if (!report || !report.checks) return;
  el.innerHTML = report.checks.map(c => `
    <div class="doctor-item">
      <div>
        <div style="font-weight:600;">${escapeHtml(c.name)}</div>
        <div style="color:var(--muted);font-size:12px;margin-top:2px;">${escapeHtml(c.detail)}</div>
        ${c.remediation ? `<div style="color:#e3b341;font-size:12px;margin-top:4px;">Tip: ${escapeHtml(c.remediation)}</div>` : ''}
      </div>
      <span class="status-pill pill-${c.status}">${c.status}</span>
    </div>
  `).join('');
}

function renderEntries(entries) {
  const sel = document.getElementById('buildEntrySelect');
  sel.innerHTML = entries.map(e => `<option value="${escapeHtml(e)}">${escapeHtml(e)}</option>`).join('');
}

function renderActiveTasks() {
  const container = document.getElementById('activeTasks');
  container.innerHTML = '';
  activeTasks.forEach((t, id) => {
    const chip = document.createElement('span');
    chip.className = 'task-chip';
    chip.innerHTML = `<span>${escapeHtml(t.label)}</span>`;
    const btn = document.createElement('button');
    btn.className = 'danger';
    btn.style.padding = '1px 6px';
    btn.textContent = 'Cancel';
    btn.onclick = () => sendRpc('task.cancel', { taskId: id });
    chip.appendChild(btn);
    container.appendChild(chip);
  });
}

function updateServeStatus(st) {
  const el = document.getElementById('serveStatusText');
  if (st && st.running) {
    el.innerHTML = `Serving <strong>${escapeHtml(st.entry)}</strong> at <a class="serve-link" href="${escapeHtml(st.url)}" target="_blank">${escapeHtml(st.url)}</a>`;
  } else {
    el.textContent = 'Server stopped.';
  }
}

function appendLog(stream, line) {
  logBuffer.push({ stream, line });
  if (logBuffer.length > 2000) logBuffer.shift();
  const filter = document.getElementById('logFilter').value.toLowerCase();
  if (!filter || line.toLowerCase().includes(filter)) {
    const out = document.getElementById('consoleOutput');
    const div = document.createElement('div');
    div.className = 'log-line ' + (stream === 'stderr' ? 'log-stderr' : stream === 'info' ? 'log-info' : '');
    div.textContent = line;
    out.appendChild(div);
    out.scrollTop = out.scrollHeight;
  }
}

function renderFilteredLogs() {
  const filter = document.getElementById('logFilter').value.toLowerCase();
  const out = document.getElementById('consoleOutput');
  out.innerHTML = '';
  for (const item of logBuffer) {
    if (!filter || item.line.toLowerCase().includes(filter)) {
      const div = document.createElement('div');
      div.className = 'log-line ' + (item.stream === 'stderr' ? 'log-stderr' : item.stream === 'info' ? 'log-info' : '');
      div.textContent = item.line;
      out.appendChild(div);
    }
  }
  out.scrollTop = out.scrollHeight;
}

function clearLogs() {
  logBuffer.length = 0;
  document.getElementById('consoleOutput').innerHTML = '';
}

function escapeHtml(s) {
  return String(s).replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;').replace(/"/g,'&quot;');
}

function runDoctor() { sendRpc('doctor.run', {}); }
function refreshEntries() { sendRpc('entries.list', {}); }
function refreshInspectables() { sendRpc('inspector.list', {}); }

function renderInspectables(files) {
  const sel = document.getElementById('inspectFileSelect');
  const paks = files.paks || [];
  const scenes = files.scenes || [];
  const tapes = files.tapes || [];
  const opts = ['<option value="">-- Select discovered artifact --</option>'];
  for (const p of paks) opts.push(`<option value="${escapeHtml(p)}">[PAK] ${escapeHtml(p)}</option>`);
  for (const s of scenes) opts.push(`<option value="${escapeHtml(s)}">[SCENE] ${escapeHtml(s)}</option>`);
  for (const t of tapes) opts.push(`<option value="${escapeHtml(t)}">[TAPE] ${escapeHtml(t)}</option>`);
  sel.innerHTML = opts.join('');
}

function runInspect() {
  sendRpc('inspector.inspect', {
    path: document.getElementById('inspectPath').value.trim(),
    xorKey: document.getElementById('inspectXor').value.trim(),
  });
}

function runTapeVerify() {
  sendRpc('tape.verify', {
    path: document.getElementById('inspectPath').value.trim(),
  });
}

function renderTapeVerifyResult(res) {
  const el = document.getElementById('inspectorResult');
  if (!res) return;
  const pill = res.passed
    ? '<span class="status-pill pill-ok">PASS</span>'
    : '<span class="status-pill pill-error">FAIL</span>';
  const mismatches = (res.mismatches || []).map(m => `<li>${escapeHtml(m)}</li>`).join('');
  el.style.color = 'var(--text)';
  el.innerHTML = `
    <div style="display:flex;align-items:center;gap:10px;">
      <strong>Replay Verification:</strong> ${escapeHtml(res.tapeName || res.path)} ${pill}
    </div>
    <div style="color:var(--muted);font-size:12px;margin-top:6px;">
      Path: ${escapeHtml(res.path)} | Frames: ${res.framesExecuted} | Checkpoints: ${res.checkpointCount} | Final Hash: <code>${res.finalSceneHash}</code>
    </div>
    ${mismatches ? `<ul style="color:#ff7b72;font-size:12px;margin-top:8px;">${mismatches}</ul>` : ''}
  `;
}

function renderInspectReport(report) {
  const el = document.getElementById('inspectorResult');
  if (!report) return;
  if (report.kind === 'tape') {
    const keys = (report.distinctKeysUsed || []).join(', ') || '(none)';
    el.style.color = 'var(--text)';
    el.innerHTML = `
      <div><strong>InputTape:</strong> ${escapeHtml(report.tapeName)} (schema v${report.schemaVersion})</div>
      <div style="color:var(--muted);font-size:12px;margin-top:4px;">
        Path: ${escapeHtml(report.path)} | Size: ${report.fileSizeBytes} B | Frames: ${report.frameCount} | Duration: ${Number(report.totalDurationSeconds || 0).toFixed(3)}s | Checkpoints: ${report.checkpointCount} | Initial Scene: ${report.hasInitialScene ? 'yes' : 'no'}
      </div>
      <div style="font-size:12px;margin-top:8px;"><strong>Distinct Keys:</strong> <code>${escapeHtml(keys)}</code></div>
    `;
    return;
  }
  if (report.kind === 'pak') {
    const ratio = report.totalRawBytes > 0
      ? ((report.totalStoredBytes / report.totalRawBytes) * 100).toFixed(1) + '%'
      : '100%';
    const rows = (report.entries || []).map(e => `
      <tr>
        <td>${escapeHtml(e.path)}</td>
        <td>${e.rawSize} B</td>
        <td>${e.storedSize} B</td>
        <td>${e.compressed ? 'RLE' : 'raw'}${e.masked ? '+XOR' : ''}</td>
        <td>0x${Number(e.crc32 >>> 0).toString(16).toUpperCase().padStart(8, '0')}</td>
      </tr>
    `).join('');
    el.style.color = 'var(--text)';
    el.innerHTML = `
      <div><strong>PAK Archive:</strong> ${escapeHtml(report.path)} (${report.fileSizeBytes} B)</div>
      <div style="color:var(--muted);font-size:12px;margin-top:4px;">
        Entries: ${report.entryCount} | Raw: ${report.totalRawBytes} B | Stored: ${report.totalStoredBytes} B (${ratio})
      </div>
      <table class="inspect-table">
        <thead><tr><th>Virtual Path</th><th>Raw</th><th>Stored</th><th>Encoding</th><th>CRC32</th></tr></thead>
        <tbody>${rows}</tbody>
      </table>
    `;
  } else if (report.kind === 'scene') {
    const compEntries = Object.entries(report.componentCounts || {});
    const rows = compEntries.map(([k, v]) => `
      <tr><td>${escapeHtml(k)}</td><td>${v}</td></tr>
    `).join('');
    el.style.color = 'var(--text)';
    el.innerHTML = `
      <div><strong>Scene:</strong> ${escapeHtml(report.sceneName)} (schema v${report.schemaVersion})</div>
      <div style="color:var(--muted);font-size:12px;margin-top:4px;">
        Path: ${escapeHtml(report.path)} | Size: ${report.fileSizeBytes} B | Roots: ${report.rootObjectCount} | Total Objects: ${report.totalObjectCount} | RenderSettings: ${report.hasRenderSettings ? 'yes' : 'no'}
      </div>
      <table class="inspect-table">
        <thead><tr><th>Component Type</th><th>Count</th></tr></thead>
        <tbody>${rows || '<tr><td colspan="2" style="color:var(--muted);">No serialized components</td></tr>'}</tbody>
      </table>
    `;
  }
}

function runCreate() {
  sendRpc('create.run', {
    name: document.getElementById('createName').value.trim(),
    template: document.getElementById('createTemplate').value,
    outDir: document.getElementById('createOut').value.trim(),
  });
}

function runBuild(isDist) {
  sendRpc(isDist ? 'dist.run' : 'build.run', {
    entry: document.getElementById('buildEntry').value.trim(),
    target: document.getElementById('buildTarget').value,
    version: document.getElementById('buildVersion').value.trim(),
    name: document.getElementById('buildName').value.trim(),
    dryRun: document.getElementById('buildDryRun').checked,
  });
}

function runPack() {
  sendRpc('pack.run', {
    mode: document.getElementById('packMode').value,
    inPath: document.getElementById('packIn').value.trim(),
    outPath: document.getElementById('packOut').value.trim(),
    xorKey: document.getElementById('packXor').value.trim(),
    noCompress: document.getElementById('packNoCompress').checked,
  });
}

function startServe() {
  sendRpc('serve.start', {
    entry: document.getElementById('serveEntry').value.trim(),
    port: parseInt(document.getElementById('servePort').value, 10) || 8080,
  });
}

function stopServe() { sendRpc('serve.stop', {}); }

function runTest() {
  sendRpc('test.run', { filter: document.getElementById('testFilter').value.trim() });
}

function runGate(gate) { sendRpc('gate.run', { gate }); }

connect();
</script>
</body>
</html>
''';
