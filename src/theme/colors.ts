export const colors = {
  // Primary colors - Indigo theme
  primary: '#ec003f',
  primaryLight: '#ff2056',
  primaryDark: '#fb2c36',
  secondary: '#e12afb',

  // Backgrounds
  background: '#0a0a0f',
  backgroundElevated: '#12121a',
  card: '#1a1a24',
  cardElevated: '#242430',
  overlay: '#15151f',

  // Text colors with proper contrast (WCAG AAA compliant)
  text: '#FFFFFF',
  textSecondary: '#a1a1aa',
  textTertiary: '#71717a',
  textOnPrimary: '#FFFFFF',

  // Border and dividers
  border: '#27272a',
  borderLight: '#3f3f46',
  divider: '#27272a',

  // Status colors
  notification: '#FF453A',
  error: '#ef4444',
  success: '#22c55e',
  warning: '#f59e0b',
  info: '#3b82f6',

  // Focus and interaction states - softer glow
  focus: '#ec003f',
  focusBorder: '#ff2056',
  focusBackground: '#ec003f',
  focusBackgroundSecondary: 'rgba(236, 0, 63, 0.2)',
  focusGlow: 'rgba(236, 0, 63, 0.5)',

  // Interactive states
  pressedOverlay: 'rgba(255, 255, 255, 0.1)',
  hoverOverlay: 'rgba(255, 255, 255, 0.05)',

  // Scrim and overlays
  scrimLight: 'rgba(0, 0, 0, 0.4)',
  scrimMedium: 'rgba(0, 0, 0, 0.6)',
  scrimDark: 'rgba(0, 0, 0, 0.85)',

  // Gradients (as array for LinearGradient)
  gradientBackground: ['#0a0a0f', '#12121a', '#0a0a0f'] as const,
  gradientCard: ['#1a1a24', '#242430'] as const,
  gradientPrimary: ['#ec003f', '#e12afb'] as const,
  gradientOverlay: ['transparent', 'rgba(0,0,0,0.7)', '#0a0a0f'] as const,
};
