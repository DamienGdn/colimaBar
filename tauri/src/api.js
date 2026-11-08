// Thin wrapper over the Tauri IPC. When the page is opened in a regular
// browser (no `window.__TAURI__`), a demo backend with sample data is used so
// the UI can be previewed and screenshotted: `npm run preview`.

const TAURI = window.__TAURI__;

export const isDemo = !TAURI;

export function invoke(cmd, args = {}) {
  return TAURI ? TAURI.core.invoke(cmd, args) : demo.invoke(cmd, args);
}

export function listen(event, handler) {
  return TAURI ? TAURI.event.listen(event, (e) => handler(e.payload)) : demo.listen(event, handler);
}

// ---------------------------------------------------------------------------
// Demo backend
// ---------------------------------------------------------------------------

const demo = (() => {
  const params = new URLSearchParams(location.search);
  const listeners = {};
  const emit = (ev, payload) => (listeners[ev] || []).forEach((h) => h(payload));
  const GiB = 1024 ** 3, MiB = 1024 ** 2;

  const mk = (name, image, project, service, state, status, ports, policy, health) => ({
    id: Math.random().toString(16).slice(2, 14), name, image, state, status, ports,
    compose_project: project, compose_service: service, health, restart_policy: policy,
  });
  let containers = [
    mk('shop-web-1', 'node:20-alpine', 'shop', 'web', 'running', 'Up 2 hours', [3000], 'unless-stopped', null),
    mk('shop-db-1', 'postgres:16-alpine', 'shop', 'db', 'running', 'Up 2 hours (healthy)', [5433], 'always', 'healthy'),
    mk('shop-redis-1', 'redis:7', 'shop', 'redis', 'running', 'Up 2 hours', [6379], 'always', null),
    mk('shop-worker-1', 'shop-worker:dev', 'shop', 'worker', 'exited', 'Exited (1) 12 minutes ago', [], 'on-failure', null),
    mk('blog-wordpress-1', 'wordpress:6', 'blog', 'wordpress', 'running', 'Up 35 minutes', [8080], 'no', null),
    mk('blog-mysql-1', 'mysql:8.4', 'blog', 'mysql', 'running', 'Up 35 minutes (healthy)', [], 'always', 'healthy'),
    mk('portainer', 'portainer/portainer-ce:latest', null, null, 'running', 'Up 3 hours', [8000, 9443], 'always', null),
    mk('minio', 'minio/minio:latest', null, null, 'exited', 'Exited (0) 2 days ago', [], 'no', null),
  ];
  const base = { 'shop-web-1': [4, 180], 'shop-db-1': [1.2, 96], 'shop-redis-1': [0.4, 12], 'blog-wordpress-1': [2.5, 140], 'blog-mysql-1': [1.8, 410], portainer: [0.1, 38] };
  let engine = params.get('state') || 'running';
  const backend = params.get('backend') || 'colima';

  function snapshot() {
    const running = engine === 'running';
    const stats = {};
    if (running) {
      for (const c of containers.filter((c) => c.state === 'running')) {
        const [cpu, mem] = base[c.name] || [0.5, 20];
        stats[c.name] = {
          cpu_percent: Math.max(0, cpu * (0.6 + Math.random() * 0.8)),
          mem_used_bytes: mem * MiB * (0.95 + Math.random() * 0.1),
          mem_limit_bytes: 7.7 * GiB,
        };
      }
    }
    const cpu = Object.values(stats).reduce((a, s) => a + s.cpu_percent, 0);
    const mem = Object.values(stats).reduce((a, s) => a + s.mem_used_bytes, 0);
    const status = engine === 'running' ? { kind: 'running' }
      : engine === 'unavailable' ? { kind: 'unavailable', message: 'Cannot connect to the Docker daemon' }
      : engine === 'transitioning' ? { kind: 'transitioning', message: 'Starting…' }
      : { kind: 'stopped' };
    return {
      backend, platform: params.get('os') || 'linux', status,
      colima: backend === 'colima' ? { name: 'default', status: running ? 'Running' : 'Stopped', cpus: 4, memory_gb: 8, disk_gb: 60, arch: 'x86_64', runtime: 'docker' } : null,
      containers: running ? containers : [], stats,
      usage: running ? { cpu_percent: cpu, mem_used_bytes: mem, mem_total_bytes: 7.7 * GiB, ncpu: 4 } : null,
      portainer: running, docker_command: backend === 'docker' && params.get('os') === 'windows' ? 'wsl -e docker' : 'docker',
      last_error: null, updated_at: Date.now() / 1000,
    };
  }

  let settings = {
    language: 'system', polling: 'normal', docker_command: '', use_colima: true, colima_profile: 'default',
    cpus: 4, memory_gb: 8, disk_gb: 60, auto_start_engine: false, show_all_containers: true,
    resource_alerts: true, start_hidden: false,
  };

  setInterval(() => emit('snapshot', snapshot()), 2000);
  const wait = (ms) => new Promise((r) => setTimeout(r, ms));

  const handlers = {
    get_snapshot: snapshot,
    refresh: () => emit('snapshot', snapshot()),
    engine_start: async () => { engine = 'transitioning'; emit('snapshot', snapshot()); await wait(1500); engine = 'running'; emit('snapshot', snapshot()); },
    engine_stop: async () => { engine = 'transitioning'; emit('snapshot', snapshot()); await wait(1200); engine = 'stopped'; emit('snapshot', snapshot()); },
    container_action: ({ name, action }) => {
      containers = containers.map((c) => c.name !== name ? c : {
        ...c,
        state: action === 'stop' ? 'exited' : 'running',
        status: action === 'stop' ? 'Exited (0) 1 second ago' : 'Up 1 second',
      });
      if (action === 'remove') containers = containers.filter((c) => c.name !== name);
      emit('snapshot', snapshot());
    },
    set_restart_policy: ({ name, policy }) => { containers = containers.map((c) => c.name === name ? { ...c, restart_policy: policy } : c); },
    container_env: () => ['PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin', 'NODE_ENV=production', 'DATABASE_URL=postgres://shop@db:5432/shop', 'REDIS_URL=redis://redis:6379'],
    container_inspect: ({ name }) => JSON.stringify([{ Id: 'f3a9c1…', Name: `/${name}`, State: { Status: 'running', Running: true }, HostConfig: { RestartPolicy: { Name: 'always' } } }], null, 2),
    logs_follow: ({ name }) => {
      const lines = ['> shop@1.4.0 start', '> node server.js', 'Server listening on http://0.0.0.0:3000', 'GET / 200 4.1 ms', 'GET /api/products 200 12.7 ms', 'POST /api/cart 201 8.3 ms', 'GET /healthz 200 0.6 ms'];
      lines.forEach((line, i) => setTimeout(() => emit('logs', { name, line: `2026-11-08T09:41:${String(10 + i).padStart(2, '0')}Z ${line}` }), 80 * i));
    },
    logs_stop: () => {},
    open_shell: () => {},
    list_images: () => [
      { id: 'a1b2c3', repository: 'postgres', tag: '16-alpine', size: '276MB', created: '2 weeks ago' },
      { id: 'b2c3d4', repository: 'node', tag: '20-alpine', size: '135MB', created: '3 weeks ago' },
      { id: 'c3d4e5', repository: 'redis', tag: '7', size: '117MB', created: '1 month ago' },
      { id: 'd4e5f6', repository: 'wordpress', tag: '6', size: '702MB', created: '1 month ago' },
      { id: 'e5f6a7', repository: 'mysql', tag: '8.4', size: '603MB', created: '5 weeks ago' },
      { id: 'f6a7b8', repository: 'portainer/portainer-ce', tag: 'latest', size: '301MB', created: '2 months ago' },
    ],
    remove_image: () => {}, pull_image: () => wait(1200),
    list_volumes: () => [
      { name: 'shop_pgdata', driver: 'local', containers: ['shop-db-1'] },
      { name: 'blog_db', driver: 'local', containers: ['blog-mysql-1'] },
      { name: 'portainer_data', driver: 'local', containers: ['portainer'] },
      { name: 'old_cache', driver: 'local', containers: [] },
    ],
    list_networks: () => [
      { id: '1f2e3d', name: 'bridge', driver: 'bridge', scope: 'local' },
      { id: '2e3d4c', name: 'host', driver: 'host', scope: 'local' },
      { id: '3d4c5b', name: 'none', driver: 'null', scope: 'local' },
      { id: '4c5b6a', name: 'shop_default', driver: 'bridge', scope: 'local' },
      { id: '5b6a79', name: 'blog_default', driver: 'bridge', scope: 'local' },
    ],
    prune: () => 'Total reclaimed space: 0B', install_portainer: () => {}, open_url: () => {},
    get_settings: () => settings,
    save_settings: ({ settings: s }) => (settings = s),
    colima_profiles: () => ['default', 'dev'],
    app_info: () => ({ version: '1.10.0', platform: params.get('os') || 'linux', lang: params.get('lang') || (navigator.language.startsWith('fr') ? 'fr' : 'en'), autostart: true }),
    set_autostart: ({ enabled }) => enabled,
    quit_app: () => {},
  };

  return {
    async invoke(cmd, args) {
      const h = handlers[cmd];
      if (!h) throw new Error(`demo: unknown command ${cmd}`);
      return h(args);
    },
    async listen(event, handler) {
      (listeners[event] ||= []).push(handler);
      return () => {};
    },
  };
})();
