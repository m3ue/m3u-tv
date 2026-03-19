import { useEffect } from 'react';
import { Platform } from 'react-native';

let injected = false;

/**
 * Injects global CSS on web/Electron for:
 * - Clean scrollbars (thin, translucent, visible only on hover/scroll)
 * Call once at app root level.
 */
export function useGlobalWebStyles(): void {
  useEffect(() => {
    if (Platform.OS !== 'web' || injected) return;
    injected = true;

    const style = document.createElement('style');
    style.textContent = `
      /* ── Global scrollbar styling ── */
      /* Hide all scrollbars by default to prevent layout shifts */
      * {
        scrollbar-width: none; /* Firefox */
      }
      *::-webkit-scrollbar {
        display: none; /* Chrome, Electron */
      }

      /* Show thin styled scrollbar only on elements marked .m3u-scroll */
      .m3u-scroll {
        scrollbar-width: thin !important;
        scrollbar-color: rgba(255,255,255,0.15) transparent !important;
      }
      .m3u-scroll::-webkit-scrollbar {
        display: block !important;
        width: 4px;
        height: 4px;
      }
      .m3u-scroll::-webkit-scrollbar-track {
        background: transparent;
      }
      .m3u-scroll::-webkit-scrollbar-thumb {
        background: rgba(255,255,255,0.15);
        border-radius: 2px;
      }
      .m3u-scroll::-webkit-scrollbar-thumb:hover {
        background: rgba(255,255,255,0.3);
      }

      /* Remove browser focus outline on interactive elements */
      [tabindex] {
        outline: none;
      }
    `;
    document.head.appendChild(style);
  }, []);
}
