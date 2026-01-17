import { createSignal, onMount, onCleanup, Show } from 'solid-js'
import { listen } from '@tauri-apps/api/event'
import { getCurrentWindow } from '@tauri-apps/api/window'
import { WebviewWindow } from '@tauri-apps/api/webviewWindow'
import { documentDir } from '@tauri-apps/api/path'
import { readTextFile, writeTextFile, mkdir, exists, readDir, rename } from '@tauri-apps/plugin-fs'
import { Editor } from './components/Editor'
import { QuickOpen } from './components/QuickOpen'
import './App.css'

const DRIFT_FOLDER = 'Drift'
const MAX_RECENT_FILES = 10

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

  let saveTimeout: number | undefined

  const ensureDriftDir = async () => {
    try {
      let docDir = await documentDir()
      console.log('Document dir:', docDir)
      // Ensure no double slashes
      if (!docDir.endsWith('/')) docDir += '/'
      const dir = `${docDir}${DRIFT_FOLDER}`
      setDriftDir(dir)

      const dirExists = await exists(dir)
      console.log('Dir exists:', dirExists)
      if (!dirExists) {
        console.log('Creating dir:', dir)
        await mkdir(dir)
      }
      return dir
    } catch (e) {
      console.error('ensureDriftDir error:', e)
      throw e
    }
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
            console.log('Renaming:', filePath, '->', newPath)
            await rename(filePath, newPath)
            oldPath = filePath
            filePath = newPath
          }
        }
      }

      setCurrentFilePath(filePath)
      console.log('Saving to:', filePath)
      await writeTextFile(filePath, contentToSave)
      console.log('Saved successfully')
      recordFileAccess(filePath, oldPath)
    } catch (e) {
      console.error('saveFile error:', e)
    }
  }

  const openFile = async (filePath: string) => {
    const fileContent = await readTextFile(filePath)
    setContent(fileContent)
    setCurrentFilePath(filePath)
    recordFileAccess(filePath)
    setQuickOpenVisible(false)
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

    // Check for file parameter in URL (for opening in new window)
    const urlParams = new URLSearchParams(window.location.search)
    const fileParam = urlParams.get('file')
    if (fileParam) {
      openFile(fileParam)
    }

    // Only respond to menu events if this window is focused
    const unlistenNew = listen('menu-new-note', () => {
      if (document.hasFocus()) newNote()
    })
    const unlistenNewWindow = listen('menu-new-window', () => {
      if (document.hasFocus()) openNewWindow()
    })
    const unlistenOpen = listen('menu-open-note', () => {
      if (document.hasFocus()) setQuickOpenVisible(true)
    })

    // Save on window close
    const appWindow = getCurrentWindow()
    const unlistenClose = appWindow.onCloseRequested(async (event) => {
      await saveNow()
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
      unlistenOpen.then(fn => fn())
      unlistenClose.then(fn => fn())
      window.removeEventListener('blur', handleBlur)
      window.removeEventListener('beforeunload', handleBeforeUnload)
      if (saveTimeout) clearTimeout(saveTimeout)
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
    </div>
  )
}

export default App
