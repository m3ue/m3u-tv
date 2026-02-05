declare module 'react-native-pixel-perfect' {
  export function create(designSize: { width: number; height: number }): (size: number) => number;
}
