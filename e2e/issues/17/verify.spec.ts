import { test, expect } from '@playwright/test'
import { getTauriMockScript } from '../../tauri-mocks'
import { assertScreenshot } from '../../helpers/screenshots'
import * as path from 'path'

const SCREENSHOTS_DIR = path.join(path.dirname(import.meta.url.replace('file://', '')), 'screenshots')

test.beforeEach(async ({ page }) => {
  await page.addInitScript(getTauriMockScript())
})

test('verify issue - app should feel fun and playful', async ({ page }) => {
  await page.goto('/')
  await expect(page.locator('.cm-editor')).toBeVisible()

  // Type some content with checkboxes to show interaction points
  const editor = page.locator('.cm-editor .cm-content')
  await editor.click()
  await page.keyboard.type('# Welcome to Drift\n\n')
  await page.keyboard.type('- [ ] Add some fun animations\n')
  await page.keyboard.type('- [ ] Make it more playful\n')
  await page.keyboard.type('- [ ] Delight the user\n\n')
  await page.keyboard.type('The app works but could use more personality!')

  // Wait for content to render
  await page.waitForTimeout(500)

  // Open Quick Open dialog to show another interaction point
  await page.keyboard.press('Meta+P')
  await expect(page.locator('.quick-open')).toBeVisible()
  await page.waitForTimeout(300)

  // Save screenshot directly to issue directory (before state)
  await page.screenshot({ path: path.join(SCREENSHOTS_DIR, 'before.png') })

  console.log('Before screenshot captured - showing current sterile interface')
})

test('verify fix - app should have fun animations and personality', async ({ page }) => {
  await page.goto('/')
  await expect(page.locator('.cm-editor')).toBeVisible()

  // Type some content with checkboxes
  const editor = page.locator('.cm-editor .cm-content')
  await editor.click()
  await page.keyboard.type('# Welcome to Drift\n\n')
  await page.keyboard.type('- [ ] Add some fun animations\n')
  await page.keyboard.type('- [ ] Make it more playful\n')
  await page.keyboard.type('- [ ] Delight the user\n\n')
  await page.keyboard.type('The app works but could use more personality!')

  // Wait for content to render
  await page.waitForTimeout(500)

  // Check a checkbox to trigger the fun animation
  const checkbox = page.locator('.checkbox-marker').first()
  await checkbox.click()
  await page.waitForTimeout(500)

  // Open Quick Open dialog to show animation
  await page.keyboard.press('Meta+P')
  await expect(page.locator('.quick-open')).toBeVisible()
  await page.waitForTimeout(500)

  // Save screenshot directly to issue directory (after state)
  await page.screenshot({ path: path.join(SCREENSHOTS_DIR, 'after.png') })

  // Verify animations are present through visual assertion
  const result = await assertScreenshot(page, 'the Quick Open dialog should have a smooth animated appearance with a subtle backdrop')
  console.log('Visual assertion result:', result)
})
