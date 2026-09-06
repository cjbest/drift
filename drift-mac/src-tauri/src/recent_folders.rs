use std::path::{Path, PathBuf};
use tauri::{
    menu::{CheckMenuItem, MenuItem, PredefinedMenuItem, Submenu},
    Manager,
};

pub struct RecentFolders(Vec<PathBuf>);

impl RecentFolders {
    pub fn directory(&self, id: &str) -> Option<PathBuf> {
        let index: usize = id.strip_prefix("recent-folder-")?.parse().ok()?;
        // The first entry is the current folder, displayed as a disabled checkmark.
        (index > 0).then(|| self.0.get(index).cloned()).flatten()
    }
}

pub fn menu(
    app: &tauri::App,
    directories: Vec<PathBuf>,
    preview: bool,
) -> tauri::Result<Submenu<tauri::Wry>> {
    let submenu = Submenu::new(app, "Change Folder", !preview)?;
    let home = app.path().home_dir().ok();
    for (index, label) in labels(&directories, home.as_deref()).iter().enumerate() {
        let id = format!("recent-folder-{index}");
        let label = label.replace('&', "&&");
        if index == 0 {
            submenu.append(&CheckMenuItem::with_id(
                app,
                id,
                label,
                false,
                true,
                None::<&str>,
            )?)?;
        } else {
            submenu.append(&MenuItem::with_id(app, id, label, !preview, None::<&str>)?)?;
        }
    }
    submenu.append(&PredefinedMenuItem::separator(app)?)?;
    submenu.append(&MenuItem::with_id(
        app,
        "choose-notebook",
        "Choose Folder…",
        !preview,
        None::<&str>,
    )?)?;
    app.manage(RecentFolders(directories));
    Ok(submenu)
}

fn labels(directories: &[PathBuf], home: Option<&Path>) -> Vec<String> {
    directories
        .iter()
        .map(|directory| {
            let name = directory.file_name();
            if let Some(name) = name {
                if directories
                    .iter()
                    .filter(|other| other.file_name() == Some(name))
                    .count()
                    == 1
                {
                    return name.to_string_lossy().into_owned();
                }
            }
            // Same-named folders need enough context to choose the right one.
            // Use stored paths only; querying a cloud folder can block the menu.
            match home.and_then(|home| directory.strip_prefix(home).ok()) {
                Some(relative) => Path::new("~").join(relative).to_string_lossy().into_owned(),
                None => directory.to_string_lossy().into_owned(),
            }
        })
        .collect()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn same_named_folders_are_distinguishable_without_accessing_them() {
        let paths = [
            "/Users/writer/Work/Notes",
            "/Users/writer/Personal/Notes",
            "/Volumes/Archive",
        ]
        .map(PathBuf::from);
        assert_eq!(
            labels(&paths, Some(Path::new("/Users/writer"))),
            ["~/Work/Notes", "~/Personal/Notes", "Archive"]
        );
        assert_eq!(labels(&[PathBuf::from("/")], None), ["/"]);
    }

    #[test]
    fn menu_ids_only_resolve_known_noncurrent_folders() {
        let folders = RecentFolders(vec!["/Current".into(), "/Previous".into()]);
        assert_eq!(
            folders.directory("recent-folder-1"),
            Some("/Previous".into())
        );
        for id in [
            "recent-folder-0",
            "recent-folder-2",
            "recent-folder-../Other",
            "choose-notebook",
        ] {
            assert_eq!(folders.directory(id), None);
        }
    }
}
