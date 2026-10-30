#!/bin/bash
set -eu

if [ "$#" -gt 1 ]; then
  printf 'Usage: %s [output file]\n' "$0" >&2
  exit 1
fi

output_file=${1:-complex_geometry.html}
export COMPLEX_GEOMETRY_FILE="$output_file"

node <<'NODE'
const fs = require('fs');

const outputFile = process.env.COMPLEX_GEOMETRY_FILE;
const gridStep = 50;
const gridCenter = 12;
const randomInt = (min, max) => min + Math.floor(Math.random() * (max - min + 1));
const pointString = ([x, y]) => `${x * gridStep},${y * gridStep}`;
const polygon = points => `<polygon points="${points.map(pointString).join(' ')}"/>`;

const radialPoints = (count, radii, phase = -Math.PI / 2) =>
  Array.from({ length: count }, (_, index) => {
    const angle = phase + (Math.PI * 2 * index) / count;
    const radius = radii[index % (count / 4)];
    return [
      gridCenter + Math.round(radius * Math.cos(angle)),
      gridCenter + Math.round(radius * Math.sin(angle))
    ];
  });

const makeStar = (outerMin, outerMax, innerMin, innerMax) => {
  const pointsPerQuarter = randomInt(2, 3) * 2;
  const radii = Array.from({ length: pointsPerQuarter }, (_, index) =>
    index % 2 === 0 ? randomInt(outerMin, outerMax) : randomInt(innerMin, innerMax)
  );
  return radialPoints(pointsPerQuarter * 4, radii);
};

const makePolygon = (sides, radiusMin, radiusMax, phase = -Math.PI / 2) => {
  const radii = Array.from({ length: sides / 4 }, () => randomInt(radiusMin, radiusMax));
  return radialPoints(sides, radii, phase);
};

const outerDiamond = makePolygon(4, 10, 11);
const framingSquare = makePolygon(4, 7, 8, -Math.PI / 4);
const outerStar = makeStar(8, 11, 4, 6);
const innerStar = makeStar(4, 6, 2, 3);
const middlePolygon = makePolygon(8, 5, 7, -Math.PI / 2 + Math.PI / 8);
const centerDiamond = makePolygon(4, 3, 4);
const centerSquare = makePolygon(4, 2, 3, -Math.PI / 4);
const innerPolygon = makePolygon(8, 1, 2, -Math.PI / 2 + Math.PI / 8);

const connectPoints = (outer, inner, stride = 1) => outer
  .filter((_, index) => index % stride === 0)
  .map((point, index) => {
    const innerIndex = Math.round((index * stride * inner.length) / outer.length) % inner.length;
    const target = inner[innerIndex];
    return `<line x1="${point[0] * gridStep}" y1="${point[1] * gridStep}" x2="${target[0] * gridStep}" y2="${target[1] * gridStep}"/>`;
  }).join('');

const starBands = connectPoints(outerStar, innerStar);
const facets = connectPoints(middlePolygon, centerDiamond, 2);
const innerFacets = connectPoints(innerPolygon, centerSquare, 2);

const dotPoints = Array.from({ length: 26 }, (_, x) => Array.from({ length: 26 }, (_, y) => `<circle class="dot" cx="${x * gridStep}" cy="${y * gridStep}" r="2.2"/>`).join('')).join('');
const svg = `<svg class="artwork" viewBox="0 0 1250 1250" role="img" aria-label="点図形の交点に沿って描く左右対称の星と八角形の幾何学模様" xmlns="http://www.w3.org/2000/svg">
  <g class="dots">${dotPoints}</g>
  <g class="shape">${polygon(outerDiamond)}${polygon(framingSquare)}${polygon(outerStar)}${starBands}${polygon(innerStar)}${polygon(middlePolygon)}${facets}${polygon(centerDiamond)}${polygon(centerSquare)}${polygon(innerPolygon)}${innerFacets}</g>
</svg>`;

const html = `<!DOCTYPE html>
<html lang="ja">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>幾何学模様のうつしがき</title>
<style>
@page { size: A4 portrait; margin: 0; }
* { box-sizing: border-box; }
html, body { margin: 0; min-height: 100%; background: #fff; }
body { display: grid; place-items: center; font-family: "Hiragino Sans", "Yu Gothic", "Meiryo", sans-serif; color: #111; }
.page { width: 210mm; height: 297mm; padding: 8mm; display: grid; grid-template-rows: 1fr 1fr; gap: 4mm; overflow: hidden; }
.half { min-height: 0; border: 1px solid #777; display: grid; grid-template-rows: 9mm minmax(0, 1fr); justify-items: center; }
h1 { width: 100%; margin: 0; padding: 1.5mm 2mm; border-bottom: 1px solid #aaa; font-size: 11pt; font-weight: 600; }
.artwork { display: block; width: min(100%, 124mm); height: min(100%, 124mm); min-height: 0; background-image: radial-gradient(circle, rgba(0,0,0,0.9) 0.9px, transparent 1px); background-size: 10mm 10mm; background-position: center; }
.copy-space { display: block; width: 100%; height: 100%; min-height: 0; background-image: radial-gradient(circle, rgba(0,0,0,0.9) 0.9px, transparent 1px); background-size: 10mm 10mm; background-position: center; }
.dots { fill: #111; opacity: 0.9; }
.shape { fill: none; stroke: #111; stroke-width: 4; stroke-linecap: round; stroke-linejoin: round; }
@media screen { body { padding: 12px; background: #e8e8e8; } .page { background: #fff; box-shadow: 0 2px 12px #0003; } }
@media print { .page { break-after: avoid; page-break-after: avoid; } }
</style>
</head>
<body><main class="page"><section class="half"><h1>おてほん</h1>${svg}</section><section class="half"><h1>おなじように かいてみましょう</h1><div class="copy-space" aria-label="かきうつす場所"></div></section></main></body>
</html>`;

fs.writeFileSync(outputFile, html);
console.log(`Created ${outputFile}`);
NODE
