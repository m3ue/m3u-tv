# Copilot Instructions (`m3u-tv`)

You are an expert React Native developer specializing in TV application development (Android TV & tvOS) using Expo.

## Project Context

- **Framework**: `expo` (v54), `react-native` (npm:react-native-tvos@0.81-stable).
- **Language**: TypeScript (Strict mode).
- **Navigation**: `@react-navigation/native` (v7) & `react-tv-space-navigation` (v6 beta).
- **Video Player**: `react-native-video` / `react-native-vlc-media-player`.
- **EPG**: `@nessprim/planby-native-pro`.
- **Styling**: `lucide-react-native` for icons, standard StyleSheet or inline styles.

## TV Development Guidelines

1.  **Spatial Navigation is Paramount**:
    - Do NOT rely on touch gestures.
    - All interactive elements must be focusable via D-Pad.
    - Use `react-tv-space-navigation` for complex focus grids and spatial logic.
    - Ensure visual focus states (borders, scale, opacity) are obvious.

2.  **Performance**:
    - Use `FlashList` (if available) or optimized FlatLists for large channels/EPG lists.
    - Memoize components heavily (`check props` before re-render).
    - Avoid anonymous functions in renders for lists.

3.  **Expo & Config**:
    - This project uses Config Plugins (`@react-native-tvos/config-tv`).
    - Run commands with `EXPO_TV=1` environment variable (e.g., `EXPO_TV=1 corepack yarn start`).

4.  **Coding Standards**:
    - Use Functional Components with Hooks.
    - **Strict TypeScript**: No `any`. Define interfaces for all props and API responses.
    - **Linting**: Follow `eslint` rules (v9 setup).

## Common Tasks

- **Creating a Screen**: register in `App.tsx` or navigation stacks. Ensure it handles `useFocusEffect` if needed.
- **Handling Data**: Fetch EPG/Playlist data asynchronously. Handle loading/error states gracefully on TV (no alerts, use toasts/overlays).
- **Video Player**: Remember to handle remote control events (Play/Pause/FastForward) explicitly.
