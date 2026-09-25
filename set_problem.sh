#!/bin/bash
set -eu

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)

if [ "${1-}" = "--new-problem" ]; then
  if [ "$#" -lt 2 ] || [ "$#" -gt 4 ]; then
    printf 'Usage: %s --new-problem "student name" [problem count] [output file]\n' "$0" >&2
    exit 1
  fi

  student_name=$2
  problem_count=${3:-6}
  output_file=${4:-new_problems.html}

  case "$student_name" in
    *'"'*|*'\n'*)
      printf 'Error: the name must not contain a double quote or newline.\n' >&2
      exit 1
      ;;
  esac

  case "$problem_count" in
    ''|*[!0-9]*|0)
      printf 'Error: problem count must be a positive integer.\n' >&2
      exit 1
      ;;
  esac

  export NEW_STUDENT_NAME="$student_name"
  export NEW_PROBLEM_COUNT="$problem_count"
  export NEW_PROBLEM_FILE="$output_file"

  node <<'NODE'
const fs = require('fs');

const name = process.env.NEW_STUDENT_NAME;
const problemCount = Number(process.env.NEW_PROBLEM_COUNT);
const outputFile = process.env.NEW_PROBLEM_FILE;
const gridSize = 10;

const escapeHtml = value => value.replace(/[&<>]/g, character => ({
  '&': '&amp;',
  '<': '&lt;',
  '>': '&gt;'
}[character]));

const connect = points => points.slice(0, -1).map((point, index) => [
  point[0], point[1], points[index + 1][0], points[index + 1][1]
]);

const makePointProblem = patternIndex => {
  const patterns = [
    [
      [[0, 1], [2, 0], [4, 2], [2, 4], [0, 3], [0, 1]],
      [[3, 3], [5, 1], [7, 2], [8, 5], [6, 7], [4, 6], [3, 3]],
      [[1, 7], [3, 6], [5, 8], [7, 7], [8, 9]]
    ],
    [
      [[0, 2], [2, 1], [4, 3], [3, 5], [1, 5], [0, 2]],
      [[5, 1], [7, 0], [9, 2], [8, 4], [6, 3], [5, 1]],
      [[2, 7], [4, 5], [6, 6], [5, 9], [3, 8], [2, 7]]
    ],
    [
      [[0, 6], [2, 4], [4, 5], [5, 7], [3, 9], [1, 8], [0, 6]],
      [[2, 1], [4, 0], [6, 2], [5, 4], [3, 3], [2, 1]],
      [[7, 5], [9, 4], [8, 7], [9, 9], [7, 8], [7, 5]]
    ]
  ];
  return patterns[patternIndex % patterns.length].flatMap(connect);
};

const point = coordinate => 12 + coordinate * (96 / (gridSize - 1));
const drawPointLines = lines => lines.map(([x1, y1, x2, y2]) =>
  `<line x1="${point(x1)}" y1="${point(y1)}" x2="${point(x2)}" y2="${point(y2)}"/>`
).join('');
const dots = Array.from({ length: gridSize }, (_, y) =>
  Array.from({ length: gridSize }, (_, x) =>
    `<circle cx="${point(x)}" cy="${point(y)}" r="1.8"/>`
  ).join('')
).join('');
const grid = Array.from({ length: gridSize }, (_, index) => {
  const coordinate = point(index);
  return `<line x1="${coordinate}" y1="${point(0)}" x2="${coordinate}" y2="${point(gridSize - 1)}"/><line x1="${point(0)}" y1="${coordinate}" x2="${point(gridSize - 1)}" y2="${coordinate}"/>`;
}).join('');
const pointSvg = (lines = '') => `<svg viewBox="0 0 120 120" role="img"><g class="grid">${grid}</g><g class="shape">${lines}</g><g class="dots">${dots}</g></svg>`;

// 立方体は i(右), j(奥行き), k(高さ) の格子座標で積み木として定義する。
// 1辺は方眼の1マスと同じ長さにして、方眼線の交点にぴったり重なるようにする。
const cubeBaseCol = 2;
const cubeBaseRow = 8;
const cubeCorner = (i, j, k) => [point(cubeBaseCol + i + j), point(cubeBaseRow - j - k)];

const cubeVoxelKey = (i, j, k) => `${i},${j},${k}`;

const cubeVisibleFaces = voxels => {
  const voxelSet = new Set(voxels.map(([i, j, k]) => cubeVoxelKey(i, j, k)));
  const hasVoxel = (i, j, k) => voxelSet.has(cubeVoxelKey(i, j, k));
  const faces = [];
  voxels.forEach(([i, j, k]) => {
    if (!hasVoxel(i, j - 1, k)) {
      faces.push({ depth: j, corners: [[i, j, k], [i + 1, j, k], [i + 1, j, k + 1], [i, j, k + 1]] });
    }
    if (!hasVoxel(i + 1, j, k)) {
      faces.push({ depth: j, corners: [[i + 1, j, k], [i + 1, j + 1, k], [i + 1, j + 1, k + 1], [i + 1, j, k + 1]] });
    }
    if (!hasVoxel(i, j, k + 1)) {
      faces.push({ depth: j, corners: [[i, j, k + 1], [i + 1, j, k + 1], [i + 1, j + 1, k + 1], [i, j + 1, k + 1]] });
    }
  });
  // 奥にある面を先に描き、手前の面で上書きすることで隠れ線を自然に消す（画家アルゴリズム）。
  return faces.sort((faceA, faceB) => faceB.depth - faceA.depth);
};

