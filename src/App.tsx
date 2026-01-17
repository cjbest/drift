import { createSignal, onMount, onCleanup, Show } from 'solid-js'
import { listen } from '@tauri-apps/api/event'
import { getCurrentWindow } from '@tauri-apps/api/window'
import { WebviewWindow, getAllWebviewWindows } from '@tauri-apps/api/webviewWindow'
import { documentDir } from '@tauri-apps/api/path'
import { readTextFile, writeTextFile, mkdir, exists, readDir, rename } from '@tauri-apps/plugin-fs'
import { Editor } from './components/Editor'
import { QuickOpen } from './components/QuickOpen'
import './App.css'

const DRIFT_FOLDER = 'Drift'
const OPEN_FILES_KEY = 'drift-open-files'

type ThemeMode = 'system' | 'light' | 'dark'
const THEME_LABELS: Record<ThemeMode, string> = { system: 'System', light: 'Light', dark: 'Dark' }

// Track which files are open in which windows
function getOpenFiles(): Record<string, string> {
  const stored = localStorage.getItem(OPEN_FILES_KEY)
  return stored ? JSON.parse(stored) : {}
}

function registerOpenFile(filePath: string, windowLabel: string) {
  const files = getOpenFiles()
  files[filePath] = windowLabel
  localStorage.setItem(OPEN_FILES_KEY, JSON.stringify(files))
}

function unregisterWindow(windowLabel: string) {
  const files = getOpenFiles()
  const updated: Record<string, string> = {}
  for (const [path, label] of Object.entries(files)) {
    if (label !== windowLabel) {
      updated[path] = label
    }
  }
  localStorage.setItem(OPEN_FILES_KEY, JSON.stringify(updated))
}

function getWindowForFile(filePath: string): string | null {
  const files = getOpenFiles()
  return files[filePath] || null
}

