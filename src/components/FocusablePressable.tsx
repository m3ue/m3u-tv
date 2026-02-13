import React, { forwardRef, useImperativeHandle, useRef, useState } from 'react';
import { Pressable, ViewStyle, View, StyleProp, findNodeHandle } from 'react-native';

type StyleType = StyleProp<ViewStyle> | ((props: { isFocused: boolean }) => StyleProp<ViewStyle>);

export type FocusablePressableRef = {
  focus: () => void;
  getNodeHandle: () => number | null;
};

interface FocusablePressableProps {
  onSelect?: () => void;
  onFocus?: () => void;
  onBlur?: () => void;
  preferredFocus?: boolean;
  nextFocusUp?: number;
  nextFocusDown?: number;
  nextFocusLeft?: number;
  nextFocusRight?: number;
  children: React.ReactNode | ((props: { isFocused: boolean }) => React.ReactNode);
  style?: StyleType;
  containerStyle?: ViewStyle;
}

export const FocusablePressable = forwardRef<FocusablePressableRef, FocusablePressableProps>(
  (
    {
      onSelect,
      onFocus,
      onBlur,
      preferredFocus,
      nextFocusUp,
      nextFocusDown,
      nextFocusLeft,
      nextFocusRight,
      children,
      style,
      containerStyle,
    },
    ref,
  ) => {
    const pressableRef = useRef<any>(null);
    const [isFocused, setIsFocused] = useState(false);
    const [forcePreferredFocus, setForcePreferredFocus] = useState(false);

    useImperativeHandle(ref, () => ({
      focus: () => {
        setForcePreferredFocus(true);
      },
      getNodeHandle: () => findNodeHandle(pressableRef.current),
    }));

    return (
      <View style={containerStyle}>
        <Pressable
          ref={pressableRef}
          focusable
          hasTVPreferredFocus={preferredFocus || forcePreferredFocus}
          nextFocusUp={nextFocusUp}
          nextFocusDown={nextFocusDown}
          nextFocusLeft={nextFocusLeft}
          nextFocusRight={nextFocusRight}
          onPress={onSelect}
          onFocus={() => {
            setIsFocused(true);
            setForcePreferredFocus(false);
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