const makeCubeFigure = voxels => cubeVisibleFaces(voxels).map(face => {
  const pts = face.corners.map(([i, j, k]) => cubeCorner(i, j, k).join(',')).join(' ');
  return `<polygon points="${pts}"/>`;
}).join('');

const cubeProblemPatterns = [
  // 階段状（3・1・1）に積んだ形
  [[0, 0, 0], [0, 0, 1], [0, 0, 2], [1, 0, 0], [2, 0, 0]],
  // 右奥に1個ずらして積んだ階段状の形
  [[0, 0, 0], [1, 0, 0], [1, 0, 1], [2, 0, 0], [2, 0, 1], [2, 0, 2], [1, 1, 0]],
  // 塔と手前の張り出し、右の一段
  [[0, 0, 0], [0, 0, 1], [1, 0, 0], [1, 0, 1], [1, 0, 2], [1, 0, 3], [2, 0, 0], [1, 1, 0]]
];

const makeCubeProblem = patternIndex =>
  makeCubeFigure(cubeProblemPatterns[patternIndex % cubeProblemPatterns.length]);

const cubeSvg = (lines = '') => `<svg viewBox="0 0 120 120" role="img"><g class="grid">${grid}</g><g class="shape">${lines}</g></svg>`;
const renderProblem = (index, lines, isCube) => {
  const render = isCube ? cubeSvg : pointSvg;
  return `<section class="problem"><h2>だい ${index + 1} もん</h2><div class="figures"><div><p>【おてほん】</p>${render(lines)}</div><div class="divider"></div><div><p>【こたえ】</p>${render()}</div></div></section>`;
};

const problemMarkup = Array.from({ length: problemCount }, (_, index) => {
  const isCube = index % 4 < 2;
  const lines = isCube ? makeCubeProblem(index) : drawPointLines(makePointProblem(index));
  return renderProblem(index, lines, isCube);
});
const pages = Array.from({ length: Math.ceil(problemCount / 4) }, (_, pageIndex) => {
  const pageProblems = problemMarkup.slice(pageIndex * 4, pageIndex * 4 + 4).join('');
  return `<main class="page"><header><h1>${escapeHtml(name)}用のてんずけい</h1><div class="name">なまえ：</div></header><p class="instruction">ひだりの おてほんを よくみて、みぎの てんや ほうがんの うえに おなじ ずけいを かきましょう。</p><div class="problems">${pageProblems}</div></main>`;
}).join('');

const html = `<!DOCTYPE html>
<html lang="ja">
<head>
<meta charset="UTF-8">
<title>${escapeHtml(name)}用のてんずけい</title>
<style>
@page { size: A4 portrait; margin: 8mm; }
* { box-sizing: border-box; }
body { margin: 0; color: #111; font-family: "Hiragino Sans", "Yu Gothic", "Meiryo", sans-serif; }
.page { width: 194mm; min-height: 281mm; display: flex; flex-direction: column; }
header { height: 18mm; display: flex; align-items: center; justify-content: space-between; border-bottom: 1.5px solid #111; }
h1 { margin: 0; font-size: 16pt; }
.name { min-width: 58mm; border-bottom: 1px solid #111; padding-bottom: 1mm; font-size: 10pt; }
.instruction { margin: 3mm 0; font-size: 9pt; }
.problems { flex: 1; display: grid; grid-template-columns: 1fr 1fr; grid-template-rows: repeat(2, 1fr); gap: 3mm; }
.problem { border: 1px solid #222; padding: 2mm; min-height: 0; }
h2 { margin: 0; padding-bottom: 1mm; border-bottom: 1px dashed #aaa; font-size: 10pt; }
.figures { height: calc(100% - 8mm); display: grid; grid-template-columns: 1fr 1px 1fr; align-items: center; gap: 2mm; text-align: center; }
.figures p { margin: 0 0 1mm; font-size: 8pt; font-weight: 700; }
.divider { height: 70%; border-left: 1px solid #999; }
svg { display: block; width: min(100%, 52mm); height: auto; margin: 0 auto; }
.grid { stroke: #aaa; stroke-width: .7; stroke-dasharray: 2 2; }
.shape { stroke: #111; stroke-width: 2.4; stroke-linecap: round; stroke-linejoin: round; fill: none; }
.shape polygon { fill: #fff; }
.dots { fill: #222; }
@media print { .page { page-break-after: always; } .page:last-child { page-break-after: auto; } }
</style>
</head>
<body>${pages}</body>
</html>`;

fs.writeFileSync(outputFile, html);
console.log(`Created ${outputFile} with ${problemCount} problems for ${name}.`);
NODE
  exit 0
fi

if [ "$#" -ne 1 ] || [ -z "$1" ]; then
  printf 'Usage: %s "student name"\n' "$0" >&2
  printf '   or: %s --new-problem "student name" [problem count] [output file]\n' "$0" >&2
  exit 1
fi

student_name=$1

case "$student_name" in
  *'"'*|*'\n'*)
    printf 'Error: the name must not contain a double quote or newline.\n' >&2
    exit 1
    ;;
esac

export NEW_STUDENT_NAME="$student_name"

for html_file in "$script_dir"/version_*.html; do
  [ -f "$html_file" ] || continue
  perl -0pi -e 's/(const\s+studentName\s*=\s*")[^"]*(";)/$1 . $ENV{NEW_STUDENT_NAME} . $2/ge' "$html_file"
done

printf 'Updated student name to: %s\n' "$student_name"
