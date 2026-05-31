import React from 'react';
import { Platform } from 'react-native';
import { useElectronTitleBar } from '../hooks/useElectronTitleBar';

/**
 * A transparent drag region pinned to the top of the Electron window.
 *
 * Why this exists:
 *   - We use frameless / overlay-style title bars (`hiddenInset` on macOS,
 *     `hidden` + `titleBarOverlay` on Windows & Linux) so the renderer paints
 *     edge-to-edge. Without the OS title bar there is no draggable surface,
 *     so the user can't move or double-click-to-zoom the window.
 *   - This component renders a thin invisible strip at the top of the window
 *     with `-webkit-app-region: drag` set, restoring drag/double-click behavior.
 *   - The strip leaves a `leftInset` / `rightInset` gap so clicks on the native
 *     window controls (macOS traffic lights, Windows/Linux overlay buttons)
 *     still register normally.
 *
 * Renders nothing outside Electron (mobile/TV native, plain browsers).
 */
export const ElectronTitleBar: React.FC = () => {
    const info = useElectronTitleBar();

    // Only meaningful on web (Electron renderer is web).
    if (Platform.OS !== 'web' || !info) return null;

    // Render raw <div>s — React Native Web filters unknown style props like
    // `WebkitAppRegion`, so we go through the DOM directly.
    return React.createElement(
        'div',
        {
            // Sits above all RN content (sidebar uses zIndex 100).
            style: {
                position: 'fixed',
                top: 0,
                left: 0,
                right: 0,
                height: info.height,
                zIndex: 9999,
                pointerEvents: 'none',
            },
            'aria-hidden': true,
        },
        React.createElement('div', {
            style: {
                position: 'absolute',
                top: 0,
                left: info.leftInset,
                right: info.rightInset,
                bottom: 0,
                // The actual drag region. Pointer events are re-enabled here so
                // the OS receives drag/double-click. Children (none) would need
                // `WebkitAppRegion: 'no-drag'` to be clickable.
                WebkitAppRegion: 'drag',
                pointerEvents: 'auto',
                // Keep it invisible — purely a hit target.
                background: 'transparent',
            } as React.CSSProperties,
        }),
    );
};

export default ElectronTitleBar;
