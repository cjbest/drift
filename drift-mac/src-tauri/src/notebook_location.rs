//! Persist notebook choices without ever moving notes or sharing recovery data.
use crate::notebook::{atomic, Notebook};
use serde::{Deserialize, Serialize};
use std::{
    collections::BTreeMap,
    fs,
    path::{Path, PathBuf},
    sync::Mutex,
};
use uuid::Uuid;
static CONFIG_WRITES: Mutex<()> = Mutex::new(());

#[derive(Serialize, Deserialize)]
#[serde(untagged)]
enum Location {
    Legacy(String),
    Selected {
        directory: String,
        notebooks: BTreeMap<String, String>,
        #[serde(
            default,
            rename = "recentDirectories",
            skip_serializing_if = "Vec::is_empty"
        )]
        recent_directories: Vec<String>,
        #[serde(
            default,
            rename = "createDirectory",
            skip_serializing_if = "std::ops::Not::not"
        )]
        create_directory: bool,
        #[serde(
            default,
            rename = "initialNote",
            skip_serializing_if = "Option::is_none"
        )]
        initial_note: Option<String>,
    },
}

fn read(data: &Path) -> Result<Option<Location>, String> {
    match fs::read(data.join("notebook-location.json")) {
        Ok(bytes) => serde_json::from_slice(&bytes)
            .map(Some)
            .map_err(|e| e.to_string()),
        Err(e) if e.kind() == std::io::ErrorKind::NotFound => Ok(None),
        Err(e) => Err(e.to_string()),
    }
}

fn legacy_notebook_exists(data: &Path) -> Result<bool, String> {
    let mut exists = false;
    for name in ["Notebook", "Recovery", "History"] {
        match fs::symlink_metadata(data.join(name)) {
            Ok(_) => exists = true,
            Err(e) if e.kind() == std::io::ErrorKind::NotFound => {}
            Err(e) => return Err(e.to_string()),
        }
    }
    Ok(exists)
}

fn selected_folders(
    directory: String,
    notebooks: &BTreeMap<String, String>,
    recent_directories: Vec<String>,
) -> Vec<String> {
    let previous = if recent_directories.is_empty() {
        // Older configurations retained recovery mappings but not visit order.
        notebooks.keys().cloned().collect()
    } else {
        recent_directories
    };
    std::iter::once(directory).chain(previous).collect()
}

fn distinct_folders(paths: impl IntoIterator<Item = PathBuf>) -> Vec<PathBuf> {
    let mut folders = Vec::new();
    for path in paths {
        // Compare stored paths without resolving symlinks or touching providers.
        if path.is_absolute() && !folders.contains(&path) {
            folders.push(path);
        }
    }
    folders
}

pub fn folders(data: &Path, current: &Path, preview: bool) -> Result<Vec<PathBuf>, String> {
    if preview {
        return Ok(vec![current.to_path_buf()]);
    }
    let previous = match read(data)? {
        Some(Location::Legacy(directory)) => vec![directory],
        Some(Location::Selected {
            directory,
            notebooks,
            recent_directories,
            ..
        }) => selected_folders(directory, &notebooks, recent_directories),
        None => Vec::new(),
    };
    Ok(distinct_folders(
        std::iter::once(current.to_path_buf()).chain(previous.into_iter().map(PathBuf::from)),
    ))
}

fn storage(
    data: &Path,
    directory: &str,
    notebooks: &BTreeMap<String, String>,
) -> Result<PathBuf, String> {
    if Path::new(directory) == data.join("Notebook") {
        return Ok(data.to_path_buf());
    }
    let relative = notebooks
        .get(directory)
        .ok_or("Notebook recovery location is missing")?;
    // Config is local, but it must never redirect recovery outside app data.
    if relative != "Live"
        && !relative
            .strip_prefix("Notebooks/")
            .is_some_and(|id| Uuid::parse_str(id).is_ok())
    {
        return Err("Invalid notebook recovery location".into());
    }
    Ok(data.join(relative))
}

