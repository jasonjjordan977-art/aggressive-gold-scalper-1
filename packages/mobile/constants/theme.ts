import { Platform } from "react-native";

/**
 * App color tokens. Recolor these to brand the app — every screen and component
 * reads from here via `useColors()` (see `hooks/use-colors.ts`), so changing a
 * value here updates the whole app in both light and dark mode.
 *
 * The token names mirror the web app's design tokens (`packages/web/src/web/styles.css`)
 * so the two platforms share one vocabulary: `background`, `foreground`, `card`,
 * `primary`, `muted`, `border`, etc. Values are plain hex/rgba strings — React
 * Native's StyleSheet does not support CSS color functions like `oklch()`.
 */
const palette = {
    background: "#090C0D", foreground: "#F3F1E9", card: "#121719", cardForeground: "#F3F1E9",
    primary: "#D7B66C", primaryForeground: "#090C0D", secondary: "#1B2224", secondaryForeground: "#F3F1E9",
    muted: "#1B2224", mutedForeground: "#79858A", accent: "#24251D", accentForeground: "#D7B66C",
    border: "#263033", destructive: "#F28585", success: "#83D7B0", warning: "#D7B66C"
  };
export const Colors = { light: palette, dark: palette } as const;

export type ColorScheme = keyof typeof Colors;
export type ThemeColors = (typeof Colors)[ColorScheme];

/**
 * Platform-appropriate font families. Use for `fontFamily` in styles, or load a
 * custom font with `useFonts` from `expo-font` and reference it here.
 */
export const Fonts = Platform.select({
  ios: {
    sans: "system-ui",
    serif: "ui-serif",
    rounded: "ui-rounded",
    mono: "ui-monospace",
  },
  default: {
    sans: "normal",
    serif: "serif",
    rounded: "normal",
    mono: "monospace",
  },
  web: {
    sans: "system-ui, -apple-system, 'Segoe UI', Roboto, sans-serif",
    serif: "Georgia, 'Times New Roman', serif",
    rounded: "'SF Pro Rounded', 'Hiragino Maru Gothic ProN', sans-serif",
    mono: "'SF Mono', 'Roboto Mono', monospace",
  },
});
