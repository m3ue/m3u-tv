import React from 'react';
import { Pressable, ViewStyle, View, StyleProp } from 'react-native';
import { SpatialNavigationFocusableView } from 'react-tv-space-navigation';

type StyleType = StyleProp<ViewStyle> | ((props: { isFocused: boolean }) => StyleProp<ViewStyle>);

interface FocusablePressableProps {
    onSelect?: () => void;
    onFocus?: () => void;
    onBlur?: () => void;
    children: React.ReactNode | ((props: { isFocused: boolean }) => React.ReactNode);
    style?: StyleType;
    containerStyle?: ViewStyle;
}

export const FocusablePressable = ({
    onSelect,
    onFocus,
    onBlur,
    children,
    style,
    containerStyle,
}: FocusablePressableProps) => {
    return (
        <SpatialNavigationFocusableView
            onSelect={onSelect}
            onFocus={onFocus}
            onBlur={onBlur}
        >
            {({ isFocused }) => (
                <View style={containerStyle}>
                    <Pressable
                        onPress={onSelect}
                        style={[
                            typeof style === 'function' ? style({ isFocused }) : style
                        ]}
                    >
                        {typeof children === 'function' ? children({ isFocused }) : children}
                    </Pressable>
                </View>
            )}
        </SpatialNavigationFocusableView>
    );
};