pub fn load(data: &Path, documents: &Path, preview: bool) -> Result<Notebook, String> {
    if preview {
        return Notebook::new(data.to_path_buf());
    }
    let (directory, notebook_data, create_directory) = match read(data)? {
        None => {
            if legacy_notebook_exists(data)? {
                // Even an empty legacy notebook is an existing installation.
                return Notebook::new(data.to_path_buf());
            }
            for name in ["Live", "Notebooks"] {
                match fs::symlink_metadata(data.join(name)) {
                    Ok(_) => return Err("The notebook configuration is missing, but saved notebook data still exists. Restore notebook-location.json before opening Drift; the existing data has not been changed.".into()),
                    Err(e) if e.kind() == std::io::ErrorKind::NotFound => {},
                    Err(e) => return Err(e.to_string()),
                }
            }
            let directory = documents.join("Drift");
            if !directory.is_absolute() {
                return Err("Documents must be an absolute folder path".into());
            }
            let relative = format!("Notebooks/{}", Uuid::new_v4());
            let notebook_data = data.join(&relative);
            let mut notebook = Notebook::new(notebook_data)?;
            let directory_string = directory.to_string_lossy().into_owned();
            let config = Location::Selected {
                directory: directory_string.clone(),
                notebooks: BTreeMap::from([(directory_string, relative)]),
                recent_directories: Vec::new(),
                create_directory: true,
                initial_note: None,
            };
            atomic(
                &data.join("notebook-location.json"),
                &serde_json::to_vec_pretty(&config).map_err(|e| e.to_string())?,
            )?;
            notebook.root = directory;
            notebook.create_default_on_access(data.to_path_buf());
            return Ok(notebook);
        }
        Some(Location::Legacy(directory)) => (directory, data.join("Live"), false),
        Some(Location::Selected {
            directory,
            notebooks,
            create_directory,
            initial_note,
            ..
        }) => {
            let notebook_data = storage(data, &directory, &notebooks)?;
            (
                directory,
                notebook_data,
                create_directory || initial_note.is_some(),
            )
        }
    };
    let root = PathBuf::from(directory);
    if !root.is_absolute() {
        return Err("Notebook location must be an absolute folder path".into());
    }
    // Protected/provider folders may need consent. Defer reading notes to the
    // normal retryable commands; only app-owned recovery directories are created.
    let mut notebook = Notebook::new(notebook_data)?;
    notebook.root = root;
    if create_directory {
        notebook.create_default_on_access(data.to_path_buf());
    }
    Ok(notebook)
}

pub(crate) fn needs_default_creation(data: &Path, root: &Path) -> Result<bool, String> {
    Ok(
        matches!(read(data)?, Some(Location::Selected { directory, create_directory: true, .. }) if Path::new(&directory) == root),
    )
}

pub(crate) fn initial_note(data: &Path, root: &Path) -> Result<Option<String>, String> {
    match read(data)? {
        Some(Location::Selected {
            directory,
            initial_note,
            ..
        }) if Path::new(&directory) == root => Ok(initial_note),
        _ => Ok(None),
    }
}

pub(crate) fn complete_default_setup(
    data: &Path,
    root: &Path,
    initial_note: Option<String>,
) -> Result<(), String> {
    let _lock = CONFIG_WRITES.lock().map_err(|e| e.to_string())?;
    if let Some(Location::Selected {
        directory,
        notebooks,
        recent_directories,
        create_directory: true,
        ..
    }) = read(data)?
    {
        if Path::new(&directory) == root {
            let config = Location::Selected {
                directory,
                notebooks,
                recent_directories,
                create_directory: false,
                initial_note,
            };
            atomic(
                &data.join("notebook-location.json"),
                &serde_json::to_vec_pretty(&config).map_err(|e| e.to_string())?,
            )?;
        }
    }
    Ok(())
}

