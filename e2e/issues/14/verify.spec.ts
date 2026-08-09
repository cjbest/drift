import { test, expect } from '@playwright/test'
import { getTauriMockScript } from '../../tauri-mocks'
import { assertScreenshot } from '../../helpers/screenshots'
import * as path from 'path'

const SCREENSHOTS_DIR = path.join(path.dirname(import.meta.url.replace('file://', '')), 'screenshots')

test.beforeEach(async ({ page }) => {
  await page.addInitScript(getTauriMockScript())
})

test('verify checkbox color - after fix', async ({ page }) => {
  await page.goto('/')
  await expect(page.locator('.cm-editor')).toBeVisible()

  // Type unchecked checkboxes
  await page.locator('.cm-content').click()
  await page.keyboard.type('- [ ] Unchecked task')
  await page.keyboard.press('Enter')
  await page.keyboard.type('Checked task')

  // Wait for rendering
  await page.waitForTimeout(200)

  // Click the second checkbox to check it
  const checkboxes = page.locator('.checkbox-marker')
  await checkboxes.nth(1).click()

  // Wait a moment for the color change
  await page.waitForTimeout(200)

  // Save "after" screenshot showing the green checkbox
  await page.screenshot({ path: path.join(SCREENSHOTS_DIR, 'after.png') })

  // Verify the checked checkbox is now green
  const result = await assertScreenshot(page, 'Check if the checked checkbox [x] appears in green color')
  console.log('Assertion result:', result)

  expect(result.passed).toBe(true)
})
