import { createSignal, createEffect, createMemo, onMount, For } from 'solid-js'
import type { JSX } from 'solid-js'
import './QuickOpen.css'

export interface NoteInfo {
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
  const days = Math.floor(minutes / 60 / 24)

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
  fileAccessTimes: Record<string, number>
  currentFile: string | null
  notes: NoteInfo[]
  onSelect: (filePath: string) => void
  onSelectNewWindow: (filePath: string) => void
  onClose: () => void
}

export function getFilename(path: string): string {
  return path.split('/').pop()?.replace('.md', '') || path
}

export function getPreview(content: string): string {
  // Get content after the first line, collapsed to single line
  const lines = content.split('\n').slice(1).filter(l => l.trim())
  return lines.join(' ').slice(0, 200)
}

function findMatch(query: string, text: string): number {
  // Returns index of match, or -1 if no match
  return text.toLowerCase().indexOf(query.toLowerCase())
}

export function QuickOpen(props: QuickOpenProps) {
  const [query, setQuery] = createSignal('')
  const [selectedIndex, setSelectedIndex] = createSignal(0)

  let inputRef: HTMLInputElement | undefined
  let listRef: HTMLDivElement | undefined

  onMount(() => {
    // Focus input immediately
    setTimeout(() => inputRef?.focus(), 0)
  })

  const getRelevantTime = (note: NoteInfo): number => {
    const accessTime = props.fileAccessTimes[note.path] || 0
    const createTime = note.createdAt?.getTime() || 0
    return Math.max(accessTime, createTime)
  }

  // Filter and sort notes reactively
  const filteredNotes = createMemo(() => {
    const q = query().trim()
    // Exclude current file
    let notes = props.notes.filter(n => n.path !== props.currentFile)

    if (q) {
      // Filter by substring match in title or preview
      notes = notes.filter(n =>
        findMatch(q, n.title) !== -1 || findMatch(q, n.preview) !== -1
      )
    }

    // Sort by most recent (either created or accessed)
    return [...notes].sort((a, b) => getRelevantTime(b) - getRelevantTime(a))
  })

  // Get display preview - show match snippet with bold highlighting
  const getDisplayPreview = (note: NoteInfo): JSX.Element => {
    const q = query().trim()
    if (!q) return <>{note.preview}</>

    const text = note.preview
    const idx = findMatch(q, text)

    if (idx === -1) return <>{text}</>

    // Get snippet around match
    const start = Math.max(0, idx - 30)
    const end = Math.min(text.length, idx + q.length + 120)

    const prefix = start > 0 ? '...' : ''
    const suffix = end < text.length ? '...' : ''

    const beforeMatch = text.slice(start, idx)
    const match = text.slice(idx, idx + q.length)
    const afterMatch = text.slice(idx + q.length, end)

    return <>{prefix}{beforeMatch}<strong>{match}</strong>{afterMatch}{suffix}</>
  }

  // Reset selection when query changes
  createEffect(() => {
    query() // track dependency
    setSelectedIndex(0)
  })

  // Scroll selected item into view
  createEffect(() => {
    const idx = selectedIndex()
    const item = listRef?.children[idx] as HTMLElement | undefined
    item?.scrollIntoView({ block: 'nearest' })
  })

  const handleKeyDown = (e: KeyboardEvent) => {
    // Stop all keyboard events from reaching CodeMirror
    e.stopPropagation()

    const notes = filteredNotes()

    switch (e.key) {
      case 'ArrowDown':
      case 'Tab':
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
          if (e.metaKey) {
            props.onSelectNewWindow(notes[selectedIndex()].path)
          } else {
            props.onSelect(notes[selectedIndex()].path)
          }
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
          autofocus
        />
        <div class="quick-open-list" ref={listRef}>
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
                  <span class="quick-open-preview">{getDisplayPreview(note)}</span>
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