pub(crate) fn acknowledge_initial_note(data: &Path, root: &Path) -> Result<(), String> {
    let _lock = CONFIG_WRITES.lock().map_err(|e| e.to_string())?;
    if let Some(Location::Selected {
        directory,
        notebooks,
        recent_directories,
        create_directory,
        initial_note: Some(_),
    }) = read(data)?
    {
        if Path::new(&directory) == root {
            let config = Location::Selected {
                directory,
                notebooks,
                recent_directories,
                create_directory,
                initial_note: None,
            };
            atomic(
                &data.join("notebook-location.json"),
                &serde_json::to_vec_pretty(&config).map_err(|e| e.to_string())?,
            )?;
        }
    }
    Ok(())
}

pub struct Selection {
    config: PathBuf,
    contents: Vec<u8>,
}

impl Selection {
    pub fn prepare(data: &Path, directory: &Path) -> Result<Self, String> {
        if !directory.is_absolute() || !directory.is_dir() {
            return Err("Choose an existing folder for your notebook.".into());
        }
        // Validate access before asking any windows to leave their notes.
        fs::read_dir(directory).map_err(|e| format!("Could not read this folder: {e}"))?;
        let probe = directory.join(format!(".drift-access-{}", Uuid::new_v4()));
        let file = fs::OpenOptions::new()
            .create_new(true)
            .write(true)
            .open(&probe)
            .map_err(|e| format!("Drift needs a folder it can save notes in: {e}"))?;
        drop(file);
        fs::remove_file(probe).map_err(|e| e.to_string())?;

        let (mut notebooks, previous) = match read(data)? {
            Some(Location::Legacy(previous)) => (
                BTreeMap::from([(previous.clone(), "Live".into())]),
                vec![previous],
            ),
            Some(Location::Selected {
                directory,
                notebooks,
                recent_directories,
                ..
            }) => {
                let previous = selected_folders(directory, &notebooks, recent_directories);
                (notebooks, previous)
            }
            None => (
                BTreeMap::new(),
                if legacy_notebook_exists(data)? {
                    vec![data.join("Notebook").to_string_lossy().into_owned()]
                } else {
                    Vec::new()
                },
            ),
        };
        let recent_directories = distinct_folders(
            std::iter::once(directory.to_path_buf()).chain(previous.into_iter().map(PathBuf::from)),
        )
        .into_iter()
        .map(|path| path.to_string_lossy().into_owned())
        .collect();
        let directory = directory.to_string_lossy().into_owned();
        if Path::new(&directory) != data.join("Notebook") {
            notebooks
                .entry(directory.clone())
                .or_insert_with(|| format!("Notebooks/{}", Uuid::new_v4()));
        }
        // Fail here if local recovery storage is unavailable, before changing the
        // persisted choice or closing an editor.
        Notebook::new(storage(data, &directory, &notebooks)?)?;
        let contents = serde_json::to_vec_pretty(&Location::Selected {
            directory,
            notebooks,
            recent_directories,
            create_directory: false,
            initial_note: None,
        })
        .map_err(|e| e.to_string())?;
        Ok(Self {
            config: data.join("notebook-location.json"),
            contents,
        })
    }

