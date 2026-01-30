use tauri::menu::{Menu, MenuItem, Submenu, PredefinedMenuItem};
use tauri::Emitter;

#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
  tauri::Builder::default()
    .plugin(tauri_plugin_fs::init())
    .plugin(tauri_plugin_shell::init())
    .setup(|app| {
      if cfg!(debug_assertions) {
        app.handle().plugin(
          tauri_plugin_log::Builder::default()
            .level(log::LevelFilter::Info)
            .build(),
        )?;
      }

      // Build menus
      let new_note = MenuItem::with_id(app, "new_note", "New Note", true, Some("CmdOrCtrl+N"))?;
      let new_window = MenuItem::with_id(app, "new_window", "New Window", true, Some("CmdOrCtrl+Shift+N"))?;
      let close_window = MenuItem::with_id(app, "close_window", "Close Window", true, Some("CmdOrCtrl+W"))?;
      let open_note = MenuItem::with_id(app, "open_note", "Open Note...", true, Some("CmdOrCtrl+P"))?;

      let file_menu = Submenu::with_items(
        app,
        "File",
        true,
        &[&new_note, &new_window, &close_window, &PredefinedMenuItem::separator(app)?, &open_note],
      )?;

      let app_menu = Submenu::with_items(
        app,
        "Drift",
        true,
        &[
          &PredefinedMenuItem::about(app, Some("About Drift"), None)?,
          &PredefinedMenuItem::separator(app)?,
          &PredefinedMenuItem::services(app, None)?,
          &PredefinedMenuItem::separator(app)?,
          &PredefinedMenuItem::hide(app, None)?,
          &PredefinedMenuItem::hide_others(app, None)?,
          &PredefinedMenuItem::show_all(app, None)?,
          &PredefinedMenuItem::separator(app)?,
          &PredefinedMenuItem::quit(app, None)?,
        ],
      )?;

      let edit_menu = Submenu::with_items(
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
        ],
      )?;

      let cycle_theme = MenuItem::with_id(app, "cycle_theme", "Toggle Theme", true, Some("CmdOrCtrl+D"))?;
      let theme_system = MenuItem::with_id(app, "theme_system", "System", true, None::<&str>)?;
      let theme_light = MenuItem::with_id(app, "theme_light", "Light", true, None::<&str>)?;
      let theme_dark = MenuItem::with_id(app, "theme_dark", "Dark", true, None::<&str>)?;
      let toggle_explosions = MenuItem::with_id(app, "toggle_explosions", "Toggle Explosions", true, Some("CmdOrCtrl+E"))?;

      let view_menu = Submenu::with_items(
        app,
        "View",
        true,
        &[
          &cycle_theme,
          &PredefinedMenuItem::separator(app)?,
          &theme_system,
          &theme_light,
          &theme_dark,
          &PredefinedMenuItem::separator(app)?,
          &toggle_explosions,
        ],
      )?;

      let menu = Menu::with_items(app, &[&app_menu, &file_menu, &edit_menu, &view_menu])?;
      app.set_menu(menu)?;

      Ok(())
    })
    .on_menu_event(|app, event| {
      match event.id().as_ref() {
        "new_note" => { let _ = app.emit("menu-new-note", ()); }
        "new_window" => { let _ = app.emit("menu-new-window", ()); }
        "close_window" => { let _ = app.emit("menu-close-window", ()); }
        "open_note" => { let _ = app.emit("menu-open-note", ()); }
        "cycle_theme" => { let _ = app.emit("menu-cycle-theme", ()); }
        "theme_system" => { let _ = app.emit("menu-theme-system", ()); }
        "theme_light" => { let _ = app.emit("menu-theme-light", ()); }
        "theme_dark" => { let _ = app.emit("menu-theme-dark", ()); }
        "toggle_explosions" => { let _ = app.emit("menu-toggle-explosions", ()); }
        _ => {}
      }
    })
    .run(tauri::generate_context!())
    .expect("error while running tauri application");
}
