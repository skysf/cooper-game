// Geometry for the static forest in the streamed co-op world, in Y-up meters.
import {clamp, lerp, random} from './scene-math.mjs';

const {cos, sin, exp, atan2, PI} = Math;
const turn = PI * 2;
const up = [0, 1, 0];
const add = (a, b) => a.map((value, i) => value + b[i]);
const sub = (a, b) => a.map((value, i) => value - b[i]);
const scale = (a, n) => a.map(value => value * n);
const length = v => Math.hypot(...v);
const unit = v => scale(v, 1 / (length(v) || 1));
const mix = (a, b, t) => a.map((value, i) => lerp(value, b[i], t));
const cross = (a, b) => [a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0]];
const angleDistance = (a, b) => atan2(sin(a - b), cos(a - b));
const direction = a => [cos(a), 0, sin(a)];

function skin(batch, vert, rings) {
  const sides = rings[0].length;
  const start = batch.p.length / 3;
  for (const [row, ring] of rings.entries()) {
    for (let j = 0; j <= sides; j++) {
      const side = j % sides;
      const before = rings[Math.max(0, row - 1)][side].position;
      const after = rings[Math.min(rings.length - 1, row + 1)][side].position;
      const right = ring[(side + 1) % sides].position;
      const left = ring[(side + sides - 1) % sides].position;
      const vertex = ring[side];
      const normal = unit(cross(sub(after, before), sub(right, left)));
      vert(batch, vertex.position, normal, [j === sides ? ring.seamU : vertex.u, vertex.v], vertex.color);
      if (j < sides && row < rings.length - 1) {
        const a = start + row * (sides + 1) + j;
        const b = a + sides + 1;
        batch.ix.push(a, b, a + 1, a + 1, b, b + 1);
      }
    }
  }
}

function barkColor(shade, weathered) {
  return [shade * (1 - .15 * weathered), shade * (1 - .06 * weathered), shade * (1 - .19 * weathered)];
}

function bole(batch, vert, trunk, h, radius, orientation, roots, scars, grain) {
  const angles = Array.from({length: 15}, (_, i) => i * turn / 15);
  for (const root of roots) {
    // Keep the crest of each root without creating nearly coincident vertices at the tip.
    if (angles.every(angle => Math.abs(angleDistance(angle, root.angle)) >= .004)) angles.push(root.angle);
  }
  angles.sort((a, b) => a - b);
  const profile = [
    [-.045, 1.22, 1.00], [.025, 1.18, .91], [.089, 1.11, .72],
    [.176, 1.04, .48], [.29, 1.00, .27], [.45, .97, .10], [.70, .95, .015],
    [h * .12, .91, 0], [h * .34, .77, 0], [h * .61, .51, 0], [h * .85, .25, 0],
    [h - .045, .018, 0],
  ];
  const ringTurns = Math.max(1, Math.round(turn * radius));
  const rings = profile.map(([y, taper, spread]) => {
    const center = trunk((y + .045) / h);
    const drift = grain + .038 * sin(y * .8 + orientation);
    const ring = angles.map(angle => {
      let lobe = 0;
      for (const root of roots) {
        const bend = root.bend * spread * spread;
        const d = angleDistance(angle, root.angle + bend);
        const shoulder = root.width + (1 - spread) * .21;
        lobe += root.length * spread ** root.slope * exp(-.5 * (d / shoulder) ** 2);
      }
      const barkRidges = 1 + .062 * sin(angle * 3 - y * 1.64 + orientation)
        + .024 * sin(8 * angle + y * 2.03 + orientation);
      let swelling = 0;
      for (const scar of scars) {
        const d = angleDistance(angle, scar.angle);
        const slope = (y - scar.y) / (radius * 1.8);
        swelling += scar.width * exp(-.5 * (d * d / .15 + slope * slope));
      }
      const neighborhood = (1 - clamp(y / .58, 0, 1)) * (.52 + .32 * sin(3 * angle + orientation));
      const shade = (.69 + .17 * (1 - exp(-Math.max(y, 0) * 1.55))) * (1 + .075 * cos(4 * angle + y * .74 + grain));
      const position = add(center, scale(direction(angle), radius * taper * barkRidges + lobe + swelling));
      return {position, u: drift + angle / turn * ringTurns, v: (-y + lobe * .72) * .92,
        color: barkColor(shade, neighborhood)};
    });
    ring.seamU = drift + ringTurns;
    return ring;
  });
  skin(batch, vert, rings);
}

function sweep(batch, vert, path, radii, sides, grain, tone, broken) {
  let meters = 0;
  let tipAxis;
  const rings = path.map((center, row) => {
    if (row) meters += length(sub(center, path[row - 1]));
    const tangent = unit(sub(path[Math.min(row + 1, path.length - 1)], path[Math.max(row - 1, 0)]));
    tipAxis = tangent;
    // Use a mostly vertical reference so trunk and branch grain meet predictably.
    const u = unit(cross(tangent, Math.abs(tangent[1]) < .86 ? up : [0, 0, 1]));
    const v = cross(u, tangent);
    const final = row === path.length - 1;
    const ring = Array.from({length: sides}, (_, side) => {
      const angle = side / sides * turn;
      const ridge = 1 + .11 * cos(angle * 3 + grain * 4 + row * .37);
      const radial = add(scale(u, cos(angle)), scale(v, sin(angle)));
      const splinter = broken && final ? radii[row] * (.54 * sin(angle + grain) + .32 * sin(3 * angle)) : 0;
      const position = add(add(center, scale(radial, radii[row] * ridge)), scale(tangent, splinter));
      return {position, u: grain + side / sides, v: -meters * 1.43,
        color: barkColor(tone * (1 + .1 * sin(angle - row * .61 + grain * 5)), .13)};
    });
    ring.seamU = grain + 1;
    return ring;
  });
  skin(batch, vert, rings);
  const tip = rings.at(-1);
  const tint = broken ? [.69, .58, .44] : barkColor(tone, .1);
  const center = vert(batch, path.at(-1), tipAxis, [grain + .035, .68], tint);
  for (const [i, end] of tip.entries()) {
    const angle = i / sides * turn;
    vert(batch, end.position, tipAxis, [grain + .035 * (1 + cos(angle)), .68 + .035 * sin(angle)], tint);
  }
  for (let i = 0; i < sides; i++) batch.ix.push(center, center + 1 + (i + 1) % sides, center + 1 + i);
}

