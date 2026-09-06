//! All note access is confined to the selected notebook. Development uses an app-owned copy.
use serde::{Deserialize, Serialize};
use std::{
    fs::{self, OpenOptions},
    io::Write,
    path::{Path, PathBuf},
    sync::{
        atomic::{AtomicBool, Ordering},
        Arc, Mutex,
    },
    time::UNIX_EPOCH,
};
use tauri::State;
use uuid::Uuid;

#[derive(Clone)]
pub struct Notebook {
    pub root: PathBuf,
    pub data: PathBuf,
    pub writes: Arc<Mutex<()>>,
    recovery_claimed: Arc<AtomicBool>,
    pending_default: Arc<Mutex<Option<PathBuf>>>,
    initial_setup: Option<PathBuf>,
}
#[derive(Clone, Serialize, Deserialize, Debug)]
#[serde(rename_all = "camelCase")]
pub struct Draft {
    pub id: String,
    pub path: Option<String>,
    pub baseline: Option<String>,
    pub text: String,
}
#[derive(Serialize, Debug)]
#[serde(rename_all = "camelCase")]
pub struct Saved {
    pub path: Option<String>,
    pub text: String,
    pub conflict: bool,
}
#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
pub struct Entry {
    pub path: String,
    pub title: String,
    pub modified: u64,
    pub size: u64,
}
#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
pub struct NotebookInfo {
    pub directory: String,
    pub drafts: Vec<Draft>,
    pub restore_drafts: bool,
    pub initialize_notebook: bool,
}

const WELCOME: &str = "Drift\n\nStart writing. Your notes save automatically.\n\n⌘ N — New note\n⌘ P — Find a note\n⌘ / — All shortcuts\n";

