import React from 'react';
import * as LucideIcons from 'lucide-react-native';
import { colors } from '../theme/colors';

export type IconName = keyof typeof LucideIcons;

interface IconProps {
    name: IconName;
    size?: number;
    color?: string;
    strokeWidth?: number;
}

export const Icon = ({
    name,
    size = 24,
    color = colors.text,
    strokeWidth = 2
}: IconProps) => {
    const LucideIcon = LucideIcons[name] as React.ElementType;

    if (!LucideIcon) {
        console.warn(`Icon "${name}" not found in lucide-react-native`);
        return null;
    }

    return <LucideIcon color={color} size={size} strokeWidth={strokeWidth} />;
};
