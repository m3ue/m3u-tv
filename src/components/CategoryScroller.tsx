import React, { useCallback, useEffect, useRef, useState } from 'react';
import {
  View,
  ScrollView,
  StyleSheet,
  Platform,
  Pressable,
  NativeSyntheticEvent,
  NativeScrollEvent,
  LayoutChangeEvent,
} from 'react-native';
import { Icon } from './Icon';
import { scaledPixels } from '../hooks/useScale';

const isWeb = Platform.OS === 'web';
const SCROLL_AMOUNT = 300;

interface CategoryScrollerProps {
  children: React.ReactNode;
}

export function CategoryScroller({ children }: CategoryScrollerProps) {
  const scrollRef = useRef<ScrollView>(null);
  const wrapperRef = useRef<View>(null);
  const [canScrollLeft, setCanScrollLeft] = useState(false);
  const [canScrollRight, setCanScrollRight] = useState(false);
  const scrollState = useRef({ offset: 0, contentWidth: 0, containerWidth: 0 });

  const updateArrows = useCallback(() => {
    const { offset, contentWidth, containerWidth } = scrollState.current;
    const hasOverflow = contentWidth > containerWidth + 5;
    setCanScrollLeft(hasOverflow && offset > 5);
    setCanScrollRight(hasOverflow && offset < contentWidth - containerWidth - 5);
  }, []);

  const handleScroll = useCallback(
    (e: NativeSyntheticEvent<NativeScrollEvent>) => {
      scrollState.current.offset = e.nativeEvent.contentOffset.x;
      scrollState.current.containerWidth = e.nativeEvent.layoutMeasurement.width;
      scrollState.current.contentWidth = e.nativeEvent.contentSize.width;
      updateArrows();
    },
    [updateArrows],
  );

  const handleLayout = useCallback(
    (e: LayoutChangeEvent) => {
      scrollState.current.containerWidth = e.nativeEvent.layout.width;
      updateArrows();
    },
    [updateArrows],
  );

  const handleContentSizeChange = useCallback(
    (w: number, _h: number) => {
      scrollState.current.contentWidth = w;
      updateArrows();
    },
    [updateArrows],
  );

  const scrollLeft = useCallback(() => {
    const newOffset = Math.max(0, scrollState.current.offset - SCROLL_AMOUNT);
    scrollRef.current?.scrollTo({ x: newOffset, animated: true });
  }, []);

  const scrollRight = useCallback(() => {
    const max = scrollState.current.contentWidth - scrollState.current.containerWidth;
    const newOffset = Math.min(max, scrollState.current.offset + SCROLL_AMOUNT);
    scrollRef.current?.scrollTo({ x: newOffset, animated: true });
  }, []);

  useEffect(() => {
    if (!isWeb) {
      return;
    }
    const node = (wrapperRef.current as any)?._nativeTag ?? (wrapperRef.current as any);
    const el = node instanceof HTMLElement ? node : null;
    if (!el) {
      return;
    }
    const onWheel = (e: WheelEvent) => {
      if (Math.abs(e.deltaY) <= Math.abs(e.deltaX)) {
        return;
      }
      e.preventDefault();
      const max = scrollState.current.contentWidth - scrollState.current.containerWidth;
      const newOffset = Math.max(0, Math.min(max, scrollState.current.offset + e.deltaY));
      scrollRef.current?.scrollTo({ x: newOffset, animated: false });
    };
    el.addEventListener('wheel', onWheel, { passive: false });
    return () => el.removeEventListener('wheel', onWheel);
  }, []);

  return (
    <View ref={wrapperRef} style={styles.wrapper}>
      <ScrollView
        ref={scrollRef}
        horizontal
        showsHorizontalScrollIndicator={false}
        onScroll={handleScroll}
        onLayout={handleLayout}
        onContentSizeChange={handleContentSizeChange}
        scrollEventThrottle={16}
        style={styles.scrollView}
        contentContainerStyle={styles.scrollContent}
      >
        {children}
      </ScrollView>

      {isWeb && canScrollLeft && (
        <Pressable style={[styles.arrowButton, styles.arrowLeft]} onPress={scrollLeft}>
          <Icon name="ChevronLeft" size={scaledPixels(18)} color="#fff" />
        </Pressable>
      )}

      {isWeb && canScrollRight && (
        <Pressable style={[styles.arrowButton, styles.arrowRight]} onPress={scrollRight}>
          <Icon name="ChevronRight" size={scaledPixels(18)} color="#fff" />
        </Pressable>
      )}
    </View>
  );
}

const ARROW_SIZE = scaledPixels(32);

const styles = StyleSheet.create({
  wrapper: {
    flex: 1,
    alignSelf: 'stretch',
    position: 'relative',
  },
  scrollView: {
    flex: 1,
    borderRadius: scaledPixels(50),
  },
  scrollContent: {
    paddingHorizontal: scaledPixels(20),
    alignItems: 'center',
  },
  arrowButton: {
    position: 'absolute',
    top: '50%',
    marginTop: -(ARROW_SIZE / 2),
    width: ARROW_SIZE,
    height: ARROW_SIZE,
    borderRadius: ARROW_SIZE / 2,
    backgroundColor: 'rgba(236, 0, 63, 0.85)',
    alignItems: 'center',
    justifyContent: 'center',
    zIndex: 20,
    ...(isWeb ? { cursor: 'pointer' as any } : {}),
  },
  arrowLeft: {
    left: scaledPixels(2),
  },
  arrowRight: {
    right: scaledPixels(2),
  },
});
