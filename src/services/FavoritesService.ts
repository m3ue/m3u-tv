import AsyncStorage from '@react-native-async-storage/async-storage';

const FAVORITES_KEY = 'm3ue_favorites';
const LAST_CATEGORY_KEY = 'm3ue_last_category';

class FavoritesService {
  private favoriteIds: Set<number> = new Set();
  private loaded = false;

  async load(): Promise<void> {
    if (this.loaded) return;
    try {
      const raw = await AsyncStorage.getItem(FAVORITES_KEY);
      if (raw) {
        const ids: number[] = JSON.parse(raw);
        this.favoriteIds = new Set(ids);
      }
    } catch {
      this.favoriteIds = new Set();
    }
    this.loaded = true;
  }

  isFavorite(streamId: number): boolean {
    return this.favoriteIds.has(streamId);
  }

  async toggle(streamId: number): Promise<boolean> {
    await this.load();
    if (this.favoriteIds.has(streamId)) {
      this.favoriteIds.delete(streamId);
    } else {
      this.favoriteIds.add(streamId);
    }
    await this.save();
    return this.favoriteIds.has(streamId);
  }

  getAll(): number[] {
    return Array.from(this.favoriteIds);
  }

  private async save(): Promise<void> {
    try {
      await AsyncStorage.setItem(FAVORITES_KEY, JSON.stringify(Array.from(this.favoriteIds)));
    } catch {
      // Storage unavailable — silently ignore
    }
  }

  async getLastCategory(): Promise<string | undefined> {
    try {
      const raw = await AsyncStorage.getItem(LAST_CATEGORY_KEY);
      return raw ? JSON.parse(raw) : undefined;
    } catch {
      return undefined;
    }
  }

  async setLastCategory(categoryId: string | undefined): Promise<void> {
    try {
      await AsyncStorage.setItem(LAST_CATEGORY_KEY, JSON.stringify(categoryId ?? null));
    } catch {
      // Storage unavailable — silently ignore
    }
  }
}

export const favoritesService = new FavoritesService();
