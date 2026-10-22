#!/bin/bash
set -eu

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)

# 使い方表示
show_usage() {
  printf 'Usage: %s [student_name] [sheet_count] [output_file]\n' "$0" >&2
  printf '   or: %s [sheet_count] [output_file]\n' "$0" >&2
  printf '   or: %s --sheets [sheet_count] [student_name] [output_file]\n' "$0" >&2
  printf '   or: %s --problems [problem_count] [student_name] [output_file]\n' "$0" >&2
  printf '\nExamples:\n' >&2
  printf '  %s\n' "$0" >&2
  printf '  %s 3\n' "$0" >&2
  printf '  %s "りのすけ" 3\n' "$0" >&2
  printf '  %s "りのすけ" 5 my_problems.html\n' "$0" >&2
  printf '  %s --sheets 2 "りのすけ" rotation.html\n' "$0" >&2
  exit 1
}

sheet_count=1
problem_count=0
student_name=""
output_file="rotation_problems.html"

# 引数解析
if [ "$#" -eq 0 ]; then
  : # デフォルトのまま (sheet_count=1, student_name="")
elif [ "${1-}" = "--sheets" ]; then
  if [ "$#" -lt 2 ]; then
    printf 'Error: --sheets requires [sheet_count].\n' >&2
    exit 1
  fi
  sheet_count=$2
  student_name=${3:-}
  output_file=${4:-rotation_problems.html}
elif [ "${1-}" = "--problems" ]; then
  if [ "$#" -lt 2 ]; then
    printf 'Error: --problems requires [problem_count].\n' >&2
    exit 1
  fi
  problem_count=$2
  student_name=${3:-}
  output_file=${4:-rotation_problems.html}
elif [ "${1-}" = "-h" ] || [ "${1-}" = "--help" ]; then
  show_usage
else
  # 第1引数が数字のみなら sheet_count として扱う
  case "$1" in
    ''|*[!0-9]*)
      student_name=$1
      if [ "$#" -ge 2 ]; then
        sheet_count=$2
      fi
      if [ "$#" -ge 3 ]; then
        output_file=$3
      fi
      ;;
    *)
      sheet_count=$1
      if [ "$#" -ge 2 ]; then
        output_file=$2
      fi
      ;;
  esac
fi

# 学生名チェック
case "$student_name" in
  *'"'*|*'\n'*)
    printf 'Error: the student name must not contain double quotes or newlines.\n' >&2
    exit 1
    ;;
esac

# シート数 / 問題数チェック
if [ "$problem_count" -gt 0 ]; then
  case "$problem_count" in
    ''|*[!0-9]*|0)
      printf 'Error: problem count must be a positive integer.\n' >&2
      exit 1
      ;;
  esac
  # 1シートあたり5問
  sheet_count=$(( (problem_count + 4) / 5 ))
else
  case "$sheet_count" in
    ''|*[!0-9]*|0)
      printf 'Error: sheet count must be a positive integer.\n' >&2
      exit 1
      ;;
  esac
fi

export ROT_STUDENT_NAME="$student_name"
export ROT_SHEET_COUNT="$sheet_count"
export ROT_OUTPUT_FILE="$output_file"

/usr/bin/python3 << 'PYTHON_SCRIPT'
import os, sys, random, html

student_name = os.environ.get("ROT_STUDENT_NAME", "").strip()
sheet_count = int(os.environ.get("ROT_SHEET_COUNT", "1"))
output_file = os.environ.get("ROT_OUTPUT_FILE", "rotation_problems.html")

