import { useCallback, useEffect } from 'react';
import { scaledPixels } from '../hooks/useScale';

declare const console: { log: (...args: unknown[]) => void };
import { DrawerContentScrollView } from '@react-navigation/drawer';
import { View, StyleSheet, Platform, Text, Image } from 'react-native';
import { DefaultFocus, SpatialNavigationFocusableView, SpatialNavigationRoot } from 'react-tv-space-navigation';
import { useNavigation, DrawerActions } from '@react-navigation/native';
import { DrawerNavigationProp } from '@react-navigation/drawer';
import { Direction } from '@bam.tech/lrud';
import { DrawerParamList } from '../navigation/types';
import { useMenuContext } from '../components/MenuContext';
import { safeZones, colors } from '../theme';

export default function CustomDrawerContent(props: any) {
  const navigation = useNavigation<DrawerNavigationProp<DrawerParamList>>();
  const { isOpen: isMenuOpen, toggleMenu } = useMenuContext();

  // Debug logging for menu state
  useEffect(() => {
    console.log(`[CustomDrawerContent] isMenuOpen changed to: ${isMenuOpen}`);
  }, [isMenuOpen]);
  const styles = drawerStyles;
  const drawerItems = [
    { name: 'Home', label: 'Home', icon: '🏠' },
    { name: 'LiveTV', label: 'Live TV', icon: '📺' },
    { name: 'VOD', label: 'Movies', icon: '🎬' },
    { name: 'Series', label: 'Series', icon: '📽️' },
  ] as const;

  const onDirectionHandledWithoutMovement = useCallback(
    (movement: Direction) => {
      if (movement === 'right') {
        navigation.dispatch(DrawerActions.closeDrawer());
        toggleMenu(false);
      }
    },
    [toggleMenu, navigation],
  );

  return (
    <SpatialNavigationRoot
      isActive={isMenuOpen}
      onDirectionHandledWithoutMovement={onDirectionHandledWithoutMovement}
    >
      <View style={styles.drawerContainer}>
        {/* Gradient-like scrim overlay */}
        <View style={styles.scrimOverlay} />
        <DrawerContentScrollView
          {...props}
          style={styles.container}
          scrollEnabled={false}
          contentContainerStyle={{
            ...(Platform.OS === 'ios' && Platform.isTV && { paddingStart: 0, paddingEnd: 0, paddingTop: 0 }),
          }}
        >
          <View style={styles.header}>
            <Image
              source={require('../assets/images/logo.png')}
              style={styles.logo}
              resizeMode="contain"
            />
            <Text style={styles.tagline}>m3u tv</Text>
          </View>
          <View style={styles.menuList}>
            {drawerItems.map((item, index) =>
              index === 0 ? (
                <DefaultFocus key={index}>
                  <SpatialNavigationFocusableView
                    onSelect={() => {
                      toggleMenu(false);
                      navigation.dispatch(DrawerActions.closeDrawer());
                      navigation.navigate(item.name as keyof DrawerParamList);
                    }}
                  >
                    {({ isFocused }) => (
                      <View style={[styles.menuItem, isFocused && styles.menuItemFocused]}>
                        <Text style={styles.menuIcon}>{item.icon}</Text>
                        <Text style={[styles.menuText, isFocused && styles.menuTextFocused]}>{item.label}</Text>
                      </View>
                    )}
                  </SpatialNavigationFocusableView>
                </DefaultFocus>
              ) : (
                <SpatialNavigationFocusableView
                  key={index}
                  onSelect={() => {
                    toggleMenu(false);
                    navigation.dispatch(DrawerActions.closeDrawer());
                    navigation.navigate(item.name as keyof DrawerParamList);
                  }}
                >
                  {({ isFocused }) => (
                    <View style={[styles.menuItem, isFocused && styles.menuItemFocused]}>
                      <Text style={styles.menuIcon}>{item.icon}</Text>
                      <Text style={[styles.menuText, isFocused && styles.menuTextFocused]}>{item.label}</Text>
                    </View>
                  )}
                </SpatialNavigationFocusableView>
              ),
            )}
          </View>
        </DrawerContentScrollView>

        {/* Settings button at bottom */}
        <View style={styles.footer}>
          <SpatialNavigationFocusableView
            onSelect={() => {
              toggleMenu(false);
              navigation.dispatch(DrawerActions.closeDrawer());
              navigation.navigate('Settings');
            }}
          >
            {({ isFocused }) => (
              <View style={[styles.settingsButton, isFocused && styles.settingsButtonFocused]}>
                <Text style={styles.settingsIcon}>⚙️</Text>
                <Text style={[styles.settingsText, isFocused && styles.settingsTextFocused]}>Settings</Text>
              </View>
            )}
          </SpatialNavigationFocusableView>
        </View>
      </View>
    </SpatialNavigationRoot>
  );
}

