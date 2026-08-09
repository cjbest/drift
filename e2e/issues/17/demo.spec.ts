import { test, expect } from '@playwright/test'
import { getTauriMockScript } from '../../tauri-mocks'

test.beforeEach(async ({ page }) => {
  await page.addInitScript(getTauriMockScript())
})

test('demo: fun animations and playful interactions', async ({ page }) => {
  test.slow()

  // Use a compact viewport to focus on content
  await page.setViewportSize({ width: 800, height: 600 })
  await page.goto('/')
  await expect(page.locator('.cm-editor')).toBeVisible()

  // Wait a moment before starting
  await page.waitForTimeout(500)

  // Type a fun welcome message
  const editor = page.locator('.cm-editor .cm-content')
  await editor.click()
  await page.keyboard.type('# Making Drift More Fun', { delay: 40 })
  await page.waitForTimeout(800)

  await page.keyboard.press('Enter')
  await page.keyboard.press('Enter')
  await page.keyboard.type('Here are the improvements:', { delay: 40 })
  await page.waitForTimeout(600)

  // Add checkboxes with bounce animation
  await page.keyboard.press('Enter')
  await page.keyboard.press('Enter')
  await page.keyboard.type('- [ ] Quick Open with scale animation', { delay: 40 })
  await page.waitForTimeout(400)

  await page.keyboard.press('Enter')
  await page.keyboard.type('- [ ] Bouncy checkbox interactions', { delay: 40 })
  await page.waitForTimeout(400)

  await page.keyboard.press('Enter')
  await page.keyboard.type('- [ ] Smooth theme transitions', { delay: 40 })
  await page.waitForTimeout(400)

  await page.keyboard.press('Enter')
  await page.keyboard.type('- [ ] Playful cursor pulse', { delay: 40 })
  await page.waitForTimeout(800)

  // Check off the first checkbox with bouncy animation
  const firstCheckbox = page.locator('.checkbox-marker').first()
  await firstCheckbox.click()
  await page.waitForTimeout(600)

  // Check off the second checkbox
  const secondCheckbox = page.locator('.checkbox-marker').nth(1)
  await secondCheckbox.click()
  await page.waitForTimeout(600)

  // Open Quick Open to show the scale-in animation
  await page.keyboard.press('Meta+P')
  await expect(page.locator('.quick-open')).toBeVisible()
  await page.waitForTimeout(1200)

  // Type a search query
  const searchInput = page.locator('.quick-open-input')
  await searchInput.type('note', { delay: 80 })
  await page.waitForTimeout(1000)

  // Close Quick Open
  await page.keyboard.press('Escape')
  await page.waitForTimeout(800)

  // Open search panel to show slide-in animation
  await page.keyboard.press('Meta+F')
  await page.waitForTimeout(1200)

  // Type in search
  const searchField = page.locator('.cm-panel.cm-search input[main-field]')
  if (await searchField.isVisible()) {
    await searchField.type('fun', { delay: 80 })
    await page.waitForTimeout(1000)
  }

  // Close search
  await page.keyboard.press('Escape')
  await page.waitForTimeout(600)

  // Add a final message
  await page.keyboard.press('End')
  await page.keyboard.press('Enter')
  await page.keyboard.press('Enter')
  await page.keyboard.type('Now it feels delightful! ✨', { delay: 40 })
  await page.waitForTimeout(1500)
})
