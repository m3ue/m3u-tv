import React, { ReactNode } from 'react';
import {
    FlatList,
    Pressable,
    ScrollView,
    StyleProp,
    View,
    ViewStyle,
} from 'react-native';

export type SpatialNavigationNodeRef = {
    focus: () => void;
};

export type Directions = 'UP' | 'DOWN' | 'LEFT' | 'RIGHT' | 'ENTER';

export const Directions = {
    UP: 'UP' as Directions,
    DOWN: 'DOWN' as Directions,
    LEFT: 'LEFT' as Directions,
    RIGHT: 'RIGHT' as Directions,
    ENTER: 'ENTER' as Directions,
};

export const SpatialNavigation = {
    configureRemoteControl: (_config: unknown) => {
        // Native tvOS/Android TV focus handling is used instead of third-party spatial navigation.
    },
};

type RootProps = {
    children: ReactNode;
    isActive?: boolean;
    style?: StyleProp<ViewStyle>;
    onDirectionHandledWithoutMovement?: (_direction: string) => void;
};

export function SpatialNavigationRoot({ children, isActive = true, style }: RootProps) {
    return (
        <View style={style} pointerEvents={isActive ? 'auto' : 'none'}>
            {children}
        </View>
    );
}

type NodeProps = {
    children: ReactNode;
    style?: StyleProp<ViewStyle>;
    orientation?: 'horizontal' | 'vertical';
    isFocusable?: boolean;
};

export function SpatialNavigationNode({ children, style }: NodeProps) {
    return <View style={style}>{children}</View>;
}

type ViewProps = {
    children: ReactNode;
    style?: StyleProp<ViewStyle>;
    direction?: 'horizontal' | 'vertical';
};

export function SpatialNavigationView({ children, style, direction = 'vertical' }: ViewProps) {
    return <View style={[direction === 'horizontal' ? { flexDirection: 'row' } : null, style]}>{children}</View>;
}

type FocusableViewProps = {
    children: (props: { isFocused: boolean }) => ReactNode;
    onSelect?: () => void;
    onFocus?: () => void;
    onBlur?: () => void;
};

export const SpatialNavigationFocusableView = React.forwardRef<SpatialNavigationNodeRef, FocusableViewProps>(
    ({ children, onSelect, onFocus, onBlur }, ref) => {
        const pressableRef = React.useRef<any>(null);
        const [isFocused, setIsFocused] = React.useState(false);

        React.useImperativeHandle(ref, () => ({
            focus: () => {
                pressableRef.current?.focus?.();
            },
        }));

        return (
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
            >
                {children({ isFocused })}
            </Pressable>
        );
    },
);

SpatialNavigationFocusableView.displayName = 'SpatialNavigationFocusableView';

type SpatialNavigationScrollViewProps = React.ComponentProps<typeof ScrollView> & {
    offsetFromStart?: number;
};

export function SpatialNavigationScrollView({
    offsetFromStart,
    contentContainerStyle,
    ...rest
}: SpatialNavigationScrollViewProps) {
    const withOffset = [offsetFromStart ? { paddingLeft: offsetFromStart } : null, contentContainerStyle];
    return <ScrollView {...rest} contentContainerStyle={withOffset}>
        {rest.children}
    </ScrollView>;
}

type SpatialListProps<T> = {
    data: T[];
    renderItem: ({ item, index }: { item: T; index: number }) => ReactNode;
    itemSize?: number;
    orientation?: 'horizontal' | 'vertical';
    numberOfColumns?: number;
    itemHeight?: number;
    style?: StyleProp<ViewStyle>;
};

export function SpatialNavigationVirtualizedList<T>({
    data,
    renderItem,
    orientation = 'vertical',
    style,
}: SpatialListProps<T>) {
    return (
        <FlatList
            style={style}
            data={data}
            horizontal={orientation === 'horizontal'}
            showsHorizontalScrollIndicator={false}
            showsVerticalScrollIndicator={false}
            keyExtractor={(_, index) => String(index)}
            renderItem={({ item, index }) => <>{renderItem({ item, index })}</>}
        />
    );
}

export function SpatialNavigationVirtualizedGrid<T>({
    data,
    renderItem,
    numberOfColumns = 1,
    style,
}: SpatialListProps<T>) {
    return (
        <FlatList
            style={style}
            data={data}
            numColumns={numberOfColumns}
            keyExtractor={(_, index) => String(index)}
            renderItem={({ item, index }) => <>{renderItem({ item, index })}</>}
            showsHorizontalScrollIndicator={false}
            showsVerticalScrollIndicator={false}
        />
    );
}

export function DefaultFocus({ children }: { children: ReactNode }) {
    return <>{children}</>;
}

export function useLockSpatialNavigation() {
    return {
        lock: () => { },
        unlock: () => { },
    };
}
