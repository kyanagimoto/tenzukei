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
const pointString = ([x, y]) => `${x * gridStep},${y * gridStep}`;
const polygon = points => `<polygon points="${points.map(pointString).join(' ')}"/>`;

const outerDiamond = [[12, 1], [23, 12], [12, 23], [1, 12]];
const framingSquare = [[4, 4], [20, 4], [20, 20], [4, 20]];
const eightPointStar = [
  [12, 3], [14, 9], [20, 4], [16, 10],
  [22, 12], [16, 14], [20, 20], [14, 15],
  [12, 21], [10, 15], [4, 20], [8, 14],
  [2, 12], [8, 10], [4, 4], [10, 9]
];
const innerStar = eightPointStar.map(([x, y]) => [
  12 + Math.round((x - 12) * 0.6),
  12 + Math.round((y - 12) * 0.6)
]);
const middleOctagon = [
  [12, 5], [16, 8], [19, 12], [16, 16],
  [12, 19], [8, 16], [5, 12], [8, 8]
];
const centerDiamond = [[12, 7], [17, 12], [12, 17], [7, 12]];
const centerSquare = [[10, 10], [14, 10], [14, 14], [10, 14]];
const innerOctagon = [
  [12, 9], [14, 10], [15, 12], [14, 14],
  [12, 15], [10, 14], [9, 12], [10, 10]
];
const facets = middleOctagon.map((point, index) => {
  const target = centerDiamond[Math.floor(index / 2)];
  return `<line x1="${point[0] * gridStep}" y1="${point[1] * gridStep}" x2="${target[0] * gridStep}" y2="${target[1] * gridStep}"/>`;
}).join('');
const starBands = eightPointStar.map((point, index) => {
  const target = innerStar[index];
  return `<line x1="${point[0] * gridStep}" y1="${point[1] * gridStep}" x2="${target[0] * gridStep}" y2="${target[1] * gridStep}"/>`;
}).join('');
const innerFacets = innerOctagon.map((point, index) => {
  const target = centerSquare[Math.floor(index / 2)];
  return `<line x1="${point[0] * gridStep}" y1="${point[1] * gridStep}" x2="${target[0] * gridStep}" y2="${target[1] * gridStep}"/>`;
}).join('');

const svg = `<svg class="artwork" viewBox="0 0 1250 1250" role="img" aria-label="方眼の交点に沿って描く左右対称の星と八角形の幾何学模様" xmlns="http://www.w3.org/2000/svg">
  <g class="shape">${polygon(outerDiamond)}${polygon(framingSquare)}${polygon(eightPointStar)}${starBands}${polygon(innerStar)}${polygon(middleOctagon)}${facets}${polygon(centerDiamond)}${polygon(centerSquare)}${polygon(innerOctagon)}${innerFacets}</g>
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
.artwork { display: block; width: min(100%, 124mm); height: min(100%, 124mm); min-height: 0; background-image: linear-gradient(to right, #d5d5d5 .2mm, transparent .2mm), linear-gradient(to bottom, #d5d5d5 .2mm, transparent .2mm), linear-gradient(to right, #999 .35mm, transparent .35mm), linear-gradient(to bottom, #999 .35mm, transparent .35mm); background-size: 5mm 5mm, 5mm 5mm, 25mm 25mm, 25mm 25mm; }
.copy-space { display: block; width: 100%; height: 100%; min-height: 0; background-image: linear-gradient(to right, #d5d5d5 .2mm, transparent .2mm), linear-gradient(to bottom, #d5d5d5 .2mm, transparent .2mm), linear-gradient(to right, #999 .35mm, transparent .35mm), linear-gradient(to bottom, #999 .35mm, transparent .35mm); background-size: 5mm 5mm, 5mm 5mm, 25mm 25mm, 25mm 25mm; }
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