fn err(e: impl std::fmt::Display) -> String {
    e.to_string()
}
fn access_err(e: std::io::Error) -> String {
    if std::env::var_os("DRIFT_PROFILE").is_some() {
        eprintln!(
            "drift-notebook access-error kind={:?} errno={:?}",
            e.kind(),
            e.raw_os_error()
        );
    }
    if e.kind() == std::io::ErrorKind::PermissionDenied {
        "Drift does not have permission to open the notebook. Allow access in System Settings → Privacy & Security → Files and Folders, then try again."
            .into()
    } else {
        err(e)
    }
}
fn title(text: &str) -> String {
    let first = text
        .lines()
        .find(|s| !s.trim().is_empty())
        .unwrap_or("Untitled")
        .trim()
        .trim_start_matches('#')
        .trim();
    let clean: String = first
        .chars()
        .filter(|c| !c.is_control() && !"<>:\"/\\|?*".contains(*c))
        .take(70)
        .collect();
    let mut end = clean.len().min(140);
    while !clean.is_char_boundary(end) {
        end -= 1;
    }
    let clean = &clean[..end];
    let clean = clean.trim().trim_matches('.').trim();
    if clean.is_empty() {
        "Untitled".into()
    } else {
        clean.into()
    }
}
pub(crate) fn atomic(path: &Path, bytes: &[u8]) -> Result<(), String> {
    let temp = path.with_file_name(format!(".{}.tmp", Uuid::new_v4()));
    let result = (|| {
        let mut file = OpenOptions::new()
            .write(true)
            .create_new(true)
            .open(&temp)
            .map_err(err)?;
        file.write_all(bytes).map_err(err)?;
        file.sync_all().map_err(err)?;
        fs::rename(&temp, path).map_err(err)?;
        Ok(())
    })();
    if result.is_err() {
        let _ = fs::remove_file(temp);
    }
    result
}
impl Notebook {
    pub fn new(data: PathBuf) -> Result<Self, String> {
        for dir in ["Notebook", "Recovery", "History"] {
            fs::create_dir_all(data.join(dir)).map_err(err)?;
        }
        Ok(Self {
            root: data.join("Notebook"),
            data,
            writes: Arc::new(Mutex::new(())),
            recovery_claimed: Arc::new(AtomicBool::new(false)),
            pending_default: Arc::new(Mutex::new(None)),
            initial_setup: None,
        })
    }
    pub(crate) fn create_default_on_access(&mut self, config_data: PathBuf) {
        self.initial_setup = Some(config_data.clone());
        self.pending_default = Arc::new(Mutex::new(Some(config_data)));
    }
    pub(crate) fn ensure_root(&self) -> Result<(), String> {
        let mut pending = self.pending_default.lock().map_err(err)?;
        if let Some(data) = pending.as_ref() {
            // Only a fresh installation's explicit default-creation intent can
            // create a root. An unavailable existing/user-selected folder must
            // remain an error, never a new empty notebook.
            if crate::notebook_location::needs_default_creation(data, &self.root)? {
                fs::create_dir_all(&self.root).map_err(access_err)?;
                let initial = self.first_note_or_welcome()?;
                crate::notebook_location::complete_default_setup(data, &self.root, initial)?;
            }
            *pending = None;
        }
        Ok(())
    }
    fn first_note_or_welcome(&self) -> Result<Option<String>, String> {
        let mut notes = Vec::new();
        let mut has_markdown = false;
        for item in fs::read_dir(&self.root).map_err(access_err)? {
            let item = item.map_err(access_err)?;
            let name = item.file_name().to_string_lossy().into_owned();
            let lower = name.to_lowercase();
            if !(lower.ends_with(".md") || lower.ends_with(".md.icloud")) {
                continue;
            }
            has_markdown = true;
            if lower.ends_with(".md")
                && !name.starts_with('.')
                && item.file_type().map_err(access_err)?.is_file()
            {
                notes.push((item.metadata().map_err(access_err)?.modified().ok(), name));
            }
        }
        if has_markdown {
            notes.sort_by(|a, b| b.0.cmp(&a.0).then(a.1.cmp(&b.1)));
            return Ok(notes.into_iter().next().map(|(_, name)| name));
        }
        // Link a fully written file into place only if Drift.md is still absent.
        // Never overwrite a note created by another window/process or sync.
        let temp = self.root.join(format!(".{}.tmp", Uuid::new_v4()));
        let result = (|| {
            let mut file = OpenOptions::new()
                .write(true)
                .create_new(true)
                .open(&temp)
                .map_err(access_err)?;
            file.write_all(WELCOME.as_bytes()).map_err(access_err)?;
            file.sync_all().map_err(access_err)?;
            match fs::hard_link(&temp, self.root.join("Drift.md")) {
                Ok(()) => Ok(Some("Drift.md".into())),
                Err(e) if e.kind() == std::io::ErrorKind::AlreadyExists => {
                    Ok(Some("Drift.md".into()))
                }
                Err(e) => Err(access_err(e)),
            }
        })();
        let _ = fs::remove_file(temp);
        result
    }
    fn path(&self, name: &str) -> Result<PathBuf, String> {
        if name.is_empty()
            || name.contains('/')
            || name.contains('\\')
            || name.starts_with('.')
            || !name.to_lowercase().ends_with(".md")
        {
            return Err("Invalid note filename".into());
        }
        let path = self.root.join(name);
        if fs::symlink_metadata(&path)
            .map(|m| m.file_type().is_symlink())
            .unwrap_or(false)
        {
            return Err("Linked files cannot be edited in the preview notebook".into());
        }
        Ok(path)
    }
    fn journal_path(&self, id: &str) -> Result<PathBuf, String> {
        Uuid::parse_str(id).map_err(err)?;
        Ok(self.data.join("Recovery").join(format!("{id}.json")))
    }
    fn journal(&self, draft: &Draft) -> Result<(), String> {
        atomic(
            &self.journal_path(&draft.id)?,
            &serde_json::to_vec(draft).map_err(err)?,
        )
    }
    fn unique(&self, stem: &str, text: &str) -> Result<String, String> {
        for n in 0..10000 {
            let name = if n == 0 {
                format!("{stem}.md")
            } else {
                format!("{stem} {n}.md")
            };
            let path = self.path(&name)?;
            // Link a fully flushed temporary file into a never-overwritten destination.
            let temp = self.root.join(format!(".{}.tmp", Uuid::new_v4()));
            let mut f = OpenOptions::new()
                .create_new(true)
                .write(true)
                .open(&temp)
                .map_err(err)?;
            if let Err(e) = f.write_all(text.as_bytes()).and_then(|_| f.sync_all()) {
                let _ = fs::remove_file(&temp);
                return Err(err(e));
            }
            let result = fs::hard_link(&temp, &path);
            let _ = fs::remove_file(&temp);
            match result {
                Ok(()) => return Ok(name),
                Err(e) if e.kind() == std::io::ErrorKind::AlreadyExists => continue,
                Err(e) => return Err(err(e)),
            }
        }
        Err("Too many notes with the same name".into())
    }
    fn history(&self, name: &str, text: &str) -> Result<(), String> {
        let stamp = std::time::SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .unwrap_or_default()
            .as_millis();
        atomic(
            &self
                .data
                .join("History")
                .join(format!("{stamp}-{}-{}", Uuid::new_v4(), title(name))),
            text.as_bytes(),
        )
    }
    pub fn save(&self, draft: Draft) -> Result<Saved, String> {
        let _lock = self.writes.lock().map_err(err)?;
        self.journal(&draft)?;
        self.ensure_root()?;
        if let Some(name) = draft.path.as_ref() {
            let path = self.path(name)?;
            return coordinated(&path, || self.save_inner(draft));
        }
        self.save_inner(draft)
    }
    fn save_inner(&self, draft: Draft) -> Result<Saved, String> {
        let finish = |path: Option<String>, conflict: bool| -> Result<Saved, String> {
            // A committed journal makes a crash between writing and cleanup idempotent.
            let committed = Draft {
                path: path.clone(),
                baseline: Some(draft.text.clone()),
                ..draft.clone()
            };
            self.journal(&committed)?;
            let _ = fs::remove_file(self.journal_path(&draft.id)?);
            Ok(Saved {
                path,
                text: draft.text.clone(),
                conflict,
            })
        };
        // Keep the incoming version independently, even if an older, uncoordinated
        // editor later overwrites the shared file. History never lives in the notebook.
        if draft.baseline.as_ref() != Some(&draft.text)
            && (draft.path.is_some() || !draft.text.trim().is_empty())
        {
            self.history(&format!("{}.md", title(&draft.text)), &draft.text)?;
        }
        let Some(name) = draft.path.as_ref() else {
            if draft.text.trim().is_empty() {
                return finish(None, false);
            }
            return finish(Some(self.unique(&title(&draft.text), &draft.text)?), false);
        };
        let path = self.path(name)?;
        let disk = match fs::read_to_string(&path) {
            Ok(s) => Some(s),
            Err(e) if e.kind() == std::io::ErrorKind::NotFound => None,
            Err(e) => return Err(err(e)),
        };
        if disk.as_deref() == Some(draft.text.as_str()) {
            return finish(Some(name.clone()), false);
        }
        if draft.baseline.as_deref() != disk.as_deref() || disk.is_none() {
            // Keep external content (or deletion) intact; materialize our writing separately.
            let name = self.unique(&format!("{} (conflict)", title(&draft.text)), &draft.text)?;
            return finish(Some(name), true);
        }
        let old = disk.unwrap();
        self.history(name, &old)?;
        // Recheck after history I/O. We never knowingly replace a newer version.
        if fs::read_to_string(&path).map_err(err)? != old {
            return finish(
                Some(self.unique(&format!("{} (conflict)", title(&draft.text)), &draft.text)?),
                true,
            );
        }
        let renamed = !draft.text.trim().is_empty() && title(&draft.text) != title(&old);
        if renamed {
            let next = self.unique(&title(&draft.text), &draft.text)?;
            // Retain both files if something changed during the new-file write.
            if fs::read_to_string(&path).map_err(err)? == old {
                fs::remove_file(&path).map_err(err)?;
            }
            finish(Some(next), false)
        } else {
            atomic(&path, draft.text.as_bytes())?;
            finish(Some(name.clone()), false)
        }
    }
}
#[tauri::command]
pub async fn notebook_info(
    window: tauri::WebviewWindow,
    store: State<'_, Notebook>,
) -> Result<NotebookInfo, String> {
    let store = store.inner().clone();
    let main = window.label() == "main";
    tauri::async_runtime::spawn_blocking(move || info(&store, main))
        .await
        .map_err(err)?
}
fn info(store: &Notebook, main: bool) -> Result<NotebookInfo, String> {
    let mut info = NotebookInfo {
        directory: store.root.to_string_lossy().into_owned(),
        drafts: Vec::new(),
        restore_drafts: false,
        initialize_notebook: main && store.initial_setup.is_some(),
    };
    // Only the first main window owns crash recovery. A recreated main window
    // may coexist with a minimized editor whose unfinished draft is still live.
    if !main || store.recovery_claimed.load(Ordering::Acquire) {
        return Ok(info);
    }
    let mut drafts = Vec::new();
    for file in fs::read_dir(store.data.join("Recovery")).map_err(err)? {
        let file = file.map_err(err)?;
        if file.path().extension().and_then(|s| s.to_str()) == Some("json") {
            let d: Draft =
                serde_json::from_slice(&fs::read(file.path()).map_err(err)?).map_err(err)?;
            if d.baseline.as_ref() != Some(&d.text) {
                drafts.push(d);
            }
        }
    }
    // An unavailable recovery directory must remain retryable. Claim ownership
    // only after every draft has been read successfully, including an empty set.
    if store
        .recovery_claimed
        .compare_exchange(false, true, Ordering::AcqRel, Ordering::Acquire)
        .is_ok()
    {
        info.drafts = drafts;
        info.restore_drafts = true;
    }
    Ok(info)
}
#[tauri::command]
pub async fn initialize_notebook(
    window: tauri::WebviewWindow,
    store: State<'_, Notebook>,
) -> Result<Option<String>, String> {
    if window.label() != "main" {
        return Ok(None);
    }
    let store = store.inner().clone();
    tauri::async_runtime::spawn_blocking(move || {
        store.ensure_root()?;
        match &store.initial_setup {
            Some(data) => match crate::notebook_location::initial_note(data, &store.root)? {
                Some(path) => {
                    // A welcome can be renamed/deleted before its first open is
                    // acknowledged. Retire that stale marker after a successful
                    // catalogue read; permission/provider errors remain retryable.
                    let entries = list(&store)?;
                    Ok(entries
                        .iter()
                        .find(|entry| entry.path == path)
                        .or_else(|| entries.first())
                        .map(|entry| entry.path.clone()))
                }
                None => Ok(None),
            },
            None => Ok(None),
        }
    })
    .await
    .map_err(err)?
}
#[tauri::command]
pub async fn initial_note_opened(store: State<'_, Notebook>) -> Result<(), String> {
    let store = store.inner().clone();
    tauri::async_runtime::spawn_blocking(move || match &store.initial_setup {
        Some(data) => crate::notebook_location::acknowledge_initial_note(data, &store.root),
        None => Ok(()),
    })
    .await
    .map_err(err)?
}
#[tauri::command]
pub async fn list_notes(store: State<'_, Notebook>) -> Result<Vec<Entry>, String> {
    let store = store.inner().clone();
    tauri::async_runtime::spawn_blocking(move || list(&store))
        .await
        .map_err(err)?
}
fn list(store: &Notebook) -> Result<Vec<Entry>, String> {
    store.ensure_root()?;
    let mut entries = Vec::new();
    let (mut seen, mut files, mut links, mut markdown, mut hidden) = (0, 0, 0, 0, 0);
    // Access failures are not empty notebooks. Keep the previous catalogue in the
    // frontend and allow the same request to succeed after macOS grants access.
    for file in fs::read_dir(&store.root).map_err(access_err)? {
        let file = file.map_err(access_err)?;
        let name = file.file_name().to_string_lossy().into_owned();
        let kind = file.file_type().map_err(access_err)?;
        seen += 1;
        files += usize::from(kind.is_file());
        links += usize::from(kind.is_symlink());
        markdown += usize::from(name.to_lowercase().ends_with(".md"));
        hidden += usize::from(name.starts_with('.'));
        if !kind.is_file() || name.starts_with('.') || !name.to_lowercase().ends_with(".md") {
            continue;
        }
        let meta = file.metadata().map_err(access_err)?;
        let modified = meta
            .modified()
            .ok()
            .and_then(|t| t.duration_since(UNIX_EPOCH).ok())
            .map(|d| d.as_millis() as u64)
            .unwrap_or(0);
        entries.push(Entry {
            title: name[..name.len() - 3].into(),
            path: name,
            modified,
            size: meta.len(),
        });
    }
    entries.sort_by(|a, b| b.modified.cmp(&a.modified).then(a.path.cmp(&b.path)));
    if std::env::var_os("DRIFT_PROFILE").is_some() {
        eprintln!(
            "drift-notebook list root={} seen={seen} files={files} symlinks={links} markdown={markdown} hidden={hidden} notes={}",
            store.root.display(), entries.len()
        );
    }
    Ok(entries)
}
#[tauri::command]
pub async fn read_note(path: String, store: State<'_, Notebook>) -> Result<String, String> {
    let store = store.inner().clone();
    tauri::async_runtime::spawn_blocking(move || read(&store, &path))
        .await
        .map_err(err)?
}
fn read(store: &Notebook, path: &str) -> Result<String, String> {
    store.ensure_root()?;
    fs::read_to_string(store.path(path)?).map_err(access_err)
}
#[tauri::command]
pub async fn save_note(draft: Draft, store: State<'_, Notebook>) -> Result<Saved, String> {
    let store = store.inner().clone();
    tauri::async_runtime::spawn_blocking(move || store.save(draft))
        .await
        .map_err(err)?
}
#[tauri::command]
pub async fn reveal_notebook(store: State<'_, Notebook>) -> Result<(), String> {
    std::process::Command::new("open")
        .arg(&store.root)
        .spawn()
        .map_err(err)?;
    Ok(())
}
#[tauri::command]
pub async fn reveal_history(store: State<'_, Notebook>) -> Result<(), String> {
    std::process::Command::new("open")
        .arg(store.data.join("History"))
        .spawn()
        .map_err(err)?;
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    fn store() -> Notebook {
        Notebook::new(std::env::temp_dir().join(format!("drift-test-{}", Uuid::new_v4()))).unwrap()
    }
    fn draft(path: Option<&str>, baseline: Option<&str>, text: &str) -> Draft {
        Draft {
            id: Uuid::new_v4().to_string(),
            path: path.map(Into::into),
            baseline: baseline.map(Into::into),
            text: text.into(),
        }
    }
    #[test]
    fn concurrent_sessions_preserve_both_edits() {
        let s = store();
        fs::write(s.root.join("A.md"), "A").unwrap();
        let other = s.clone();
        let t = std::thread::spawn(move || {
            other
                .save(draft(Some("A.md"), Some("A"), "A\nfirst"))
                .unwrap()
        });
        let second = s.save(draft(Some("A.md"), Some("A"), "A\nsecond")).unwrap();
        let first = t.join().unwrap();
        assert_ne!(first.path, second.path);
        let texts: Vec<_> = fs::read_dir(&s.root)
            .unwrap()
            .map(|e| fs::read_to_string(e.unwrap().path()).unwrap())
            .collect();
        assert!(texts.contains(&"A\nfirst".to_string()));
        assert!(texts.contains(&"A\nsecond".to_string()));
    }
    #[test]
    fn long_unicode_title_fits_the_filesystem_and_history() {
        let s = store();
        let content = "📝".repeat(90);
        let first = s.save(draft(None, None, &content)).unwrap();
        s.save(draft(
            first.path.as_deref(),
            Some(&content),
            &(content.clone() + "\nbody"),
        ))
        .unwrap();
        assert_eq!(
            fs::read_to_string(s.root.join(first.path.unwrap())).unwrap(),
            content + "\nbody"
        );
    }
    #[test]
    fn parallel_new_notes_with_same_title_get_distinct_files() {
        let s = store();
        let other = s.clone();
        let t = std::thread::spawn(move || other.save(draft(None, None, "Same\nfirst")).unwrap());
        let second = s.save(draft(None, None, "Same\nsecond")).unwrap();
        assert_ne!(t.join().unwrap().path, second.path);
    }
    #[test]
    fn empty_composer_creates_nothing() {
        let s = store();
        assert!(s.save(draft(None, None, " \n")).unwrap().path.is_none());
        assert_eq!(fs::read_dir(&s.root).unwrap().count(), 0);
    }
    #[test]
    fn erase_existing_persists_empty() {
        let s = store();
        fs::write(s.root.join("A.md"), "A\nbody").unwrap();
        s.save(draft(Some("A.md"), Some("A\nbody"), "")).unwrap();
        assert_eq!(fs::read_to_string(s.root.join("A.md")).unwrap(), "");
        assert_eq!(fs::read_dir(s.data.join("History")).unwrap().count(), 2);
    }
    #[test]
    fn conflict_preserves_both() {
        let s = store();
        fs::write(s.root.join("A.md"), "phone").unwrap();
        let r = s.save(draft(Some("A.md"), Some("A"), "desktop")).unwrap();
        assert!(r.conflict);
        assert_eq!(fs::read_to_string(s.root.join("A.md")).unwrap(), "phone");
        assert_eq!(
            fs::read_to_string(s.root.join(r.path.unwrap())).unwrap(),
            "desktop"
        );
    }
    #[test]
    fn deleted_file_not_resurrected() {
        let s = store();
        let r = s.save(draft(Some("A.md"), Some("A"), "A edited")).unwrap();
        assert!(r.conflict);
        assert!(!s.root.join("A.md").exists());
    }
    #[test]
    fn rename_collision_keeps_other_note() {
        let s = store();
        fs::write(s.root.join("A.md"), "A").unwrap();
        fs::write(s.root.join("B.md"), "other B").unwrap();
        let r = s.save(draft(Some("A.md"), Some("A"), "B")).unwrap();
        assert_eq!(r.path.as_deref(), Some("B 1.md"));
        assert_eq!(fs::read_to_string(s.root.join("B.md")).unwrap(), "other B");
        assert!(!s.root.join("A.md").exists());
    }
    #[test]
    fn duplicate_title_does_not_churn() {
        let s = store();
        fs::write(s.root.join("A 1.md"), "A").unwrap();
        let r = s.save(draft(Some("A 1.md"), Some("A"), "A\nmore")).unwrap();
        assert_eq!(r.path.as_deref(), Some("A 1.md"));
    }
    #[test]
    fn reject_paths_outside_notebook() {
        let s = store();
        for path in ["../work.md", "/tmp/work.md", ".hidden.md", "work.txt"] {
            assert!(s.path(path).is_err());
        }
    }
    #[test]
    fn reject_symlinks() {
        let s = store();
        std::os::unix::fs::symlink("/tmp/outside", s.root.join("link.md")).unwrap();
        assert!(s.path("link.md").is_err());
    }
    #[test]
    fn failed_save_keeps_recovery() {
        let s = store();
        fs::create_dir(s.root.join("A.md")).unwrap();
        let d = draft(Some("A.md"), Some("A"), "new writing");
        assert!(s.save(d.clone()).is_err());
        let saved: Draft =
            serde_json::from_slice(&fs::read(s.journal_path(&d.id).unwrap()).unwrap()).unwrap();
        assert_eq!(saved.text, "new writing");
    }
    #[test]
    fn same_content_is_idempotent() {
        let s = store();
        fs::write(s.root.join("A.md"), "A").unwrap();
        s.save(draft(Some("A.md"), Some("old"), "A")).unwrap();
        assert_eq!(fs::read_dir(&s.root).unwrap().count(), 1);
        assert_eq!(fs::read_dir(s.data.join("History")).unwrap().count(), 1);
    }
    #[test]
    fn unavailable_notebook_is_an_error_and_can_be_retried() {
        let s = store();
        let unavailable = s.data.join("Temporarily unavailable");
        fs::write(s.root.join("A.md"), "A\nwork").unwrap();
        fs::rename(&s.root, &unavailable).unwrap();
        assert!(list(&s).is_err());
        fs::rename(&unavailable, &s.root).unwrap();
        let entries = list(&s).unwrap();
        assert_eq!(entries.len(), 1);
        assert_eq!(entries[0].path, "A.md");
        assert_eq!(read(&s, "A.md").unwrap(), "A\nwork");
        fs::remove_dir_all(s.data).unwrap();
    }
    #[test]
    fn empty_notebook_is_successfully_distinct_from_an_access_failure() {
        let s = store();
        assert!(list(&s).unwrap().is_empty());
        let message = access_err(std::io::Error::from(std::io::ErrorKind::PermissionDenied));
        assert!(message.contains("permission"));
        assert!(message.contains("Files and Folders"));
        assert!(message.contains("try again"));
        fs::remove_dir_all(s.data).unwrap();
    }
    #[cfg(unix)]
    #[test]
    fn denied_reads_recover_after_permission_is_restored() {
        use std::os::unix::fs::PermissionsExt;
        let s = store();
        let note = s.root.join("A.md");
        fs::write(&note, "A\nwork").unwrap();
        let original = fs::metadata(&s.root).unwrap().permissions();
        fs::set_permissions(&s.root, fs::Permissions::from_mode(0o000)).unwrap();
        // Restore access before assertions, even if this test is run as root and
        // the OS legitimately permits the read. Never leave a locked test folder.
        let catalogue = list(&s);
        let content = read(&s, "A.md");
        fs::set_permissions(&s.root, original).unwrap();
        if let Err(message) = catalogue {
            assert!(message.contains("permission"));
            assert!(content.unwrap_err().contains("permission"));
        }
        assert_eq!(list(&s).unwrap().len(), 1);
        assert_eq!(read(&s, "A.md").unwrap(), "A\nwork");
        fs::remove_dir_all(s.data).unwrap();
    }
    #[test]
    fn recovery_is_claimed_only_by_the_first_main_window() {
        let s = store();
        let draft = draft(None, None, "Unfinished writing");
        s.journal(&draft).unwrap();
        let secondary = info(&s, false).unwrap();
        assert!(!secondary.restore_drafts);
        assert!(secondary.drafts.is_empty());
        let first = info(&s, true).unwrap();
        assert!(first.restore_drafts);
        assert_eq!(first.drafts.len(), 1);
        assert_eq!(first.drafts[0].text, draft.text);
        let recreated = info(&s.clone(), true).unwrap();
        assert!(!recreated.restore_drafts);
        assert!(recreated.drafts.is_empty());
        assert!(s.journal_path(&draft.id).unwrap().exists());
        assert!(list(&s).unwrap().is_empty());
        fs::remove_dir_all(s.data).unwrap();
    }
    #[test]
    fn unsuccessful_recovery_read_does_not_claim_ownership() {
        let s = store();
        let damaged = s.data.join("Recovery").join("unreadable.json");
        fs::write(&damaged, "{incomplete").unwrap();
        assert!(info(&s, true).is_err());
        fs::remove_file(damaged).unwrap();
        let draft = draft(None, None, "Recovered on retry");
        s.journal(&draft).unwrap();
        let retry = info(&s, true).unwrap();
        assert!(retry.restore_drafts);
        assert_eq!(retry.drafts[0].text, draft.text);
        assert!(!info(&s, true).unwrap().restore_drafts);
        fs::remove_dir_all(s.data).unwrap();
    }
}

