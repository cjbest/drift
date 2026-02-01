import { test, expect } from '@playwright/test'
import { getTauriMockScript } from '../../tauri-mocks'
import { assertScreenshot } from '../../helpers/screenshots'

test.beforeEach(async ({ page }) => {
  await page.addInitScript(getTauriMockScript())
})

test('verify fonts - light mode', async ({ page }) => {
  // Force light mode
  await page.addInitScript(() => {
    localStorage.setItem('drift-theme', 'light')
  })

  await page.goto('/')
  await expect(page.locator('.cm-editor')).toBeVisible()

  // Add sample content showcasing typography
  await page.locator('.cm-content').click()
  await page.keyboard.type('Beautiful Typography Test', { delay: 10 })
  await page.keyboard.press('Enter')
  await page.keyboard.press('Enter')
  await page.keyboard.type('This is regular body text in the editor. It should be highly readable and comfortable for long-form writing. The spacing, weight, and character forms all contribute to the overall aesthetic.', { delay: 5 })
  await page.keyboard.press('Enter')
  await page.keyboard.press('Enter')
  await page.keyboard.type('**Bold text** and *italic text* for emphasis.', { delay: 5 })
  await page.keyboard.press('Enter')
  await page.keyboard.press('Enter')
  await page.keyboard.type('# Heading Level 1', { delay: 10 })
  await page.keyboard.press('Enter')
  await page.keyboard.type('## Heading Level 2', { delay: 10 })
  await page.keyboard.press('Enter')
  await page.keyboard.type('### Heading Level 3', { delay: 10 })
  await page.keyboard.press('Enter')
  await page.keyboard.press('Enter')
  await page.keyboard.type('> A thoughtful blockquote that demonstrates italic styling and proper spacing.', { delay: 5 })
  await page.keyboard.press('Enter')
  await page.keyboard.press('Enter')
  await page.keyboard.type('- [ ] Task list item', { delay: 5 })
  await page.keyboard.press('Enter')
  await page.keyboard.type('* Bullet point item', { delay: 5 })

  // Wait for rendering
  await page.waitForTimeout(500)

  // Capture screenshot
  const result = await assertScreenshot(page, 'typography is elegant and refined with good spacing and hierarchy in light mode', {
    save: { testFile: import.meta.url, name: 'after-light' }
  })
  console.log('Light mode assertion:', result)
})

test('verify fonts - dark mode', async ({ page }) => {
  // Force dark mode
  await page.addInitScript(() => {
    localStorage.setItem('drift-theme', 'dark')
  })

  await page.goto('/')
  await expect(page.locator('.cm-editor')).toBeVisible()

  // Add same sample content
  await page.locator('.cm-content').click()
  await page.keyboard.type('Beautiful Typography Test', { delay: 10 })
  await page.keyboard.press('Enter')
  await page.keyboard.press('Enter')
  await page.keyboard.type('This is regular body text in the editor. It should be highly readable and comfortable for long-form writing. The spacing, weight, and character forms all contribute to the overall aesthetic.', { delay: 5 })
  await page.keyboard.press('Enter')
  await page.keyboard.press('Enter')
  await page.keyboard.type('**Bold text** and *italic text* for emphasis.', { delay: 5 })
  await page.keyboard.press('Enter')
  await page.keyboard.press('Enter')
  await page.keyboard.type('# Heading Level 1', { delay: 10 })
  await page.keyboard.press('Enter')
  await page.keyboard.type('## Heading Level 2', { delay: 10 })
  await page.keyboard.press('Enter')
  await page.keyboard.type('### Heading Level 3', { delay: 10 })
  await page.keyboard.press('Enter')
  await page.keyboard.press('Enter')
  await page.keyboard.type('> A thoughtful blockquote that demonstrates italic styling and proper spacing.', { delay: 5 })
  await page.keyboard.press('Enter')
  await page.keyboard.press('Enter')
  await page.keyboard.type('- [ ] Task list item', { delay: 5 })
  await page.keyboard.press('Enter')
  await page.keyboard.type('* Bullet point item', { delay: 5 })

  // Wait for rendering
  await page.waitForTimeout(500)

  // Capture screenshot
  const result = await assertScreenshot(page, 'typography is elegant and refined with good spacing and hierarchy in dark mode', {
    save: { testFile: import.meta.url, name: 'after-dark' }
  })
  console.log('Dark mode assertion:', result)
})
