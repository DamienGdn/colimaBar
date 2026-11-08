import { invoke, listen, isDemo } from './api.js';
import { t, setLang } from './i18n.js';
import { icon } from './icons.js';

// ---------------------------------------------------------------------------
// State
// ---------------------------------------------------------------------------

const S = {
  snap: null,
  info: { version: '', platform: 'linux', lang: 'en', autostart: false },
  settings: null,
  tab: 'compose',
  search: '',
  showAll: true,
  sort: { key: 'name', asc: true },
  selected: null,          // container name
  collapsed: new Set(),    // collapsed compose projects
  history: {},             // name -> { cpu: [], mem: [] }
  images: [], volumes: [], networks: [],
  selectedImage: null,
  logs: null,              // { name, following }
  pending: {},             // container name -> action in flight
};
const HISTORY = 30;

const $ = (sel) => document.querySelector(sel);
const esc = (v) => String(v ?? '').replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
const md = (s) => esc(s).replace(/`([^`]+)`/g, '<code>$1</code>');

function bytes(b) {
  if (!b) return '0 MB';
  const g = b / 1024 ** 3;
  return g >= 1 ? `${g.toFixed(1)} GB` : `${Math.round(b / 1024 ** 2)} MB`;
}
const pct = (v) => `${(v ?? 0).toFixed(1)}%`;

// ---------------------------------------------------------------------------
// Toasts & modal
// ---------------------------------------------------------------------------

function toast(msg, kind = 'info') {
  const el = document.createElement('div');
  el.className = `toast ${kind}`;
  el.innerHTML = `${icon(kind === 'error' ? 'alert' : 'check')}<span>${esc(msg)}</span>`;
  $('#toasts').append(el);
  setTimeout(() => el.remove(), kind === 'error' ? 6000 : 3000);
}

async function run(promise, okMsg) {
  try {
    const r = await promise;
    if (okMsg) toast(okMsg);
    return r;
  } catch (e) {
    toast(String(e), 'error');
    throw e;
  }
}

let onModalClose = null;
function openModal({ title, body, tools = '', foot = '', narrow = false, onClose = null }) {
  $('#modal-title').textContent = title;
  $('#modal-tools').innerHTML = tools;
  $('#modal-body').innerHTML = body;
  $('#modal-foot').innerHTML = foot;
  $('#modal .modal').classList.toggle('narrow', narrow);
  $('#modal').hidden = false;
  onModalClose = onClose;
}
function closeModal() {
  $('#modal').hidden = true;
  if (onModalClose) onModalClose();
  onModalClose = null;
}

function confirmDialog(title, text, okLabel, danger = true) {
  return new Promise((resolve) => {
    openModal({
      title, narrow: true,
      body: `<p style="margin:0">${esc(text)}</p>`,
      foot: `<button class="btn" data-c="0">${t('cancel')}</button>
             <button class="btn ${danger ? 'danger solid' : 'primary'}" data-c="1">${esc(okLabel)}</button>`,
      onClose: () => resolve(false),
    });
    $('#modal-foot').onclick = (e) => {
      const b = e.target.closest('[data-c]');
      if (!b) return;
      onModalClose = null;
      $('#modal').hidden = true;
      resolve(b.dataset.c === '1');
    };
  });
}

function promptDialog(title, value) {
  return new Promise((resolve) => {
    openModal({
      title, narrow: true,
      body: `<div class="field" style="grid-template-columns:1fr"><input id="prompt-input" value="${esc(value)}" spellcheck="false"></div>`,
      foot: `<button class="btn" data-c="0">${t('cancel')}</button><button class="btn primary" data-c="1">OK</button>`,
      onClose: () => resolve(null),
    });
    const input = $('#prompt-input');
    input.focus(); input.select();
    const done = (ok) => { onModalClose = null; $('#modal').hidden = true; resolve(ok ? input.value : null); };
    input.onkeydown = (e) => { if (e.key === 'Enter') done(true); };
    $('#modal-foot').onclick = (e) => { const b = e.target.closest('[data-c]'); if (b) done(b.dataset.c === '1'); };
  });
}

// ---------------------------------------------------------------------------
// Header
// ---------------------------------------------------------------------------

function statusInfo(snap) {
  const k = snap?.status?.kind ?? 'transitioning';
  const label = {
    running: t('running'), stopped: t('stopped'), unavailable: t('unavailable'),
    transitioning: snap?.status?.message || t('starting'),
  }[k];
  return { k, label };
}

function renderHeader() {
  const snap = S.snap;
  $('#refresh-btn').title = t('refresh');
  $('#settings-btn').title = t('settings');
  const { k, label } = statusInfo(snap);
  const colima = snap?.backend === 'colima';
  const engine = colima ? 'Colima' : 'Docker';

  $('#status-pill').innerHTML = `<span class="dot ${k}"></span>${engine} · ${esc(label)}`;

  let sub = '';
  if (colima && snap.colima) {
    const c = snap.colima;
    sub = `${c.name} · ${c.cpus} CPU · ${Math.round(c.memory_gb)} GB · ${Math.round(c.disk_gb)} GB disk`;
  } else if (snap) {
    sub = `${t('backendDocker')} · ${snap.docker_command}`;
  }
  $('#engine-sub').textContent = sub;

  const u = snap?.usage;
  if (u && k === 'running') {
    const cpuCap = Math.max(1, u.ncpu) * 100;
    const cpuP = Math.min(100, (u.cpu_percent / cpuCap) * 100);
    const memP = u.mem_total_bytes ? Math.min(100, (u.mem_used_bytes / u.mem_total_bytes) * 100) : 0;
    $('#meters').innerHTML = `
      <div class="meter"><div class="meter-head"><span>CPU</span><b>${pct(u.cpu_percent)}</b></div>
        <div class="meter-bar"><i style="width:${cpuP}%;background:${cpuP > 80 ? '#FFA24C' : '#3EE0C5'}"></i></div></div>
      <div class="meter"><div class="meter-head"><span>RAM</span><b>${bytes(u.mem_used_bytes)} / ${bytes(u.mem_total_bytes)}</b></div>
        <div class="meter-bar"><i style="width:${memP}%;background:${memP > 90 ? '#FFA24C' : '#A5B4FC'}"></i></div></div>`;
  } else {
    $('#meters').innerHTML = '';
  }

  const btn = $('#engine-btn');
  btn.hidden = !colima;
  if (colima) {
    const running = k === 'running';
    btn.disabled = k === 'transitioning';
    btn.innerHTML = `${icon(running ? 'stop' : 'play')}${running ? t('stopEngine') : t('startEngine')}`;
    btn.classList.toggle('primary', !running);
    btn.onclick = () => invoke(running ? 'engine_stop' : 'engine_start');
  }
}

// ---------------------------------------------------------------------------
// Tabs
// ---------------------------------------------------------------------------

const TABS = [
  { id: 'compose', icon: 'compose', label: 'tabCompose' },
  { id: 'containers', icon: 'box', label: 'tabContainers' },
  { id: 'images', icon: 'layers', label: 'tabImages' },
  { id: 'volumes', icon: 'disk', label: 'tabVolumes' },
  { id: 'networks', icon: 'network', label: 'tabNetworks' },
];

function tabCount(id) {
  const c = S.snap?.containers ?? [];
  switch (id) {
    case 'compose': return new Set(c.map((x) => x.compose_project).filter(Boolean)).size;
    case 'containers': return c.length;
    case 'images': return S.images.length || '';
    case 'volumes': return S.volumes.length || '';
    case 'networks': return S.networks.length || '';
  }
  return '';
}

function renderTabs() {
  $('#tabs').innerHTML = TABS.map((tab) => {
    const n = tabCount(tab.id);
    return `<button class="tab ${S.tab === tab.id ? 'active' : ''}" data-tab="${tab.id}" role="tab">
      ${icon(tab.icon)}${t(tab.label)}${n !== '' ? `<span class="count">${n}</span>` : ''}</button>`;
  }).join('');
}

function setTab(id) {
  S.tab = id;
  S.search = '';
  if (id === 'images') loadImages();
  if (id === 'volumes') loadVolumes();
  if (id === 'networks') loadNetworks();
  render();
}

// ---------------------------------------------------------------------------
// Containers / Compose tables
// ---------------------------------------------------------------------------

function stateBadge(c) {
  if (S.pending[c.name]) return `<span class="badge warn"><span class="dot transitioning"></span>${t(`pending_${S.pending[c.name]}`)}</span>`;
  if (c.state === 'running') {
    if (c.health === 'unhealthy') return `<span class="badge err"><span class="dot" style="background:var(--red)"></span>unhealthy</span>`;
    if (c.health === 'starting') return `<span class="badge warn"><span class="dot transitioning"></span>starting</span>`;
    return `<span class="badge ok"><span class="dot running" style="box-shadow:none"></span>${c.health === 'healthy' ? 'healthy' : t('running')}</span>`;
  }
  if (c.state === 'paused') return `<span class="badge warn">paused</span>`;
  return `<span class="badge"><span class="dot"></span>${esc(c.state || t('stopped'))}</span>`;
}

function portsHtml(c) {
  if (!c.ports?.length) return '<span class="faint">—</span>';
  return c.ports.map((p) => `<span class="port" data-port="${p}">${p}${icon('external')}</span>`).join('');
}

function cpuCell(c) {
  const s = S.snap?.stats?.[c.name];
  if (!s || c.state !== 'running') return '<span class="faint">—</span>';
  return s.cpu_percent > 80 ? `<span style="color:var(--orange);font-weight:600">${pct(s.cpu_percent)}</span>` : pct(s.cpu_percent);
}

function ramCell(c) {
  const s = S.snap?.stats?.[c.name];
  if (!s || c.state !== 'running') return '<span class="faint">—</span>';
  return bytes(s.mem_used_bytes);
}

function matches(c) {
  const q = S.search.trim().toLowerCase();
  if (!q) return true;
  return [c.name, c.image, c.compose_project, c.compose_service].some((v) => v && v.toLowerCase().includes(q));
}

function sortedContainers(list) {
  const { key, asc } = S.sort;
  const st = (c) => S.snap?.stats?.[c.name];
  const val = {
    name: (c) => c.name.toLowerCase(), image: (c) => c.image.toLowerCase(), status: (c) => c.state,
    cpu: (c) => st(c)?.cpu_percent ?? -1, ram: (c) => st(c)?.mem_used_bytes ?? -1,
    ports: (c) => c.ports?.[0] ?? 99999,
  }[key] || ((c) => c.name);
  return [...list].sort((a, b) => {
    const x = val(a), y = val(b);
    return (x < y ? -1 : x > y ? 1 : 0) * (asc ? 1 : -1);
  });
}

function th(key, label, cls = '') {
  const on = S.sort.key === key;
  return `<th class="sortable ${cls}" data-sort="${key}">${label}${on ? `<span class="arrow">${S.sort.asc ? '↑' : '↓'}</span>` : ''}</th>`;
}

function containerRow(c, extraCls = '') {
  return `<tr class="${extraCls} ${S.selected === c.name ? 'selected' : ''}" data-name="${esc(c.name)}">
    <td><div class="name-cell"><span class="dot ${c.state === 'running' ? 'running' : 'stopped'}" style="box-shadow:none"></span>
      <span class="label" title="${esc(c.name)}">${esc(c.name)}</span>${c.compose_service && extraCls.includes('child') ? `<span class="svc">${esc(c.compose_service)}</span>` : ''}</div></td>
    <td class="muted" title="${esc(c.image)}">${esc(c.image)}</td>
    <td title="${esc(c.status)}">${stateBadge(c)}</td>
    <td>${portsHtml(c)}</td>
    <td class="num">${cpuCell(c)}</td>
    <td class="num">${ramCell(c)}</td>
  </tr>`;
}

const COLGROUP = '<colgroup><col style="width:29%"><col style="width:23%"><col style="width:15%"><col style="width:13%"><col style="width:10%"><col style="width:10%"></colgroup>';

function containerHead() {
  return `<thead><tr>${th('name', t('colName'))}${th('image', t('colImage'))}${th('status', t('colStatus'))}${th('ports', t('colPorts'))}${th('cpu', t('colCpu'), 'num')}${th('ram', t('colRam'), 'num')}</tr></thead>`;
}

function engineGate() {
  const k = S.snap?.status?.kind;
  if (!S.snap || k === 'running') return null;
  if (k === 'transitioning') {
    return `<div class="empty"><img src="assets/logo.svg" alt=""><h3>${esc(statusInfo(S.snap).label)}</h3><p>${t('starting')}</p></div>`;
  }
  if (k === 'stopped' && S.snap.backend === 'colima') {
    return `<div class="empty"><img class="dim" src="assets/logo.svg" alt=""><h3>${t('engineStoppedTitle')}</h3>
      <p>${t('engineStoppedHint')}</p><button class="btn primary" data-act="engine-start">${icon('play')}${t('startEngine')}</button></div>`;
  }
  const hint = { windows: 'dockerHintWindows', macos: 'dockerHintMac' }[S.snap.platform] || 'dockerHintLinux';
  return `<div class="empty"><img class="dim" src="assets/logo.svg" alt=""><h3>${t('dockerUnavailableTitle')}</h3>
    <p>${md(t(hint))}</p>
    ${S.snap.status?.message ? `<p class="faint mono">${esc(S.snap.status.message)}</p>` : ''}
    <div style="display:flex;gap:8px"><button class="btn" data-act="refresh">${icon('refresh')}${t('refresh')}</button>
    <button class="btn" data-act="settings">${icon('gear')}${t('settings')}</button></div></div>`;
}

function renderContainers() {
  const gate = engineGate();
  if (gate) return gate;
  const all = S.snap.containers;
  if (!all.length) return `<div class="empty"><img src="assets/logo.svg" alt=""><h3>${t('emptyContainers')}</h3><p>${md(t('emptyContainersHint'))}</p></div>`;
  const list = sortedContainers(all.filter((c) => (S.showAll || c.state === 'running') && matches(c)));
  if (!list.length) return `<div class="empty"><h3>${esc(t('emptySearch', { q: S.search }))}</h3></div>`;
  return `<table>${COLGROUP}${containerHead()}<tbody>${list.map((c) => containerRow(c)).join('')}</tbody></table>`;
}

function renderCompose() {
  const gate = engineGate();
  if (gate) return gate;
  const all = S.snap.containers;
  const groups = new Map();
  for (const c of all) {
    const p = c.compose_project || '';
    if (!groups.has(p)) groups.set(p, []);
    groups.get(p).push(c);
  }
  const projects = [...groups.keys()].filter(Boolean).sort();
  if (!projects.length && !all.length) {
    return `<div class="empty"><img src="assets/logo.svg" alt=""><h3>${t('emptyCompose')}</h3><p>${t('emptyComposeHint')}</p></div>`;
  }
  const order = [...projects, ...(groups.has('') ? [''] : [])];
  let rows = '';
  for (const p of order) {
    const items = sortedContainers(groups.get(p).filter((c) => matches(c) || (p && p.toLowerCase().includes(S.search.toLowerCase()))));
    if (!items.length) continue;
    const total = groups.get(p).length;
    const running = groups.get(p).filter((c) => c.state === 'running').length;
    const open = !S.collapsed.has(p);
    const badge = running === total ? `<span class="badge ok">${t('allRunning')}</span>`
      : running === 0 ? `<span class="badge">${t('projStopped')}</span>`
      : `<span class="badge warn">${t('partRunning', { r: running, t: total })}</span>`;
    const cpu = groups.get(p).reduce((a, c) => a + (S.snap.stats?.[c.name]?.cpu_percent ?? 0), 0);
    const mem = groups.get(p).reduce((a, c) => a + (S.snap.stats?.[c.name]?.mem_used_bytes ?? 0), 0);
    rows += `<tr class="project ${open ? 'open' : ''}" data-project="${esc(p)}">
      <td><div class="name-cell">${icon('chevron', 'chev')}<span class="label">${p ? esc(p) : t('noProject')}</span></div></td>
      <td class="muted">${total === 1 ? t('containerOne') : t('containersCount', { n: total })}</td>
      <td>${badge}</td><td></td>
      <td class="num muted">${running ? pct(cpu) : ''}</td><td class="num muted">${running ? bytes(mem) : ''}</td></tr>`;
    if (open) rows += items.map((c) => containerRow(c, 'child')).join('');
  }
  if (!rows) return `<div class="empty"><h3>${esc(t('emptySearch', { q: S.search }))}</h3></div>`;
  return `<table>${COLGROUP}${containerHead()}<tbody>${rows}</tbody></table>`;
}

// ---------------------------------------------------------------------------
// Images / volumes / networks
// ---------------------------------------------------------------------------

async function loadImages() { if (S.snap?.status?.kind === 'running') { S.images = await run(invoke('list_images')).catch(() => []); render(); } }
async function loadVolumes() { if (S.snap?.status?.kind === 'running') { S.volumes = await run(invoke('list_volumes')).catch(() => []); render(); } }
async function loadNetworks() { if (S.snap?.status?.kind === 'running') { S.networks = await run(invoke('list_networks')).catch(() => []); render(); } }

const q = () => S.search.trim().toLowerCase();

function renderImages() {
  const gate = engineGate(); if (gate) return gate;
  const list = S.images.filter((i) => !q() || `${i.repository}:${i.tag}`.toLowerCase().includes(q()));
  return `<table><colgroup><col style="width:40%"><col style="width:18%"><col style="width:14%"><col style="width:16%"><col style="width:12%"></colgroup>
    <thead><tr><th>${t('colRepo')}</th><th>${t('colTag')}</th><th class="num">${t('colSize')}</th><th>${t('colCreated')}</th><th>${t('colId')}</th></tr></thead>
    <tbody>${list.map((i) => `<tr data-image="${esc(i.id)}" class="${S.selectedImage === i.id ? 'selected' : ''}">
      <td><div class="name-cell">${icon('layers')}<span class="label">${esc(i.repository)}</span></div></td>
      <td><span class="badge">${esc(i.tag)}</span></td><td class="num">${esc(i.size)}</td>
      <td class="muted">${esc(i.created)}</td><td class="faint mono">${esc(i.id.slice(0, 12))}</td></tr>`).join('')}</tbody></table>`;
}

function renderVolumes() {
  const gate = engineGate(); if (gate) return gate;
  const list = S.volumes.filter((v) => !q() || v.name.toLowerCase().includes(q()));
  return `<table><colgroup><col style="width:42%"><col style="width:14%"><col style="width:44%"></colgroup>
    <thead><tr><th>${t('colName')}</th><th>${t('colDriver')}</th><th>${t('colUsedBy')}</th></tr></thead>
    <tbody>${list.map((v) => `<tr><td><div class="name-cell">${icon('disk')}<span class="label">${esc(v.name)}</span></div></td>
      <td class="muted">${esc(v.driver)}</td>
      <td>${v.containers.length ? v.containers.map((c) => `<span class="badge">${esc(c)}</span>`).join(' ') : '<span class="faint">—</span>'}</td></tr>`).join('')}</tbody></table>`;
}

function renderNetworks() {
  const gate = engineGate(); if (gate) return gate;
  const list = S.networks.filter((n) => !q() || n.name.toLowerCase().includes(q()));
  return `<table><colgroup><col style="width:40%"><col style="width:20%"><col style="width:20%"><col style="width:20%"></colgroup>
    <thead><tr><th>${t('colName')}</th><th>${t('colDriver')}</th><th>${t('colScope')}</th><th>${t('colId')}</th></tr></thead>
    <tbody>${list.map((n) => `<tr><td><div class="name-cell">${icon('network')}<span class="label">${esc(n.name)}</span></div></td>
      <td><span class="badge">${esc(n.driver)}</span></td><td class="muted">${esc(n.scope)}</td>
      <td class="faint mono">${esc(n.id.slice(0, 12))}</td></tr>`).join('')}</tbody></table>`;
}

// ---------------------------------------------------------------------------
// Toolbar
// ---------------------------------------------------------------------------

function renderToolbar() {
  const running = S.snap?.status?.kind === 'running';
  const search = `<div class="search">${icon('search')}<input id="search" placeholder="${t('search')}" value="${esc(S.search)}" spellcheck="false"></div>`;
  let right = '';
  switch (S.tab) {
    case 'containers':
      right = `<div class="seg"><button class="${S.showAll ? 'on' : ''}" data-filter="all">${t('all')}</button><button class="${S.showAll ? '' : 'on'}" data-filter="running">${t('runningOnly')}</button></div>
        <button class="btn" data-act="prune-system" ${running ? '' : 'disabled'}>${icon('trash')}${t('pruneSystem')}</button>`;
      break;
    case 'compose':
      right = `${S.snap?.portainer ? `<button class="btn" data-act="portainer">${icon('external')}${t('openPortainer')}</button>`
        : running ? `<button class="btn" data-act="install-portainer">${icon('download')}${t('installPortainer')}</button>` : ''}
        <button class="btn" data-act="prune-system" ${running ? '' : 'disabled'}>${icon('trash')}${t('pruneSystem')}</button>`;
      break;
    case 'images':
      right = `<div class="pull"><input id="pull-input" placeholder="${t('pullPlaceholder')}" spellcheck="false" ${running ? '' : 'disabled'}>
        <button class="btn primary" data-act="pull" ${running ? '' : 'disabled'}>${icon('download')}${t('pull')}</button></div>
        <button class="btn danger" data-act="remove-image" ${S.selectedImage ? '' : 'disabled'}>${icon('trash')}${t('remove')}</button>
        <button class="btn" data-act="prune-images" ${running ? '' : 'disabled'}>${t('pruneImages')}</button>`;
      break;
    case 'volumes':
      right = `<button class="btn" data-act="prune-volumes" ${running ? '' : 'disabled'}>${icon('trash')}${t('pruneVolumes')}</button>`;
      break;
    case 'networks':
      right = `<button class="btn" data-act="prune-networks" ${running ? '' : 'disabled'}>${icon('trash')}${t('pruneNetworks')}</button>`;
      break;
  }
  const bar = $('#toolbar');
  const hadFocus = document.activeElement?.id === 'search';
  const caret = hadFocus ? document.activeElement.selectionStart : null;
  const pullVal = $('#pull-input')?.value ?? '';
  bar.innerHTML = `${search}<div class="spacer"></div>${right}`;
  if ($('#pull-input')) $('#pull-input').value = pullVal;
  if (hadFocus) { const s = $('#search'); s.focus(); s.setSelectionRange(caret, caret); }
}

// ---------------------------------------------------------------------------
// Detail panel
// ---------------------------------------------------------------------------

function sparkSvg(values, color, max) {
  const w = 288, h = 42;
  if (values.length < 2) return `<svg viewBox="0 0 ${w} ${h}"></svg>`;
  const m = Math.max(max ?? 0, ...values, 1e-9);
  const step = w / (HISTORY - 1);
  const off = (HISTORY - values.length) * step;
  const pts = values.map((v, i) => [off + i * step, h - 3 - (v / m) * (h - 8)]);
  const line = pts.map((p, i) => `${i ? 'L' : 'M'}${p[0].toFixed(1)},${p[1].toFixed(1)}`).join('');
  const id = `g${color.replace(/\W/g, '')}`;
  return `<svg viewBox="0 0 ${w} ${h}" preserveAspectRatio="none">
    <defs><linearGradient id="${id}" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="${color}" stop-opacity=".35"/><stop offset="1" stop-color="${color}" stop-opacity="0"/></linearGradient></defs>
    <path d="${line}L${pts.at(-1)[0]},${h}L${pts[0][0]},${h}Z" fill="url(#${id})"/>
    <path d="${line}" fill="none" stroke="${color}" stroke-width="1.8" stroke-linejoin="round" stroke-linecap="round" vector-effect="non-scaling-stroke"/></svg>`;
}

function renderDetail() {
  const el = $('#detail');
  const containerTabs = S.tab === 'compose' || S.tab === 'containers';
  el.hidden = !containerTabs || S.snap?.status?.kind !== 'running';
  if (el.hidden) return;
  const c = S.snap.containers.find((x) => x.name === S.selected);
  if (!c) {
    el.innerHTML = `<div class="placeholder">${icon('box')}<p>${t('selectContainer')}</p></div>`;
    return;
  }
  const running = c.state === 'running';
  const busy = Boolean(S.pending[c.name]);
  const s = S.snap.stats?.[c.name];
  const h = S.history[c.name] || { cpu: [], mem: [] };
  const policies = ['no', 'always', 'on-failure', 'unless-stopped'];
  el.innerHTML = `
    <div class="detail-head"><h3><span class="dot ${running ? 'running' : 'stopped'}" style="box-shadow:none"></span>${esc(c.name)}</h3>
      <div class="sub">${esc(c.image)}</div></div>
    <div class="detail-actions">
      <button class="btn sm" data-c-act="start" ${running || busy ? 'disabled' : ''}>${icon('play')}${t('start')}</button>
      <button class="btn sm" data-c-act="stop" ${running && !busy ? '' : 'disabled'}>${icon('stop')}${t('stop')}</button>
      <button class="btn sm" data-c-act="restart" ${running && !busy ? '' : 'disabled'}>${icon('restart')}${t('restart')}</button>
      <button class="btn sm" data-c-act="logs">${icon('logs')}${t('logs')}</button>
      <button class="btn sm" data-c-act="shell" ${running ? '' : 'disabled'}>${icon('terminal')}${t('shell')}</button>
      <button class="btn sm" data-c-act="env">${icon('env')}${t('env')}</button>
    </div>
    ${running ? `<div class="detail-section">
      <div class="spark"><div class="spark-head"><span>${t('cpuHistory')}</span><b>${pct(s?.cpu_percent)}</b></div>${sparkSvg(h.cpu, '#12A894')}</div>
      <div class="spark" style="margin-bottom:0"><div class="spark-head"><span>${t('ramHistory')}</span><b>${s ? `${bytes(s.mem_used_bytes)} / ${bytes(s.mem_limit_bytes)}` : '—'}</b></div>${sparkSvg(h.mem, '#7C8CFF')}</div>
    </div>` : ''}
    <div class="detail-section"><dl class="kv">
      <dt>${t('colStatus')}</dt><dd>${esc(c.status)}</dd>
      ${c.health ? `<dt>${t('health')}</dt><dd>${esc(c.health)}</dd>` : ''}
      <dt>${t('ports')}</dt><dd>${portsHtml(c)}</dd>
      ${c.compose_project ? `<dt>Compose</dt><dd>${esc(c.compose_project)} / ${esc(c.compose_service || '')}</dd>` : ''}
      <dt>ID</dt><dd class="mono">${esc(c.id.slice(0, 12))}</dd>
    </dl></div>
    <div class="detail-section">
      <div class="spark-head"><span>${t('restartPolicy')}</span></div>
      <select id="policy">${policies.map((p) => `<option ${c.restart_policy === p || (!c.restart_policy && p === 'no') ? 'selected' : ''}>${p}</option>`).join('')}</select>
    </div>
    <div class="detail-section" style="display:flex;gap:6px">
      <button class="btn sm" data-c-act="inspect" style="flex:1">${icon('inspect')}${t('inspect')}</button>
      <button class="btn sm danger" data-c-act="remove" style="flex:1">${icon('trash')}${t('remove')}</button>
    </div>`;
}

// ---------------------------------------------------------------------------
// Render
// ---------------------------------------------------------------------------

function render() {
  renderHeader();
  renderTabs();
  renderToolbar();
  const wrap = $('#table-wrap');
  const scroll = wrap.scrollTop;
  wrap.innerHTML = {
    compose: renderCompose, containers: renderContainers, images: renderImages,
    volumes: renderVolumes, networks: renderNetworks,
  }[S.tab]();
  wrap.scrollTop = scroll;
  renderDetail();
}

function onSnapshot(snap) {
  const wasRunning = S.snap?.status?.kind === 'running';
  S.snap = snap;
  for (const c of snap.containers) {
    const s = snap.stats?.[c.name];
    if (!s) continue;
    const h = (S.history[c.name] ||= { cpu: [], mem: [] });
    h.cpu.push(s.cpu_percent); h.mem.push(s.mem_used_bytes);
    if (h.cpu.length > HISTORY) { h.cpu.shift(); h.mem.shift(); }
  }
  if (S.selected && !snap.containers.some((c) => c.name === S.selected)) S.selected = null;
  if (!wasRunning && snap.status.kind === 'running') {
    if (S.tab === 'images') loadImages();
    if (S.tab === 'volumes') loadVolumes();
    if (S.tab === 'networks') loadNetworks();
  }
  if (!$('#modal').hidden && S.logs) return renderHeaderOnly();
  render();
}

function renderHeaderOnly() { renderHeader(); renderTabs(); }

// ---------------------------------------------------------------------------
// Container actions
// ---------------------------------------------------------------------------

async function containerAction(name, act) {
  switch (act) {
    case 'start': case 'stop': case 'restart':
      S.pending[name] = act;
      render();
      try {
        await run(invoke('container_action', { name, action: act }));
      } finally {
        delete S.pending[name];
        render();
      }
      return;
    case 'remove':
      if (await confirmDialog(t('remove'), t('removeContainerText', { name }), t('remove'))) {
        S.pending[name] = 'remove';
        render();
        try {
          await run(invoke('container_action', { name, action: 'remove' }), t('done'));
        } finally {
          delete S.pending[name];
          render();
        }
      }
      return;
    case 'logs': return openLogs(name);
    case 'shell': {
      const cmd = await promptDialog(t('shellPrompt', { name }), 'sh');
      if (cmd) await run(invoke('open_shell', { name, command: cmd }), t('shellOpened'));
      return;
    }
    case 'env': {
      const env = await run(invoke('container_env', { name }));
      openModal({
        title: t('envOf', { name }),
        tools: `<button class="btn sm" id="copy-env">${icon('copy')}${t('copy')}</button>`,
        body: `<ul class="env-list">${env.map((e) => { const i = e.indexOf('='); return `<li><b>${esc(e.slice(0, i))}</b>=${esc(e.slice(i + 1))}</li>`; }).join('')}</ul>`,
      });
      $('#copy-env').onclick = () => navigator.clipboard.writeText(env.join('\n')).then(() => toast(t('copied')));
      return;
    }
    case 'inspect': {
      const json = await run(invoke('container_inspect', { name }));
      openModal({
        title: t('inspectOf', { name }),
        tools: `<button class="btn sm" id="copy-json">${icon('copy')}${t('copy')}</button>`,
        body: `<pre class="json">${esc(json)}</pre>`,
      });
      $('#copy-json').onclick = () => navigator.clipboard.writeText(json).then(() => toast(t('copied')));
      return;
    }
  }
}

function openLogs(name) {
  S.logs = { name, following: true };
  const tools = () => `<button class="btn sm" id="logs-follow">${icon(S.logs.following ? 'stop' : 'play')}${S.logs.following ? t('pause') : t('follow')}</button>
    <button class="btn sm" id="logs-clear">${icon('trash')}${t('clear')}</button>`;
  openModal({
    title: t('logsOf', { name }), tools: tools(),
    body: '<div class="terminal" id="term"></div>',
    onClose: () => { invoke('logs_stop'); S.logs = null; },
  });
  const bindTools = () => {
    $('#logs-follow').onclick = () => {
      S.logs.following = !S.logs.following;
      invoke(S.logs.following ? 'logs_follow' : 'logs_stop', S.logs.following ? { name, tail: 0 } : {});
      $('#modal-tools').innerHTML = tools(); bindTools();
    };
    $('#logs-clear').onclick = () => { $('#term').innerHTML = ''; };
  };
  bindTools();
  run(invoke('logs_follow', { name, tail: 300 })).catch(() => {});
}

function appendLog({ name, line }) {
  if (!S.logs || S.logs.name !== name) return;
  const term = $('#term');
  if (!term) return;
  const atBottom = term.scrollHeight - term.scrollTop - term.clientHeight < 40;
  const m = line.match(/^(\d{4}-\d\d-\d\dT[\d:.]+Z?)\s(.*)$/);
  const div = document.createElement('div');
  div.innerHTML = m ? `<span class="ts">${esc(m[1])}</span> ${esc(m[2])}` : esc(line);
  term.append(div);
  while (term.childElementCount > 5000) term.firstElementChild.remove();
  if (atBottom) term.scrollTop = term.scrollHeight;
}

// ---------------------------------------------------------------------------
// Global actions
// ---------------------------------------------------------------------------

async function prune(what) {
  const text = { system: 'pruneSystemText', volumes: 'pruneVolumesText', networks: 'pruneNetworksText', images: 'pruneImagesText' }[what];
  const label = { system: 'pruneSystem', volumes: 'pruneVolumes', networks: 'pruneNetworks', images: 'pruneImages' }[what];
  if (!(await confirmDialog(t(label).replace('…', ''), t(text), t(label).replace('…', '')))) return;
  const out = await run(invoke('prune', { what }));
  toast(out.trim().split('\n').pop() || t('done'));
  if (what === 'volumes') loadVolumes();
  if (what === 'networks') loadNetworks();
  if (what === 'images') loadImages();
}

async function globalAction(act) {
  switch (act) {
    case 'engine-start': return invoke('engine_start');
    case 'refresh': return invoke('refresh');
    case 'settings': return openSettings();
    case 'portainer': return invoke('open_url', { url: 'https://localhost:9443' });
    case 'install-portainer': return run(invoke('install_portainer'), 'Portainer ✓');
    case 'prune-system': return prune('system');
    case 'prune-volumes': return prune('volumes');
    case 'prune-networks': return prune('networks');
    case 'prune-images': return prune('images');
    case 'pull': {
      const name = $('#pull-input').value.trim();
      if (!name) return;
      toast(t('pulling', { name }));
      await run(invoke('pull_image', { name }), t('pulled', { name }));
      $('#pull-input').value = '';
      return loadImages();
    }
    case 'remove-image': {
      const img = S.images.find((i) => i.id === S.selectedImage);
      if (!img) return;
      const label = `${img.repository}:${img.tag}`;
      if (!(await confirmDialog(t('remove'), t('removeImageText', { name: label }), t('remove')))) return;
      await run(invoke('remove_image', { id: img.id }), t('done'));
      S.selectedImage = null;
      return loadImages();
    }
  }
}

// ---------------------------------------------------------------------------
// Settings
// ---------------------------------------------------------------------------

async function openSettings() {
  const s = { ...(await invoke('get_settings')) };
  const info = await invoke('app_info');
  const profiles = S.snap?.backend === 'colima' ? await invoke('colima_profiles').catch(() => []) : [];
  const opt = (vals, cur, fmt = (v) => v) => vals.map((v) => `<option value="${v}" ${String(v) === String(cur) ? 'selected' : ''}>${fmt(v)}</option>`).join('');
  const chk = (id, on, label) => `<label class="check"><input type="checkbox" id="${id}" ${on ? 'checked' : ''}>${label}</label>`;
  const isWin = info.platform === 'windows';
  const hasColima = S.snap?.backend === 'colima';
  openModal({
    title: t('settings'),
    body: `<div class="settings">
      <h4>${t('sGeneral')}</h4>
      <div class="field"><label>${t('sLanguage')}</label><select id="s-lang">${opt(['system', 'fr', 'en'], s.language, (v) => ({ system: t('sSystem'), fr: 'Français', en: 'English' }[v]))}</select></div>
      <div class="field"><label>${t('sPolling')}</label><select id="s-poll">${opt(['fast', 'normal', 'slow'], s.polling, (v) => ({ fast: `${t('sFast')} (2 s)`, normal: `${t('sNormal')} (5 s)`, slow: `${t('sSlow')} (15 s)` }[v]))}</select></div>
      ${chk('s-autostart', info.autostart, t('sAutostart'))}
      ${chk('s-hidden', s.start_hidden, t('sStartHidden'))}
      ${chk('s-alerts', s.resource_alerts, t('sAlerts'))}
      <h4>${t('sEngine')}</h4>
      <div class="field"><label>${t('sDockerCmd')}</label><input id="s-docker" value="${esc(s.docker_command)}" placeholder="${isWin ? 'docker  |  wsl -e docker' : 'docker'}" spellcheck="false">
        <div class="hint">${md(t('sDockerCmdHint'))}</div></div>
      ${isWin ? '' : chk('s-colima', s.use_colima, t('sUseColima'))}
      ${!isWin && !hasColima ? `<div class="note">${t('noColima')}</div>` : ''}
      ${isWin || !hasColima ? '' : `<h4>${t('sColima')}</h4>
      <div class="field"><label>${t('sProfile')}</label><select id="s-profile">${opt([...new Set([s.colima_profile, ...profiles])], s.colima_profile)}</select></div>
      <div class="field"><label>${t('sCpus')}</label><select id="s-cpus">${opt([1, 2, 4, 6, 8], s.cpus)}</select></div>
      <div class="field"><label>${t('sMemory')}</label><select id="s-mem">${opt([2, 4, 6, 8, 16], s.memory_gb, (v) => `${v} GB`)}</select></div>
      <div class="field"><label>${t('sDisk')}</label><select id="s-disk">${opt([20, 40, 60, 100, 200], s.disk_gb, (v) => `${v} GB`)}</select></div>
      ${chk('s-autoeng', s.auto_start_engine, t('sAutoStartEngine'))}
      <div class="note">${t('sApplyRestart')}</div>`}
      <div class="about"><img src="assets/logo.svg" alt="">${esc(t('about', { v: info.version, os: info.platform }))}${isDemo ? ' · demo' : ''}
        <span class="spacer" style="flex:1"></span><button class="btn sm danger" id="s-quit">${icon('power')}${t('quit')}</button></div>
    </div>`,
    foot: `<button class="btn" id="s-cancel">${t('cancel')}</button><button class="btn primary" id="s-save">${t('save')}</button>`,
  });
  $('#s-cancel').onclick = closeModal;
  $('#s-quit').onclick = () => invoke('quit_app');
  $('#s-save').onclick = async () => {
    const v = (id) => $(id)?.value;
    const next = {
      ...s,
      language: v('#s-lang'), polling: v('#s-poll'), docker_command: v('#s-docker').trim(),
      start_hidden: $('#s-hidden').checked, resource_alerts: $('#s-alerts').checked,
      use_colima: $('#s-colima') ? $('#s-colima').checked : s.use_colima,
      colima_profile: v('#s-profile') ?? s.colima_profile,
      cpus: Number(v('#s-cpus') ?? s.cpus), memory_gb: Number(v('#s-mem') ?? s.memory_gb), disk_gb: Number(v('#s-disk') ?? s.disk_gb),
      auto_start_engine: $('#s-autoeng') ? $('#s-autoeng').checked : s.auto_start_engine,
    };
    await run(invoke('save_settings', { settings: next }));
    if ($('#s-autostart').checked !== info.autostart) await run(invoke('set_autostart', { enabled: $('#s-autostart').checked })).catch(() => {});
    S.settings = next;
    const i2 = await invoke('app_info');
    setLang(i2.lang);
    closeModal();
    toast(t('sSaved'));
    render();
  };
}

// ---------------------------------------------------------------------------
// Events
// ---------------------------------------------------------------------------

function bind() {
  $('#refresh-btn').innerHTML = icon('refresh');
  $('#refresh-btn').title = t('refresh');
  $('#refresh-btn').onclick = () => invoke('refresh');
  $('#settings-btn').innerHTML = icon('gear');
  $('#settings-btn').title = t('settings');
  $('#settings-btn').onclick = openSettings;
  $('#modal-close').innerHTML = icon('x');
  $('#modal-close').onclick = closeModal;
  $('#modal').addEventListener('mousedown', (e) => { if (e.target.id === 'modal') closeModal(); });
  document.addEventListener('keydown', (e) => {
    if (e.key === 'Escape' && !$('#modal').hidden) closeModal();
    if ((e.ctrlKey || e.metaKey) && e.key === 'f') { e.preventDefault(); $('#search')?.focus(); }
    if ((e.ctrlKey || e.metaKey) && e.key === ',') { e.preventDefault(); openSettings(); }
    if (e.key === 'F5' || ((e.ctrlKey || e.metaKey) && e.key === 'r')) { e.preventDefault(); invoke('refresh'); }
  });

  $('#tabs').onclick = (e) => { const b = e.target.closest('[data-tab]'); if (b) setTab(b.dataset.tab); };

  $('#toolbar').addEventListener('input', (e) => {
    if (e.target.id === 'search') { S.search = e.target.value; render(); }
  });
  $('#toolbar').addEventListener('keydown', (e) => {
    if (e.target.id === 'pull-input' && e.key === 'Enter') globalAction('pull');
  });
  $('#toolbar').onclick = (e) => {
    const f = e.target.closest('[data-filter]');
    if (f) { S.showAll = f.dataset.filter === 'all'; render(); return; }
    const a = e.target.closest('[data-act]');
    if (a) globalAction(a.dataset.act);
  };

  $('#table-wrap').onclick = (e) => {
    const port = e.target.closest('[data-port]');
    if (port) { invoke('open_url', { url: `http://localhost:${port.dataset.port}` }); return; }
    const act = e.target.closest('[data-act]');
    if (act) { globalAction(act.dataset.act); return; }
    const sort = e.target.closest('[data-sort]');
    if (sort) {
      const k = sort.dataset.sort;
      S.sort = { key: k, asc: S.sort.key === k ? !S.sort.asc : !['cpu', 'ram'].includes(k) };
      render(); return;
    }
    const proj = e.target.closest('[data-project]');
    if (proj) {
      const p = proj.dataset.project;
      S.collapsed.has(p) ? S.collapsed.delete(p) : S.collapsed.add(p);
      render(); return;
    }
    const row = e.target.closest('[data-name]');
    if (row) {
      S.selected = row.dataset.name;
      document.querySelectorAll('#table-wrap tr.selected').forEach((r) => r.classList.remove('selected'));
      row.classList.add('selected');
      renderDetail();
      return;
    }
    const img = e.target.closest('[data-image]');
    if (img) { S.selectedImage = img.dataset.image; render(); }
  };
  $('#table-wrap').ondblclick = (e) => {
    const row = e.target.closest('[data-name]');
    if (row) containerAction(row.dataset.name, 'logs');
  };

  $('#detail').onclick = (e) => {
    const port = e.target.closest('[data-port]');
    if (port) { invoke('open_url', { url: `http://localhost:${port.dataset.port}` }); return; }
    const b = e.target.closest('[data-c-act]');
    if (b && S.selected) containerAction(S.selected, b.dataset.cAct);
  };
  $('#detail').onchange = (e) => {
    if (e.target.id === 'policy' && S.selected) {
      run(invoke('set_restart_policy', { name: S.selected, policy: e.target.value }), t('done'));
    }
  };
}

async function init() {
  S.info = await invoke('app_info');
  setLang(S.info.lang);
  document.body.dataset.platform = S.info.platform;
  bind();
  await listen('snapshot', onSnapshot);
  await listen('logs', appendLog);
  await listen('error', (msg) => toast(String(msg), 'error'));
  await listen('ui', (what) => {
    if (what === 'settings') openSettings();
    if (what === 'confirm-prune') prune('system');
  });
  const params = new URLSearchParams(location.search);
  if (params.get('tab')) S.tab = params.get('tab');
  onSnapshot(await invoke('get_snapshot'));
  if (isDemo) {
    // Pre-fill some history so sparklines look alive in previews.
    for (let i = 0; i < HISTORY - 1; i++) onSnapshot(await invoke('get_snapshot'));
    if (params.get('select')) { S.selected = params.get('select'); render(); }
    if (S.tab === 'images') loadImages();
    if (S.tab === 'volumes') loadVolumes();
    if (S.tab === 'networks') loadNetworks();
    if (params.get('modal') === 'settings') openSettings();
    if (params.get('modal') === 'logs') openLogs(params.get('select') || 'shop-web-1');
  }
}

init();
