import { test, expect } from '@playwright/test'
import { getTauriMockScript } from './tauri-mocks'

test.beforeEach(async ({ page }) => {
  await page.addInitScript(getTauriMockScript())
})

test('demo: writing a note with bullets and theme toggle', async ({ page }) => {
  // Slow down for demo effect
  test.slow()

  await page.setViewportSize({ width: 800, height: 600 })
  await page.goto('/')
  await expect(page.locator('.cm-editor')).toBeVisible()
  await page.locator('.cm-content').click()

  // Type a title
  await page.keyboard.type('Shopping List', { delay: 40 })
  await page.waitForTimeout(300)
  await page.keyboard.press('Enter')
  await page.keyboard.press('Enter')

  // Type some bullets
  await page.keyboard.type('- Apples', { delay: 40 })
  await page.waitForTimeout(200)
  await page.keyboard.press('Enter')

  await page.keyboard.type('- Bananas', { delay: 40 })
  await page.waitForTimeout(200)
  await page.keyboard.press('Enter')

  await page.keyboard.type('- Milk (oat milk if they have it, otherwise almond)', { delay: 30 })
  await page.waitForTimeout(400)
  await page.keyboard.press('Enter')

  await page.keyboard.type('- Bread', { delay: 40 })
  await page.waitForTimeout(500)

  // Toggle theme
  await page.keyboard.press('Meta+d')
  await page.waitForTimeout(800)

  // Toggle back
  await page.keyboard.press('Meta+d')
  await page.waitForTimeout(500)

  // Open quick open
  await page.keyboard.press('Meta+p')
  await page.waitForTimeout(600)

  // Close it
  await page.keyboard.press('Escape')
  await page.waitForTimeout(300)
})

test('demo: word count feature', async ({ page }) => {
  // Slow down for demo effect
  test.slow()

  await page.setViewportSize({ width: 800, height: 600 })
  await page.goto('/')
  await expect(page.locator('.cm-editor')).toBeVisible()
  await page.locator('.cm-content').click()

  // Type a title
  await page.keyboard.type('# My Writing Project', { delay: 50 })
  await page.waitForTimeout(400)
  await page.keyboard.press('Enter')
  await page.keyboard.press('Enter')

  // Type a paragraph
  await page.keyboard.type('This is a sample paragraph to demonstrate the word count feature.', { delay: 35 })
  await page.waitForTimeout(600)

  // Word count should be visible
  await expect(page.locator('.word-count')).toBeVisible()
  await page.waitForTimeout(400)

  // Add another sentence
  await page.keyboard.type(' It updates in real-time as you type.', { delay: 35 })
  await page.waitForTimeout(800)

  // Add more content
  await page.keyboard.press('Enter')
  await page.keyboard.press('Enter')
  await page.keyboard.type('The word count appears in the bottom-right corner.', { delay: 35 })
  await page.waitForTimeout(800)
})