# -------------------------------------------------------------
# 1. セルパターンの定義と回転・反転遷移テーブル
# -------------------------------------------------------------
CELL_TRANSITIONS = {
    "triangle": {
        "variants": ["TL", "TR", "BR", "BL"],
        "rot90": {"TL": "TR", "TR": "BR", "BR": "BL", "BL": "TL"},
        "flipH": {"TL": "TR", "TR": "TL", "BL": "BR", "BR": "BL"},
        "flipV": {"TL": "BL", "BL": "TL", "TR": "BR", "BR": "TR"},
    },
    "arc": {
        "variants": ["TL", "TR", "BR", "BL", "TL_inv", "TR_inv", "BR_inv", "BL_inv"],
        "rot90": {
            "TL": "TR", "TR": "BR", "BR": "BL", "BL": "TL",
            "TL_inv": "TR_inv", "TR_inv": "BR_inv", "BR_inv": "BL_inv", "BL_inv": "TL_inv"
        },
        "flipH": {
            "TL": "TR", "TR": "TL", "BL": "BR", "BR": "BL",
            "TL_inv": "TR_inv", "TR_inv": "TL_inv", "BL_inv": "BR_inv", "BR_inv": "BL_inv"
        },
        "flipV": {
            "TL": "BL", "BL": "TL", "TR": "BR", "BR": "TR",
            "TL_inv": "BL_inv", "BL_inv": "TL_inv", "TR_inv": "BR_inv", "BR_inv": "TR_inv"
        }
    },
    "split": {
        "variants": ["L", "R", "T", "B"],
        "rot90": {"L": "T", "T": "R", "R": "B", "B": "L"},
        "flipH": {"L": "R", "R": "L", "T": "T", "B": "B"},
        "flipV": {"T": "B", "B": "T", "L": "L", "R": "R"}
    },
    "split_line": {
        "variants": ["V", "H"],
        "rot90": {"V": "H", "H": "V"},
        "flipH": {"V": "V", "H": "H"},
        "flipV": {"V": "V", "H": "H"}
    },
    "hourglass": {
        "variants": ["TB", "LR"],
        "rot90": {"TB": "LR", "LR": "TB"},
        "flipH": {"TB": "TB", "LR": "LR"},
        "flipV": {"TB": "TB", "LR": "LR"}
    },
    "grid_block": {
        "variants": ["TL", "TR", "BR", "BL", "L_TL", "L_TR", "L_BR", "L_BL"],
        "rot90": {
            "TL": "TR", "TR": "BR", "BR": "BL", "BL": "TL",
            "L_TL": "L_TR", "L_TR": "L_BR", "L_BR": "L_BL", "L_BL": "L_TL"
        },
        "flipH": {
            "TL": "TR", "TR": "TL", "BL": "BR", "BR": "BL",
            "L_TL": "L_TR", "L_TR": "L_TL", "L_BL": "L_BR", "L_BR": "L_BL"
        },
        "flipV": {
            "TL": "BL", "BL": "TL", "TR": "BR", "BR": "TR",
            "L_TL": "L_BL", "L_BL": "L_TL", "L_TR": "L_BR", "L_BR": "L_TR"
        }
    },
    "solid": {
        "variants": ["W", "K"],
        "rot90": {"W": "W", "K": "K"},
        "flipH": {"W": "W", "K": "K"},
        "flipV": {"W": "W", "K": "K"}
    }
}

def rot_cell(cell, step=1):
    c_type, c_var = cell
    t = CELL_TRANSITIONS[c_type]
    var = c_var
    for _ in range(step % 4):
        var = t["rot90"][var]
    return (c_type, var)

def flip_h_cell(cell):
    c_type, c_var = cell
    return (c_type, CELL_TRANSITIONS[c_type]["flipH"][c_var])

def flip_v_cell(cell):
    c_type, c_var = cell
    return (c_type, CELL_TRANSITIONS[c_type]["flipV"][c_var])

def rot90_figure(fig, step=1):
    res = fig
    for _ in range(step % 4):
        res = (
            rot_cell(res[2], 1),
            rot_cell(res[0], 1),
            rot_cell(res[3], 1),
            rot_cell(res[1], 1)
        )
    return res

def flip_h_figure(fig):
    return (
        flip_h_cell(fig[1]),
        flip_h_cell(fig[0]),
        flip_h_cell(fig[3]),
        flip_h_cell(fig[2])
    )

def flip_v_figure(fig):
    return (
        flip_v_cell(fig[2]),
        flip_v_cell(fig[3]),
        flip_v_cell(fig[0]),
        flip_v_cell(fig[1])
    )

def is_asymmetric(fig):
    for r in [1, 2, 3]:
        if rot90_figure(fig, r) == fig:
            return False
    return True