const drawerStyles = StyleSheet.create({
  drawerContainer: {
    flex: 1,
    backgroundColor: 'rgba(0, 0, 0, 0.85)',
    overflow: 'visible',
  },
  scrimOverlay: {
    position: 'absolute',
    top: 0,
    left: 0,
    right: 0,
    bottom: 0,
    backgroundColor: 'rgba(0, 0, 0, 0.6)',
    opacity: 0.9,
  },
  container: {
    flex: 1,
    paddingTop: scaledPixels(safeZones.titleSafe.vertical),
    overflow: 'visible',
  },
  header: {
    paddingHorizontal: scaledPixels(safeZones.actionSafe.horizontal),
    paddingVertical: scaledPixels(32),
    marginBottom: scaledPixels(24),
    borderBottomWidth: scaledPixels(2),
    borderBottomColor: colors.border,
  },
  logo: {
    alignSelf: 'center',
    width: scaledPixels(120),
    height: scaledPixels(120),
    borderRadius: scaledPixels(16),
  },
  tagline: {
    color: colors.textSecondary,
    textAlign: 'center',
    fontSize: scaledPixels(20),
    marginTop: scaledPixels(8),
  },
  menuList: {
    overflow: 'visible',
    paddingHorizontal: scaledPixels(8),
  },
  menuIcon: {
    fontSize: scaledPixels(32),
    marginRight: scaledPixels(16),
  },
  menuItem: {
    flexDirection: 'row',
    alignItems: 'center',
    paddingVertical: scaledPixels(18),
    paddingHorizontal: scaledPixels(24),
    marginHorizontal: scaledPixels(8),
    marginVertical: scaledPixels(4),
    borderRadius: scaledPixels(12),
    minHeight: scaledPixels(68),
    borderWidth: scaledPixels(2),
    borderColor: 'transparent',
    backgroundColor: 'transparent',
  },
  menuItemFocused: {
    backgroundColor: colors.primary,
    borderColor: colors.primary,
    shadowColor: colors.primary,
    shadowOffset: {
      width: 0,
      height: scaledPixels(4),
    },
    shadowOpacity: 0.4,
    shadowRadius: scaledPixels(8),
    elevation: 8,
  },
  menuText: {
    color: colors.text,
    fontSize: scaledPixels(36),
    fontWeight: '500',
  },
  menuTextFocused: {
    color: colors.textOnPrimary,
    fontWeight: '600',
  },
  footer: {
    paddingHorizontal: scaledPixels(16),
    paddingBottom: scaledPixels(safeZones.actionSafe.vertical),
    paddingTop: scaledPixels(16),
    borderTopWidth: scaledPixels(1),
    borderTopColor: colors.border,
    overflow: 'visible',
  },
  settingsButton: {
    flexDirection: 'row',
    alignItems: 'center',
    paddingVertical: scaledPixels(18),
    paddingHorizontal: scaledPixels(24),
    marginHorizontal: scaledPixels(8),
    borderRadius: scaledPixels(12),
    minHeight: scaledPixels(68),
    borderWidth: scaledPixels(2),
    borderColor: 'transparent',
    backgroundColor: 'transparent',
  },
  settingsButtonFocused: {
    backgroundColor: colors.primary,
    borderColor: colors.primary,
    shadowColor: colors.primary,
    shadowOffset: {
      width: 0,
      height: scaledPixels(4),
    },
    shadowOpacity: 0.4,
    shadowRadius: scaledPixels(8),
    elevation: 8,
  },
  settingsIcon: {
    fontSize: scaledPixels(32),
    marginRight: scaledPixels(16),
  },
  settingsText: {
    color: colors.text,
    fontSize: scaledPixels(36),
    fontWeight: '500',
  },
  settingsTextFocused: {
    color: colors.textOnPrimary,
    fontWeight: '600',
  },
});
