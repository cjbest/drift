mod notebook;
mod notebook_location;
mod recent_folders;
use notebook::*;
use std::{
    collections::{HashMap, HashSet},
    path::PathBuf,
    sync::{
        atomic::{AtomicBool, Ordering},
        Mutex,
    },
};
use tauri::menu::{Menu, MenuItem, PredefinedMenuItem, Submenu};
use tauri::{Emitter, Manager, State};
use tauri_plugin_shell::ShellExt;
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
    notebook_selection: Mutex<Option<notebook_location::Selection>>,
    choosing_notebook: AtomicBool,
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
    prepare_quit(app, None);
}
fn prepare_quit(app: &tauri::AppHandle, selection: Option<notebook_location::Selection>) {
    lifecycle_trace(app, "quit-requested");
    let state = app.state::<Windows>();
    let mut waiting = state.quitting.lock().unwrap();
    if waiting.is_some() {
        if selection.is_some() {
            state.choosing_notebook.store(false, Ordering::SeqCst);
        }
        return;
    }
    // Claim the folder switch and its save-before-quit request together. A
    // normal Quit must not interleave between these two state changes.
    *state.notebook_selection.lock().unwrap() = selection;
    let labels: HashSet<_> = app.webview_windows().keys().cloned().collect();
    let complete = labels.is_empty();
    *waiting = Some(labels);
    if complete {
        drop(waiting);
        finish_quit(app);
        return;
    }
    drop(waiting);
    let _ = app.emit("prepare-quit", ());
}
fn acknowledge_quit(label: &str, app: &tauri::AppHandle) {
    let state = app.state::<Windows>();
    let complete = {
        let mut waiting = state.quitting.lock().unwrap();
        waiting
            .as_mut()
            .is_some_and(|labels| labels.remove(label) && labels.is_empty())
    };
    if complete {
        finish_quit(app);
    }
}
fn finish_quit(app: &tauri::AppHandle) {
    let state = app.state::<Windows>();
    let selection = state.notebook_selection.lock().unwrap().take();
    let switching = selection.is_some();
    if let Some(selection) = selection {
        if let Err(error) = selection.commit() {
            *state.quitting.lock().unwrap() = None;
            state.choosing_notebook.store(false, Ordering::SeqCst);
            let _ = app.emit("quit-cancelled", ());
            let _ = app.emit(
                "notebook-switch-failed",
                format!("Could not change notebooks. Your current notebook is still open: {error}"),
            );
            return;
        }
    }
    state.exit.store(true, Ordering::SeqCst);
    // All drafts are safe. Remove the windows before WebKit tears down so
    // its empty background cannot flash during shutdown.
    for window in app.webview_windows().values() {
        let _ = window.hide();
    }
    if switching {
        app.request_restart();
    } else {
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
    let mut waiting = state.quitting.lock().unwrap();
    *waiting = None;
    *state.notebook_selection.lock().unwrap() = None;
    state.choosing_notebook.store(false, Ordering::SeqCst);
    drop(waiting);
    let _ = app.emit("quit-cancelled", ());
}
fn open_notebook_folder(app: &tauri::AppHandle, path: PathBuf) {
    if path == app.state::<Notebook>().root {
        app.state::<Windows>()
            .choosing_notebook
            .store(false, Ordering::SeqCst);
        let _ = app.emit("notebook-access-granted", ());
        return;
    }
    let handle = app.clone();
    // Folder providers and disk access can be slow; keep them off the UI thread.
    tauri::async_runtime::spawn_blocking(move || {
        let selection = handle
            .path()
            .app_data_dir()
            .map_err(|e| e.to_string())
            .and_then(|data| notebook_location::Selection::prepare(&data, &path));
        match selection {
            Ok(selection) => {
                prepare_quit(&handle, Some(selection));
            }
            Err(error) => {
                handle
                    .state::<Windows>()
                    .choosing_notebook
                    .store(false, Ordering::SeqCst);
                let _ = handle.emit(
                    "notebook-switch-failed",
                    format!("Could not open this folder: {error} Use File → Change Folder → Choose Folder… to locate it or allow access."),
                );
            }
        }
    });
}
fn choose_notebook(app: &tauri::AppHandle, directory: Option<PathBuf>) {
    #[cfg(target_os = "macos")]
    {
        // Development must never redirect the copied notebook to real notes.
        if std::env::var("DRIFT_NOTEBOOK_MODE").as_deref() == Ok("preview")
            || app.state::<Windows>().quitting.lock().unwrap().is_some()
            || app
                .state::<Windows>()
                .choosing_notebook
                .swap(true, Ordering::SeqCst)
        {
            return;
        }
        if let Some(directory) = directory {
            open_notebook_folder(app, directory);
            return;
        }
        let root = app.state::<Notebook>().root.clone();
        let handle = app.clone();
        if let Err(error) = app.run_on_main_thread(move || {
            extern "C" {
                fn drift_choose_notebook(path: *const std::ffi::c_char) -> *mut std::ffi::c_char;
                fn drift_free_notebook_path(path: *mut std::ffi::c_char);
            }
            let Ok(current) = std::ffi::CString::new(root.to_string_lossy().as_bytes()) else {
                handle
                    .state::<Windows>()
                    .choosing_notebook
                    .store(false, Ordering::SeqCst);
                return;
            };
            let selected = unsafe { drift_choose_notebook(current.as_ptr()) };
            if selected.is_null() {
                handle
                    .state::<Windows>()
                    .choosing_notebook
                    .store(false, Ordering::SeqCst);
                return;
            }
            let path = unsafe {
                std::ffi::CStr::from_ptr(selected)
                    .to_string_lossy()
                    .into_owned()
            };
            unsafe { drift_free_notebook_path(selected) };
            open_notebook_folder(&handle, PathBuf::from(path));
        }) {
            app.state::<Windows>()
                .choosing_notebook
                .store(false, Ordering::SeqCst);
            let _ = app.emit(
                "notebook-switch-failed",
                format!("Could not open the folder chooser: {error}"),
            );
        }
    }
    #[cfg(not(target_os = "macos"))]
    let _ = (app, directory);
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
            initialize_notebook,
            initial_note_opened,
            list_notes,
            read_note,
            save_note,
            claim_note,
            window_for_note,
            focus_note_window,
            quit_ready,
            cancel_quit
        ])
        .setup(|app| {
            let data = app.path().app_data_dir()?;
            let preview = std::env::var("DRIFT_NOTEBOOK_MODE").as_deref() == Ok("preview");
            // Native fresh-install QA may substitute disposable Documents only
            // in the separately identified QA app; production ignores overrides.
            let documents = if app.config().identifier == "com.drift.release-qa" {
                std::env::var_os("DRIFT_QA_DOCUMENTS_DIR")
                    .map(std::path::PathBuf::from)
                    .map(Ok)
                    .unwrap_or_else(|| app.path().document_dir())?
            } else {
                app.path().document_dir()?
            };
            let store = notebook_location::load(&data, &documents, preview)
                .map_err(std::io::Error::other)?;
            if std::env::var_os("DRIFT_PROFILE").is_some() {
                eprintln!(
                    "drift-notebook configured root={} data={} preview={}",
                    store.root.display(),
                    store.data.display(),
                    std::env::var("DRIFT_NOTEBOOK_MODE").as_deref() == Ok("preview")
                );
            }
            let folders = notebook_location::folders(&data, &store.root, preview)
                .map_err(std::io::Error::other)?;
            let change_folder = recent_folders::menu(app, folders, preview)?;
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
                    &item("check-for-updates", "Check for Updates…", None)?,
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
                    &PredefinedMenuItem::separator(app)?,
                    &change_folder,
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
            #[allow(deprecated)] // Reuse the shell plugin that already opens note links.
            "check-for-updates" => {
                if let Err(error) = app.shell().open("https://drift.christopher.best/", None) {
                    eprintln!("Could not open the Drift website: {error}");
                }
            }
            "choose-notebook" => choose_notebook(app, None),
            id if id.starts_with("recent-folder-") => {
                let directory = app.state::<recent_folders::RecentFolders>().directory(id);
                if let Some(directory) = directory {
                    choose_notebook(app, Some(directory));
                }
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