function sanitizeFilename(content: string): string {
  // Get first line, prefer heading
  const lines = content.split('\n').filter(l => l.trim())
  if (lines.length === 0) return 'Untitled'

  let title = lines[0]
  // Remove markdown heading prefix
  title = title.replace(/^#+\s*/, '')
  // Remove characters not safe for filenames
  title = title.replace(/[<>:"/\\|?*]/g, '')
  // Limit length
  title = title.slice(0, 50).trim()

  return title || 'Untitled'
}

function App() {
  const [content, setContent] = createSignal('')
  const [currentFilePath, setCurrentFilePath] = createSignal<string | null>(null)
  const [fileAccessTimes, setFileAccessTimes] = createSignal<Record<string, number>>({})
  const [quickOpenVisible, setQuickOpenVisible] = createSignal(false)
  const [driftDir, setDriftDir] = createSignal('')
  const [theme, setTheme] = createSignal<ThemeMode>((localStorage.getItem('drift-theme') as ThemeMode) || 'system')
  const [statusMessage, setStatusMessage] = createSignal<string | null>(null)

  let saveTimeout: number | undefined
  let statusTimeout: number | undefined

  const applyTheme = (mode: ThemeMode) => {
    document.documentElement.removeAttribute('data-theme')
    if (mode === 'light') {
      document.documentElement.setAttribute('data-theme', 'light')
    } else if (mode === 'dark') {
      document.documentElement.setAttribute('data-theme', 'dark')
    }
  }

  const showStatus = (message: string) => {
    setStatusMessage(message)
    if (statusTimeout) clearTimeout(statusTimeout)
    statusTimeout = setTimeout(() => setStatusMessage(null), 1500) as unknown as number
  }

  const cycleTheme = () => {
    const modes: ThemeMode[] = ['system', 'light', 'dark']
    const current = theme()
    const next = modes[(modes.indexOf(current) + 1) % modes.length]
    setTheme(next)
    localStorage.setItem('drift-theme', next)
    applyTheme(next)
    showStatus(`${THEME_LABELS[next]} mode`)
  }

  const setThemeMode = (mode: ThemeMode) => {
    setTheme(mode)
    localStorage.setItem('drift-theme', mode)
    applyTheme(mode)
    showStatus(`${THEME_LABELS[mode]} mode`)
  }

  const ensureDriftDir = async () => {
    let docDir = await documentDir()
    // Ensure no double slashes
    if (!docDir.endsWith('/')) docDir += '/'
    const dir = `${docDir}${DRIFT_FOLDER}`
    setDriftDir(dir)

    const dirExists = await exists(dir)
    if (!dirExists) {
      await mkdir(dir)
    }
    return dir
  }

  const loadFileAccessTimes = () => {
    const stored = localStorage.getItem('drift-file-access-times')
    if (stored) {
      setFileAccessTimes(JSON.parse(stored))
    }
  }

  const recordFileAccess = (filePath: string, oldPath?: string) => {
    const times = { ...fileAccessTimes() }
    // If renaming, transfer the old timestamp
    if (oldPath && oldPath !== filePath && times[oldPath]) {
      times[filePath] = times[oldPath]
      delete times[oldPath]
    }
    // Update access time to now
    times[filePath] = Date.now()
    setFileAccessTimes(times)
    localStorage.setItem('drift-file-access-times', JSON.stringify(times))
  }

  const saveFile = async (contentToSave: string, existingPath?: string | null) => {
    if (!contentToSave.trim()) return

    try {
      const dir = await ensureDriftDir()
      let filePath = existingPath ?? currentFilePath()
      let oldPath: string | undefined

      if (!filePath) {
        // Create new file with name from content
        const filename = sanitizeFilename(contentToSave)
        filePath = `${dir}/${filename}.md`

        // Handle duplicates
        let counter = 1
        while (await exists(filePath)) {
          filePath = `${dir}/${filename} ${counter}.md`
          counter++
        }
      } else {
        // Check if title changed and we need to rename
        const currentFilename = filePath.split('/').pop()?.replace('.md', '') || ''
        const newFilename = sanitizeFilename(contentToSave)

        if (currentFilename !== newFilename) {
          let newPath = `${dir}/${newFilename}.md`

          // Handle duplicates (but not with self)
          let counter = 1
          while (await exists(newPath) && newPath !== filePath) {
            newPath = `${dir}/${newFilename} ${counter}.md`
            counter++
          }

          if (newPath !== filePath) {
            await rename(filePath, newPath)
            oldPath = filePath
            filePath = newPath
          }
        }
      }

      setCurrentFilePath(filePath)
      await writeTextFile(filePath, contentToSave)
      recordFileAccess(filePath, oldPath)

      // Update file registration (handles new files and renames)
      const appWindow = getCurrentWindow()
      if (oldPath) {
        // Renamed: remove old registration
        const files = getOpenFiles()
        if (files[oldPath] === appWindow.label) {
          delete files[oldPath]
          localStorage.setItem(OPEN_FILES_KEY, JSON.stringify(files))
        }
      }
      registerOpenFile(filePath, appWindow.label)
    } catch (e) {
      console.error('saveFile error:', e)
    }
  }

  const openFile = async (filePath: string) => {
    try {
      const appWindow = getCurrentWindow()
      const myLabel = appWindow.label

      // Check if file is already open in another window
      const existingWindowLabel = getWindowForFile(filePath)
      if (existingWindowLabel && existingWindowLabel !== myLabel) {
        // Find the actual window
        const allWindows = await getAllWebviewWindows()
        const otherWindow = allWindows.find(w => w.label === existingWindowLabel)
        if (otherWindow) {
          setQuickOpenVisible(false)
          await otherWindow.setFocus()
          appWindow.close()
          return
        }
        // Window no longer exists, clean up stale entry
        unregisterWindow(existingWindowLabel)
      }

      // Unregister old file if we had one
      const oldPath = currentFilePath()
      if (oldPath) {
        const files = getOpenFiles()
        if (files[oldPath] === myLabel) {
          delete files[oldPath]
          localStorage.setItem(OPEN_FILES_KEY, JSON.stringify(files))
        }
      }

      const fileContent = await readTextFile(filePath)
      setContent(fileContent)
      setCurrentFilePath(filePath)
      recordFileAccess(filePath)
      registerOpenFile(filePath, myLabel)
      setQuickOpenVisible(false)
    } catch (e) {
      console.error('openFile error:', e)
    }
  }

  const listAllNotes = async (): Promise<string[]> => {
    const dir = await ensureDriftDir()
    try {
      const entries = await readDir(dir)
      return entries
        .filter(e => e.name?.endsWith('.md'))
        .map(e => `${dir}/${e.name}`)
    } catch {
      return []
    }
  }

  const handleContentChange = (newContent: string) => {
    setContent(newContent)

    // Debounced auto-save
    if (saveTimeout) clearTimeout(saveTimeout)
    saveTimeout = setTimeout(() => {
      saveFile(newContent)
    }, 1000) as unknown as number
  }

  const newNote = async () => {
    // Cancel any pending auto-save
    if (saveTimeout) clearTimeout(saveTimeout)

    // Always save current note if it has content
    const currentContent = content()
    const currentPath = currentFilePath()
    if (currentContent.trim()) {
      await saveFile(currentContent, currentPath)
    }

    // Unregister old file
    if (currentPath) {
      const appWindow = getCurrentWindow()
      const files = getOpenFiles()
      if (files[currentPath] === appWindow.label) {
        delete files[currentPath]
        localStorage.setItem(OPEN_FILES_KEY, JSON.stringify(files))
      }
    }

    setContent('')
    setCurrentFilePath(null)
    setQuickOpenVisible(false)
  }

  const saveNow = async () => {
    if (saveTimeout) clearTimeout(saveTimeout)
    const currentContent = content()
    const currentPath = currentFilePath()
    if (currentContent.trim()) {
      await saveFile(currentContent, currentPath)
    }
  }

  const openNewWindow = async (filePath?: string) => {
    const label = `drift-${Date.now()}`
    // Use current origin to work in both dev and production
    const base = window.location.origin
    const url = filePath ? `${base}/?file=${encodeURIComponent(filePath)}` : base
    new WebviewWindow(label, {
      url,
      title: 'Drift',
      width: 900,
      height: 700,
      minWidth: 400,
      minHeight: 300,
      titleBarStyle: 'overlay',
      hiddenTitle: true,
    })
  }

  onMount(async () => {
    await ensureDriftDir()
    loadFileAccessTimes()
    applyTheme(theme())

    const appWindow = getCurrentWindow()

    // Check for file parameter in URL (for opening in new window)
    const urlParams = new URLSearchParams(window.location.search)
    const fileParam = urlParams.get('file')
    if (fileParam) {
      openFile(fileParam)
    } else {
      // On refresh, reload the file if this window has one registered
      const files = getOpenFiles()
      const myFile = Object.entries(files).find(([_, label]) => label === appWindow.label)?.[0]
      if (myFile) {
        readTextFile(myFile).then(content => {
          setContent(content)
          setCurrentFilePath(myFile)
        }).catch(() => {
          // File no longer exists, clean up
          unregisterWindow(appWindow.label)
        })
      }
    }

    // Only respond to menu events if this window is focused
    const unlistenNew = listen('menu-new-note', () => {
      if (document.hasFocus()) newNote()
    })
    const unlistenNewWindow = listen('menu-new-window', () => {
      if (document.hasFocus()) openNewWindow()
    })
    const unlistenCloseWindow = listen('menu-close-window', () => {
      if (document.hasFocus()) {
        saveNow()
        unregisterWindow(appWindow.label)
        appWindow.close()
      }
    })
    const unlistenOpen = listen('menu-open-note', () => {
      if (document.hasFocus()) setQuickOpenVisible(true)
    })
    const unlistenCycleTheme = listen('menu-cycle-theme', () => {
      if (document.hasFocus()) cycleTheme()
    })
    const unlistenThemeSystem = listen('menu-theme-system', () => {
      if (document.hasFocus()) setThemeMode('system')
    })
    const unlistenThemeLight = listen('menu-theme-light', () => {
      if (document.hasFocus()) setThemeMode('light')
    })
    const unlistenThemeDark = listen('menu-theme-dark', () => {
      if (document.hasFocus()) setThemeMode('dark')
    })

    // Save on window close and unregister
    const unlistenClose = appWindow.onCloseRequested((event) => {
      saveNow() // Don't await - let it save in background
      unregisterWindow(appWindow.label)
    })

    // Save on window blur (switching apps)
    const handleBlur = () => saveNow()
    window.addEventListener('blur', handleBlur)

    // Save before browser unload (backup)
    const handleBeforeUnload = () => saveNow()
    window.addEventListener('beforeunload', handleBeforeUnload)

    onCleanup(() => {
      unlistenNew.then(fn => fn())
      unlistenNewWindow.then(fn => fn())
      unlistenCloseWindow.then(fn => fn())
      unlistenOpen.then(fn => fn())
      unlistenCycleTheme.then(fn => fn())
      unlistenThemeSystem.then(fn => fn())
      unlistenThemeLight.then(fn => fn())
      unlistenThemeDark.then(fn => fn())
      unlistenClose.then(fn => fn())
      window.removeEventListener('blur', handleBlur)
      window.removeEventListener('beforeunload', handleBeforeUnload)
      if (saveTimeout) clearTimeout(saveTimeout)
      if (statusTimeout) clearTimeout(statusTimeout)
    })
  })

  return (
    <div class="app">
      <div class="titlebar" data-tauri-drag-region />
      <Editor
        content={content()}
        onChange={handleContentChange}
        onNewNote={newNote}
        onOpenNote={() => setQuickOpenVisible(true)}
        onNewWindow={() => openNewWindow()}
        onCycleTheme={cycleTheme}
      />
      <Show when={quickOpenVisible()}>
        <QuickOpen
          fileAccessTimes={fileAccessTimes()}
          currentFile={currentFilePath()}
          onSelect={openFile}
          onSelectNewWindow={(path) => {
            setQuickOpenVisible(false)
            openNewWindow(path)
          }}
          onClose={() => setQuickOpenVisible(false)}
          listAllNotes={listAllNotes}
        />
      </Show>
      <Show when={statusMessage()}>
        <div class="status-message">{statusMessage()}</div>
      </Show>
    </div>
  )
}

export default App
