export const lerp = (a, b, t) => a + (b - a) * t;
export const clamp = (x, lo, hi) => Math.max(lo, Math.min(hi, x));
export const smooth = x => { const t = clamp(x, 0, 1); return t * t * (3 - 2 * t); };
export function random(seed) {
  return () => {
    seed = (seed * 1664525 + 1013904223) >>> 0;
    return seed / 4294967296;
  };
}
export function trailX(route, z) {
  let i = 0;
  while (i < route.length - 2 && z < route[i + 1][2]) i++;
  const left = route[i], right = route[i + 1];
  const t = clamp((z - left[2]) / (right[2] - left[2]), 0, 1);
  return lerp(left[1], right[1], smooth(t));
}
