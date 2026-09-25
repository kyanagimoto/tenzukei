#!/bin/bash
set -eu

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)

if [ "${1-}" = "--new-problem" ]; then
  if [ "$#" -lt 2 ] || [ "$#" -gt 5 ]; then
    printf 'Usage: %s --new-problem "student name" [problem count] [output file]\n' "$0" >&2
    printf '   or: %s --new-problem "student name" --sheets [sheet count] [output file]\n' "$0" >&2
    exit 1
  fi

  student_name=$2
  shift 2

  case "$student_name" in
    *'"'*|*'\n'*)
      printf 'Error: the name must not contain a double quote or newline.\n' >&2
      exit 1
      ;;
  esac

  if [ "${1-}" = "--sheets" ]; then
    if [ "$#" -lt 2 ]; then
      printf 'Error: --sheets requires a sheet count.\n' >&2
      exit 1
    fi
    sheet_count=$2
    shift 2

    case "$sheet_count" in
      ''|*[!0-9]*|0)
        printf 'Error: sheet count must be a positive integer.\n' >&2
        exit 1
        ;;
    esac

    # 1枚 = 4問として、指定された枚数分の問題数に変換する。
    problem_count=$((sheet_count * 4))
  else
    problem_count=${1:-6}
    if [ "$#" -ge 1 ]; then
      shift
    fi

    case "$problem_count" in
      ''|*[!0-9]*|0)
        printf 'Error: problem count must be a positive integer.\n' >&2
        exit 1
        ;;
    esac
  fi

  output_file=${1:-new_problems.html}

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

const randomInt = (min, max) => min + Math.floor(Math.random() * (max - min + 1));
const randomFloat = (min, max) => min + Math.random() * (max - min);

// 点図形も、盤面を3つの領域に分けてそれぞれにランダムな多角形を1つ生成する。
const POINT_REGIONS = [
  { x: [1, 3], y: [1, 3], radius: 2 },
  { x: [5, 8], y: [1, 3], radius: 2.3 },
  { x: [2, 7], y: [6, 8], radius: 2.6 }
];

const clampCoordinate = value => Math.min(gridSize - 1, Math.max(0, value));

const makeRandomPolygon = region => {
  const vertexCount = randomInt(4, 6);
  const centerX = randomFloat(region.x[0], region.x[1]);
  const centerY = randomFloat(region.y[0], region.y[1]);
  const angleStep = (2 * Math.PI) / vertexCount;
  const rawPoints = Array.from({ length: vertexCount }, (_, index) => {
    const angle = angleStep * index + randomFloat(-angleStep * 0.3, angleStep * 0.3);
    const radius = region.radius * randomFloat(0.55, 1);
    return [
      clampCoordinate(Math.round(centerX + radius * Math.cos(angle))),
      clampCoordinate(Math.round(centerY + radius * Math.sin(angle)))
    ];
  });
  const points = rawPoints.filter((current, index) => {
    const previous = rawPoints[index === 0 ? rawPoints.length - 1 : index - 1];
    return current[0] !== previous[0] || current[1] !== previous[1];
  });
  return points.length >= 3 ? [...points, points[0]] : null;
};

const makePointProblem = () => POINT_REGIONS
  .map(region => {
    let polygon = null;
    for (let attempt = 0; attempt < 5 && !polygon; attempt += 1) {
      polygon = makeRandomPolygon(region);
    }
    return polygon || [
      [region.x[0], region.y[0]], [region.x[1], region.y[0]],
      [region.x[1], region.y[1]], [region.x[0], region.y[0]]
    ];
  })
  .flatMap(connect);

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

// 積み木の形をランダムに生成する。i:0-2, j:0-1 の列に、下から積み上げる（宙に浮いた立方体ができないようにする）。
const CUBE_BOUNDS = { i: 3, j: 2, k: 4 };

const generateRandomCubeShape = (cubeCount = randomInt(4, 7)) => {
  const columnKey = (i, j) => `${i},${j}`;
  const columns = new Map();
  columns.set(columnKey(randomInt(0, CUBE_BOUNDS.i - 1), randomInt(0, CUBE_BOUNDS.j - 1)), 1);
  let total = 1;

  const neighborsOf = (i, j) => [[i + 1, j], [i - 1, j], [i, j + 1], [i, j - 1]]
    .filter(([ni, nj]) => ni >= 0 && ni < CUBE_BOUNDS.i && nj >= 0 && nj < CUBE_BOUNDS.j);

  let attempts = 0;
  while (total < cubeCount && attempts < 60) {
    attempts += 1;
    const existingKeys = [...columns.keys()];
    const [pi, pj] = existingKeys[randomInt(0, existingKeys.length - 1)].split(',').map(Number);

    if (Math.random() < 0.5) {
      // 既にある柱の上に積む
      const height = columns.get(columnKey(pi, pj));
      if (height < CUBE_BOUNDS.k) {
        columns.set(columnKey(pi, pj), height + 1);
        total += 1;
      }
    } else {
      // 隣に新しい柱を1個置く（必ず既存の柱に接するので、形はつながる）
      const candidates = neighborsOf(pi, pj).filter(([ni, nj]) => !columns.has(columnKey(ni, nj)));
      if (candidates.length > 0) {
        const [ni, nj] = candidates[randomInt(0, candidates.length - 1)];
        columns.set(columnKey(ni, nj), 1);
        total += 1;
      }
    }
  }

  const voxels = [];
  columns.forEach((height, key) => {
    const [i, j] = key.split(',').map(Number);
    for (let k = 0; k < height; k += 1) voxels.push([i, j, k]);
  });
  return voxels;
};

const makeCubeProblem = () => makeCubeFigure(generateRandomCubeShape());

const cubeSvg = (lines = '') => `<svg viewBox="0 0 120 120" role="img"><g class="grid">${grid}</g><g class="shape">${lines}</g></svg>`;
const renderProblem = (index, lines, isCube) => {
  const render = isCube ? cubeSvg : pointSvg;
  return `<section class="problem"><h2>だい ${index + 1} もん</h2><div class="figures"><div><p>【おてほん】</p>${render(lines)}</div><div class="divider"></div><div><p>【こたえ】</p>${render()}</div></div></section>`;
};

const problemMarkup = Array.from({ length: problemCount }, (_, index) => {
  const isCube = index % 4 < 2;
  const lines = isCube ? makeCubeProblem() : drawPointLines(makePointProblem());
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
