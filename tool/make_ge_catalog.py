#!/usr/bin/env python3
"""把学校下发的《通识课程库》xlsx 转成 App 用的 JSON asset。

用法：
    python tool/make_ge_catalog.py <源 xlsx> [-o assets/general_education/ge_catalog.json]

源文件不入库（学校内部下发件）；产物 `assets/general_education/ge_catalog.json`
**入库**，`GeneralEducationCatalogParser` 只认这个 JSON。

源表结构（三张 sheet，一张一个适用年级区间）：
    模块 | 课程编码 | 课程名称 | 课程归属 | 新学分 | 备注
- 「模块」列是**纵向合并单元格**，openpyxl 只在合并区左上角给值 → 必须按
  `merged_cells.ranges` 回填，否则整段课程会丢模块（2021-2023 那张表更是有
  一整段 89 门课没有模块标签，属源表真实缺口，产物里 module 记 null）。
- 「备注」列里藏着**旧课程代码**（`原代码：xxx` / `原课程代码xxx`），
  老生的成绩只认旧码 → 一并抽出来进 `oldCodes`。
- 2021-2023 表尾部有两行没有课程编码的通识课（学科前沿课 / 竞赛指导课，
  学分是个区间），照实收下，`credit` 记 null。
- 外校网课表有一行把 4 个编码写在一格里（军事与艺术 I~IV）→ 拆成多码。
"""

import argparse
import json
import re
import sys

import openpyxl

# 表头列名在各 sheet 里略有差异，统一按列序号取（0 模块 / 1 编码 / 2 名称 / 3 归属 / 4 学分 / 5 备注）
COL_MODULE, COL_CODE, COL_NAME, COL_DEPT, COL_CREDIT = 0, 1, 2, 3, 4
COL_NOTE = 5

CODE_RE = re.compile(r'\d{6,}')
OLD_CODE_RE = re.compile(r'原(?:课程)?代码[：:\s]*(\d{6,})')
# 「适用于2021-2023级」「适用于2024-2025级」「适用于各年级」（「于」可有可无）
COHORT_RE = re.compile(r'适用(?:于)?\s*(\d{4})\s*[-~—]\s*(\d{4})\s*级')
ALL_COHORT_RE = re.compile(r'适用(?:于)?各年级')


def _fill_merged(ws):
    """把纵向合并单元格的值回填到合并区每一行（只处理第 0 列）。"""
    extra = {}
    for rng in ws.merged_cells.ranges:
        if rng.min_col == 1 and rng.max_col == 1 and rng.max_row > rng.min_row:
            value = ws.cell(row=rng.min_row, column=1).value
            if value:
                for r in range(rng.min_row + 1, rng.max_row + 1):
                    extra[r] = str(value).strip()
    return extra


def _parse_credit(raw):
    if raw is None:
        return None
    text = str(raw).strip()
    if not text:
        return None
    try:
        return float(text)
    except ValueError:
        # 「0.5-1」「1-1.5」这类区间：取区间值没意义，记 null 由界面显示原文
        return None


def _split_codes(raw):
    if raw is None:
        return []
    return CODE_RE.findall(str(raw))


def parse_sheet(ws):
    merged = _fill_merged(ws)
    title = (ws.cell(row=1, column=1).value or '').strip()
    rows = []
    module = None
    for idx, row in enumerate(ws.iter_rows(values_only=True), start=1):
        if idx <= 2:  # 第 1 行大标题、第 2 行表头
            continue
        cells = list(row) + [''] * (8 - len(row))
        raw_module = merged.get(idx) or ('' if cells[COL_MODULE] is None
                                         else str(cells[COL_MODULE]).strip())
        if raw_module:
            module = raw_module
        name = ('' if cells[COL_NAME] is None else str(cells[COL_NAME])).strip()
        codes = _split_codes(cells[COL_CODE])
        if not name and not codes:
            continue
        if not name:
            continue
        note = ('' if cells[COL_NOTE] is None else str(cells[COL_NOTE])).strip()
        old_codes = [c for c in OLD_CODE_RE.findall(note) if c not in codes]
        credit_raw = cells[COL_CREDIT]
        credit = _parse_credit(credit_raw)
        credit_text = '' if credit_raw is None else str(credit_raw).strip()
        dept = ('' if cells[COL_DEPT] is None else str(cells[COL_DEPT])).strip()
        entry = {
            'code': codes[0] if codes else '',
            'name': name,
            'credit': credit,
        }
        if len(codes) > 1:
            entry['extraCodes'] = codes[1:]
        if credit is None and credit_text:
            # 区间学分（0.5-1 / 1-1.5）保留原文
            entry['creditText'] = credit_text
        if module:
            entry['module'] = module
        if dept:
            entry['dept'] = dept
        if old_codes:
            entry['oldCodes'] = old_codes
        if note:
            entry['note'] = note
        rows.append(entry)

    cohorts = COHORT_RE.search(title)
    all_cohorts = bool(ALL_COHORT_RE.search(title))
    return {
        'title': title,
        'cohortFrom': int(cohorts.group(1)) if cohorts else None,
        'cohortTo': int(cohorts.group(2)) if cohorts else None,
        'allCohorts': all_cohorts,
        'courses': rows,
    }


def main(argv):
    ap = argparse.ArgumentParser()
    ap.add_argument('source', help='通识课程库 xlsx 路径')
    ap.add_argument('-o', '--output',
                    default='assets/general_education/ge_catalog.json')
    ap.add_argument('--revision', default='2026-06-23')
    args = ap.parse_args(argv)

    wb = openpyxl.load_workbook(args.source, data_only=True)
    sheets = [parse_sheet(ws) for ws in wb.worksheets]
    doc = {
        'revision': args.revision,
        'sourceName': '江西财经大学通识课程库（含外校网课）',
        'sheets': sheets,
    }
    with open(args.output, 'w', encoding='utf-8') as f:
        json.dump(doc, f, ensure_ascii=False, indent=1, sort_keys=False)
        f.write('\n')

    for s in sheets:
        mods = {}
        for c in s['courses']:
            mods[c.get('module')] = mods.get(c.get('module'), 0) + 1
        print(f"{s['title']}: {len(s['courses'])} 门 "
              f"cohort={s['cohortFrom']}-{s['cohortTo']} all={s['allCohorts']}")
        for m, n in mods.items():
            print(f'    {m}: {n}')
    print('written ->', args.output)
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
