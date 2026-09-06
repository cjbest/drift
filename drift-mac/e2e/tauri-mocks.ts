import { previewMocks } from './preview-mocks'

/** Compatibility entry point for the original editor interaction fixtures. */
export function getTauriMockScript() {
  return previewMocks() + `
    window.__emitTauriEvent = (event, payload) => window.__emit(event, payload);
  `;
}

// Helper for tests to interact with the mock file system
export const mockFS = {
  set: (page: any, path: string, content: string) =>
    page.evaluate(([p, c]: [string, string]) => window.__mockFS.set(p, c), [path, content]),

  get: (page: any, path: string) =>
    page.evaluate((p: string) => window.__mockFS.get(p), path),

  has: (page: any, path: string) =>
    page.evaluate((p: string) => window.__mockFS.has(p), path),

  list: (page: any) =>
    page.evaluate(() => Array.from(window.__mockFS.keys())),

  clear: (page: any) =>
    page.evaluate(() => window.__mockFS.clear()),
}

// Helper to emit Tauri events from tests
export const emitEvent = (page: any, event: string, payload?: any) =>
  page.evaluate(([e, p]: [string, any]) => window.__emitTauriEvent(e, p), [event, payload])

// TypeScript declarations for the mocks
declare global {
  interface Window {
    __mockFS: Map<string, string>
    __mockDirs: Set<string>
    __eventListeners: Map<string, Set<Function>>
    __mockWindowLabel: string
    __emitTauriEvent: (event: string, payload?: any) => void
    __onCloseCallback?: Function
    __TAURI_INTERNALS__: any
  }
}
