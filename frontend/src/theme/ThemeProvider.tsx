/**
 * The current accent (#72).
 *
 * `color` stays a static object because surfaces, text and status colours never
 * change with a theme — only `accent` and `accentFg` do, and they move here so
 * a change reaches every screen without each one re-reading a preference.
 *
 * `accentA(alpha)` replaces the hardcoded `rgba(255,74,28,…)` tints that theming
 * could not see: without it the tab pill would stay orange under Volt.
 */
import { createContext, useContext, useEffect, useMemo, useState, type ReactNode } from 'react';

import { accentAlpha, DEFAULT_THEME_ID, paletteById, type Palette, type ThemeId } from './palettes';
import { getThemeId, setThemeId as persistThemeId } from '../lib/themePref';

type ThemeValue = {
  palette: Palette;
  accent: string;
  accentFg: string;
  /** The accent at an opacity, for tints and glows. */
  accentA: (alpha: number) => string;
  setTheme: (id: ThemeId) => void;
};

/**
 * Defaults to Ember so anything rendered before the stored preference loads
 * looks like the app has always looked, rather than flashing a different accent.
 */
const fallback = paletteById(DEFAULT_THEME_ID);
const ThemeContext = createContext<ThemeValue>({
  palette: fallback,
  accent: fallback.accent,
  accentFg: fallback.accentFg,
  accentA: (a) => accentAlpha(fallback.accent, a),
  setTheme: () => {},
});

export function ThemeProvider({ children }: { children: ReactNode }) {
  const [id, setId] = useState<ThemeId>(DEFAULT_THEME_ID);

  useEffect(() => {
    let alive = true;
    void getThemeId().then((stored) => {
      if (alive) setId(stored);
    });
    return () => {
      alive = false;
    };
  }, []);

  const value = useMemo<ThemeValue>(() => {
    const palette = paletteById(id);
    return {
      palette,
      accent: palette.accent,
      accentFg: palette.accentFg,
      accentA: (alpha: number) => accentAlpha(palette.accent, alpha),
      setTheme: (next: ThemeId) => {
        setId(next);
        void persistThemeId(next);
      },
    };
  }, [id]);

  return <ThemeContext.Provider value={value}>{children}</ThemeContext.Provider>;
}

export function useTheme(): ThemeValue {
  return useContext(ThemeContext);
}
