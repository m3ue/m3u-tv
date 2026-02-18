import React, { forwardRef, useEffect, useImperativeHandle, useRef, useState } from 'react';
import { Pressable, ViewStyle, StyleProp } from 'react-native';

type StyleType = StyleProp<ViewStyle> | ((props: { isFocused: boolean }) => StyleProp<ViewStyle>);

export type FocusablePressableRef = {
  focus: () => void;
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
    },
    ref,
  ) => {
    const focusTimerRef = useRef<ReturnType<typeof setTimeout>>(undefined);
    const [isFocused, setIsFocused] = useState(false);
    const [forcePreferredFocus, setForcePreferredFocus] = useState(false);

    useImperativeHandle(ref, () => ({
      focus: () => {
        setForcePreferredFocus(true);
        if (focusTimerRef.current) {
          clearTimeout(focusTimerRef.current);
        }
        focusTimerRef.current = setTimeout(() => {
          setForcePreferredFocus(false);
        }, 250);
      },
    }));

    useEffect(() => {
      return () => {
        if (focusTimerRef.current) {
          clearTimeout(focusTimerRef.current);
        }
      };
    }, []);

    return (
      <Pressable
        collapsable={false}
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
    );
  },
);

FocusablePressable.displayName = 'FocusablePressable';
