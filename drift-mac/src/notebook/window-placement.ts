/** All coordinates are logical pixels on the originating monitor. */
export function cascadeWindow(
  parent: { x: number; y: number; width: number; height: number },
  area: { x: number; y: number; width: number; height: number },
) {
  const width = Math.min(parent.width, area.width);
  const height = Math.min(parent.height, area.height);
  const maxX = area.x + area.width - width;
  const maxY = area.y + area.height - height;
  return {
    width,
    height,
    x:
      parent.x + 28 <= maxX
        ? Math.max(area.x, parent.x + 28)
        : Math.min(area.x + 16, maxX),
    y:
      parent.y + 28 <= maxY
        ? Math.max(area.y, parent.y + 28)
        : Math.min(area.y + 16, maxY),
  };
}
