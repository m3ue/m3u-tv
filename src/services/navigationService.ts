import { createNavigationContainerRef } from '@react-navigation/native';
import { DrawerParamList } from './navigation/types';

export const contentNavigationRef = createNavigationContainerRef<DrawerParamList>();

export function navigateContent(name: keyof DrawerParamList, params?: any) {
  if (contentNavigationRef.isReady()) {
    contentNavigationRef.navigate(name as any, params);
  }
}
