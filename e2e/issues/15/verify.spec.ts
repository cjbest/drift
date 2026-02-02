import { test, expect } from '@playwright/test'
import { getTauriMockScript } from '../../tauri-mocks'
import { assertScreenshot } from '../../helpers/screenshots'
import * as path from 'path'

const SCREENSHOTS_DIR = path.join(path.dirname(import.meta.url.replace('file://', '')), 'screenshots')

test.beforeEach(async ({ page }) => {
  await page.addInitScript(getTauriMockScript())
})

test('verify keyboard shortcut hints appear when Cmd is held', async ({ page }) => {
  await page.goto('/')
  await expect(page.locator('.cm-editor')).toBeVisible()

  // Type some content in the editor
  await page.locator('.cm-editor').click()
  await page.keyboard.type('This is a test note')

  // BEFORE: Without Cmd held - should NOT show hints
  await page.screenshot({ path: path.join(SCREENSHOTS_DIR, 'before.png') })

  // AFTER: Hold Cmd key and capture - should show hints
  await page.keyboard.down('Meta')
  await page.waitForTimeout(300) // Wait for fade-in animation

  // Verify hints are visible
  await expect(page.locator('.keyboard-hints')).toBeVisible()

  await page.screenshot({ path: path.join(SCREENSHOTS_DIR, 'after.png') })

  const result = await assertScreenshot(page, 'keyboard shortcut hints are visible showing shortcuts like ⌘N, ⌘P, ⌘D')
  console.log('After assertion:', result)

  await page.keyboard.up('Meta')

  // Verify hints disappear when Cmd is released
  await page.waitForTimeout(100)
  await expect(page.locator('.keyboard-hints')).not.toBeVisible()
})
