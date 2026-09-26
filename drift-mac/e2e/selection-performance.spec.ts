import { test, expect, type Page } from "@playwright/test";
import { previewMocks } from "./preview-mocks";

const longNote = [
  "Selection field test",
  "",
  ...Array.from({ length: 100 }, (_, i) =>
    `Paragraph ${String(i + 1).padStart(3, "0")} — ` +
    "A long thought should stay easy to select as it wraps across the quiet page. ".repeat(5) +
    (i % 7 === 0 ? "English עברית العربية English." : "The end of this thought.") +
    "\n",
  ),
].join("\n");

async function settleSelection(page: Page) {
  await page.evaluate(() => new Promise<void>((resolve) => {
    requestAnimationFrame(() => requestAnimationFrame(() => resolve()));
  }));
}

async function openNote(page: Page, text: string) {
  await page.addInitScript(previewMocks());
  await page.goto("/");
  await expect(page.locator(".cm-editor")).toBeVisible();
  await page.evaluate(() => document.fonts.ready);
  await page.keyboard.insertText(text);
  await page.keyboard.press("Meta+Home");
  await page.evaluate(async () => {
    // Import the running Vite module so the counter observes the editor's real
    // coordinate hit tests, including work performed by selection painting.
    const modulePath = "/node_modules/.vite/deps/@codemirror_view.js";
    const { EditorView } = await import(modulePath);
    const view = EditorView.findFromDOM(document.querySelector(".cm-content"));
    if (!view) throw new Error("The test editor was not found");
    (window as any).__selectionView = view;
    (window as any).__selectionHitTests = 0;
    const prototype = Object.getPrototypeOf(view);
    const original = prototype.posAtCoords;
    prototype.posAtCoords = function (...args: any[]) {
      (window as any).__selectionHitTests++;
      return original.apply(this, args);
    };
  });
  await settleSelection(page);
}

async function select(page: Page, anchor: number, head: number) {
  await page.evaluate(({ anchor, head }) => {
    (window as any).__selectionView.dispatch({ selection: { anchor, head } });
  }, { anchor, head });
  await settleSelection(page);
}

async function copiedText(page: Page) {
  return page.locator(".cm-content").evaluate((el) => {
    const data = new DataTransfer();
    el.dispatchEvent(new ClipboardEvent("copy", {
      clipboardData: data,
      bubbles: true,
      cancelable: true,
    }));
    return data.getData("text/plain");
  });
}

async function expectVisibleTextHighlighted(page: Page) {
  await expect.poll(() => page.evaluate(() => {
    const view = (window as any).__selectionView;
    const selection = view.state.selection.main;
    const viewport = view.scrollDOM.getBoundingClientRect();
    const highlights = Array.from(document.querySelectorAll(
      ".drift-selectionLayer .cm-selectionBackground",
    ), (el) => el.getBoundingClientRect());
    let checked = 0;
    const missed: number[] = [];
    for (const visible of view.visibleRanges) {
      const from = Math.max(visible.from, selection.from);
      const to = Math.min(visible.to, selection.to);
      for (let pos = from; pos < to; pos += 13) {
        if (/\s/.test(view.state.doc.sliceString(pos, pos + 1))) continue;
        const start = view.domAtPos(pos);
        const end = view.domAtPos(pos + 1);
        const range = document.createRange();
        range.setStart(start.node, start.offset);
        range.setEnd(end.node, end.offset);
        for (const rect of Array.from(range.getClientRects())) {
          if (rect.width < 1 || rect.height < 1) continue;
          const x = (rect.left + rect.right) / 2;
          const y = (rect.top + rect.bottom) / 2;
          if (y < viewport.top + 2 || y > viewport.bottom - 2) continue;
          checked++;
          if (!highlights.some((highlight) =>
            x >= highlight.left - 1 && x <= highlight.right + 1 &&
            y >= highlight.top - 1 && y <= highlight.bottom + 1,
          )) missed.push(pos);
        }
      }
    }
    return { checkedEnough: checked > 10, missed };
  })).toEqual({ checkedEnough: true, missed: [] });
}

test("extending a long wrapped selection does not hit-test every visual row", async ({ page }) => {
  await page.setViewportSize({ width: 600, height: 850 });
  await openNote(page, longNote);
  await select(page, 0, longNote.length - 30);
  await expectVisibleTextHighlighted(page);
  expect(await page.locator(".drift-selectionLayer .cm-selectionBackground").count())
    .toBeGreaterThan(15);

  const counts: number[] = [];
  for (let i = 1; i <= 12; i++) {
    await page.evaluate(() => { (window as any).__selectionHitTests = 0; });
    await select(page, 0, longNote.length - 30 + i);
    counts.push(await page.evaluate(() => (window as any).__selectionHitTests));
  }
  // Native input may need a few coordinate queries. Painting a growing
  // selection must not add dozens or hundreds of hit tests on every update.
  expect(Math.max(...counts)).toBeLessThan(10);
  expect(await copiedText(page)).toBe(longNote.slice(0, longNote.length - 18));
});

