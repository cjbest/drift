import { test, expect } from '@playwright/test'
import { getTauriMockScript } from '../../tauri-mocks'

test.beforeEach(async ({ page }) => {
  await page.addInitScript(getTauriMockScript())
})

test('demo: keyboard shortcut hints fade in when holding Cmd', async ({ page }) => {
  test.slow()

  // Use a compact viewport for the demo
  await page.setViewportSize({ width: 700, height: 500 })

  await page.goto('/')
  await expect(page.locator('.cm-editor')).toBeVisible()

  // Type some content naturally
  await page.locator('.cm-editor').click()
  await page.keyboard.type('Planning my day...', { delay: 40 })
  await page.waitForTimeout(1000)

  // Press Enter to create a new line
  await page.keyboard.press('Enter')
  await page.waitForTimeout(500)

  // Type more content
  await page.keyboard.type('Need to remember the shortcuts', { delay: 40 })
  await page.waitForTimeout(1500)

  // Hold down Cmd to show hints
  await page.keyboard.down('Meta')
  await page.waitForTimeout(2500) // Show the hints for a while

  // Release Cmd to hide hints
  await page.keyboard.up('Meta')
  await page.waitForTimeout(1000)

  // Hold Cmd again to demonstrate it works repeatedly
  await page.keyboard.down('Meta')
  await page.waitForTimeout(2000)

  await page.keyboard.up('Meta')
  await page.waitForTimeout(800)
})
