import { test, expect } from '@playwright/test'
import { getTauriMockScript } from './tauri-mocks'

test.beforeEach(async ({ page }) => {
  await page.addInitScript(getTauriMockScript())
})

test('bullet list with long wrapping lines', async ({ page }) => {
  // Use a narrower viewport to force wrapping
  await page.setViewportSize({ width: 600, height: 800 })

  await page.goto('/')
  await expect(page.locator('.cm-editor')).toBeVisible()
  await page.locator('.cm-content').click()

  // Start with a title, then bullet list
  await page.keyboard.type('My Notes')
  await page.keyboard.press('Enter')
  await page.keyboard.press('Enter')

  // Type bullet list with long lines using dashes
  const longText1 = 'This is a very long bullet point that should wrap multiple times because it contains so much text that it cannot possibly fit on a single line in the editor'
  const longText2 = 'Here is another extremely long bullet point with even more content that will definitely need to wrap around to multiple lines to demonstrate the indentation behavior'
  const longText3 = 'And a third long bullet point to really show how the wrapping and indentation works when you have several items in a list with lengthy content'

  await page.keyboard.type(`- ${longText1}`)
  await page.screenshot({ path: 'e2e/screenshots/bullet-wrap-1.png' })

  await page.keyboard.press('Enter')
  await page.keyboard.type(`- ${longText2}`)
  await page.screenshot({ path: 'e2e/screenshots/bullet-wrap-2.png' })

  await page.keyboard.press('Enter')
  await page.keyboard.type(`- ${longText3}`)
  await page.screenshot({ path: 'e2e/screenshots/bullet-wrap-3.png' })
})

test('checkbox list with long wrapping lines', async ({ page }) => {
  await page.setViewportSize({ width: 600, height: 800 })

  await page.goto('/')
  await expect(page.locator('.cm-editor')).toBeVisible()
  await page.locator('.cm-content').click()

  const longText1 = 'This is a checkbox item with a very long description that needs to wrap multiple times to fit in the viewport and should maintain proper indentation'
  const longText2 = 'Another checkbox with lengthy content that demonstrates how the text wraps and whether the indentation remains consistent across multiple lines'

  await page.keyboard.type(`- [ ] ${longText1}`)
  await page.screenshot({ path: 'e2e/screenshots/checkbox-wrap-1.png' })

  await page.keyboard.press('Enter')
  await page.keyboard.type(`- [ ] ${longText2}`)
  await page.screenshot({ path: 'e2e/screenshots/checkbox-wrap-2.png' })
})