# -------------------------------------------------------------
# 2. ランダム図形の生成
# -------------------------------------------------------------
def generate_random_figure():
    pool = ["triangle", "arc", "split", "split_line", "hourglass", "grid_block", "solid"]
    weights = [35, 20, 15, 10, 10, 20, 15]
    for _ in range(300):
        chosen_types = random.choices(pool, weights=weights, k=4)
        cells = []
        for t in chosen_types:
            v = random.choice(CELL_TRANSITIONS[t]["variants"])
            cells.append((t, v))
        fig = tuple(cells)
        # 全面白や全面黒ばかりにならないようにチェック
        solid_count = sum(1 for c in fig if c[0] == "solid")
        if solid_count <= 2 and is_asymmetric(fig):
            return fig
    raise RuntimeError("Failed to generate asymmetric figure")

# -------------------------------------------------------------
# 3. 1問の生成（正解と3つの質の高いダミー候補）
# -------------------------------------------------------------
def generate_problem(instruction_marks):
    mark_values = {
        "▲": 3, # 左に1回倒す = 反時計90度 = 時計270度 (+3 mod 4)
        "△": 2, # 左に2回倒す = 反時計180度 = 180度 (+2 mod 4)
        "◆": 1, # 右に1回倒す = 時計90度 (+1 mod 4)
        "◇": 2  # 右に2回倒す = 時計180度 (+2 mod 4)
    }
    net_rot = sum(mark_values[m] for m in instruction_marks) % 4
    if net_rot == 0:
        instruction_marks = list(instruction_marks)
        instruction_marks[-1] = "◆" if instruction_marks[-1] == "▲" else "▲"
        net_rot = sum(mark_values[m] for m in instruction_marks) % 4

    orig = generate_random_figure()
    ans = rot90_figure(orig, net_rot)

    candidates = []
    # 1. 他の回転角（倒す回数・向きを間違えた）
    for r in [1, 2, 3]:
        fig_r = rot90_figure(orig, (net_rot + r) % 4)
        if fig_r != ans:
            candidates.append(fig_r)
    # 2. 正解の左右反転（鏡像の勘違い）
    fh = flip_h_figure(ans)
    if fh != ans:
        candidates.append(fh)
    # 3. 正解の上下反転
    fv = flip_v_figure(ans)
    if fv != ans:
        candidates.append(fv)
    # 4. ニアミス変異（1セルだけ変異、そっくりなひっかけ）
    for idx in range(4):
        mut1 = rot_cell(ans[idx], 1)
        if mut1 != ans[idx]:
            mfig = list(ans)
            mfig[idx] = mut1
            tfig = tuple(mfig)
            if tfig != ans:
                candidates.append(tfig)
        mut2 = flip_h_cell(ans[idx])
        if mut2 != ans[idx]:
            mfig = list(ans)
            mfig[idx] = mut2
            tfig = tuple(mfig)
            if tfig != ans:
                candidates.append(tfig)

    unique_dummies = []
    seen = {ans}
    random.shuffle(candidates)
    for c in candidates:
        if c not in seen:
            seen.add(c)
            unique_dummies.append(c)
        if len(unique_dummies) == 3:
            break

    attempt = 0
    while len(unique_dummies) < 3 and attempt < 50:
        attempt += 1
        extra = generate_random_figure()
        if extra not in seen:
            seen.add(extra)
            unique_dummies.append(extra)

    options = [ans] + unique_dummies
    random.shuffle(options)
    ans_idx = options.index(ans)

    return {
        "marks": instruction_marks,
        "net_rot": net_rot,
        "orig": orig,
        "ans": ans,
        "options": options,
        "ans_idx": ans_idx
    }

