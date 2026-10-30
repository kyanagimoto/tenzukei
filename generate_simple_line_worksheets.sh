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

  output_file=${1:-simple_problems.html}

  export SIMPLE_STUDENT_NAME="$student_name"
  export SIMPLE_PROBLEM_COUNT="$problem_count"
  export SIMPLE_PROBLEM_FILE="$output_file"

  node <<'NODE'
const fs = require('fs');

const name = process.env.SIMPLE_STUDENT_NAME;
const problemCount = Number(process.env.SIMPLE_PROBLEM_COUNT);
const outputFile = process.env.SIMPLE_PROBLEM_FILE;
const gridSize = 10;

const escapeHtml = value => value.replace(/[&<>]/g, character => ({
  '&': '&amp;',
  '<': '&lt;',
  '>': '&gt;'
}[character]));

const clampCoordinate = value => Math.min(gridSize - 1, Math.max(0, value));
const randomInt = (min, max) => min + Math.floor(Math.random() * (max - min + 1));

const point = coordinate => 12 + coordinate * (96 / (gridSize - 1));
const connect = points => points.slice(0, -1).map((pointItem, index) => [
  pointItem[0], pointItem[1], points[index + 1][0], points[index + 1][1]
]);
const lineMarkup = ([x1, y1, x2, y2]) => `<line x1="${point(x1)}" y1="${point(y1)}" x2="${point(x2)}" y2="${point(y2)}"/>`;
const drawLines = lines => lines.map(lineMarkup).join('');

const grid = Array.from({ length: gridSize }, (_, index) => {
  const coordinate = point(index);
  return `<line x1="${coordinate}" y1="${point(0)}" x2="${coordinate}" y2="${point(gridSize - 1)}"/><line x1="${point(0)}" y1="${coordinate}" x2="${point(gridSize - 1)}" y2="${coordinate}"/>`;
}).join('');

const makeSimplePointProblem = () => {
  const patterns = [
    [[2, 2], [5, 2], [7, 4], [6, 7], [3, 8], [2, 5], [2, 2]],
    [[2, 4], [5, 4], [7, 6], [5, 8], [2, 8], [2, 4]],
    [[3, 2], [7, 2], [7, 5], [5, 8], [3, 8], [2, 5], [3, 2]]
  ];
  const chosen = patterns[randomInt(0, patterns.length - 1)];
  return drawLines(connect(chosen));
};

const makeSimpleCubeProblem = () => {
  const cell = point(1) - point(0);
  const square = (x, y) => {
    const left = point(x) - cell / 2;
    const top = point(y) - cell / 2;
    return `<rect x="${left.toFixed(1)}" y="${top.toFixed(1)}" width="${cell.toFixed(1)}" height="${cell.toFixed(1)}"/>`;
  };

  const patterns = [
    [[2, 2], [3, 2], [2, 3]],
    [[3, 2], [4, 2], [4, 3]],
    [[2, 2], [3, 2], [4, 2]],
    [[2, 2], [3, 2], [2, 3], [2, 4]],
    [[2, 2], [3, 2], [2, 3], [3, 3]]
  ];

  const cells = patterns[randomInt(0, patterns.length - 1)];
  return cells.map(([x, y]) => square(x, y)).join('');
};

const pointSvg = (lines = '') => `<svg viewBox="0 0 120 120" role="img"><g class="grid">${grid}</g><g class="shape">${lines}</g><g class="dots">${Array.from({ length: gridSize }, (_, y) => Array.from({ length: gridSize }, (_, x) => `<circle cx="${point(x)}" cy="${point(y)}" r="1.7"/>`).join('')).join('')}</g></svg>`;
const cubeSvg = (lines = '') => `<svg viewBox="0 0 120 120" role="img"><g class="grid">${grid}</g><g class="shape">${lines}</g></svg>`;

const renderProblem = (index, lines, kind) => {
  const render = { cube: cubeSvg, point: pointSvg }[kind];
  return `<section class="problem"><h2>だい ${index + 1} もん</h2><div class="figures"><div><p>【おてほん】</p>${render(lines)}</div><div class="divider"></div><div><p>【こたえ】</p>${render()}</div></div></section>`;
};

const problemMarkup = Array.from({ length: problemCount }, (_, index) => {
  const kind = index % 2 === 0 ? 'cube' : 'point';
  const lines = { cube: makeSimpleCubeProblem, point: makeSimplePointProblem }[kind]();
  return renderProblem(index, lines, kind);
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
.shape { stroke: #111; stroke-width: 2.2; stroke-linecap: round; stroke-linejoin: round; fill: none; }
.shape polygon { fill: #fff; }
.dots { fill: #222; }
@media print { .page { page-break-after: always; } .page:last-child { page-break-after: auto; } }
</style>
</head>
<body>${pages}</body>
</html>`;

fs.writeFileSync(outputFile, html);
console.log(`Created ${outputFile} with ${problemCount} simple problems for ${name}.`);
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

printf 'This script generates a simplified worksheet set.\n' >&2
printf 'Use: %s --new-problem "student name" [problem count] [output file]\n' "$0" >&2
exit 1
