import { useEffect, useRef } from 'react';
import { Platform, View } from 'react-native';

/**
 * On web, converts vertical mouse wheel events to horizontal scrolling
 * for the best scrollable child element inside the ref'd container.
 * Uses a MutationObserver to re-detect when content changes (e.g. categories load async).
 * Marks the scrollable element with `.m3u-scroll` for styled scrollbar CSS.
 * Returns a ref to attach to the container View wrapping a horizontal ScrollView.
 * No-op on native platforms.
 */
export function useHorizontalWheelScroll() {
  const ref = useRef<View>(null);

  useEffect(() => {
    if (Platform.OS !== 'web') return;
    const el = ref.current as unknown as HTMLElement;
    if (!el?.addEventListener) return;

    let scrollableEl: HTMLElement | null = null;

    /**
     * Find the ScrollView's scroll container by walking up from buttons.
     * Structure: ref > wrapper > ScrollView-container > content-row > buttons
     * The ScrollView-container (grandparent of buttons) is what we want.
     */
    const findScrollable = (): HTMLElement | null => {
      const firstButton = el.querySelector('button') || el.querySelector('[role="button"]');
      if (!firstButton) {
        return null;
      }
      const contentRow = firstButton.parentElement;
      if (!contentRow || contentRow === el) {
        return null;
      }
      const scrollContainer = contentRow.parentElement;
      if (!scrollContainer || scrollContainer === el) {
        return contentRow as HTMLElement;
      }
      return scrollContainer as HTMLElement;
    };

    const applyScrollStyles = (): void => {
      const found = findScrollable();
      if (found && found !== scrollableEl) {
        if (scrollableEl) {
          scrollableEl.classList.remove('m3u-scroll');
          scrollableEl.style.overflowX = '';
        }
        scrollableEl = found;
        found.style.overflowX = 'auto';
        found.classList.add('m3u-scroll');
      }
    };

    const handler = (e: WheelEvent) => {
      if (Math.abs(e.deltaY) <= Math.abs(e.deltaX)) {
        return;
      }
      if (!scrollableEl) {
        applyScrollStyles();
      }
      if (scrollableEl) {
        e.preventDefault();
        scrollableEl.scrollLeft += e.deltaY;
      }
    };

    applyScrollStyles();

    const observer = new MutationObserver(() => {
      applyScrollStyles();
    });
    observer.observe(el, { childList: true, subtree: true });

    el.addEventListener('wheel', handler, { passive: false });
    return () => {
      observer.disconnect();
      el.removeEventListener('wheel', handler);
      if (scrollableEl) {
        scrollableEl.classList.remove('m3u-scroll');
        scrollableEl.style.overflowX = '';
      }
      scrollableEl = null;
    };
  }, []);

  return ref;
}