    // Called only after every window has saved. A failed atomic write leaves the
    // previous choice intact and cancels the switch.
    pub fn commit(self) -> Result<(), String> {
        let _lock = CONFIG_WRITES.lock().map_err(|e| e.to_string())?;
        atomic(&self.config, &self.contents)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn fresh_location() -> (PathBuf, PathBuf, PathBuf) {
        let base = std::env::temp_dir().join(format!("drift-onboarding-{}", Uuid::new_v4()));
        (base.clone(), base.join("AppData"), base.join("Documents"))
    }

    #[test]
    fn fresh_documents_setup_is_deferred_and_welcome_is_once_only() {
        let (base, data, documents) = fresh_location();
        let notebook = load(&data, &documents, false).unwrap();
        assert_eq!(notebook.root, documents.join("Drift"));
        assert!(
            !documents.exists(),
            "loading configuration must not access Documents"
        );
        let other = notebook.clone();
        let task = std::thread::spawn(move || other.ensure_root().unwrap());
        notebook.ensure_root().unwrap();
        task.join().unwrap();
        assert_eq!(fs::read_dir(&notebook.root).unwrap().count(), 1);
        let welcome = notebook.root.join("Drift.md");
        assert_eq!(fs::read_to_string(&welcome).unwrap(), "Drift\n\nStart writing. Your notes save automatically.\n\n⌘ N — New note\n⌘ P — Find a note\n⌘ / — All shortcuts\n");
        assert_eq!(
            initial_note(&data, &notebook.root).unwrap().as_deref(),
            Some("Drift.md")
        );
        let again = load(&data, &documents, false).unwrap();
        again.ensure_root().unwrap();
        assert_eq!(fs::read_dir(&notebook.root).unwrap().count(), 1);
        acknowledge_initial_note(&data, &notebook.root).unwrap();
        fs::remove_file(welcome).unwrap();
        fs::remove_dir(&notebook.root).unwrap();
        load(&data, &documents, false)
            .unwrap()
            .ensure_root()
            .unwrap();
        assert!(
            !notebook.root.exists(),
            "a completed default must not be recreated after removal"
        );
        fs::remove_dir_all(base).unwrap();
    }

    #[test]
    fn existing_markdown_and_cloud_placeholders_never_receive_sample_notes() {
        for filename in ["Existing.MD", ".Existing.md.icloud"] {
            let (base, data, documents) = fresh_location();
            let root = documents.join("Drift");
            fs::create_dir_all(&root).unwrap();
            fs::write(root.join(filename), "User writing").unwrap();
            load(&data, &documents, false)
                .unwrap()
                .ensure_root()
                .unwrap();
            assert_eq!(fs::read_dir(&root).unwrap().count(), 1);
            assert_eq!(
                fs::read_to_string(root.join(filename)).unwrap(),
                "User writing"
            );
            assert_eq!(
                initial_note(&data, &root).unwrap(),
                if filename.starts_with('.') {
                    None
                } else {
                    Some(filename.into())
                }
            );
            fs::remove_dir_all(base).unwrap();
        }
    }

    #[test]
    fn failed_documents_creation_is_retryable_and_keeps_creation_intent() {
        let (base, data, documents) = fresh_location();
        fs::create_dir_all(&base).unwrap();
        fs::write(&documents, "An obstruction, not a directory").unwrap();
        let notebook = load(&data, &documents, false).unwrap();
        assert!(notebook.ensure_root().is_err());
        assert!(needs_default_creation(&data, &notebook.root).unwrap());
        assert_eq!(
            fs::read_to_string(&documents).unwrap(),
            "An obstruction, not a directory"
        );
        fs::remove_file(&documents).unwrap();
        notebook.ensure_root().unwrap();
        assert!(notebook.root.join("Drift.md").is_file());
        fs::remove_dir_all(base).unwrap();
    }

    #[test]
    fn legacy_empty_default_and_preview_stay_in_app_data() {
        let (base, data, documents) = fresh_location();
        let old = Notebook::new(data.clone()).unwrap();
        assert_eq!(load(&data, &documents, false).unwrap().root, old.root);
        let preview_data = base.join("Preview");
        let preview = load(&preview_data, &documents, true).unwrap();
        preview.ensure_root().unwrap();
        assert_eq!(preview.root, preview_data.join("Notebook"));
        assert!(!documents.exists());
        assert!(!data.join("notebook-location.json").exists());
        fs::remove_dir_all(base).unwrap();
    }

    #[test]
    fn missing_selected_folder_and_orphaned_state_are_not_fresh_installs() {
        let (base, data, documents) = fresh_location();
        fs::create_dir_all(&data).unwrap();
        let selected = base.join("Unavailable provider");
        atomic(
            &data.join("notebook-location.json"),
            &serde_json::to_vec(&selected).unwrap(),
        )
        .unwrap();
        let notebook = load(&data, &documents, false).unwrap();
        notebook.ensure_root().unwrap();
        assert!(!selected.exists());
        assert!(!documents.exists());
        fs::remove_file(data.join("notebook-location.json")).unwrap();
        assert!(load(&data, &documents, false).is_err());
        assert!(!documents.exists());
        fs::remove_dir_all(base).unwrap();
    }

    #[test]
    fn late_default_completion_cannot_replace_a_new_folder_choice() {
        let (base, data, documents) = fresh_location();
        let old = load(&data, &documents, false).unwrap();
        let chosen = base.join("Chosen");
        fs::create_dir(&chosen).unwrap();
        Selection::prepare(&data, &chosen)
            .unwrap()
            .commit()
            .unwrap();
        complete_default_setup(&data, &old.root, Some("Drift.md".into())).unwrap();
        acknowledge_initial_note(&data, &old.root).unwrap();
        assert_eq!(load(&data, &documents, false).unwrap().root, chosen);
        assert!(!documents.exists());
        fs::remove_dir_all(base).unwrap();
    }

    #[cfg(unix)]
    #[test]
    fn dangling_legacy_link_does_not_redirect_to_documents() {
        let (base, data, documents) = fresh_location();
        fs::create_dir_all(&data).unwrap();
        std::os::unix::fs::symlink(base.join("Missing"), data.join("Notebook")).unwrap();
        assert!(load(&data, &documents, false).is_err());
        assert!(!documents.exists());
        fs::remove_dir_all(base).unwrap();
    }

    #[test]
    fn switching_preserves_existing_notes_and_isolates_recovery() {
        let data = std::env::temp_dir().join(format!("drift-location-{}", Uuid::new_v4()));
        let old = Notebook::new(data.clone()).unwrap();
        fs::write(old.root.join("Original.md"), "Original writing").unwrap();
        let first = data.join("First");
        let second = data.join("Second");
        fs::create_dir(&first).unwrap();
        fs::create_dir(&second).unwrap();
        fs::write(first.join("Existing.md"), "Existing writing").unwrap();
        let selection = Selection::prepare(&data, &first).unwrap();
        assert_eq!(
            load(&data, &data.join("Documents"), false).unwrap().root,
            old.root
        );
        selection.commit().unwrap();
        let a = load(&data, &data.join("Documents"), false).unwrap();
        fs::write(a.data.join("Recovery/private.json"), "old recovery").unwrap();
        Selection::prepare(&data, &second)
            .unwrap()
            .commit()
            .unwrap();
        let b = load(&data, &data.join("Documents"), false).unwrap();
        assert_ne!(a.data, b.data);
        assert_eq!(fs::read_dir(b.data.join("Recovery")).unwrap().count(), 0);
        Selection::prepare(&data, &first).unwrap().commit().unwrap();
        assert_eq!(
            load(&data, &data.join("Documents"), false).unwrap().data,
            a.data
        );
        Selection::prepare(&data, &old.root)
            .unwrap()
            .commit()
            .unwrap();
        assert_eq!(
            load(&data, &data.join("Documents"), false).unwrap().data,
            old.data
        );
        assert_eq!(
            fs::read_to_string(old.root.join("Original.md")).unwrap(),
            "Original writing"
        );
        assert_eq!(
            fs::read_to_string(first.join("Existing.md")).unwrap(),
            "Existing writing"
        );
        assert_eq!(fs::read_dir(first).unwrap().count(), 1);
        fs::remove_dir_all(data).unwrap();
    }

    #[test]
    fn legacy_history_survives_switching_and_preview_ignores_live_choices() {
        let data = std::env::temp_dir().join(format!("drift-location-{}", Uuid::new_v4()));
        let default = Notebook::new(data.clone()).unwrap();
        let first = data.join("First");
        let second = data.join("Second");
        fs::create_dir(&first).unwrap();
        fs::create_dir(&second).unwrap();
        atomic(
            &data.join("notebook-location.json"),
            &serde_json::to_vec(&first).unwrap(),
        )
        .unwrap();
        let legacy = load(&data, &data.join("Documents"), false).unwrap();
        assert_eq!(legacy.data, data.join("Live"));
        fs::write(legacy.data.join("History/old"), "previous version").unwrap();
        Selection::prepare(&data, &second)
            .unwrap()
            .commit()
            .unwrap();
        assert_eq!(
            load(&data, &data.join("Documents"), true).unwrap().root,
            default.root
        );
        Selection::prepare(&data, &first).unwrap().commit().unwrap();
        assert_eq!(
            load(&data, &data.join("Documents"), false).unwrap().data,
            legacy.data
        );
        assert_eq!(
            fs::read_to_string(legacy.data.join("History/old")).unwrap(),
            "previous version"
        );
        let before = fs::read(data.join("notebook-location.json")).unwrap();
        assert!(Selection::prepare(&data, &data.join("Missing")).is_err());
        assert_eq!(
            fs::read(data.join("notebook-location.json")).unwrap(),
            before
        );
        fs::remove_dir_all(data).unwrap();
    }

    #[test]
    fn recent_folders_survive_restart_and_repeated_switches_without_duplicates() {
        let (base, data, documents) = fresh_location();
        let original = Notebook::new(data.clone()).unwrap();
        let first = base.join("First");
        let second = base.join("Second");
        fs::create_dir(&first).unwrap();
        fs::create_dir(&second).unwrap();
        assert_eq!(
            folders(&data, &original.root, false).unwrap(),
            vec![original.root.clone()]
        );
        for directory in [&first, &second, &first, &first] {
            Selection::prepare(&data, directory)
                .unwrap()
                .commit()
                .unwrap();
        }
        let restarted = load(&data, &documents, false).unwrap();
        assert_eq!(restarted.root, first);
        assert_eq!(
            folders(&data, &restarted.root, false).unwrap(),
            vec![first.clone(), second.clone(), original.root.clone()]
        );
        Selection::prepare(&data, &original.root)
            .unwrap()
            .commit()
            .unwrap();
        let restored = load(&data, &documents, false).unwrap();
        assert_eq!(restored.data, original.data);
        assert_eq!(
            folders(&data, &restored.root, false).unwrap(),
            vec![original.root, first, second]
        );
        fs::remove_dir_all(base).unwrap();
    }

    #[test]
    fn abandoned_and_failed_selections_leave_recent_folders_unchanged() {
        let (base, data, documents) = fresh_location();
        let original = load(&data, &documents, false).unwrap();
        let next = base.join("Next");
        fs::create_dir(&next).unwrap();
        let before = fs::read(data.join("notebook-location.json")).unwrap();
        drop(Selection::prepare(&data, &next).unwrap());
        assert!(Selection::prepare(&data, &base.join("Missing")).is_err());
        assert_eq!(
            fs::read(data.join("notebook-location.json")).unwrap(),
            before
        );
        assert_eq!(
            folders(&data, &original.root, false).unwrap(),
            vec![original.root.clone()]
        );

        let pending = Selection::prepare(&data, &next).unwrap();
        let temporarily_unavailable = base.join("Unavailable app data");
        fs::rename(&data, &temporarily_unavailable).unwrap();
        fs::write(&data, "Storage is unavailable").unwrap();
        assert!(pending.commit().is_err());
        fs::remove_file(&data).unwrap();
        fs::rename(&temporarily_unavailable, &data).unwrap();
        assert_eq!(
            fs::read(data.join("notebook-location.json")).unwrap(),
            before
        );
        let restarted = load(&data, &documents, false).unwrap();
        assert_eq!(restarted.root, original.root);
        assert_eq!(
            folders(&data, &restarted.root, false).unwrap(),
            vec![original.root]
        );
        fs::remove_dir_all(base).unwrap();
    }

    #[test]
    fn old_recovery_mappings_become_recent_folders_on_the_next_successful_switch() {
        let (base, data, documents) = fresh_location();
        fs::create_dir_all(&data).unwrap();
        let first = base.join("A unavailable provider");
        let second = base.join("B unavailable provider");
        let next = base.join("Next");
        fs::create_dir(&next).unwrap();
        let notebooks = BTreeMap::from([
            (first.to_string_lossy().into_owned(), "Live".to_owned()),
            (
                second.to_string_lossy().into_owned(),
                format!("Notebooks/{}", Uuid::new_v4()),
            ),
        ]);
        // This is the selected-folder format from before recency was recorded.
        let old_config = serde_json::json!({
            "directory": second,
            "notebooks": notebooks,
        });
        atomic(
            &data.join("notebook-location.json"),
            &serde_json::to_vec(&old_config).unwrap(),
        )
        .unwrap();
        assert_eq!(
            folders(&data, &second, false).unwrap(),
            vec![second.clone(), first.clone()]
        );
        assert!(!first.exists());
        assert!(!second.exists());
        Selection::prepare(&data, &next).unwrap().commit().unwrap();
        let restarted = load(&data, &documents, false).unwrap();
        assert_eq!(
            folders(&data, &restarted.root, false).unwrap(),
            vec![next, second, first.clone()]
        );
        match read(&data).unwrap().unwrap() {
            Location::Selected { notebooks, .. } => {
                assert_eq!(notebooks[&first.to_string_lossy().into_owned()], "Live");
            }
            _ => panic!("A successful switch should migrate the configuration"),
        }
        fs::remove_dir_all(base).unwrap();
    }

    #[test]
    fn legacy_string_choice_is_kept_in_recent_folders() {
        let (base, data, documents) = fresh_location();
        fs::create_dir_all(&data).unwrap();
        let previous = base.join("Legacy provider");
        let next = base.join("Next");
        fs::create_dir(&next).unwrap();
        atomic(
            &data.join("notebook-location.json"),
            &serde_json::to_vec(&previous).unwrap(),
        )
        .unwrap();
        assert_eq!(
            folders(&data, &previous, false).unwrap(),
            vec![previous.clone()]
        );
        Selection::prepare(&data, &next).unwrap().commit().unwrap();
        let restarted = load(&data, &documents, false).unwrap();
        assert_eq!(
            folders(&data, &restarted.root, false).unwrap(),
            vec![next, previous]
        );
        fs::remove_dir_all(base).unwrap();
    }

    #[test]
    fn setup_and_welcome_acknowledgment_preserve_recent_folders() {
        let (base, data, documents) = fresh_location();
        let original = load(&data, &documents, false).unwrap();
        let previous = base.join("Previous");
        let config_path = data.join("notebook-location.json");
        let mut config: serde_json::Value =
            serde_json::from_slice(&fs::read(&config_path).unwrap()).unwrap();
        config["recentDirectories"] = serde_json::json!([original.root, previous]);
        atomic(&config_path, &serde_json::to_vec(&config).unwrap()).unwrap();

        complete_default_setup(&data, &original.root, Some("Drift.md".into())).unwrap();
        assert_eq!(
            folders(&data, &original.root, false).unwrap(),
            vec![original.root.clone(), previous.clone()]
        );
        acknowledge_initial_note(&data, &original.root).unwrap();
        assert_eq!(
            folders(&data, &original.root, false).unwrap(),
            vec![original.root, previous]
        );
        fs::remove_dir_all(base).unwrap();
    }

    #[test]
    fn preview_folder_menu_ignores_even_unreadable_live_configuration() {
        let (base, data, _) = fresh_location();
        fs::create_dir_all(&data).unwrap();
        fs::write(data.join("notebook-location.json"), "Invalid config").unwrap();
        let preview_root = base.join("Copied notebook");
        assert_eq!(
            folders(&data, &preview_root, true).unwrap(),
            vec![preview_root.clone()]
        );
        assert!(folders(&data, &preview_root, false).is_err());
        assert!(!preview_root.exists());
        fs::remove_dir_all(base).unwrap();
    }
}
