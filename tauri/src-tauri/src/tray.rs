//! System tray icon + menu.
//!
//! Linux (AppIndicator) only supports the menu, not clicks, so every action is
//! reachable from the menu. On Windows a left click toggles the window.

use crate::breathing;
use crate::model::{Backend, EngineStatus, Settings, Snapshot};
use crate::{engine_lifecycle, show_main_window, Shared};
use std::sync::{Arc, Mutex, OnceLock};
use std::time::Duration;
use tauri::image::Image;
use tauri::menu::{Menu, MenuItem, PredefinedMenuItem};
use tauri::tray::{MouseButton, MouseButtonState, TrayIconBuilder, TrayIconEvent};
use tauri::{AppHandle, Emitter, Manager, Wry};

const TRAY_ID: &str = "colimabar";

static ICON_RUNNING: &[u8] = include_bytes!("../icons/tray/running.png");
static ICON_TRANSITION: &[u8] = include_bytes!("../icons/tray/transitioning.png");
static ICON_STOPPED: &[u8] = include_bytes!("../icons/tray/stopped.png");

/// Frames of one breath, shown in a loop while Colima is transitioning.
const FRAME_COUNT: u32 = 8;
/// Time between two frames (one breath = `FRAME_COUNT` frames, ≈ 200 ms each).
const FRAME_STEP_SECS: f64 = breathing::PERIOD_SECS / FRAME_COUNT as f64;

/// Breathing animator state; at most one animator thread is live at a time.
struct Animator {
    /// Bumped on every start and stop: a thread whose generation no longer
    /// matches exits, and its pending frames are dropped.
    generation: u64,
    active: bool,
}

static ANIMATOR: Mutex<Animator> = Mutex::new(Animator {
    generation: 0,
    active: false,
});

/// Handles to the menu items whose text / visibility changes with the state.
pub struct TrayItems {
    status: MenuItem<Wry>,
    usage: MenuItem<Wry>,
    start: MenuItem<Wry>,
    stop: MenuItem<Wry>,
    containers: MenuItem<Wry>,
    portainer: MenuItem<Wry>,
    prune: MenuItem<Wry>,
    last_icon: Mutex<&'static str>,
}

type ItemsState = Mutex<Option<TrayItems>>;

fn build_menu(app: &AppHandle, s: &Settings) -> tauri::Result<(Menu<Wry>, TrayItems)> {
    let status = MenuItem::with_id(app, "status", "Colima", false, None::<&str>)?;
    let usage = MenuItem::with_id(app, "usage", "", false, None::<&str>)?;
    let start = MenuItem::with_id(
        app,
        "start",
        s.t("Démarrer Colima", "Start Colima"),
        true,
        None::<&str>,
    )?;
    let stop = MenuItem::with_id(
        app,
        "stop",
        s.t("Arrêter Colima", "Stop Colima"),
        true,
        None::<&str>,
    )?;
    let containers = MenuItem::with_id(
        app,
        "open",
        s.t("Ouvrir ColimaBar", "Open ColimaBar"),
        true,
        None::<&str>,
    )?;
    let portainer = MenuItem::with_id(
        app,
        "portainer",
        s.t("Ouvrir Portainer", "Open Portainer"),
        true,
        None::<&str>,
    )?;
    let prune = MenuItem::with_id(
        app,
        "prune",
        s.t("Vider Docker…", "Prune Docker…"),
        true,
        None::<&str>,
    )?;
    let settings = MenuItem::with_id(
        app,
        "settings",
        s.t("Paramètres…", "Settings…"),
        true,
        None::<&str>,
    )?;
    let quit = MenuItem::with_id(app, "quit", s.t("Quitter", "Quit"), true, None::<&str>)?;

    let menu = Menu::with_items(
        app,
        &[
            &status,
            &usage,
            &PredefinedMenuItem::separator(app)?,
            &start,
            &stop,
            &PredefinedMenuItem::separator(app)?,
            &containers,
            &portainer,
            &prune,
            &PredefinedMenuItem::separator(app)?,
            &settings,
            &quit,
        ],
    )?;
    Ok((
        menu,
        TrayItems {
            status,
            usage,
            start,
            stop,
            containers,
            portainer,
            prune,
            last_icon: Mutex::new(""),
        },
    ))
}