# -------------------------------------------------------------
# 4. SVG レンダリング関数群
# -------------------------------------------------------------
def render_cell_svg(c_type, c_var):
    elements = []
    if c_type == "triangle":
        pts_map = {
            "TL": "0,0 50,0 0,50",
            "TR": "0,0 50,0 50,50",
            "BR": "50,0 50,50 0,50",
            "BL": "0,0 0,50 50,50"
        }
        line_map = {
            "TL": ("50,0", "0,50"),
            "BR": ("50,0", "0,50"),
            "TR": ("0,0", "50,50"),
            "BL": ("0,0", "50,50")
        }
        elements.append(f'<polygon points="{pts_map[c_var]}" fill="#111"/>')
        p1, p2 = line_map[c_var]
        elements.append(f'<line x1="{p1.split(",")[0]}" y1="{p1.split(",")[1]}" x2="{p2.split(",")[0]}" y2="{p2.split(",")[1]}" stroke="#111" stroke-width="1.8"/>')
    elif c_type == "arc":
        base = c_var.replace("_inv", "")
        is_inv = "_inv" in c_var
        arc_path_map = {
            "TL": "M 0,0 L 50,0 A 50 50 0 0 1 0,50 Z",
            "TR": "M 50,0 L 50,50 A 50 50 0 0 1 0,0 Z",
            "BR": "M 50,50 L 0,50 A 50 50 0 0 1 50,0 Z",
            "BL": "M 0,50 L 0,0 A 50 50 0 0 1 50,50 Z"
        }
        arc_line_map = {
            "TL": "M 50,0 A 50 50 0 0 1 0,50",
            "TR": "M 50,50 A 50 50 0 0 1 0,0",
            "BR": "M 0,50 A 50 50 0 0 1 50,0",
            "BL": "M 0,0 A 50 50 0 0 1 50,50"
        }
        if not is_inv:
            elements.append(f'<path d="{arc_path_map[base]}" fill="#111"/>')
        else:
            elements.append('<rect width="50" height="50" fill="#111"/>')
            elements.append(f'<path d="{arc_path_map[base]}" fill="#fff"/>')
        elements.append(f'<path d="{arc_line_map[base]}" fill="none" stroke="#111" stroke-width="1.8"/>')
    elif c_type == "split":
        rect_map = {
            "L": '<rect x="0" y="0" width="25" height="50" fill="#111"/>',
            "R": '<rect x="25" y="0" width="25" height="50" fill="#111"/>',
            "T": '<rect x="0" y="0" width="50" height="25" fill="#111"/>',
            "B": '<rect x="0" y="25" width="50" height="25" fill="#111"/>'
        }
        line_map = {
            "L": '<line x1="25" y1="0" x2="25" y2="50" stroke="#111" stroke-width="1.8"/>',
            "R": '<line x1="25" y1="0" x2="25" y2="50" stroke="#111" stroke-width="1.8"/>',
            "T": '<line x1="0" y1="25" x2="50" y2="25" stroke="#111" stroke-width="1.8"/>',
            "B": '<line x1="0" y1="25" x2="50" y2="25" stroke="#111" stroke-width="1.8"/>'
        }
        elements.append(rect_map[c_var])
        elements.append(line_map[c_var])
    elif c_type == "split_line":
        if c_var == "V":
            elements.append('<line x1="25" y1="0" x2="25" y2="50" stroke="#111" stroke-width="1.8"/>')
        else:
            elements.append('<line x1="0" y1="25" x2="50" y2="25" stroke="#111" stroke-width="1.8"/>')
    elif c_type == "hourglass":
        elements.append('<line x1="0" y1="0" x2="50" y2="50" stroke="#111" stroke-width="1.8"/>')
        elements.append('<line x1="50" y1="0" x2="0" y2="50" stroke="#111" stroke-width="1.8"/>')
        if c_var == "TB":
            elements.append('<polygon points="0,0 50,0 25,25" fill="#111"/>')
            elements.append('<polygon points="0,50 50,50 25,25" fill="#111"/>')
        else:
            elements.append('<polygon points="0,0 0,50 25,25" fill="#111"/>')
            elements.append('<polygon points="50,0 50,50 25,25" fill="#111"/>')
    elif c_type == "grid_block":
        s_map = {
            "TL": (0, 0),
            "TR": (25, 0),
            "BR": (25, 25),
            "BL": (0, 25)
        }
        if c_var.startswith("L_"):
            hole = c_var.replace("L_", "")
            elements.append('<rect width="50" height="50" fill="#111"/>')
            hx, hy = s_map[hole]
            elements.append(f'<rect x="{hx}" y="{hy}" width="25" height="25" fill="#fff"/>')
        else:
            bx, by = s_map[c_var]
            elements.append(f'<rect x="{bx}" y="{by}" width="25" height="25" fill="#111"/>')
        elements.append('<line x1="25" y1="0" x2="25" y2="50" stroke="#111" stroke-width="1.4"/>')
        elements.append('<line x1="0" y1="25" x2="50" y2="25" stroke="#111" stroke-width="1.4"/>')
    elif c_type == "solid":
        if c_var == "K":
            elements.append('<rect width="50" height="50" fill="#111"/>')
    return "".join(elements)

