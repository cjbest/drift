import { test, expect } from "@playwright/test";
import { previewMocks } from "./preview-mocks";
const bare =
  "https://example.com/reports/a-long-and-useful-report-name?section=overview&source=notebook";
const named =
  "https://example.org/research/a_(balanced)_address?version=2&full=true";
const fixture = `Link field test\n\nBefore ${bare} beside [Research](${named}) after.\n\nAfter the links`;

test.beforeEach(async ({ page }) => {
  await page.addInitScript(previewMocks());
  await page.goto("/");
  await expect
    .poll(() => page.evaluate(() => (window as any).__presented))
    .toBe(true);
  await page.keyboard.insertText(fixture);
  await page.keyboard.press("Meta+Home");
});
const compact = (page: any, url: string) =>
  page.locator(`[data-compact-link][data-url="${url}"]`);
const saved = (page: any) =>
  page.evaluate(() => (window as any).__mockFS.get("Link field test.md"));

test("collapsed links retain the host and sixteen characters of path", async ({ page }) => {
  await expect(compact(page, bare)).toHaveText("example.com/reports/a-long-…");
  await expect(compact(page, named)).toHaveText("(example.org/research/a_(bal…)");
  await expect.poll(() => saved(page)).toBe(fixture);
});

test("Cmd-click opens the exact destination from every shortened link surface, without moving the page", async ({
  page,
}) => {
  const after = page.getByText("After the links", { exact: true });
  const before = await after.boundingBox();
  for (const target of [
    compact(page, bare),
    page.locator(".note-link").filter({ hasText: /^Research$/ }),
    compact(page, named),
  ]) {
    await expect(target).toBeVisible();
    await target.click({ modifiers: ["Meta"] });
  }
  expect(await page.evaluate(() => (window as any).__openedUrls)).toEqual([
    bare,
    named,
    named,
  ]);
  expect(await page.evaluate(() => (window as any).__dragged)).toBe(false);
  expect((await after.boundingBox())!.y).toBe(before!.y);
  await expect.poll(() => saved(page)).toBe(fixture);
});

for (const kind of ["bare", "named"]) {
  test(`plain click edits a shortened ${kind} link in place without opening it`, async ({
    page,
  }) => {
    const url = kind === "bare" ? bare : named;
    const target = compact(page, url);
    const size = await target.boundingBox();
    await target.click({
      position: { x: size!.width - 2, y: size!.height / 2 },
    });
    await expect(compact(page, url)).toHaveCount(0);
    await expect(compact(page, kind === "bare" ? named : bare)).toBeVisible();
    await page.keyboard.insertText("&extra=1");
    await expect
      .poll(() => saved(page))
      .toBe(fixture.replace(url, url + "&extra=1"));
    expect(await page.evaluate(() => (window as any).__openedUrls)).toEqual([]);
  });
}

for (const kind of ["bare", "named"]) {
  for (const portion of ["host", "path"]) {
    test(`clicking visible ${portion} text places the cursor at that character in a ${kind} address`, async ({
      page,
    }) => {
      const url = kind === "bare" ? bare : named;
      if (kind === "named" && portion === "path")
        await page.setViewportSize({ width: 400, height: 700 });
      const offset = portion === "host" ? 4 : url.indexOf("/", 8) + 4 - 8;
      const point = await compact(page, url)
        .locator("[data-compact-text]")
        .evaluate((el: HTMLElement, index: number) => {
          const range = document.createRange();
          range.setStart(el.firstChild!, index);
          range.setEnd(el.firstChild!, index + 1);
          const box = range.getBoundingClientRect();
          return { x: box.left + 1, y: box.top + box.height / 2 };
        }, offset);
      await page.mouse.click(point.x, point.y);
      await page.keyboard.insertText("Z");
      const sourceOffset = 8 + offset;
      await expect
        .poll(() => saved(page))
        .toBe(
          fixture.replace(
            url,
            url.slice(0, sourceOffset) + "Z" + url.slice(sourceOffset),
          ),
        );
      expect(await page.evaluate(() => (window as any).__openedUrls)).toEqual([]);
    });
  }
}

test("clicked positions stay exact inside angle-delimited and escaped Markdown addresses", async ({
  page,
}) => {
  const source = "https://example.com/a\\(b\\) long-address?full=true";
  const note = `Link field test\n\n[Address](<${source}>)`;
  await page.keyboard.press("Meta+a");
  await page.keyboard.insertText(note);
  await page.keyboard.press("Meta+Home");
  const target = page.locator("[data-compact-text]");
  const point = await target.evaluate((el: HTMLElement) => {
    const index = el.textContent!.indexOf("b");
    const range = document.createRange();
    range.setStart(el.firstChild!, index);
    range.setEnd(el.firstChild!, index + 1);
    const box = range.getBoundingClientRect();
    return { x: box.left + 1, y: box.top + box.height / 2 };
  });
  await page.mouse.click(point.x, point.y);
  await page.keyboard.insertText("Z");
  await expect.poll(() => saved(page)).toBe(note.replace("a\\(b", "a\\(Zb"));
});

