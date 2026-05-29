// Utilities for pointer and keyboard interactions in the Electron/web build.

/**
 * Enables click-drag scrolling on all ScrollView containers.
 * Returns a cleanup function to remove the listeners.
 */
export function enableDragScroll(): () => void {
  let dragTarget: Element | null = null;
  let startX = 0;
  let startY = 0;
  let scrollLeft = 0;
  let scrollTop = 0;

  const onMouseDown = (e: MouseEvent) => {
    const target = e.target as Element;
    const scroller = target.closest('[data-focusable], [role="scrollbar"], .rn-overflow-scroll, [style*="overflow"]') ??
      findScrollParent(target);
    if (!scroller) return;
    dragTarget = scroller;
    startX = e.clientX;
    startY = e.clientY;
    scrollLeft = (scroller as HTMLElement).scrollLeft;
    scrollTop = (scroller as HTMLElement).scrollTop;
    (scroller as HTMLElement).style.cursor = 'grabbing';
    e.preventDefault();
  };

  const onMouseMove = (e: MouseEvent) => {
    if (!dragTarget) return;
    const dx = e.clientX - startX;
    const dy = e.clientY - startY;
    (dragTarget as HTMLElement).scrollLeft = scrollLeft - dx;
    (dragTarget as HTMLElement).scrollTop = scrollTop - dy;
  };

  const onMouseUp = () => {
    if (dragTarget) {
      (dragTarget as HTMLElement).style.cursor = '';
      dragTarget = null;
    }
  };

  document.addEventListener('mousedown', onMouseDown);
  document.addEventListener('mousemove', onMouseMove);
  document.addEventListener('mouseup', onMouseUp);

  return () => {
    document.removeEventListener('mousedown', onMouseDown);
    document.removeEventListener('mousemove', onMouseMove);
    document.removeEventListener('mouseup', onMouseUp);
  };
}

function findScrollParent(el: Element | null): Element | null {
  while (el && el !== document.body) {
    const style = window.getComputedStyle(el);
    const overflow = style.overflow + style.overflowX + style.overflowY;
    if (/auto|scroll/.test(overflow)) return el;
    el = el.parentElement;
  }
  return null;
}

type Direction = 'ArrowLeft' | 'ArrowRight' | 'ArrowUp' | 'ArrowDown';

/**
 * Moves focus to the nearest focusable element in the given direction
 * using bounding-rect spatial proximity.
 */
export function spatialNavigate(direction: Direction): void {
  const current = document.activeElement as HTMLElement | null;
  if (!current) return;

  const candidates = Array.from(
    document.querySelectorAll<HTMLElement>('[tabindex="0"], button:not([disabled]), a[href], input:not([disabled])'),
  ).filter((el) => el !== current && !el.contains(current));

  const rect = current.getBoundingClientRect();
  const cx = rect.left + rect.width / 2;
  const cy = rect.top + rect.height / 2;

  let best: HTMLElement | null = null;
  let bestScore = Infinity;

  for (const el of candidates) {
    const r = el.getBoundingClientRect();
    if (r.width === 0 && r.height === 0) continue;
    const ex = r.left + r.width / 2;
    const ey = r.top + r.height / 2;
    const dx = ex - cx;
    const dy = ey - cy;

    const inDirection =
      direction === 'ArrowRight' ? dx > 0 :
      direction === 'ArrowLeft'  ? dx < 0 :
      direction === 'ArrowDown'  ? dy > 0 :
      /* ArrowUp */                dy < 0;

    if (!inDirection) continue;

    // Primary axis distance + weighted perpendicular penalty
    const primary = direction === 'ArrowRight' || direction === 'ArrowLeft' ? Math.abs(dx) : Math.abs(dy);
    const perp    = direction === 'ArrowRight' || direction === 'ArrowLeft' ? Math.abs(dy) : Math.abs(dx);
    const score   = primary + perp * 2;

    if (score < bestScore) {
      bestScore = score;
      best = el;
    }
  }

  best?.focus();
}