def render_figure_svg(fig, is_answer=False):
    offsets = [(0, 0), (50, 0), (0, 50), (50, 50)]
    cells_svg = []
    for idx, (ox, oy) in enumerate(offsets):
        c_type, c_var = fig[idx]
        c_inner = render_cell_svg(c_type, c_var)
        cells_svg.append(f'<g transform="translate({ox},{oy})">{c_inner}</g>')

    ans_circle = ""
    if is_answer:
        ans_circle = '<circle cx="50" cy="50" r="43" fill="none" stroke="#2563eb" stroke-width="4.8" opacity="0.88"/>'

    return f"""<svg viewBox="0 0 100 100" class="figure-svg" xmlns="http://www.w3.org/2000/svg">
    <rect width="100" height="100" fill="#fff"/>
    {''.join(cells_svg)}
    <line x1="50" y1="0" x2="50" y2="100" stroke="#111" stroke-width="1.8"/>
    <line x1="0" y1="50" x2="100" y2="50" stroke="#111" stroke-width="1.8"/>
    <rect x="0" y="0" width="100" height="100" fill="none" stroke="#111" stroke-width="2.6"/>
    {ans_circle}
</svg>"""

def render_instruction_marks_svg(marks):
    total = len(marks)
    # 高さは一定、各記号の大きさも一定
    view_h = 100
    items = []
    # 記号の配置位置
    if total == 1:
        centers = [50]
    elif total == 2:
        centers = [32, 68]
    else:
        centers = [22, 50, 78]

    for m, cy in zip(marks, centers):
        if m == "▲":
            items.append(f'<polygon points="17,{cy-10} 7,{cy+9} 27,{cy+9}" fill="#111"/>')
        elif m == "△":
            items.append(f'<polygon points="17,{cy-10} 7,{cy+9} 27,{cy+9}" fill="#fff" stroke="#111" stroke-width="2.2"/>')
        elif m == "◆":
            items.append(f'<polygon points="17,{cy-10} 27,{cy} 17,{cy+10} 7,{cy}" fill="#111"/>')
        elif m == "◇":
            items.append(f'<polygon points="17,{cy-10} 27,{cy} 17,{cy+10} 7,{cy}" fill="#fff" stroke="#111" stroke-width="2.2"/>')

    return f"""<svg viewBox="0 0 34 {view_h}" class="marks-svg" xmlns="http://www.w3.org/2000/svg">
    {''.join(items)}
</svg>"""

def render_dice_icon():
    return """<svg viewBox="0 0 44 44" class="dice-icon" xmlns="http://www.w3.org/2000/svg">
    <rect x="2" y="2" width="40" height="40" rx="6" fill="#fff" stroke="#111" stroke-width="2"/>
    <circle cx="11" cy="11" r="3.2" fill="#111"/>
    <circle cx="33" cy="11" r="3.2" fill="#111"/>
    <circle cx="22" cy="22" r="3.2" fill="#111"/>
    <circle cx="11" cy="33" r="3.2" fill="#111"/>
    <circle cx="33" cy="33" r="3.2" fill="#111"/>
</svg>"""

