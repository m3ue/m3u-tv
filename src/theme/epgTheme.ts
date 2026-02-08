import { colors } from "./colors";

export const epgTheme = {
    primary: {
        600: "#1a202c",
        900: colors.backgroundElevated,
    },
    grey: { 300: "#d1d1d1" },
    white: "#fff",
    teal: {
        100: "#00d492",
    },
    green: {
        200: "#00d492",
        300: "#00bc7d",
    },
    loader: {
        teal: colors.primary,
        purple: colors.primaryLight,
        pink: colors.primaryDark,
        bg: colors.background,
    },
    scrollbar: {
        border: "#ffffff",
        thumb: {
            bg: "#e1e1e1",
        },
    },
    gradient: {
        blue: {
            300: "#00bc7d",
            600: "#007a55",
            900: "#004f3b"
        },
    },
    text: {
        grey: {
            300: colors.text,
            500: colors.textSecondary,
        },
    },
    timeline: {
        divider: {
            bg: "#718096",
        },
    },
    grid: {
        item: "#7180961a",
        divider: "#7180961a",
        highlight: colors.primary,
    },
    program: {
        border: "#171923",
        hover: {
            title: "#a0aec0",
            text: "#718096",
            border: "#171923",
        },
    },
};