import React, { forwardRef, useImperativeHandle, useRef, useState } from 'react';
import { Pressable, ViewStyle, View, StyleProp } from 'react-native';

type StyleType = StyleProp<ViewStyle> | ((props: { isFocused: boolean }) => StyleProp<ViewStyle>);

export type FocusablePressableRef = {
  focus: () => void;
};

interface FocusablePressableProps {
  onSelect?: () => void;
  onFocus?: () => void;
  onBlur?: () => void;
  preferredFocus?: boolean;
  children: React.ReactNode | ((props: { isFocused: boolean }) => React.ReactNode);
  style?: StyleType;
  containerStyle?: ViewStyle;
}

export const FocusablePressable = forwardRef<FocusablePressableRef, FocusablePressableProps>(
  ({ onSelect, onFocus, onBlur, preferredFocus, children, style, containerStyle }, ref) => {
    const pressableRef = useRef<any>(null);
    const [isFocused, setIsFocused] = useState(false);

    useImperativeHandle(ref, () => ({
      focus: () => {
        pressableRef.current?.focus?.();
      },
    }));

    return (
      <View style={containerStyle}>
        <Pressable
          ref={pressableRef}
          focusable
          hasTVPreferredFocus={preferredFocus}
          onPress={onSelect}
          onFocus={() => {
            setIsFocused(true);
            onFocus?.();
          }}
          onBlur={() => {
            setIsFocused(false);
            onBlur?.();
          }}
          style={[typeof style === 'function' ? style({ isFocused }) : style]}
        >
          {typeof children === 'function' ? children({ isFocused }) : children}
        </Pressable>
      </View>
    );
  },
);

FocusablePressable.displayName = 'FocusablePressable';