export function woodlandFirWood(batch, vert, {x, z, h, radius, orientation, trunk, snags, crowns}) {
  // Use a separate seed so wood variation leaves the placement and needles deterministic.
  const rng = random((Math.imul(Math.round(x * 1000), 1597334677) ^ Math.imul(Math.round(z * 1000), 3812015801)) >>> 0);
  const range = (a, b) => lerp(a, b, rng());
  const grain = rng();
  const count = 3 + Math.floor(rng() * 4);
  const roots = Array.from({length: count}, (_, i) => ({
    angle: (orientation + i * turn / count + range(-.41, .41) + turn) % turn,
    length: radius * range(.54, i === 0 ? 2.24 : 1.66),
    bend: range(-.26, .26), width: range(.14, .27), slope: range(.86, 1.45),
  }));
  const exposed = snags.slice().sort((a, b) => a.t - b.t);
  const numForks = 1 + Math.floor(rng() * 3);
  const visible = new Set(exposed.slice(0, numForks));
  const scars = [];
  for (const [i, snag] of snags.entries()) {
    const {angle, t, reach, dy} = snag;
    const center = trunk(t);
    const forward = direction(angle), flank = direction(angle + PI / 2);
    const isFork = visible.has(snag);
    const broken = !isFork || rng() < .32;
    const reachScale = isFork ? range(.48, .94) : range(.07, .19);
    const extent = radius * .91 + reach * reachScale;
    const thick = radius * range(.14, .26) * (1 - t * .5);
    const crooked = range(-.25, .25) * extent;
    const slope = isFork ? clamp(dy * .75, -.23, .15) + range(-.12, .18) : range(-.04, .075);
    const point = (fraction, spread, y) => add(add(add(center, scale(forward, extent * fraction)), scale(flank, spread)), [0, y, 0]);
    const collar = add(center, scale(forward, radius * .43));
    const shoulder = point(Math.min(.85, radius * .94 / extent), 0, thick * .10);
    const elbow = point(.71, crooked * .45, slope * .42 - thick * .3);
    const tip = point(1, crooked, slope);
    const path = isFork ? [collar, shoulder, elbow, tip] : [collar, shoulder, tip];
    const radii = isFork ? [thick * 1.55, thick, thick * .54, broken ? thick * .22 : .0035]
      : [thick * 1.28, thick * .77, thick * .39];
    const tone = range(.66, .82);
    if (isFork || (i + count) % 2 === 0) sweep(batch, vert, path, radii, isFork ? 6 : 5, grain + i * .13, tone, broken);
    if (isFork && (i + count) % 3 !== 1) {
      const offshoot = add(mix(elbow, tip, .82), add(scale(flank, Math.sign(crooked) * extent * .31), [0, range(.12, .26), 0]));
      sweep(batch, vert, [mix(shoulder, elbow, .89), mix(elbow, offshoot, .56), offshoot],
        [thick * .42, thick * .2, .0025], 4, grain + i * .2, .71, false);
    }
    scars.push({angle, y: center[1], width: thick * .58});
  }
  for (const [i, branch] of crowns.entries()) {
    const {p, angle, reach, drop} = branch;
    // Keep more supports in the low, exposed whorls. The upper cards hide most fine shoots.
    if (i < 14 ? i % 3 === count % 3 : i % 3 !== count % 3) continue;
    const forward = direction(angle), flank = direction(angle + PI / 2);
    const thick = radius * range(.10, .19) * (1 - .052 * Math.floor(i / 7));
    const shoulder = add(p, add(scale(forward, reach * .24), [0, drop * .30 - .04, 0]));
    const curve = add(p, add(add(scale(forward, reach * .48), scale(flank, range(-.11, .11))), [0, drop * .65 - .09, 0]));
    const tip = add(p, add(add(scale(forward, reach * range(.66, .87)), scale(flank, range(-.23, .23))), [0, drop * .56 + range(-.07, .10), 0]));
    sweep(batch, vert, [p, curve, tip], [thick, thick * .44, .0035], 4, grain + i * .08, .77, false);
    if (i < 16 && i % 4 === 0) {
      const fork = add(curve, add(scale(direction(angle + (i % 8 ? .63 : -.66)), reach * .31), [0, range(.05, .23), 0]));
      sweep(batch, vert, [mix(shoulder, curve, .7), mix(curve, fork, .51), fork],
        [thick * .42, thick * .26, .0025], 4, grain + i * .04, .76, false);
    }
  }
  bole(batch, vert, trunk, h, radius, orientation, roots, scars, grain);
}