test("dragging across wrapped paragraphs and blank lines selects the exact text", async ({ page }) => {
  await page.setViewportSize({ width: 650, height: 1000 });
  await openNote(page, longNote);
  const from = longNote.indexOf("Paragraph 001") + 5;
  const to = longNote.indexOf("Paragraph 002") + 70;
  const points = await page.evaluate(({ from, to }) => {
    const view = (window as any).__selectionView;
    const point = (pos: number) => {
      const rect = view.coordsAtPos(pos, 1);
      if (!rect) throw new Error(`Position ${pos} is not rendered`);
      return { x: rect.left, y: (rect.top + rect.bottom) / 2 };
    };
    return { from: point(from), to: point(to) };
  }, { from, to });
  await page.mouse.move(points.from.x, points.from.y);
  await page.mouse.down();
  await page.mouse.move(points.to.x, points.to.y, { steps: 24 });
  await page.mouse.up();
  await settleSelection(page);
  await expect.poll(() => copiedText(page)).toBe(longNote.slice(from, to));
  await expectVisibleTextHighlighted(page);

  const blankLineHighlighted = await page.evaluate(() => {
    const view = (window as any).__selectionView;
    const blank = view.state.doc.line(4);
    const rect = view.coordsAtPos(blank.from);
    const y = (rect.top + rect.bottom) / 2;
    return Array.from(document.querySelectorAll(
      ".drift-selectionLayer .cm-selectionBackground",
    )).some((el) => {
      const box = el.getBoundingClientRect();
      return box.top <= y && box.bottom >= y && box.width > 20;
    });
  });
  expect(blankLineHighlighted).toBe(true);
});

test("selection highlights follow rewraps, scrolling, edits, and expanding links", async ({ page }) => {
  await page.setViewportSize({ width: 700, height: 800 });
  const url = "https://example.com/reports/a-long-and-useful-report-name?section=overview&source=notebook";
  const text = longNote.replace("Paragraph 001", `Before ${url} after.\n\nParagraph 001`);
  await openNote(page, text);
  const compact = page.locator("[data-compact-link]");
  await expect(compact).toHaveCount(1);
  await select(page, text.indexOf("Before"), text.length);
  await expect(compact).toHaveCount(0);
  await expectVisibleTextHighlighted(page);

  await page.setViewportSize({ width: 430, height: 650 });
  await expectVisibleTextHighlighted(page);
  await page.locator(".cm-scroller").evaluate((el) => { el.scrollTop = 1800; });
  await expectVisibleTextHighlighted(page);
  await page.locator(".cm-scroller").evaluate((el) => { el.scrollTop = 0; });
  await settleSelection(page);

  // Moving outside the address contracts it and moves the later visual rows.
  const paragraph = text.indexOf("Paragraph 001");
  await select(page, paragraph, paragraph + 300);
  await expect(compact).toHaveCount(1);
  await expectVisibleTextHighlighted(page);

  const inserted = "Extra words change the wrapping. ".repeat(3);
  await page.evaluate(({ paragraph, inserted }) => {
    (window as any).__selectionView.dispatch({
      changes: { from: paragraph + 20, insert: inserted },
      selection: { anchor: paragraph, head: paragraph + 300 + inserted.length },
    });
  }, { paragraph, inserted });
  await expectVisibleTextHighlighted(page);
  expect(await copiedText(page)).toBe(
    text.slice(paragraph, paragraph + 20) + inserted + text.slice(paragraph + 20, paragraph + 300),
  );
});

test("drag selection survives edge scrolling, reversal, and copying after scrolling away", async ({ page }) => {
  await page.setViewportSize({ width: 600, height: 750 });
  await openNote(page, longNote);
  const anchor = longNote.indexOf("Paragraph 001") + 5;
  const start = await page.evaluate((anchor) => {
    const rect = (window as any).__selectionView.coordsAtPos(anchor);
    return { x: rect.left, y: (rect.top + rect.bottom) / 2 };
  }, anchor);
  await page.mouse.move(start.x, start.y);
  await page.mouse.down();
  await page.mouse.move(280, 738, { steps: 20 });
  await expect.poll(() => page.locator(".cm-scroller").evaluate(el => el.scrollTop))
    .toBeGreaterThan(200);
  const forwardHead = await page.evaluate(() => (window as any).__selectionView.state.selection.main.head);
  expect(forwardHead).toBeGreaterThan(anchor);
  await page.mouse.move(280, 45, { steps: 15 });
  await expect.poll(() => page.evaluate(() => (window as any).__selectionView.state.selection.main.head))
    .toBeLessThan(forwardHead);
  await page.mouse.move(280, 300, { steps: 8 });
  await page.mouse.up();
  await settleSelection(page);

  const selected = await page.evaluate(() => {
    const v = (window as any).__selectionView;
    const r = v.state.selection.main;
    return { anchor: r.anchor, head: r.head, text: v.state.sliceDoc(r.from, r.to) };
  });
  expect(selected.anchor).toBe(anchor);
  expect(selected.text.length).toBeGreaterThan(20);
  expect(await copiedText(page)).toBe(selected.text);
  await page.mouse.wheel(0, 1600);
  await expect.poll(() => page.locator(".cm-scroller").evaluate(el => el.scrollTop))
    .toBeGreaterThan(1000);
  await settleSelection(page);
  const top = await page.locator(".cm-scroller").evaluate(el => el.scrollTop);
  expect(await copiedText(page)).toBe(selected.text);
  await settleSelection(page);
  expect(await page.locator(".cm-scroller").evaluate(el => el.scrollTop)).toBeCloseTo(top, 0);
  expect(await page.evaluate(() => {
    const r = (window as any).__selectionView.state.selection.main;
    return { anchor: r.anchor, head: r.head };
  })).toEqual({ anchor: selected.anchor, head: selected.head });
});
