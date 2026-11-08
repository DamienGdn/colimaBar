//! ColimaBar for Linux and Windows (Tauri v2).
//!
//! A background thread polls the engine, stores the latest [`Snapshot`],
//! pushes it to the web UI (`snapshot` event) and refreshes the tray.

mod breathing;
mod engine;
mod model;
mod tray;

use engine::Engine;
use model::*;
use serde::Serialize;
use std::collections::HashSet;
use std::io::{BufRead, BufReader};
use std::path::PathBuf;
use std::process::{Child, Stdio};
use std::sync::{Arc, Condvar, Mutex};
use std::time::Duration;
use tauri::{AppHandle, Emitter, Manager, State, WindowEvent};
use tauri_plugin_autostart::ManagerExt as _;
use tauri_plugin_notification::NotificationExt as _;

/// State shared by the poller, the tray and the commands.
pub struct Shared {
    settings: Mutex<Settings>,
    engine: Mutex<Engine>,
    snapshot: Mutex<Snapshot>,
    /// Status override while Colima starts / stops.
    transition: Mutex<Option<String>>,
    /// Wakes the poller early (after an action or a settings change).
    wake: (Mutex<bool>, Condvar),
    logs: Mutex<Option<Child>>,
    alerts: Mutex<Alerts>,
    settings_path: Mutex<Option<PathBuf>>,
}

#[derive(Default)]
struct Alerts {
    high_cpu: u32,
    high_mem: u32,
    running: Option<HashSet<String>>,
}

type SharedState<'a> = State<'a, Arc<Shared>>;

impl Shared {
    fn new(settings: Settings) -> Self {
        let engine = Engine::detect(&settings);
        let snapshot = Snapshot::empty(engine.backend, engine.docker_command_label());
        Shared {
            settings: Mutex::new(settings),
            engine: Mutex::new(engine),
            snapshot: Mutex::new(snapshot),
            transition: Mutex::new(None),
            wake: (Mutex::new(false), Condvar::new()),
            logs: Mutex::new(None),
            alerts: Mutex::new(Alerts::default()),
            settings_path: Mutex::new(None),
        }
    }

    fn engine(&self) -> Engine {
        self.engine.lock().unwrap().clone()
    }

    fn settings(&self) -> Settings {
        self.settings.lock().unwrap().clone()
    }

    fn wake(&self) {
        let (lock, cv) = &self.wake;
        *lock.lock().unwrap() = true;
        cv.notify_all();
    }

    fn sleep(&self, secs: u64) {
        let (lock, cv) = &self.wake;
        let guard = lock.lock().unwrap();
        let (mut woken, _) = cv
            .wait_timeout_while(guard, Duration::from_secs(secs), |w| !*w)
            .unwrap();
        *woken = false;
    }
}

// ---------------------------------------------------------------------------
// Polling
// ---------------------------------------------------------------------------

fn poll_loop(app: AppHandle, shared: Arc<Shared>) {
    loop {
        let engine = shared.engine();
        let mut snap = engine.snapshot();
        if let Some(msg) = shared.transition.lock().unwrap().clone() {
            snap.status = EngineStatus::Transitioning(msg);
        }
        notify_changes(&app, &shared, &snap);
        *shared.snapshot.lock().unwrap() = snap.clone();
        let _ = app.emit("snapshot", &snap);
        tray::update(&app, &shared.settings(), &snap);

        let (running_secs, stopped_secs) = shared.settings().intervals();
        let secs = match snap.status {
            EngineStatus::Running => running_secs,
            EngineStatus::Transitioning(_) => 2,
            _ => stopped_secs,
        };
        shared.sleep(secs);
    }
}