test("hover shows the whole address without reflow and Escape dismisses it", async ({
  page,
}, info) => {
  await page.setViewportSize({ width: 430, height: 660 });
  await page.evaluate(() => {
    document.documentElement.dataset.theme = "dark";
  });
  const after = page.getByText("After the links", { exact: true });
  const before = await after.boundingBox();
  await compact(page, named).hover();
  const tooltip = page.getByRole("tooltip");
  await expect(tooltip).toContainText(named);
  expect((await after.boundingBox())!.y).toBe(before!.y);
  const box = await tooltip.boundingBox();
  expect(box!.x).toBeGreaterThanOrEqual(12);
  expect(box!.x + box!.width).toBeLessThanOrEqual(418);
  await page.screenshot({ path: info.outputPath("link-hover.png") });
  await page.keyboard.press("Escape");
  await expect(tooltip).toHaveCount(0);
  await expect.poll(() => saved(page)).toBe(fixture);
});

test("keyboard editing expands only the entered link and copying retains full addresses", async ({
  page,
}) => {
  for (let i = 0; i < "Link field test\n\nBefore ".length; i++)
    await page.keyboard.press("ArrowRight");
  await expect(compact(page, bare)).toHaveCount(0);
  await expect(compact(page, named)).toBeVisible();
  await page.keyboard.press("ArrowLeft");
  await expect(compact(page, bare)).toBeVisible();
  await page.keyboard.press("Meta+a");
  const copied = await page.locator(".cm-content").evaluate((el) => {
    const data = new DataTransfer();
    el.dispatchEvent(
      new ClipboardEvent("copy", {
        clipboardData: data,
        bubbles: true,
        cancelable: true,
      }),
    );
    return data.getData("text/plain");
  });
  expect(copied).toBe(fixture);
});

test("URL punctuation is preserved correctly and code and unsafe destinations stay inert", async ({
  page,
}) => {
  await page.keyboard.press("Meta+a");
  await page.keyboard.insertText(
    "Link field test\n\nSee https://example.com/a_(b). And `https://example.net/code`. [No](javascript:alert(1))",
  );
  await page.keyboard.press("Meta+Home");
  const links = page.locator("[data-url]");
  await expect(links).toHaveCount(1);
  await links.click({ modifiers: ["Meta"] });
  expect(await page.evaluate(() => (window as any).__openedUrls)).toEqual([
    "https://example.com/a_(b)",
  ]);
});

test("a failed browser launch is reported without changing the note", async ({
  page,
}) => {
  await page.evaluate(() => {
    (window as any).__failOpen = true;
  });
  await compact(page, bare).click({ modifiers: ["Meta"] });
  await expect(page.getByRole("status")).toContainText(
    "Could not open this link",
  );
  await expect.poll(() => saved(page)).toBe(fixture);
});

test("Shift-click extends a selection across shortened text instead of replacing the cursor", async ({
  page,
}) => {
  await compact(page, bare).click({ modifiers: ["Shift"] });
  const selected = await page.evaluate(() => window.getSelection()?.toString());
  expect(selected).toContain("Link field test");
  expect(selected).toContain("Before");
  expect(await page.evaluate(() => (window as any).__openedUrls)).toEqual([]);
});

test("hover also works on a bare address and the named label", async ({
  page,
}) => {
  await compact(page, bare).hover();
  await expect(page.getByRole("tooltip")).toContainText(bare);
  await page.getByText("After the links", { exact: true }).hover();
  await page.locator(".note-link").filter({ hasText: /^Research$/ }).hover();
  await expect(page.getByRole("tooltip")).toContainText(named);
});

test("editing an angle-delimited Markdown address keeps its delimiters intact", async ({
  page,
}) => {
  const source = "https://example.com/a long address?x=1";
  await page.keyboard.press("Meta+a");
  await page.keyboard.insertText(`Link field test\n\n[Address](<${source}>)`);
  await page.keyboard.press("Meta+Home");
  const target = compact(page, new URL(source).href);
  const box = await target.boundingBox();
  await target.click({ position: { x: box!.width - 2, y: box!.height / 2 } });
  await page.keyboard.insertText("&y=2");
  await expect
    .poll(() => saved(page))
    .toBe(`Link field test\n\n[Address](<${source}&y=2>)`);
});

test("literal ampersands in bare addresses are not decoded as Markdown entities", async ({
  page,
}) => {
  const source = "https://example.com/?q=one&amp;literal=two";
  await page.keyboard.press("Meta+a");
  await page.keyboard.insertText(
    `Link field test\n\n${source}\n\n[Named](${source})`,
  );
  await page.keyboard.press("Meta+Home");
  await page.locator(`[data-url="${source}"]`).click({ modifiers: ["Meta"] });
  await page
    .locator(".note-link")
    .filter({ hasText: "Named" })
    .click({ modifiers: ["Meta"] });
  expect(await page.evaluate(() => (window as any).__openedUrls)).toEqual([
    source,
    source.replace("&amp;", "&"),
  ]);
});
