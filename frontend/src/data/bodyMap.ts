/**
 * The body diagram's artwork (#66).
 *
 * Drawn for this project rather than traced from anything, so it ships under
 * the repo's own licence — unlike the exercise line art, which is CC BY-SA and
 * carries attribution.
 *
 * Shapes are primitives rather than one big path, because each region has to be
 * filled and tapped independently: a single path could be drawn but not lit up
 * muscle by muscle, which is the entire point of the screen.
 *
 *   r: [x, y, w, h, rx]   rounded rect
 *   e: [cx, cy, rx, ry]   ellipse
 *   d: "..."              path
 *
 * `m` is the region key, matching `MUSCLE_REGIONS` in domain/muscleMap. Shapes
 * without one belong to BODY — the silhouette, which is never tinted or tapped.
 */

export const BODY_VIEWBOX = { width: 100, height: 214 } as const;

export type BodyShape = {
  /** Region key; absent on the plain silhouette. */
  m?: string;
  d?: string;
  r?: number[];
  e?: number[];
};

/** Front view, head to calves. */
export const BODY_FRONT: BodyShape[] = [
  { m: "Neck", r: [45, 23, 10, 8, 3] },
  { m: "Side Delts", e: [24, 40, 5, 7.5] },
  { m: "Side Delts", e: [76, 40, 5, 7.5] },
  { m: "Front Delts", e: [31.5, 40, 5.5, 8] },
  { m: "Front Delts", e: [68.5, 40, 5.5, 8] },
  { m: "Chest", d: "M49 33 L38 34 Q33 44 36 55 L49 56 Z" },
  { m: "Chest", d: "M51 33 L62 34 Q67 44 64 55 L51 56 Z" },
  { m: "Biceps", e: [23, 60, 5, 11] },
  { m: "Biceps", e: [77, 60, 5, 11] },
  { m: "Forearms", e: [20, 86, 4.5, 12.5] },
  { m: "Forearms", e: [80, 86, 4.5, 12.5] },
  { m: "Abs", r: [43.5, 59, 13, 37, 4] },
  { m: "Obliques", d: "M42 60 L36 59 Q34 78 38 95 L42 95 Z" },
  { m: "Obliques", d: "M58 60 L64 59 Q66 78 62 95 L58 95 Z" },
  { m: "Quads", d: "M47 104 L35 101 Q31 128 36 152 L46 152 Q48.5 128 47 104 Z" },
  { m: "Quads", d: "M53 104 L65 101 Q69 128 64 152 L54 152 Q51.5 128 53 104 Z" },
  { m: "Adductors", d: "M49 101 L47.5 104 Q48.5 118 49 126 Z" },
  { m: "Adductors", d: "M51 101 L52.5 104 Q51.5 118 51 126 Z" },
  { m: "Calves", e: [40, 178, 4.5, 16] },
  { m: "Calves", e: [60, 178, 4.5, 16] },
];

/** Back view. */
export const BODY_BACK: BodyShape[] = [
  { m: "Neck", r: [45, 23, 10, 5, 2] },
  { m: "Traps", d: "M50 27 L37 35 L44 44 L50 52 L56 44 L63 35 Z" },
  { m: "Rear Delts", e: [28, 40, 6.5, 8] },
  { m: "Rear Delts", e: [72, 40, 6.5, 8] },
  { m: "Upper Back", d: "M44 45 L50 53 L56 45 L57 62 L43 62 Z" },
  { m: "Lats", d: "M42 47 L36 47 Q33 66 41 85 L43 64 Z" },
  { m: "Lats", d: "M58 47 L64 47 Q67 66 59 85 L57 64 Z" },
  { m: "Lower Back", r: [43.5, 65, 13, 30, 4] },
  { m: "Triceps", e: [23, 60, 5, 11] },
  { m: "Triceps", e: [77, 60, 5, 11] },
  { m: "Forearms", e: [20, 86, 4.5, 12.5] },
  { m: "Forearms", e: [80, 86, 4.5, 12.5] },
  { m: "Glutes", d: "M49.5 99 L37 101 Q33 113 39 120 L49.5 118 Z" },
  { m: "Glutes", d: "M50.5 99 L63 101 Q67 113 61 120 L50.5 118 Z" },
  { m: "Hamstrings", d: "M48 122 L36 122 Q33 140 37 153 L46 153 Q48.5 138 48 122 Z" },
  { m: "Hamstrings", d: "M52 122 L64 122 Q67 140 63 153 L54 153 Q51.5 138 52 122 Z" },
  { m: "Calves", e: [40, 176, 5.5, 17] },
  { m: "Calves", e: [60, 176, 5.5, 17] },
];

/** Head, hands and feet — context only, never interactive. */
export const BODY_SILHOUETTE: BodyShape[] = [
  { e: [50, 13, 8.5, 10] },
  { e: [15.5, 102, 3.5, 5] },
  { e: [84.5, 102, 3.5, 5] },
  { d: "M42 97 L58 97 L57 102 L50 100 L43 102 Z" },
  { r: [34, 156, 13, 5, 2.5] },
  { r: [53, 156, 13, 5, 2.5] },
  { e: [40, 204, 5, 3.5] },
  { e: [60, 204, 5, 3.5] },
];