pub fn create(app: &AppHandle, settings: &Settings) -> tauri::Result<()> {
    let (menu, items) = build_menu(app, settings)?;
    app.manage::<ItemsState>(Mutex::new(Some(items)));

    TrayIconBuilder::with_id(TRAY_ID)
        .icon(Image::from_bytes(ICON_STOPPED)?)
        .tooltip("ColimaBar")
        .menu(&menu)
        .show_menu_on_left_click(false)
        .on_menu_event(|app, event| on_menu(app, event.id().as_ref()))
        .on_tray_icon_event(|tray, event| {
            if let TrayIconEvent::Click {
                button: MouseButton::Left,
                button_state: MouseButtonState::Up,
                ..
            } = event
            {
                let app = tray.app_handle();
                match app.get_webview_window("main") {
                    Some(w)
                        if w.is_visible().unwrap_or(false) && w.is_focused().unwrap_or(false) =>
                    {
                        let _ = w.hide();
                    }
                    _ => show_main_window(app),
                }
            }
        })
        .build(app)?;
    Ok(())
}

/// Rebuilds the menu (language change).
pub fn rebuild(app: &AppHandle, settings: &Settings) {
    let Ok((menu, items)) = build_menu(app, settings) else {
        return;
    };
    if let Some(tray) = app.tray_by_id(TRAY_ID) {
        let _ = tray.set_menu(Some(menu));
    }
    if let Some(state) = app.try_state::<ItemsState>() {
        *state.lock().unwrap() = Some(items);
    }
    let snap = app.state::<Arc<Shared>>().snapshot.lock().unwrap().clone();
    update(app, settings, &snap);
}

fn on_menu(app: &AppHandle, id: &str) {
    let shared = app.state::<Arc<Shared>>().inner().clone();
    match id {
        "start" => engine_lifecycle(app, shared, true),
        "stop" => engine_lifecycle(app, shared, false),
        "open" => show_main_window(app),
        "portainer" => {
            let _ = tauri_plugin_opener::open_url("https://localhost:9443", None::<&str>);
        }
        "prune" => {
            show_main_window(app);
            let _ = app.emit("ui", "confirm-prune");
        }
        "settings" => {
            show_main_window(app);
            let _ = app.emit("ui", "settings");
        }
        "quit" => {
            if let Some(mut child) = shared.logs.lock().unwrap().take() {
                let _ = child.kill();
            }
            app.exit(0);
        }
        _ => {}
    }
}

fn format_bytes(b: f64) -> String {
    let gib = b / 1024f64.powi(3);
    if gib >= 1.0 {
        format!("{gib:.1} GB")
    } else {
        format!("{:.0} MB", b / 1024f64.powi(2))
    }
}

/// Applies a snapshot to the tray icon, tooltip and menu.
pub fn update(app: &AppHandle, s: &Settings, snap: &Snapshot) {
    let Some(state) = app.try_state::<ItemsState>() else {
        return;
    };
    let guard = state.lock().unwrap();
    let Some(items) = guard.as_ref() else { return };

    let colima = snap.backend == Backend::Colima;
    let engine_name = if colima { "Colima" } else { "Docker" };
    let running = snap.status == EngineStatus::Running;
    let (status_text, icon_key) = match &snap.status {
        EngineStatus::Running => (
            format!(
                "● {engine_name} : {}",
                s.t("en cours d'exécution", "running")
            ),
            "running",
        ),
        EngineStatus::Stopped => (
            format!("○ {engine_name} : {}", s.t("arrêté", "stopped")),
            "stopped",
        ),
        EngineStatus::Transitioning(m) => (format!("◐ {engine_name} : {m}"), "transitioning"),
        EngineStatus::Unavailable(_) => (
            format!("○ Docker : {}", s.t("indisponible", "unavailable")),
            "stopped",
        ),
    };
    let _ = items.status.set_text(&status_text);

    let usage = snap.usage.as_ref().filter(|_| running).map(|u| {
        format!(
            "CPU {:.1}% · RAM {} / {}",
            u.cpu_percent,
            format_bytes(u.mem_used_bytes),
            format_bytes(u.mem_total_bytes)
        )
    });
    let _ = items.usage.set_text(usage.unwrap_or_default());

    let transitioning = matches!(snap.status, EngineStatus::Transitioning(_));
    let _ = items
        .start
        .set_enabled(colima && !running && !transitioning);
    let _ = items.stop.set_enabled(colima && running && !transitioning);
    let _ = items.start.set_text(if colima {
        s.t("Démarrer Colima", "Start Colima")
    } else {
        s.t(
            "Démarrer Colima (non installé)",
            "Start Colima (not installed)",
        )
    });
    let _ = items.portainer.set_enabled(running && snap.portainer);
    let _ = items.prune.set_enabled(running);
    let total = snap.containers.len();
    let open_text = if running && total > 0 {
        format!("{}/{} containers…", snap.running_count(), total)
    } else {
        s.t("Ouvrir ColimaBar", "Open ColimaBar")
    };
    let _ = items.containers.set_text(open_text);

    if let Some(tray) = app.tray_by_id(TRAY_ID) {
        let _ = tray.set_tooltip(Some(format!("ColimaBar — {status_text}")));
        let mut last = items.last_icon.lock().unwrap();
        if icon_key == "transitioning" && start_breathing(app) {
            // The animator owns the icon until the transition ends: forget the
            // cached key so the static icon is applied again afterwards.
            *last = "";
        } else {
            stop_breathing();
            if *last != icon_key {
                let bytes = match icon_key {
                    "running" => ICON_RUNNING,
                    "transitioning" => ICON_TRANSITION,
                    _ => ICON_STOPPED,
                };
                if let Ok(img) = Image::from_bytes(bytes) {
                    let _ = tray.set_icon(Some(img));
                    *last = icon_key;
                }
            }
        }
    }
}