#[cfg(target_os = "macos")]
fn coordinated<T>(path: &Path, operation: impl FnOnce() -> Result<T, String>) -> Result<T, String> {
    use std::ffi::{c_void, CString};
    extern "C" {
        fn drift_coordinate_write(
            path: *const std::ffi::c_char,
            callback: extern "C" fn(*mut c_void),
            context: *mut c_void,
        ) -> bool;
    }
    struct Context<F, T> {
        operation: Option<F>,
        result: Option<Result<T, String>>,
    }
    extern "C" fn run<F: FnOnce() -> Result<T, String>, T>(raw: *mut c_void) {
        let context = unsafe { &mut *(raw as *mut Context<F, T>) };
        context.result = Some(
            std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
                context.operation.take().unwrap()()
            }))
            .unwrap_or_else(|_| Err("File operation was interrupted".into())),
        );
    }
    fn invoke<F: FnOnce() -> Result<T, String>, T>(path: &Path, op: F) -> Result<T, String> {
        let path = CString::new(path.to_string_lossy().as_bytes()).map_err(err)?;
        let mut context = Context {
            operation: Some(op),
            result: None,
        };
        let ok = unsafe {
            drift_coordinate_write(
                path.as_ptr(),
                run::<F, T>,
                &mut context as *mut _ as *mut c_void,
            )
        };
        if !ok {
            return Err("The file provider could not coordinate this save. Your recovery draft is retained.".into());
        }
        context
            .result
            .unwrap_or_else(|| Err("File provider did not complete the save".into()))
    }
    invoke(path, operation)
}
#[cfg(not(target_os = "macos"))]
fn coordinated<T>(
    _path: &Path,
    operation: impl FnOnce() -> Result<T, String>,
) -> Result<T, String> {
    operation()
}