def render_legend():
    return """<div class="legend-box">
    <div class="legend-item">
        <svg viewBox="0 0 84 44" class="legend-svg">
            <!-- 反時計回り 1回矢印（左肩の外側、被らない） -->
            <path d="M 44,12 A 18 18 0 0 0 24,28" fill="none" stroke="#111" stroke-width="1.8" stroke-linecap="round"/>
            <polygon points="24,28 29,21 23,21" fill="#111"/>
            <polygon points="52,15 39,38 65,38" fill="#111"/>
        </svg>
    </div>
    <div class="legend-item">
        <svg viewBox="0 0 84 44" class="legend-svg">
            <!-- 反時計回り 2回矢印（内側と外側にしっかり離して配置） -->
            <path d="M 45,15 A 15 15 0 0 0 28,29" fill="none" stroke="#111" stroke-width="1.7" stroke-linecap="round"/>
            <polygon points="28,29 33,22 27,22" fill="#111"/>
            <path d="M 41,7 A 23 23 0 0 0 15,28" fill="none" stroke="#111" stroke-width="1.7" stroke-linecap="round"/>
            <polygon points="15,28 20,21 14,21" fill="#111"/>
            <polygon points="52,15 39,38 65,38" fill="#fff" stroke="#111" stroke-width="2"/>
        </svg>
    </div>
    <div class="legend-item">
        <svg viewBox="0 0 84 44" class="legend-svg">
            <!-- 時計回り 1回矢印（右肩の外側、被らない） -->
            <path d="M 40,12 A 18 18 0 0 1 60,28" fill="none" stroke="#111" stroke-width="1.8" stroke-linecap="round"/>
            <polygon points="60,28 61,21 55,21" fill="#111"/>
            <polygon points="32,15 43,26 32,37 21,26" fill="#111"/>
        </svg>
    </div>
    <div class="legend-item">
        <svg viewBox="0 0 84 44" class="legend-svg">
            <!-- 時計回り 2回矢印（内側と外側にしっかり離して配置） -->
            <path d="M 39,15 A 15 15 0 0 1 56,29" fill="none" stroke="#111" stroke-width="1.7" stroke-linecap="round"/>
            <polygon points="56,29 57,22 51,22" fill="#111"/>
            <path d="M 43,7 A 23 23 0 0 1 69,28" fill="none" stroke="#111" stroke-width="1.7" stroke-linecap="round"/>
            <polygon points="69,28 70,21 64,21" fill="#111"/>
            <polygon points="32,15 43,26 32,37 21,26" fill="#fff" stroke="#111" stroke-width="2"/>
        </svg>
    </div>
</div>"""

# -------------------------------------------------------------
# 5. 1シート（5問）の組み立て
# -------------------------------------------------------------
def generate_sheet_problems():
    problems = []
    for r_idx in range(5):
        if r_idx == 0:
            marks = [random.choice(["▲", "◆", "△", "◇"])]
        elif r_idx in [1, 2]:
            marks = [random.choice(["▲", "△"]), random.choice(["◆", "◇"])]
            random.shuffle(marks)
        else:
            marks = [random.choice(["▲", "△"]), random.choice(["◆", "◇"]), random.choice(["▲", "△", "◆", "◇"])]
            random.shuffle(marks)
        prob = generate_problem(marks)
        problems.append(prob)
    return problems

def render_page(sheet_idx, problems, is_answer_sheet=False):
    ans_badge = '<span class="ans-badge">【こたえ】</span>' if is_answer_sheet else ''

    rows_html = []
    for p_idx, prob in enumerate(problems):
        marks_svg = render_instruction_marks_svg(prob["marks"])
        orig_svg = render_figure_svg(prob["orig"])
        options_html = []
        for opt_idx, opt_fig in enumerate(prob["options"]):
            is_ans = is_answer_sheet and (opt_idx == prob["ans_idx"])
            opt_svg = render_figure_svg(opt_fig, is_answer=is_ans)
            options_html.append(f'<div class="col-option">{opt_svg}</div>')

        row_str = f"""<div class="problem-row">
            <div class="col-marks">{marks_svg}</div>
            <div class="col-orig">{orig_svg}</div>
            {''.join(options_html)}
        </div>"""
        rows_html.append(row_str)

    page_class = "sheet answer-sheet" if is_answer_sheet else "sheet problem-sheet"

    return f"""<section class="{page_class}">
    <header class="sheet-header">
        <div class="header-left"></div>
        <div class="header-center">
            {render_legend()}
        </div>
        <div class="header-right">
            <div class="name-box">
                <span class="name-label">なまえ：</span>
            </div>
        </div>
    </header>
    <div class="sheet-title-row">
        <span class="sheet-number">第 {sheet_idx + 1} 集 {ans_badge}</span>
        <span class="sheet-instruction">ひだりの ずけいを しるしの とおりに たおした ときの かたちを、みぎの ４つから えらんで ○ を つけましょう。</span>
    </div>
    <div class="problems-table">
        {''.join(rows_html)}
    </div>
    <footer class="sheet-footer">
        <span>{sheet_idx + 1} - {'解答' if is_answer_sheet else '問題'}</span>
    </footer>
</section>"""

# -------------------------------------------------------------
# 6. HTMLファイルの出力
# -------------------------------------------------------------
all_pages = []
for s in range(sheet_count):
    probs = generate_sheet_problems()
    # 問題シート
    all_pages.append(render_page(s, probs, is_answer_sheet=False))
    # 解答シート
    all_pages.append(render_page(s, probs, is_answer_sheet=True))

