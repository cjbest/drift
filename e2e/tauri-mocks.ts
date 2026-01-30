/**
 * Tauri API mocks for browser testing.
 * This gets injected into the page before app scripts run.
 */

// In-memory file system for testing
const mockFileSystem: Map<string, string> = new Map()
const mockDirectories: Set<string> = new Set(['/mock-documents/Drift'])

// Event listeners for menu events
const eventListeners: Map<string, Set<Function>> = new Map()

// Mock window state
let mockWindowLabel = 'main'

export function getTauriMockScript() {
  return `
    // In-memory file system
    window.__mockFS = new Map();
    window.__mockDirs = new Set(['/mock-documents/Drift']);
    window.__eventListeners = new Map();
    window.__mockWindowLabel = 'main';

    // Mock Tauri internals
    window.__TAURI_INTERNALS__ = {
      invoke: async (cmd, args) => {
        // console.log('Tauri invoke:', cmd, args);

        // File system commands (plugin:fs)
        if (cmd === 'plugin:fs|read_text_file') {
          const path = args.path;
          if (window.__mockFS.has(path)) {
            return window.__mockFS.get(path);
          }
          throw new Error('File not found: ' + path);
        }

        if (cmd === 'plugin:fs|write_text_file') {
          window.__mockFS.set(args.path, args.contents);
          return null;
        }

        if (cmd === 'plugin:fs|exists') {
          const path = args.path;
          return window.__mockFS.has(path) || window.__mockDirs.has(path);
        }

        if (cmd === 'plugin:fs|create_dir' || cmd === 'plugin:fs|mkdir') {
          window.__mockDirs.add(args.path);
          return null;
        }

        if (cmd === 'plugin:fs|read_dir') {
          const dir = args.path;
          const entries = [];
          for (const path of window.__mockFS.keys()) {
            if (path.startsWith(dir + '/')) {
              const name = path.slice(dir.length + 1);
              if (!name.includes('/')) {
                entries.push({ name, isFile: true, isDirectory: false });
              }
            }
          }
          return entries;
        }

        if (cmd === 'plugin:fs|rename') {
          const content = window.__mockFS.get(args.oldPath);
          if (content !== undefined) {
            window.__mockFS.delete(args.oldPath);
            window.__mockFS.set(args.newPath, content);
          }
          return null;
        }

        if (cmd === 'plugin:fs|stat') {
          return {
            isFile: true,
            isDirectory: false,
            size: 100,
            birthtime: Date.now() - 1000000,
            mtime: Date.now(),
          };
        }

        // Path commands
        // Tauri 2 uses numeric enums for directories:
        // 6 = Document, 5 = Desktop, 7 = Download, etc.
        if (cmd === 'plugin:path|resolve_directory') {
          if (args.directory === 6 || args.directory === 'Document') {
            return '/mock-documents';
          }
          return '/mock-dir-' + args.directory;
        }

        // Window commands
        if (cmd === 'plugin:window|current') {
          return { label: window.__mockWindowLabel };
        }

        // Webview window commands
        if (cmd === 'plugin:webview|get_all_webviews') {
          return [{ label: window.__mockWindowLabel }];
        }

        if (cmd === 'plugin:webview|create_webview_window') {
          return { label: 'drift-' + Date.now() };
        }

        // Default: log and return null
        console.log('Unhandled Tauri invoke:', cmd, args);
        return null;
      },

      transformCallback: (callback, once) => {
        const id = Math.random().toString(36).slice(2);
        window['_' + id] = callback;
        return id;
      },
    };

    // Mock for @tauri-apps/api/event listen()
    window.__TAURI_INTERNALS__.metadata = {
      currentWindow: { label: window.__mockWindowLabel },
      currentWebview: { label: window.__mockWindowLabel },
    };

    // Helper to emit mock events (for tests to trigger menu actions)
    window.__emitTauriEvent = (event, payload) => {
      const listeners = window.__eventListeners.get(event) || [];
      listeners.forEach(fn => fn({ payload }));
    };

    // Intercept event listener registration
    const originalInvoke = window.__TAURI_INTERNALS__.invoke;
    window.__TAURI_INTERNALS__.invoke = async (cmd, args) => {
      if (cmd === 'plugin:event|listen') {
        const { event, handler } = args;
        if (!window.__eventListeners.has(event)) {
          window.__eventListeners.set(event, new Set());
        }
        window.__eventListeners.get(event).add(window['_' + handler]);
        return handler;
      }
      if (cmd === 'plugin:event|unlisten') {
        return null;
      }
      return originalInvoke(cmd, args);
    };

    // Mock window methods that get called on the window object
    window.__TAURI_INTERNALS__.windowMethods = {
      close: () => console.log('Window close requested'),
      setFocus: () => Promise.resolve(),
      startDragging: () => Promise.resolve(),
      onCloseRequested: (cb) => {
        window.__onCloseCallback = cb;
        return Promise.resolve(() => {});
      },
    };
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
