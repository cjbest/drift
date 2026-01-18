import { createSignal } from 'solid-js'
import './ApiKeyDialog.css'

interface ApiKeyDialogProps {
  onSubmit: (key: string) => void
  onCancel: () => void
}

export function ApiKeyDialog(props: ApiKeyDialogProps) {
  const [key, setKey] = createSignal('')
  let inputRef: HTMLInputElement | undefined

  const handleSubmit = (e: Event) => {
    e.preventDefault()
    if (key().trim()) {
      props.onSubmit(key().trim())
    }
  }

  // Focus input on mount
  setTimeout(() => inputRef?.focus(), 0)

  return (
    <div class="api-key-overlay" onClick={props.onCancel}>
      <form class="api-key-dialog" onClick={(e) => e.stopPropagation()} onSubmit={handleSubmit}>
        <div class="api-key-title">Enter OpenAI API Key</div>
        <input
          ref={inputRef}
          type="password"
          class="api-key-input"
          placeholder="sk-..."
          value={key()}
          onInput={(e) => setKey(e.currentTarget.value)}
        />
        <div class="api-key-buttons">
          <button type="button" class="api-key-btn cancel" onClick={props.onCancel}>
            Cancel
          </button>
          <button type="submit" class="api-key-btn submit">
            Save
          </button>
        </div>
      </form>
    </div>
  )
}