/// `ICON_TRANSITION` with its opacity following one breath, decoded once.
/// Empty if the icon cannot be decoded (the static icon is used instead).
fn breathing_frames() -> &'static [Image<'static>] {
    static FRAMES: OnceLock<Vec<Image<'static>>> = OnceLock::new();
    FRAMES.get_or_init(|| {
        let Ok(base) = Image::from_bytes(ICON_TRANSITION) else {
            return Vec::new();
        };
        (0..FRAME_COUNT)
            .map(|i| {
                let alpha = breathing::breathing_alpha(f64::from(i) * FRAME_STEP_SECS);
                let rgba = breathing::scale_alpha(base.rgba(), alpha);
                Image::new_owned(rgba, base.width(), base.height())
            })
            .collect()
    })
}

/// Starts the animator unless one is already live. Returns `false` when no
/// animation is available, so the caller falls back to the static icon.
fn start_breathing(app: &AppHandle) -> bool {
    let frames = breathing_frames();
    if frames.is_empty() {
        return false;
    }
    let mut anim = ANIMATOR.lock().unwrap();
    if !anim.active {
        anim.active = true;
        anim.generation = anim.generation.wrapping_add(1);
        let generation = anim.generation;
        let app = app.clone();
        std::thread::spawn(move || breathe(&app, generation, frames));
    }
    true
}

/// Stops the live animator, if any. Must run before the static icon is set so
/// that no frame still queued on the main thread can overwrite it.
fn stop_breathing() {
    let mut anim = ANIMATOR.lock().unwrap();
    if anim.active {
        anim.active = false;
        anim.generation = anim.generation.wrapping_add(1);
    }
}

fn is_current(generation: u64) -> bool {
    ANIMATOR.lock().unwrap().generation == generation
}

/// Animator thread: pushes one frame per step until its generation is stale.
/// Frames are applied on the main thread, where the generation is checked
/// again so a frame queued before a stop is dropped instead of shown.
fn breathe(app: &AppHandle, generation: u64, frames: &'static [Image<'static>]) {
    let step = Duration::from_secs_f64(FRAME_STEP_SECS);
    for frame in frames.iter().cycle() {
        if !is_current(generation) {
            return;
        }
        let handle = app.clone();
        let frame = frame.clone();
        let queued = app.run_on_main_thread(move || {
            if !is_current(generation) {
                return;
            }
            if let Some(tray) = handle.tray_by_id(TRAY_ID) {
                let _ = tray.set_icon(Some(frame));
            }
        });
        if queued.is_err() {
            // Event loop gone (app exiting): release the slot and stop.
            let mut anim = ANIMATOR.lock().unwrap();
            if anim.generation == generation {
                anim.active = false;
            }
            return;
        }
        std::thread::sleep(step);
    }
}
