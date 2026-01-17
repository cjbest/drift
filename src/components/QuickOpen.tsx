import { createSignal, createEffect, onMount, For } from 'solid-js'
import { readTextFile, stat } from '@tauri-apps/plugin-fs'
import './QuickOpen.css'

interface NoteInfo {
  path: string
  title: string
  preview: string
  createdAt: Date | null
}

function formatRelativeDate(date: Date | null): string {
  if (!date) return ''

  const now = new Date()
  const diff = now.getTime() - date.getTime()
  const seconds = Math.floor(diff / 1000)
  const minutes = Math.floor(seconds / 60)
  const hours = Math.floor(minutes / 60)
  const days = Math.floor(hours / 24)

  // Within last minute
  if (seconds < 60) return `${seconds}s ago`

  // Within last hour
  if (minutes < 60) return `${minutes} min ago`

  // Today (but over an hour ago)
  const isToday = date.toDateString() === now.toDateString()
  if (isToday) {
    return date.toLocaleTimeString('en-US', { hour: 'numeric', minute: undefined, hour12: true }).toLowerCase()
  }

  // Yesterday
  const yesterday = new Date(now)
  yesterday.setDate(yesterday.getDate() - 1)
  if (date.toDateString() === yesterday.toDateString()) return 'yesterday'

  // Within last week
  if (days < 7) {
    return date.toLocaleDateString('en-US', { weekday: 'short' })
  }

  // This year
  if (date.getFullYear() === now.getFullYear()) {
    return date.toLocaleDateString('en-US', { month: 'short', day: 'numeric' })
  }

  // Older
  return date.toLocaleDateString('en-US', { month: 'short', day: 'numeric', year: 'numeric' })
}

interface QuickOpenProps {
  recentFiles: string[]
  onSelect: (filePath: string) => void
  onClose: () => void
  listAllNotes: () => Promise<string[]>
}

function getFilename(path: string): string {
  return path.split('/').pop()?.replace('.md', '') || path
}

function getPreview(content: string): string {
  // Get content after the first line, collapsed to single line
  const lines = content.split('\n').slice(1).filter(l => l.trim())
  return lines.join(' ').slice(0, 200)
}

function fuzzyMatch(query: string, text: string): boolean {
  const lowerQuery = query.toLowerCase()
  const lowerText = text.toLowerCase()
  let qi = 0
  for (let ti = 0; ti < lowerText.length && qi < lowerQuery.length; ti++) {
    if (lowerText[ti] === lowerQuery[qi]) qi++
  }
  return qi === lowerQuery.length
}

export function QuickOpen(props: QuickOpenProps) {
  const [query, setQuery] = createSignal('')
  const [allNotes, setAllNotes] = createSignal<NoteInfo[]>([])
  const [filteredNotes, setFilteredNotes] = createSignal<NoteInfo[]>([])
  const [selectedIndex, setSelectedIndex] = createSignal(0)

  let inputRef: HTMLInputElement | undefined

  onMount(async () => {
    // Load all notes with previews and creation dates
    const paths = await props.listAllNotes()
    const notes: NoteInfo[] = await Promise.all(
      paths.map(async (path) => {
        try {
          const [content, fileStat] = await Promise.all([
            readTextFile(path),
            stat(path),
          ])
          return {
            path,
            title: getFilename(path),
            preview: getPreview(content),
            createdAt: fileStat.birthtime ? new Date(fileStat.birthtime) : null,
          }
        } catch {
          return { path, title: getFilename(path), preview: '', createdAt: null }
        }
      })
    )
    setAllNotes(notes)

    // Start with recent files if no query
    updateFilteredNotes('')

    // Focus input
    inputRef?.focus()
  })

  const updateFilteredNotes = (q: string) => {
    const all = allNotes()
    if (!q.trim()) {
      // Show recent files first, then others
      const recentPaths = new Set(props.recentFiles)
      const recent = all.filter(n => recentPaths.has(n.path))
      const others = all.filter(n => !recentPaths.has(n.path))
      setFilteredNotes([...recent, ...others])
    } else {
      // Filter by query (match title or preview)
      const matches = all.filter(n =>
        fuzzyMatch(q, n.title) || fuzzyMatch(q, n.preview)
      )
      setFilteredNotes(matches)
    }
    setSelectedIndex(0)
  }

  createEffect(() => {
    updateFilteredNotes(query())
  })

  const handleKeyDown = (e: KeyboardEvent) => {
    // Stop all keyboard events from reaching CodeMirror
    e.stopPropagation()

    const notes = filteredNotes()

    switch (e.key) {
      case 'ArrowDown':
        e.preventDefault()
        setSelectedIndex(i => Math.min(i + 1, notes.length - 1))
        break
      case 'ArrowUp':
        e.preventDefault()
        setSelectedIndex(i => Math.max(i - 1, 0))
        break
      case 'Enter':
        e.preventDefault()
        if (notes[selectedIndex()]) {
          props.onSelect(notes[selectedIndex()].path)
        }
        break
      case 'Escape':
        e.preventDefault()
        props.onClose()
        break
    }
  }

  return (
    <div class="quick-open-overlay" onClick={() => props.onClose()}>
      <div class="quick-open" onClick={e => e.stopPropagation()}>
        <input
          ref={inputRef}
          type="text"
          class="quick-open-input"
          placeholder="Search..."
          value={query()}
          onInput={e => setQuery(e.currentTarget.value)}
          onKeyDown={handleKeyDown}
        />
        <div class="quick-open-list">
          <For each={filteredNotes()}>
            {(note, index) => (
              <div
                class="quick-open-item"
                classList={{ selected: index() === selectedIndex() }}
                onClick={() => props.onSelect(note.path)}
                onMouseMove={() => setSelectedIndex(index())}
              >
                <span class="quick-open-title">{note.title}</span>
                {note.preview && (
                  <span class="quick-open-preview">{note.preview}</span>
                )}
                {note.createdAt && (
                  <span class="quick-open-date">{formatRelativeDate(note.createdAt)}</span>
                )}
              </div>
            )}
          </For>
          {filteredNotes().length === 0 && (
            <div class="quick-open-empty">No notes found</div>
          )}
        </div>
      </div>
    </div>
  )
}
