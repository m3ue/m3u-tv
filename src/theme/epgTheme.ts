import { colors } from "./colors";

export const epgTheme = {
    primary: {
        600: "#1a202c",
        900: "#171923",
    },
    grey: { 300: "#d1d1d1" },
    white: "#fff",
    teal: {
        100: "#38B2AC",
    },
    green: {
        200: "#389493",
        300: "#2C7A7B",
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
            300: "#002eb3",
            600: "#002360",
            900: "#051937",
        },
    },
    text: {
        grey: {
            300: "#a0aec0",
            500: "#718096",
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
        highlight: "#38B2AC",
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