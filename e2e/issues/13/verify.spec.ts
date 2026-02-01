import { test, expect } from '@playwright/test'
import { getTauriMockScript } from '../../tauri-mocks'
import { assertScreenshot } from '../../helpers/screenshots'
import * as path from 'path'

const SCREENSHOTS_DIR = path.join(path.dirname(import.meta.url.replace('file://', '')), 'screenshots')

test.beforeEach(async ({ page }) => {
  await page.addInitScript(getTauriMockScript())
})

test('verify title underline', async ({ page }) => {
  await page.goto('/')
  await expect(page.locator('.cm-editor')).toBeVisible()

  // Type a title and some body content
  await page.locator('.cm-content').click()
  await page.keyboard.type('My Important Note')
  await page.keyboard.press('Enter')
  await page.keyboard.type('This is the body content of the note.')

  // Wait for rendering
  await page.waitForTimeout(500)

  // Save after screenshot
  await page.screenshot({ path: path.join(SCREENSHOTS_DIR, 'after.png') })

  // Verify the title has an underline
  const result = await assertScreenshot(page, 'title has a subtle gray underline below it')
  console.log('Title underline check:', result)
})
