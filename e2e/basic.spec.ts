import { test, expect } from '@playwright/test'
import { getTauriMockScript, mockFS, emitEvent } from './tauri-mocks'

// Inject Tauri mocks before each test
test.beforeEach(async ({ page }) => {
  await page.addInitScript(getTauriMockScript())
})

test('app loads and shows editor', async ({ page }) => {
  await page.goto('/')

  // Wait for the app to be ready
  await expect(page.locator('.app')).toBeVisible()

  // Editor should be visible
  await expect(page.locator('.cm-editor')).toBeVisible()

  // Take a screenshot for inspection
  await page.screenshot({ path: 'e2e/screenshots/app-loaded.png' })
})

test('can type in the editor', async ({ page }) => {
  await page.goto('/')

  // Wait for CodeMirror to be ready
  await expect(page.locator('.cm-editor')).toBeVisible()

  // Click to focus the editor
  await page.locator('.cm-content').click()

  // Type some content
  await page.keyboard.type('# Hello World\n\nThis is a test note.')

  // Verify content appears
  await expect(page.locator('.cm-content')).toContainText('Hello World')

  await page.screenshot({ path: 'e2e/screenshots/typed-content.png' })
})

test('Cmd+P opens quick open dialog', async ({ page }) => {
  await page.goto('/')
  await expect(page.locator('.cm-editor')).toBeVisible()

  // Press Cmd+P (Meta+P on Mac)
  await page.keyboard.press('Meta+p')

  // Quick open should appear
  await expect(page.locator('.quick-open')).toBeVisible()

  await page.screenshot({ path: 'e2e/screenshots/quick-open.png' })

  // Press Escape to close
  await page.keyboard.press('Escape')
  await expect(page.locator('.quick-open')).not.toBeVisible()
})

test('can see existing note in quick open', async ({ page }) => {
  await page.goto('/')
  await expect(page.locator('.cm-editor')).toBeVisible()

  // Add the file to mock FS
  await page.evaluate(() => {
    window.__mockFS.set('/mock-documents/Drift/Test Note.md', '# Test Note\n\nThis is test content.')
  })

  // Trigger window focus to refresh the notes cache
  await page.evaluate(() => window.dispatchEvent(new Event('focus')))
  await page.waitForTimeout(500)

  // Open quick open
  await page.keyboard.press('Meta+p')
  await expect(page.locator('.quick-open')).toBeVisible()

  // The note should appear in the list
  await expect(page.locator('.quick-open-item')).toContainText('Test Note')

  await page.screenshot({ path: 'e2e/screenshots/quick-open-with-note.png' })
})

test('theme toggle works', async ({ page }) => {
  await page.goto('/')
  await expect(page.locator('.cm-editor')).toBeVisible()

  // Take screenshot of default theme
  await page.screenshot({ path: 'e2e/screenshots/theme-default.png' })

  // Press Cmd+Shift+L to toggle theme
  await page.keyboard.press('Meta+Shift+l')

  // Wait for theme change
  await page.waitForTimeout(100)

  // Take screenshot of toggled theme
  await page.screenshot({ path: 'e2e/screenshots/theme-toggled.png' })
})

test('creates new note on Cmd+N', async ({ page }) => {
  await page.goto('/')
  await expect(page.locator('.cm-editor')).toBeVisible()

  // Type some content first
  await page.locator('.cm-content').click()
  await page.keyboard.type('# First Note')

  // Wait a bit for auto-save
  await page.waitForTimeout(1100)

  // Press Cmd+N for new note
  await page.keyboard.press('Meta+n')

  // Editor should be cleared (or show new note)
  await page.waitForTimeout(100)

  await page.screenshot({ path: 'e2e/screenshots/new-note.png' })
})