/// Crash + resource notifications (same rules as the macOS app).
fn notify_changes(app: &AppHandle, shared: &Shared, snap: &Snapshot) {
    let settings = shared.settings();
    let mut alerts = shared.alerts.lock().unwrap();
    if snap.status != EngineStatus::Running {
        alerts.running = None;
        return;
    }
    let now: HashSet<String> = snap
        .containers
        .iter()
        .filter(|c| c.is_running())
        .map(|c| c.name.clone())
        .collect();
    if let Some(prev) = &alerts.running {
        for c in &snap.containers {
            if prev.contains(&c.name) && (c.state == "exited" || c.state == "dead") {
                notify(
                    app,
                    &settings.t(
                        &format!("Le container « {} » s'est arrêté inopinément", c.name),
                        &format!("Container '{}' exited unexpectedly", c.name),
                    ),
                );
            }
        }
    }
    alerts.running = Some(now);

    if !settings.resource_alerts {
        return;
    }
    if let Some(u) = &snap.usage {
        let cpu_capacity = (u.ncpu.max(1) as f64) * 100.0;
        let cpu = u.cpu_percent / cpu_capacity * 100.0;
        alerts.high_cpu = if cpu > 80.0 { alerts.high_cpu + 1 } else { 0 };
        if alerts.high_cpu == 2 {
            notify(
                app,
                &settings.t(
                    &format!("CPU élevé : {cpu:.0} %"),
                    &format!("High CPU: {cpu:.0}%"),
                ),
            );
        }
        let mem = if u.mem_total_bytes > 0.0 {
            u.mem_used_bytes / u.mem_total_bytes * 100.0
        } else {
            0.0
        };
        alerts.high_mem = if mem > 90.0 { alerts.high_mem + 1 } else { 0 };
        if alerts.high_mem == 2 {
            notify(
                app,
                &settings.t(
                    &format!("RAM élevée : {mem:.0} %"),
                    &format!("High RAM: {mem:.0}%"),
                ),
            );
        }
    }
}

fn notify(app: &AppHandle, body: &str) {
    let _ = app
        .notification()
        .builder()
        .title("ColimaBar")
        .body(body)
        .show();
}

// ---------------------------------------------------------------------------
// Settings persistence
// ---------------------------------------------------------------------------

fn load_settings(path: &PathBuf) -> Settings {
    std::fs::read_to_string(path)
        .ok()
        .and_then(|s| serde_json::from_str(&s).ok())
        .unwrap_or_default()
}

fn store_settings(shared: &Shared, settings: &Settings) -> Result<(), String> {
    let Some(path) = shared.settings_path.lock().unwrap().clone() else {
        return Ok(());
    };
    if let Some(dir) = path.parent() {
        std::fs::create_dir_all(dir).map_err(|e| e.to_string())?;
    }
    let json = serde_json::to_string_pretty(settings).map_err(|e| e.to_string())?;
    std::fs::write(&path, json).map_err(|e| e.to_string())
}

// ---------------------------------------------------------------------------
// Commands
// ---------------------------------------------------------------------------

/// Runs blocking CLI work off the async runtime.
async fn blocking<T: Send + 'static>(f: impl FnOnce() -> T + Send + 'static) -> T {
    tauri::async_runtime::spawn_blocking(f)
        .await
        .expect("blocking task panicked")
}

#[tauri::command]
fn get_snapshot(state: SharedState) -> Snapshot {
    state.snapshot.lock().unwrap().clone()
}

#[tauri::command]
fn refresh(state: SharedState) {
    state.wake();
}

pub(crate) fn engine_lifecycle(app: &AppHandle, shared: Arc<Shared>, start: bool) {
    let settings = shared.settings();
    let msg = if start {
        settings.t("Démarrage…", "Starting…")
    } else {
        settings.t("Arrêt…", "Stopping…")
    };
    *shared.transition.lock().unwrap() = Some(msg);
    shared.wake();
    let app = app.clone();
    std::thread::spawn(move || {
        let engine = shared.engine();
        let started = std::time::Instant::now();
        let result = if start {
            engine.start_engine(&settings)
        } else {
            engine.stop_engine()
        };
        *shared.transition.lock().unwrap() = None;
        shared.wake();
        let body = match &result {
            Ok(()) if start => settings.t(
                &format!("Colima démarré en {} s", started.elapsed().as_secs()),
                &format!("Colima started in {}s", started.elapsed().as_secs()),
            ),
            Ok(()) => settings.t("Colima arrêté", "Colima stopped"),
            Err(e) => e.clone(),
        };
        notify(&app, &body);
        if let Err(e) = result {
            let _ = app.emit("error", e);
        }
    });
}

#[tauri::command]
fn engine_start(app: AppHandle, state: SharedState) {
    engine_lifecycle(&app, state.inner().clone(), true);
}

#[tauri::command]
fn engine_stop(app: AppHandle, state: SharedState) {
    engine_lifecycle(&app, state.inner().clone(), false);
}

#[tauri::command]
async fn container_action(
    state: SharedState<'_>,
    name: String,
    action: String,
) -> Result<(), String> {
    let shared = state.inner().clone();
    blocking(move || {
        let r = shared.engine().container_action(&name, &action);
        shared.wake();
        r
    })
    .await
}

