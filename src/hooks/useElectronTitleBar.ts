import { useEffect, useState } from 'react';
import { Platform } from 'react-native';

export type ElectronPlatform = 'darwin' | 'win32' | 'linux';

export interface ElectronTitleBarInfo {
    /** Underlying OS reported by the Electron main process. */
    platform: ElectronPlatform;
    /** Height (in CSS px) reserved for the custom title-bar drag region. */
    height: number;
    /**
     * Pixels reserved on the left side that should NOT be draggable, because the
     * native window controls (e.g. macOS traffic lights) live there.
     */
    leftInset: number;
    /**
     * Pixels reserved on the right side that should NOT be draggable, because the
     * native window controls (Windows/Linux titleBarOverlay) live there.
     */
    rightInset: number;
}

interface ElectronAPI {
    isElectron?: boolean;
    platform?: ElectronPlatform;
    getTitleBarInfo?: () => Promise<ElectronTitleBarInfo>;
}

const getElectronAPI = (): ElectronAPI | undefined => {
    if (Platform.OS !== 'web') return undefined;
    if (typeof window === 'undefined') return undefined;
    return (window as any).electronAPI as ElectronAPI | undefined;
};

export const isRunningInElectron = (): boolean => !!getElectronAPI()?.isElectron;

/**
 * Returns title-bar metrics from the Electron main process, or `null` when the
 * app isn't running inside Electron (mobile/TV native or plain browser).
 *
 * The metrics depend on the host OS and dictate how much vertical space the
 * renderer should reserve for the custom drag region, plus the side insets that
 * must remain non-draggable so the user can still click native window controls.
 */
export function useElectronTitleBar(): ElectronTitleBarInfo | null {
    const [info, setInfo] = useState<ElectronTitleBarInfo | null>(null);

    useEffect(() => {
        const api = getElectronAPI();
        if (!api?.isElectron || !api.getTitleBarInfo) return;
        let cancelled = false;
        api.getTitleBarInfo()
            .then((result) => {
                if (!cancelled) setInfo(result);
            })
            .catch(() => {
                // Fall back to sensible defaults if the IPC call fails.
                if (cancelled) return;
                const platform = (api.platform ?? 'darwin') as ElectronPlatform;
                setInfo({
                    platform,
                    height: platform === 'darwin' ? 28 : 32,
                    leftInset: platform === 'darwin' ? 80 : 0,
                    rightInset: platform === 'darwin' ? 0 : 140,
                });
            });
        return () => {
            cancelled = true;
        };
    }, []);

    return info;
}