pages_html_content = "".join(all_pages)

html_template = """<!DOCTYPE html>
<html lang="ja">
<head>
<meta charset="UTF-8">
<title>__DOC_TITLE__</title>
<style>
@page {
    size: A4 landscape;
    margin: 5mm;
}
* {
    box-sizing: border-box;
    -webkit-print-color-adjust: exact;
    print-color-adjust: exact;
}
body {
    margin: 0;
    padding: 0;
    font-family: "Hiragino Kaku Gothic ProN", "Yu Gothic", "Meiryo", sans-serif;
    background: #525659;
    color: #111;
}
.screen-toolbar {
    position: sticky;
    top: 0;
    z-index: 1000;
    background: #2b2d30;
    color: #fff;
    padding: 8px 16px;
    display: flex;
    align-items: center;
    justify-content: space-between;
    box-shadow: 0 2px 8px rgba(0,0,0,0.3);
}
.screen-toolbar h1 {
    margin: 0;
    font-size: 15px;
    font-weight: normal;
}
.toolbar-buttons {
    display: flex;
    gap: 10px;
}
.btn {
    background: #0d6efd;
    color: white;
    border: none;
    padding: 6px 14px;
    border-radius: 4px;
    font-size: 13px;
    cursor: pointer;
    font-weight: bold;
    transition: background 0.15s;
}
.btn:hover {
    background: #0b5ed7;
}
.btn-secondary {
    background: #495057;
}
.btn-secondary:hover {
    background: #343a40;
}
.pages-container {
    display: flex;
    flex-direction: column;
    align-items: center;
    gap: 16px;
    padding: 16px 0;
}
.sheet {
    width: 287mm;
    height: 200mm;
    background: #fff;
    padding: 4mm 6mm;
    display: flex;
    flex-direction: column;
    justify-content: space-between;
    box-shadow: 0 4px 12px rgba(0,0,0,0.25);
    page-break-after: always;
    break-after: page;
}
.sheet-header {
    display: flex;
    align-items: center;
    justify-content: space-between;
    height: 18mm;
    margin-bottom: 1.5mm;
}
.header-left {
    display: flex;
    align-items: center;
    gap: 10px;
    width: 55mm;
}
.dice-icon {
    width: 12mm;
    height: 12mm;
}
.score-box {
    display: flex;
    flex-direction: column;
    align-items: flex-start;
    border: 1.2px solid #111;
    border-radius: 4px;
    padding: 1px 6px;
    width: 26mm;
    height: 11mm;
}
.score-label {
    font-size: 7.5pt;
    color: #444;
}
.score-line {
    font-size: 11pt;
    font-weight: bold;
    align-self: flex-end;
    margin-top: -3px;
}
.header-center {
    flex: 1;
    display: flex;
    justify-content: center;
}
.legend-box {
    display: flex;
    border: 1.6px solid #111;
    background: #fff;
    padding: 2px 10px;
    gap: 10mm;
}
.legend-item {
    display: flex;
    align-items: center;
    justify-content: center;
}
.legend-svg {
    width: 25mm;
    height: 13mm;
}
.header-right {
    width: 55mm;
    display: flex;
    justify-content: flex-end;
}
.name-box {
    display: flex;
    align-items: flex-end;
    border-bottom: 1.5px solid #111;
    width: 48mm;
    padding-bottom: 1mm;
    font-size: 11pt;
}
.name-label {
    font-size: 10pt;
    font-weight: bold;
    color: #333;
}
.name-text {
    font-size: 12pt;
    font-weight: bold;
    margin-left: 4px;
}
.sheet-title-row {
    display: flex;
    justify-content: space-between;
    align-items: center;
    font-size: 8.5pt;
    color: #333;
    margin-bottom: 1.5mm;
    padding: 0 2mm;
}
.sheet-number {
    font-weight: bold;
    font-size: 9.5pt;
    color: #111;
}
.ans-badge {
    color: #2563eb;
    font-weight: bold;
    margin-left: 6px;
}
.sheet-instruction {
    font-size: 8.5pt;
    color: #222;
}
.problems-table {
    border: 2px solid #111;
    display: flex;
    flex-direction: column;
    flex: 1;
}
.problem-row {
    display: grid;
    grid-template-columns: 22mm 48mm 1fr 1fr 1fr 1fr;
    flex: 1;
    border-bottom: 1.5px solid #111;
}
.problem-row:last-child {
    border-bottom: none;
}
.col-marks {
    display: flex;
    align-items: center;
    justify-content: center;
    border-right: 1.5px solid #111;
    padding: 1px;
}
.marks-svg {
    width: 12mm;
    height: auto;
    max-height: 25mm;
}
.col-orig {
    display: flex;
    align-items: center;
    justify-content: center;
    border-right: 3.5px double #111;
    padding: 2mm;
    background: #fafafa;
}
.col-option {
    display: flex;
    align-items: center;
    justify-content: center;
    border-right: 1.5px solid #111;
    padding: 2mm;
}
.col-option:last-child {
    border-right: none;
}
.figure-svg {
    width: 25.5mm;
    height: 25.5mm;
}
.sheet-footer {
    display: flex;
    justify-content: flex-end;
    font-size: 7pt;
    color: #888;
    margin-top: 1mm;
    padding: 0 2mm;
}

@media print {
    body {
        background: #fff;
    }
    .screen-toolbar {
        display: none !important;
    }
    .pages-container {
        padding: 0;
        gap: 0;
    }
    .sheet {
        box-shadow: none;
        width: 100% !important;
        height: 100% !important;
        margin: 0;
        padding: 2.5mm 3.5mm;
        page-break-after: always;
        break-after: page;
    }
    .sheet:last-child {
        page-break-after: auto;
        break-after: auto;
    }
    .hide-in-print {
        display: none !important;
    }
}
</style>
</head>
<body>
<div class="screen-toolbar">
    <h1>__DOC_TITLE__ - 計 __SHEET_COUNT__ セット（全 __TOTAL_PROBLEMS__ 問）</h1>
    <div class="toolbar-buttons">
        <button class="btn" onclick="window.print()">印刷する</button>
        <button class="btn btn-secondary" onclick="printMode('all')">全ページ印刷</button>
        <button class="btn btn-secondary" onclick="printMode('problems')">問題のみ印刷</button>
        <button class="btn btn-secondary" onclick="printMode('answers')">解答のみ印刷</button>
        <button class="btn btn-secondary" id="toggleAnswersBtn" onclick="toggleAnswers()">解答の表示切替</button>
    </div>
</div>

<div class="pages-container" id="pagesContainer">
    __PAGES_CONTENT__
</div>

<script>
function printMode(mode) {
    var problems = document.querySelectorAll('.problem-sheet');
    var answers = document.querySelectorAll('.answer-sheet');
    if (mode === 'problems') {
        problems.forEach(function(el) { el.classList.remove('hide-in-print'); });
        answers.forEach(function(el) { el.classList.add('hide-in-print'); });
    } else if (mode === 'answers') {
        problems.forEach(function(el) { el.classList.add('hide-in-print'); });
        answers.forEach(function(el) { el.classList.remove('hide-in-print'); });
    } else {
        problems.forEach(function(el) { el.classList.remove('hide-in-print'); });
        answers.forEach(function(el) { el.classList.remove('hide-in-print'); });
    }
    window.print();
}

var showAnswers = true;
function toggleAnswers() {
    showAnswers = !showAnswers;
    var answers = document.querySelectorAll('.answer-sheet');
    answers.forEach(function(el) {
        el.style.display = showAnswers ? 'flex' : 'none';
    });
    document.getElementById('toggleAnswersBtn').innerText = showAnswers ? '解答を隠す' : '解答を表示';
}
</script>
</body>
</html>
"""

doc_title = f"{student_name} 用の回転図形プリント（図形倒し）" if student_name else "回転図形プリント（図形倒し）"

html_final = html_template.replace("__DOC_TITLE__", html.escape(doc_title))
html_final = html_final.replace("__SHEET_COUNT__", str(sheet_count))
html_final = html_final.replace("__TOTAL_PROBLEMS__", str(sheet_count * 5))
html_final = html_final.replace("__PAGES_CONTENT__", pages_html_content)

with open(output_file, "w", encoding="utf-8") as f:
    f.write(html_final)

msg_name = f" for {student_name}" if student_name else ""
print(f"Created {output_file} with {sheet_count} sheet(s) ({sheet_count * 5} problems){msg_name}.")
PYTHON_SCRIPT