#[tauri::command]
async fn set_restart_policy(
    state: SharedState<'_>,
    name: String,
    policy: String,
) -> Result<(), String> {
    let shared = state.inner().clone();
    blocking(move || {
        let r = shared.engine().set_restart_policy(&name, &policy);
        shared.wake();
        r
    })
    .await
}

#[tauri::command]
async fn container_env(state: SharedState<'_>, name: String) -> Result<Vec<String>, String> {
    let e = state.engine();
    blocking(move || e.env(&name)).await
}

#[tauri::command]
async fn container_inspect(state: SharedState<'_>, name: String) -> Result<String, String> {
    let e = state.engine();
    blocking(move || e.inspect(&name)).await
}

#[derive(Clone, Serialize)]
struct LogLine {
    name: String,
    line: String,
}

/// Streams `docker logs -f` into `logs` events until [`logs_stop`].
#[tauri::command]
fn logs_follow(
    app: AppHandle,
    state: SharedState,
    name: String,
    tail: Option<u32>,
) -> Result<(), String> {
    stop_logs(&state);
    let engine = state.engine();
    let tail = tail.unwrap_or(200).to_string();
    let argv = engine.docker_argv(&["logs", "-f", "--tail", &tail, &name]);
    let mut child = engine::command(&argv[0])
        .args(&argv[1..])
        .stdin(Stdio::null())
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .spawn()
        .map_err(|e| e.to_string())?;
    for pipe in [
        child
            .stdout
            .take()
            .map(|p| Box::new(p) as Box<dyn std::io::Read + Send>),
        child
            .stderr
            .take()
            .map(|p| Box::new(p) as Box<dyn std::io::Read + Send>),
    ]
    .into_iter()
    .flatten()
    {
        let app = app.clone();
        let name = name.clone();
        std::thread::spawn(move || {
            for line in BufReader::new(pipe).lines().map_while(Result::ok) {
                let _ = app.emit(
                    "logs",
                    LogLine {
                        name: name.clone(),
                        line,
                    },
                );
            }
        });
    }
    *state.logs.lock().unwrap() = Some(child);
    Ok(())
}

fn stop_logs(shared: &Shared) {
    if let Some(mut child) = shared.logs.lock().unwrap().take() {
        let _ = child.kill();
        let _ = child.wait();
    }
}

#[tauri::command]
fn logs_stop(state: SharedState) {
    stop_logs(&state);
}

#[tauri::command]
fn open_shell(state: SharedState, name: String, command: Option<String>) -> Result<(), String> {
    let cmd = command
        .filter(|c| !c.trim().is_empty())
        .unwrap_or_else(|| "sh".into());
    let mut args: Vec<String> = vec!["exec".into(), "-it".into(), name];
    args.extend(cmd.split_whitespace().map(String::from));
    let refs: Vec<&str> = args.iter().map(String::as_str).collect();
    engine::open_terminal(&state.engine().docker_argv(&refs))
}

#[tauri::command]
async fn list_images(state: SharedState<'_>) -> Result<Vec<Image>, String> {
    let e = state.engine();
    blocking(move || e.images()).await
}

#[tauri::command]
async fn remove_image(state: SharedState<'_>, id: String) -> Result<(), String> {
    let e = state.engine();
    blocking(move || e.remove_image(&id)).await
}

#[tauri::command]
async fn pull_image(state: SharedState<'_>, name: String) -> Result<(), String> {
    let e = state.engine();
    blocking(move || e.pull_image(&name)).await
}

#[tauri::command]
async fn list_volumes(state: SharedState<'_>) -> Result<Vec<Volume>, String> {
    let e = state.engine();
    blocking(move || e.volumes()).await
}

#[tauri::command]
async fn list_networks(state: SharedState<'_>) -> Result<Vec<Network>, String> {
    let e = state.engine();
    blocking(move || e.networks()).await
}

#[tauri::command]
async fn prune(state: SharedState<'_>, what: String) -> Result<String, String> {
    let shared = state.inner().clone();
    blocking(move || {
        let r = shared.engine().prune(&what);
        shared.wake();
        r
    })
    .await
}

#[tauri::command]
async fn install_portainer(state: SharedState<'_>) -> Result<(), String> {
    let shared = state.inner().clone();
    blocking(move || {
        let r = shared.engine().install_portainer();
        shared.wake();
        r
    })
    .await
}

