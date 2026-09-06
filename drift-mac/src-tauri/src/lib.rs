mod notebook;
use notebook::*;
use std::{
    collections::{HashMap, HashSet},
    sync::{
        atomic::{AtomicBool, Ordering},
        Mutex,
    },
};
use tauri::menu::{Menu, MenuItem, PredefinedMenuItem, Submenu};
use tauri::{Emitter, Manager, State};
struct LifecycleTiming {
    started: std::time::Instant,
    enabled: bool,
}
fn lifecycle_trace(app: &tauri::AppHandle, event: &str) {
    let timing = app.state::<LifecycleTiming>();
    if timing.enabled {
        eprintln!(
            "drift-lifecycle {} {:.1}ms",
            event,
            timing.started.elapsed().as_secs_f64() * 1000.
        );
    }
}
#[tauri::command]
fn window_ready(window: tauri::WebviewWindow, dark: bool) -> Result<bool, String> {
    let app = window.app_handle();
    lifecycle_trace(app, "window-ready");
    // A quit request can precede JavaScript's event registration. Replay it now
    // that the frontend has restored its draft and installed its save handler.
    if app
        .state::<Windows>()
        .quitting
        .lock()
        .unwrap()
        .as_ref()
        .is_some_and(|labels| labels.contains(window.label()))
    {
        window.emit("prepare-quit", ()).map_err(|e| e.to_string())?;
        return Ok(false);
    }
    let color = if dark {
        tauri::window::Color(33, 31, 27, 255)
    } else {
        tauri::window::Color(250, 247, 240, 255)
    };
    window
        .set_background_color(Some(color))
        .map_err(|e| e.to_string())?;
    window.show().map_err(|e| e.to_string())?;
    window.set_focus().map_err(|e| e.to_string())?;
    lifecycle_trace(app, "window-shown");
    Ok(true)
}
#[derive(Default)]
struct Windows {
    files: Mutex<HashMap<String, String>>,
    quitting: Mutex<Option<HashSet<String>>>,
    exit: AtomicBool,
}
#[tauri::command]
fn claim_note(path: Option<String>, label: String, state: State<Windows>) -> Result<(), String> {
    let mut files = state.files.lock().map_err(|e| e.to_string())?;
    files.retain(|_, v| v != &label);
    if let Some(path) = path {
        files.insert(path, label);
    }
    Ok(())
}
#[tauri::command]
fn window_for_note(path: String, app: tauri::AppHandle, state: State<Windows>) -> Option<String> {
    state
        .files
        .lock()
        .ok()?
        .get(&path)
        .filter(|label| app.get_webview_window(label).is_some())
        .cloned()
}
#[tauri::command]
fn focus_note_window(label: String, app: tauri::AppHandle) -> Result<(), String> {
    if let Some(w) = app.get_webview_window(&label) {
        let _ = w.unminimize();
        w.set_focus().map_err(|e| e.to_string())?;
    }
    Ok(())
}
fn begin_quit(app: &tauri::AppHandle) {
    lifecycle_trace(app, "quit-requested");
    let state = app.state::<Windows>();
    let mut waiting = state.quitting.lock().unwrap();
    if waiting.is_some() {
        return;
    }
    let labels: HashSet<_> = app.webview_windows().keys().cloned().collect();
    if labels.is_empty() {
        state.exit.store(true, Ordering::SeqCst);
        app.exit(0);
        return;
    }
    *waiting = Some(labels);
    drop(waiting);
    let _ = app.emit("prepare-quit", ());
}
fn acknowledge_quit(label: &str, app: &tauri::AppHandle) {
    let state = app.state::<Windows>();
    let complete = {
        let mut waiting = state.quitting.lock().unwrap();
        waiting.as_mut().is_some_and(|labels| {
            labels.remove(label);
            labels.is_empty()
        })
    };
    if complete {
        state.exit.store(true, Ordering::SeqCst);
        // All drafts are safe. Remove the windows before WebKit tears down so
        // its empty background cannot flash during shutdown.
        for window in app.webview_windows().values() {
            let _ = window.hide();
        }
        app.exit(0);
    }
}
#[tauri::command]
fn quit_ready(label: String, app: tauri::AppHandle) {
    lifecycle_trace(&app, "quit-saved");
    acknowledge_quit(&label, &app);
}
#[tauri::command]
fn cancel_quit(app: tauri::AppHandle, state: State<Windows>) {
    *state.quitting.lock().unwrap() = None;
    let _ = app.emit("quit-cancelled", ());
}
fn allow_notebook_access(app: &tauri::AppHandle) {
    #[cfg(target_os = "macos")]
    {
        let root = app.state::<Notebook>().root.clone();
        let handle = app.clone();
        let _ = app.run_on_main_thread(move || {
            extern "C" {
                fn drift_allow_notebook_access(path: *const std::ffi::c_char) -> bool;
            }
            if let Ok(path) = std::ffi::CString::new(root.to_string_lossy().as_bytes()) {
                if unsafe { drift_allow_notebook_access(path.as_ptr()) } {
                    let _ = handle.emit("notebook-access-granted", ());
                }
            }
        });
    }
    #[cfg(not(target_os = "macos"))]
    let _ = app;
}
#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    let timing = LifecycleTiming {
        started: std::time::Instant::now(),
        enabled: std::env::var_os("DRIFT_PROFILE").is_some(),
    };
    let app = tauri::Builder::default()
        .manage(timing)
        .plugin(tauri_plugin_shell::init())
        .manage(Windows::default())
        .invoke_handler(tauri::generate_handler![
            window_ready,
            notebook_info,
            list_notes,
            read_note,
            save_note,
            reveal_notebook,
            reveal_history,
            claim_note,
            window_for_note,
            focus_note_window,
            quit_ready,
            cancel_quit
        ])
        .setup(|app| {
            let data = app.path().app_data_dir()?;
            // Only an explicitly configured notebook can leave the app-owned test folder.
            let mut store = Notebook::new(data.clone()).map_err(std::io::Error::other)?;
            let config = data.join("notebook-location.json");
            if config.exists() && std::env::var("DRIFT_NOTEBOOK_MODE").as_deref() != Ok("preview") {
                let path: String = serde_json::from_slice(&std::fs::read(config)?)?;
                let root = std::path::PathBuf::from(path);
                if !root.is_absolute() {
                    return Err("Notebook location must be an absolute folder path".into());
                }
                // Access to Documents can require consent. Defer filesystem checks
                // to notebook commands so a refusal leaves a usable retry UI.
                store = Notebook::new(data.join("Live")).map_err(std::io::Error::other)?;
                store.root = root;
            }
            if std::env::var_os("DRIFT_PROFILE").is_some() {
                eprintln!(
                    "drift-notebook configured root={} data={} preview={}",
                    store.root.display(),
                    store.data.display(),
                    std::env::var("DRIFT_NOTEBOOK_MODE").as_deref() == Ok("preview")
                );
            }
            app.manage(store);
            let item = |id: &str, title: &str, key: Option<&str>| {
                MenuItem::with_id(app, id, title, true, key)
            };
            let name = app.package_info().name.clone();
            let app_menu = Submenu::with_items(
                app,
                &name,
                true,
                &[
                    &PredefinedMenuItem::about(app, None, None)?,
                    &PredefinedMenuItem::separator(app)?,
                    &PredefinedMenuItem::services(app, None)?,
                    &PredefinedMenuItem::separator(app)?,
                    &PredefinedMenuItem::hide(app, None)?,
                    &PredefinedMenuItem::hide_others(app, None)?,
                    &PredefinedMenuItem::show_all(app, None)?,
                    &PredefinedMenuItem::separator(app)?,
                    &item("quit", &format!("Quit {name}"), Some("CmdOrCtrl+Q"))?,
                ],
            )?;
            let file = Submenu::with_items(
                app,
                "File",
                true,
                &[
                    &item("new-note", "New Note", Some("CmdOrCtrl+N"))?,
                    &item("new-window", "New Window", Some("CmdOrCtrl+Shift+N"))?,
                    &item("open-note", "Open Note…", Some("CmdOrCtrl+P"))?,
                    &item("save", "Save", Some("CmdOrCtrl+S"))?,
                    &PredefinedMenuItem::separator(app)?,
                    &item("reveal-notebook", "Show Notebook in Finder", None)?,
                    &item("allow-notebook-access", "Allow Notebook Access…", None)?,
                    &item("reveal-history", "Saved History…", None)?,
                    &PredefinedMenuItem::separator(app)?,
                    &item("close-window", "Close Window", Some("CmdOrCtrl+W"))?,
                ],
            )?;
            let edit = Submenu::with_items(
                app,
                "Edit",
                true,
                &[
                    &PredefinedMenuItem::undo(app, None)?,
                    &PredefinedMenuItem::redo(app, None)?,
                    &PredefinedMenuItem::separator(app)?,
                    &PredefinedMenuItem::cut(app, None)?,
                    &PredefinedMenuItem::copy(app, None)?,
                    &PredefinedMenuItem::paste(app, None)?,
                    &PredefinedMenuItem::select_all(app, None)?,
                    &item("select-line", "Select Line", Some("CmdOrCtrl+L"))?,
                    &PredefinedMenuItem::separator(app)?,
                    &item("find", "Find in Note…", Some("CmdOrCtrl+F"))?,
                    &item("find-next", "Find Next", Some("CmdOrCtrl+G"))?,
                    &item("find-previous", "Find Previous", Some("CmdOrCtrl+Shift+G"))?,
                ],
            )?;
            let format = Submenu::with_items(
                app,
                "Format",
                true,
                &[
                    &item("bullet", "Toggle Bullet List", Some("CmdOrCtrl+Shift+8"))?,
                    &item("checklist", "Toggle Checklist", Some("CmdOrCtrl+Shift+L"))?,
                    &item("check", "Check / Uncheck", Some("CmdOrCtrl+Enter"))?,
                    &PredefinedMenuItem::separator(app)?,
                    &item("indent", "Indent (Tab)", None)?,
                    &item("outdent", "Outdent (Shift+Tab)", None)?,
                ],
            )?;
            let view = Submenu::with_items(
                app,
                "View",
                true,
                &[
                    &item("cycle-theme", "Toggle Light / Dark", Some("CmdOrCtrl+D"))?,
                    &PredefinedMenuItem::separator(app)?,
                    &item("theme-system", "Follow System", Some("CmdOrCtrl+Shift+D"))?,
                    &item("theme-light", "Light", None)?,
                    &item("theme-dark", "Dark", None)?,
                ],
            )?;
            let window = Submenu::with_items(
                app,
                "Window",
                true,
                &[
                    &PredefinedMenuItem::minimize(app, None)?,
                    &PredefinedMenuItem::maximize(app, None)?,
                ],
            )?;
            let help = Submenu::with_items(
                app,
                "Help",
                true,
                &[&item(
                    "shortcuts",
                    "Keyboard Shortcuts…",
                    Some("CmdOrCtrl+Slash"),
                )?],
            )?;
            app.set_menu(Menu::with_items(
                app,
                &[&app_menu, &file, &edit, &format, &view, &window, &help],
            )?)?;
            #[cfg(target_os = "macos")]
            unsafe {
                extern "C" {
                    fn drift_use_return_key();
                }
                drift_use_return_key();
            }
            Ok(())
        })
        .on_menu_event(|app, event| match event.id().as_ref() {
            "quit" => begin_quit(app),
            "allow-notebook-access" => allow_notebook_access(app),
            "reveal-notebook" | "reveal-history" => {
                let store = app.state::<Notebook>();
                let path = if event.id().as_ref() == "reveal-notebook" {
                    store.root.clone()
                } else {
                    store.data.join("History")
                };
                let _ = std::process::Command::new("open").arg(path).spawn();
            }
            id => {
                if let Some(w) = app
                    .webview_windows()
                    .values()
                    .find(|w| w.is_focused().unwrap_or(false))
                {
                    let _ = w.emit(&format!("menu-{id}"), ());
                }
            }
        })
        .on_window_event(|w, e| {
            if matches!(e, tauri::WindowEvent::Destroyed) {
                let state = w.state::<Windows>();
                state
                    .files
                    .lock()
                    .unwrap()
                    .retain(|_, label| label != w.label());
                acknowledge_quit(w.label(), w.app_handle());
            }
        })
        .build(tauri::generate_context!())
        .expect("Could not start Drift");
    app.run(|app, event| match event {
        tauri::RunEvent::ExitRequested { api, .. } => {
            if !app.state::<Windows>().exit.load(Ordering::SeqCst) {
                api.prevent_exit();
                begin_quit(app);
            }
        }
        tauri::RunEvent::Reopen {
            has_visible_windows: false,
            ..
        } => {
            let _ = tauri::WebviewWindowBuilder::new(
                app,
                "main",
                tauri::WebviewUrl::App("index.html".into()),
            )
            .title(&app.package_info().name)
            .visible(false)
            .inner_size(900., 700.)
            .min_inner_size(400., 300.)
            .title_bar_style(tauri::TitleBarStyle::Overlay)
            .hidden_title(true)
            .build();
        }
        tauri::RunEvent::Exit => lifecycle_trace(app, "exit"),
        _ => {}
    });
}
