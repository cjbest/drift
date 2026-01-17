use tauri::menu::{Menu, MenuItem, Submenu, PredefinedMenuItem};
use tauri::Emitter;

#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
  tauri::Builder::default()
    .plugin(tauri_plugin_fs::init())
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

      let menu = Menu::with_items(app, &[&app_menu, &file_menu, &edit_menu])?;
      app.set_menu(menu)?;

      Ok(())
    })
    .on_menu_event(|app, event| {
      match event.id().as_ref() {
        "new_note" => { let _ = app.emit("menu-new-note", ()); }
        "new_window" => { let _ = app.emit("menu-new-window", ()); }
        "close_window" => { let _ = app.emit("menu-close-window", ()); }
        "open_note" => { let _ = app.emit("menu-open-note", ()); }
        _ => {}
      }
    })
    .run(tauri::generate_context!())
    .expect("error while running tauri application");
}
