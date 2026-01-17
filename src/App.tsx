import { createSignal } from 'solid-js'
import { Editor } from './components/Editor'
import './App.css'

function App() {
  const [content, setContent] = createSignal('')

  return (
    <div class="app">
      <div class="titlebar" data-tauri-drag-region />
      <Editor
        content={content()}
        onChange={setContent}
      />
    </div>
  )
}

export default App