#[tauri::command]
fn open_url(url: String) -> Result<(), String> {
    if !(url.starts_with("http://") || url.starts_with("https://")) {
        return Err("only http(s) URLs can be opened".into());
    }
    tauri_plugin_opener::open_url(url, None::<&str>).map_err(|e| e.to_string())
}

#[tauri::command]
fn get_settings(state: SharedState) -> Settings {
    state.settings()
}

#[tauri::command]
fn save_settings(
    app: AppHandle,
    state: SharedState,
    settings: Settings,
) -> Result<Settings, String> {
    store_settings(&state, &settings)?;
    *state.engine.lock().unwrap() = Engine::detect(&settings);
    *state.settings.lock().unwrap() = settings.clone();
    tray::rebuild(&app, &settings);
    state.wake();
    Ok(settings)
}

#[tauri::command]
async fn colima_profiles(state: SharedState<'_>) -> Result<Vec<String>, String> {
    let e = state.engine();
    Ok(blocking(move || e.profiles()).await)
}

#[derive(Serialize)]
struct AppInfo {
    version: String,
    platform: &'static str,
    lang: &'static str,
    autostart: bool,
}

#[tauri::command]
fn app_info(app: AppHandle, state: SharedState) -> AppInfo {
    AppInfo {
        version: app.package_info().version.to_string(),
        platform: std::env::consts::OS,
        lang: state.settings().lang(),
        autostart: app.autolaunch().is_enabled().unwrap_or(false),
    }
}

#[tauri::command]
fn set_autostart(app: AppHandle, enabled: bool) -> Result<bool, String> {
    let al = app.autolaunch();
    if enabled { al.enable() } else { al.disable() }.map_err(|e| e.to_string())?;
    al.is_enabled().map_err(|e| e.to_string())
}

#[tauri::command]
fn quit_app(app: AppHandle, state: SharedState) {
    stop_logs(&state);
    app.exit(0);
}

pub(crate) fn show_main_window(app: &AppHandle) {
    if let Some(w) = app.get_webview_window("main") {
        let _ = w.unminimize();
        let _ = w.show();
        let _ = w.set_focus();
    }
}

// ---------------------------------------------------------------------------
// Entry point
// ---------------------------------------------------------------------------

#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    tauri::Builder::default()
        .plugin(tauri_plugin_single_instance::init(|app, _args, _cwd| {
            show_main_window(app)
        }))
        .plugin(tauri_plugin_opener::init())
        .plugin(tauri_plugin_notification::init())
        .plugin(tauri_plugin_autostart::init(
            tauri_plugin_autostart::MacosLauncher::LaunchAgent,
            Some(vec!["--hidden"]),
        ))
        .setup(|app| {
            let path = app
                .path()
                .app_config_dir()
                .ok()
                .map(|d| d.join("settings.json"));
            let settings = path.as_ref().map(load_settings).unwrap_or_default();
            let shared = Arc::new(Shared::new(settings.clone()));
            *shared.settings_path.lock().unwrap() = path;
            app.manage(shared.clone());

            tray::create(app.handle(), &settings)?;

            let launched_hidden = std::env::args().any(|a| a == "--hidden");
            if !(settings.start_hidden || launched_hidden) {
                show_main_window(app.handle());
            }

            if settings.auto_start_engine && shared.engine().backend == Backend::Colima {
                engine_lifecycle(app.handle(), shared.clone(), true);
            }

            let handle = app.handle().clone();
            std::thread::spawn(move || poll_loop(handle, shared));
            Ok(())
        })
        .on_window_event(|window, event| {
            // Closing the window keeps the app alive in the tray.
            if let WindowEvent::CloseRequested { api, .. } = event {
                api.prevent_close();
                let _ = window.hide();
            }
        })
        .invoke_handler(tauri::generate_handler![
            get_snapshot,
            refresh,
            engine_start,
            engine_stop,
            container_action,
            set_restart_policy,
            container_env,
            container_inspect,
            logs_follow,
            logs_stop,
            open_shell,
            list_images,
            remove_image,
            pull_image,
            list_volumes,
            list_networks,
            prune,
            install_portainer,
            open_url,
            get_settings,
            save_settings,
            colima_profiles,
            app_info,
            set_autostart,
            quit_app,
        ])
        .run(tauri::generate_context!())
        .expect("error while running ColimaBar");
}
