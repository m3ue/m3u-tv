import React, { forwardRef, useCallback, useImperativeHandle, useRef, useState } from 'react';
import { Pressable } from 'react-native';
import type { FocusablePressableRef, FocusablePressableProps } from './FocusablePressable.types';
import { spatialNavigate } from '../utils/webInteractions';

export type { FocusablePressableRef, FocusablePressableProps } from './FocusablePressable.types';

export const FocusablePressable = forwardRef<FocusablePressableRef, FocusablePressableProps>(
  (
    {
      onSelect,
      onFocus,
      onBlur,
      preferredFocus,
      focusable = true,
      children,
      style,
    },
    ref,
  ) => {
    const pressableRef = useRef<any>(null);
    const [isFocused, setIsFocused] = useState(false);

    useImperativeHandle(ref, () => ({
      focus: () => {
        pressableRef.current?.focus?.();
      },
      getNodeHandle: () => null,
    }));

    const handleKeyDown = useCallback(
      (e: any) => {
        const key = e.nativeEvent?.key ?? e.key;
        if (key === 'Enter' || key === ' ') {
          e.preventDefault?.();
          onSelect?.();
        } else if (key === 'ArrowLeft' || key === 'ArrowRight' || key === 'ArrowUp' || key === 'ArrowDown') {
          e.preventDefault?.();
          spatialNavigate(key);
        }
      },
      [onSelect],
    );

    return (
      <Pressable
        ref={pressableRef}
        tabIndex={focusable ? 0 : -1}
        role="button"
        onPress={(e) => {
          // Don't fire onSelect if user clicked directly on an input/textarea inside
          const target = (e as any).target || (e as any).nativeEvent?.target;
          if (target) {
            const tag = target.tagName?.toLowerCase?.();
            if (tag === 'input' || tag === 'textarea') {
              return;
            }
          }
          onSelect?.();
        }}
        onFocus={(e) => {
          // Don't mark as focused if the focus moved to a child input
          const relTarget = (e as any).nativeEvent?.target;
          const tag = relTarget?.tagName?.toLowerCase?.();
          if (tag === 'input' || tag === 'textarea') {
            return;
          }
          setIsFocused(true);
          onFocus?.();
        }}
        onBlur={() => {
          setIsFocused(false);
          onBlur?.();
        }}
        // @ts-expect-error — onKeyDown is valid on web via react-native-web
        onKeyDown={handleKeyDown}
        autoFocus={preferredFocus}
        style={[
          typeof style === 'function' ? style({ isFocused }) : style,
          { userSelect: 'none', cursor: 'pointer' } as any,
        ]}
      >
        {typeof children === 'function' ? children({ isFocused }) : children}
      </Pressable>
    );
  },
);

FocusablePressable.displayName = 'FocusablePressable';
