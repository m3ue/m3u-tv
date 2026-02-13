import React, { forwardRef, useImperativeHandle, useRef, useState } from 'react';
import { Pressable, ViewStyle, View, StyleProp } from 'react-native';
import { SpatialNavigationNodeRef } from '../lib/tvNavigation';

type StyleType = StyleProp<ViewStyle> | ((props: { isFocused: boolean }) => StyleProp<ViewStyle>);

interface FocusablePressableProps {
  onSelect?: () => void;
  onFocus?: () => void;
  onBlur?: () => void;
  children: React.ReactNode | ((props: { isFocused: boolean }) => React.ReactNode);
  style?: StyleType;
  containerStyle?: ViewStyle;
}

export const FocusablePressable = forwardRef<SpatialNavigationNodeRef, FocusablePressableProps>(
  ({ onSelect, onFocus, onBlur, children, style, containerStyle }, ref) => {
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
