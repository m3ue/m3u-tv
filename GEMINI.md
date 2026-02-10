<project_context>
This is the `m3u-tv` project, a React Native application built with Expo targeting Android TV and Apple TV (tvOS).
</project_context>

<tech_stack>
- **Core**: React Native TVOS (0.81), Expo (54), React (18/19).
- **Language**: TypeScript.
- **Navigation**: React Navigation 7, React TV Space Navigation (Spatial Nav).
- **Media**: react-native-video, react-native-vlc-media-player.
</tech_stack>

<development_rules>
    <rule name="TV First UX">
        - Design for D-Pad navigation, not touch.
        - Every interactive element MUST have a visible focus state.
        - Use `react-tv-space-navigation` for managing focus in complex layouts.
    </rule>

    <rule name="Performance">
        - This is a media app; UI must be buttery smooth (60fps) even during playback.
        - Optimize list rendering (virtualization) for EPG and Channel lists.
    </rule>

    <rule name="Code Quality">
        - Strict TypeScript usage.
        - Follow ESLint v9 configuration.
        - Prefer `lucide-react-native` for icons.
    </rule>
</development_rules>

<commands>
- Start Bundler: `corepack yarn start` (Runs `EXPO_TV=1 expo start`)
- Run Android: `corepack yarn android`
- Run iOS/tvOS: `corepack yarn ios`
- Lint: `corepack yarn lint`
</commands>
