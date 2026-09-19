import { test, expect } from "@playwright/test";
import { previewMocks } from "./preview-mocks";

test.use({ locale: "en-US", timezoneId: "America/Los_Angeles" });

test("opening an older note promotes it and displays the same last-used date", async ({ page }) => {
  await page.clock.setFixedTime(new Date("2026-09-07T19:00:00Z"));
  await page.addInitScript(`
    ${previewMocks({
      "Edited note.md": "Edited note\n\nRecent writing",
      "Opened note.md": "Opened note\n\nEarlier writing",
      "Older note.md": "Older note\n\nOld writing",
    })}
    const modified = {
      'Edited note.md': Date.now() - 10 * 60000,
      'Opened note.md': Date.now() - 10 * 86400000,
      'Older note.md': Date.now() - 5 * 86400000,
    };
    localStorage.setItem('notebook:/isolated/Notebook:access', JSON.stringify({
      'Edited note.md': Date.now() - 30 * 60000,
      'Opened note.md': Date.now() - 5 * 60000,
    }));
    const originalInvoke = window.__TAURI_INTERNALS__.invoke;
    window.__TAURI_INTERNALS__.invoke = async (command, args) => {
      const result = await originalInvoke(command, args);
      return command === 'list_notes'
        ? result.map(note => ({ ...note, modified: modified[note.path] }))
        : result;
    };
  `);
  await page.goto("/");
  await expect(page.locator(".cm-editor")).toBeVisible();
  await page.keyboard.press("Meta+p");
  const titles = page.locator(".quick-open-title");
  const dates = page.locator(".quick-open-date");
  const ordered = ["Opened note", "Edited note", "Older note"];
  await expect(titles).toHaveText(ordered);
  await expect(dates).toHaveText(["11:55 AM", "11:50 AM", "Sep 2"]);
  await page.getByRole("combobox").fill("note");
  await expect(titles).toHaveText(ordered);
  await page.getByRole("combobox").fill("");
  await expect(titles).toHaveText(ordered);
  await page.getByRole("option").filter({ hasText: "Older note" }).click();
  await expect(page.locator(".quick-open")).toHaveCount(0);
  await expect(page.locator(".cm-content")).toContainText("Old writing");
  await page.keyboard.press("Meta+p");
  await expect(titles).toHaveText(["Opened note", "Edited note"]);
  await page.keyboard.press("Escape");
  await page.keyboard.press("Meta+n");
  await page.keyboard.press("Meta+p");
  await expect(titles).toHaveText(["Older note", "Opened note", "Edited note"]);
  await expect(dates).toHaveText(["12:00 PM", "11:55 AM", "11:50 AM"]);
  expect(await page.evaluate(() => (window as any).__writes)).toEqual([]);
});

test("synced pins appear first with clean titles before note bodies have loaded", async ({ page }) => {
  await page.addInitScript(`
    ${previewMocks({
      "Older.pinned.md": "Older\n\nA pinned note",
      "Recent.md": "Recent\n\nRecent writing",
    })}
    window.__readDelay = 10000;
    const originalInvoke = window.__TAURI_INTERNALS__.invoke;
    window.__TAURI_INTERNALS__.invoke = async (command, args) => {
      const result = await originalInvoke(command, args);
      return command === 'list_notes'
        ? result.map(note => ({ ...note, modified: note.path === 'Recent.md' ? 2000000 : 1000000 }))
        : result;
    };
  `);
  await page.goto("/");
  await expect(page.locator(".cm-editor")).toBeVisible();
  await page.keyboard.press("Meta+p");
  const titles = page.locator(".quick-open-title");
  await expect(titles).toHaveText(["Older", "Recent"]);
  const pinned = page.locator('[data-path="Older.pinned.md"]');
  const ordinary = page.locator('[data-path="Recent.md"]');
  await expect(pinned.getByRole("img", { name: "Pinned" })).toBeVisible();
  await expect(ordinary.locator(".quick-open-pin")).toHaveCount(0);
  const pinnedTitle = await pinned.locator(".quick-open-title").boundingBox();
  const ordinaryTitle = await ordinary.locator(".quick-open-title").boundingBox();
  expect(pinnedTitle!.x).toBe(ordinaryTitle!.x);
  expect((await pinned.boundingBox())!.height).toBe(61);
  expect((await ordinary.boundingBox())!.height).toBe(61);
  await page.getByRole("combobox").fill("e");
  await expect(titles).toHaveText(["Recent", "Older"]);
  await page.getByRole("combobox").fill("");
  await expect(titles).toHaveText(["Older", "Recent"]);
  expect(await page.evaluate(() => (window as any).__writes)).toEqual([]);
});
