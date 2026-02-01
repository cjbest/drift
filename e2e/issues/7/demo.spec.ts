import { test, expect } from '@playwright/test'
import { getTauriMockScript } from '../../tauri-mocks'

test.beforeEach(async ({ page }) => {
  await page.addInitScript(getTauriMockScript())
})

test('demo: rainbow text in action', async ({ page }) => {
  test.slow()
  await page.setViewportSize({ width: 1000, height: 700 })
  await page.goto('/')
  await expect(page.locator('.cm-editor')).toBeVisible()

  // Type a title to showcase the rainbow effect
  const editor = page.locator('.cm-content')
  await editor.click()
  await page.keyboard.type('Rainbow Notes', { delay: 40 })
  await page.waitForTimeout(800)

  // Add a new line and type more content
  await page.keyboard.press('Enter')
  await page.waitForTimeout(400)
  await page.keyboard.type('Every character you type appears in a beautiful rainbow gradient.', { delay: 40 })
  await page.waitForTimeout(800)

  // Add another line with different content
  await page.keyboard.press('Enter')
  await page.keyboard.press('Enter')
  await page.waitForTimeout(400)
  await page.keyboard.type('The colors flow smoothly across your text, creating a subtle and pleasant visual effect.', { delay: 40 })
  await page.waitForTimeout(800)

  // Add a final line
  await page.keyboard.press('Enter')
  await page.keyboard.press('Enter')
  await page.waitForTimeout(400)
  await page.keyboard.type('Try typing anything - watch the rainbow unfold!', { delay: 40 })
  await page.waitForTimeout(1500)
})
