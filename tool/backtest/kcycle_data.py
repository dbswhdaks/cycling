"""KCYCLE HTML 파싱과 출주표/공식 결과 정규화 공통 기능."""

from __future__ import annotations

import html
import json
import re
from collections import defaultdict
from html.parser import HTMLParser
from pathlib import Path
from typing import Iterable

MEETS = {
    1: {"name": "광명", "kcycle_code": "001"},
    2: {"name": "창원", "kcycle_code": "002"},
    3: {"name": "부산", "kcycle_code": "004"},
}
MEET_ALIASES = {
    "광명": 1,
    "광명스피돔": 1,
    "창원": 2,
    "창원경륜장": 2,
    "부산": 3,
    "부산경륜장": 3,
}
BET_TYPES = {
    "단승": "win",
    "단승식": "win",
    "연승": "place",
    "연승식": "place",
    "쌍승": "exacta",
    "쌍승식": "exacta",
    "복승": "quinella",
    "복승식": "quinella",
    "삼복승": "trio",
    "삼복승식": "trio",
    "쌍복승": "exacta_trio",
    "쌍복승식": "exacta_trio",
    "삼쌍승": "trifecta",
    "삼쌍승식": "trifecta",
}
ODDS_FIELDS = tuple(dict.fromkeys(BET_TYPES.values()))


def clean(value: object) -> str:
    return re.sub(r"\s+", " ", html.unescape(str(value or "")).replace("\xa0", " ")).strip()


def integer(value: object, default: int = 0) -> int:
    match = re.search(r"\d+", clean(value))
    return int(match.group()) if match else default


def date_key(value: object) -> str:
    digits = re.sub(r"\D", "", clean(value))
    return digits[:8] if len(digits) >= 8 else ""


def meet_code(row: dict) -> int:
    annotated = integer(row.get("_meet"))
    if annotated in MEETS:
        return annotated
    name = clean(row.get("_meet_nm") or row.get("meet_nm"))
    return MEET_ALIASES.get(name, 0)


class _TableParser(HTMLParser):
    """외부 패키지 없이 표의 셀 텍스트와 링크 속성을 보존한다."""

    def __init__(self) -> None:
        super().__init__(convert_charrefs=True)
        self.tables: list[list[list[dict]]] = []
        self._table: list[list[dict]] | None = None
        self._row: list[dict] | None = None
        self._cell: dict | None = None

    def handle_starttag(self, tag: str, attrs: list[tuple[str, str | None]]) -> None:
        attrs_dict = dict(attrs)
        if tag == "table" and self._table is None:
            self._table = []
        elif tag == "tr" and self._table is not None:
            self._row = []
        elif tag in {"th", "td"} and self._row is not None:
            self._cell = {"tag": tag, "parts": [], "attrs": {}}
        elif self._cell is not None:
            if tag == "br":
                self._cell["parts"].append(" ")
            if tag in {"a", "span"}:
                self._cell["attrs"].setdefault(tag, []).append(attrs_dict)

    def handle_data(self, data: str) -> None:
        if self._cell is not None:
            self._cell["parts"].append(data)

    def handle_endtag(self, tag: str) -> None:
        if tag in {"th", "td"} and self._cell is not None and self._row is not None:
            self._cell["text"] = clean("".join(self._cell.pop("parts")))
            self._row.append(self._cell)
            self._cell = None
        elif tag == "tr" and self._row is not None and self._table is not None:
            if self._row:
                self._table.append(self._row)
            self._row = None
        elif tag == "table" and self._table is not None:
            self.tables.append(self._table)
            self._table = None


def _tables(html_text: str) -> list[list[list[dict]]]:
    parser = _TableParser()
    parser.feed(html_text)
    return parser.tables


def parse_rank_table(html_text: str) -> list[dict]:
    """착차 표에서 배번·선수번호·착순·기록·승부수·제재를 정규화한다."""
    for table in _tables(html_text):
        text = " ".join(cell["text"] for row in table for cell in row)
        if "주행시간" not in text or "착차" not in text:
            continue
        results = []
        for row in table:
            if len(row) < 4 or row[0]["tag"] != "th":
                continue
            first = row[0]
            number = integer(first["text"])
            rank = integer(row[1]["text"])
            links = first["attrs"].get("a", [])
            if not number or not rank or not links:
                continue
            onclick = links[0].get("onclick") or ""
            racer_match = re.search(r"\d{6,}", onclick)
            name = re.sub(r"^\d+\s*", "", first["text"])
            values = [cell["text"] for cell in row[1:]]
            results.append(
                {
                    "back_no": number,
                    "racer_no": racer_match.group() if racer_match else "",
                    "racer_nm": clean(name),
                    "rank": rank,
                    "arrival_diff": values[1] if len(values) > 1 else "",
                    "race_time": values[2] if len(values) > 2 else "",
                    "tactic": "" if len(values) <= 3 or values[3] == "-" else values[3],
                    "disqualification": "" if len(values) <= 4 or values[4] == "-" else values[4],
                    "warning": "" if len(values) <= 5 or values[5] == "-" else values[5],
                    "caution": "" if len(values) <= 6 or values[6] == "-" else values[6],
                    "withdrawal": "" if len(values) <= 7 or values[7] == "-" else values[7],
                    "finish_status": "" if len(values) <= 8 or values[8] == "-" else values[8],
                    "time_200m": values[9] if len(values) > 9 else "",
                    "avg_speed": values[10] if len(values) > 10 else "",
                }
            )
        return sorted(results, key=lambda row: (row["rank"], row["back_no"]))
    return []


def _add_odd(odds: dict[str, dict[str, float]], bet_type: str, winner: str, value: str) -> None:
    field = BET_TYPES.get(clean(bet_type))
    numbers = re.findall(r"\d+", winner)
    try:
        parsed = float(clean(value).replace(",", ""))
    except ValueError:
        return
    if field and numbers and parsed > 0:
        odds[field]["-".join(numbers)] = parsed


def parse_odds_table(html_text: str) -> dict[str, dict[str, float]]:
    """가로형/세로형 KCYCLE 확정배당 표의 일곱 승식을 파싱한다."""
    odds = {field: {} for field in ODDS_FIELDS}
    for table in _tables(html_text):
        matrix = [[cell["text"] for cell in row] for row in table]
        flat = " ".join(value for row in matrix for value in row)
        if "승자" not in flat or "배당" not in flat:
            continue
        for row in matrix:
            if len(row) >= 3 and row[0] in BET_TYPES:
                _add_odd(odds, row[0], row[1], row[2])
        type_row = next((row for row in matrix if any(v in BET_TYPES for v in row[1:])), [])
        winner_row = next((row for row in matrix if row and row[0] == "승자"), [])
        value_row = next((row for row in matrix if row and "배당" in row[0]), [])
        for bet_type, winner, value in zip(type_row[1:], winner_row[1:], value_row[1:]):
            _add_odd(odds, bet_type, winner, value)
    return odds


def parse_lepopark_entries(html_text: str, date: str) -> list[dict]:
    """레포츠파크 확정출주표에서 창원·부산의 학습 피처를 추출한다."""
    header_pattern = re.compile(
        r"<h3[^>]*>\s*(창원|부산|광명)\s*(\d+)\s*경주\s*\[([^\]]*)\]"
        r"\s*출발\s*(\d+:\d+).*?</h3>",
        re.DOTALL,
    )
    headers = list(header_pattern.finditer(html_text))
    entries = []
    for index, header in enumerate(headers):
        venue, race_no, grade, departure = header.groups()
        end = headers[index + 1].start() if index + 1 < len(headers) else len(html_text)
        if venue == "광명":
            continue
        meet = MEET_ALIASES[venue]
        section = html_text[header.end():end]
        tables = _tables(section)
        section_entries = []
        for table in tables:
            for row in table:
                if len(row) < 16:
                    continue
                links = row[0]["attrs"].get("a", [])
                href = links[0].get("href", "") if links else ""
                racer_match = re.search(r"/racer/(\d+)", href)
                identity = row[0]["text"]
                identity_match = re.match(r"(\d+)\s*(.*?)\s+(\d+)기\s+(\d+)세", identity)
                if not racer_match or not identity_match:
                    continue
                values = [cell["text"] for cell in row]
                outing = re.findall(r"\d+", values[7])
                section_entries.append(
                    {
                        "race_ymd": f"{date[:4]}.{date[4:6]}.{date[6:8]}",
                        "race_no": race_no,
                        "back_no": identity_match.group(1),
                        "racer_no": racer_match.group(1),
                        "racer_nm": clean(identity_match.group(2)),
                        "racer_age": identity_match.group(4),
                        "gear_rate": values[1],
                        "rec_200m_scr": values[2].replace("”", '"'),
                        "trng_plc_nm": values[3],
                        "win_rate": values[4],
                        "high_rate": values[5],
                        "high_3_rate": values[6],
                        "win_tot_tcnt": outing[0] if outing else "0",
                        "run_day_tcnt": outing[1] if len(outing) > 1 else "0",
                        "pre_win_cnt": values[8],
                        "brk_win_cnt": values[9],
                        "pas_win_cnt": values[10],
                        "mrk_win_cnt": values[11],
                        "racer_grd_cur_cd": values[12],
                        "racer_grd_bef_cd": values[13],
                        "area_tms3_avg_scr": values[14],
                        "tot_tms_avg_scr": values[15],
                        "dptre_tm": departure,
                        "_meet": meet,
                        "_meet_nm": venue,
                        "meet_nm": venue,
                        "data_source": "scrape_lepopark",
                    }
                )
        by_racer = {row["racer_no"]: row for row in section_entries}
        for table in tables:
            table_text = " ".join(cell["text"] for row in table for cell in row)
            if "최근 3회전 성적" not in table_text:
                continue
            for row in table:
                if len(row) < 16:
                    continue
                links = row[0]["attrs"].get("a", [])
                href = links[0].get("href", "") if links else ""
                racer_match = re.search(r"/racer/(\d+)", href)
                target = by_racer.get(racer_match.group(1) if racer_match else "")
                if target is None:
                    continue
                values = [cell["text"] for cell in row]
                for tms, start in ((3, 1), (2, 6), (1, 11)):
                    target[f"bf{tms}_meet_nm"] = values[start]
                    target[f"bf{tms}_day1_ymd"] = values[start + 1]
                    for day in range(1, 4):
                        target[f"bf{tms}_day{day}_rank"] = values[start + 1 + day]
                if len(values) > 16:
                    target["cur_day1_rank"] = values[16]
                if len(values) > 17:
                    target["cur_day2_rank"] = values[17]
        entries.extend(section_entries)
    return entries


def race_status(
    results: list[dict],
    odds: dict[str, dict[str, float]],
    cancelled: bool = False,
) -> str:
    if cancelled:
        return "cancelled"
    if not results:
        return "missing"
    if any(row["rank"] == results[index - 1]["rank"] for index, row in enumerate(results[1:], 1)):
        return "dead_heat"
    if not any(odds.values()):
        return "odds_missing"
    return "complete"


def normalize_official_race(meta: dict, html_text: str, source_url: str) -> dict:
    results = parse_rank_table(html_text)
    odds = parse_odds_table(html_text)
    plain_text = clean(re.sub(r"<[^>]+>", " ", html_text))
    cancelled = any(label in plain_text for label in ("경주취소", "전액환불", "경주 취소"))
    normalized = {
        "date": date_key(meta.get("date")),
        "year": integer(meta.get("year")),
        "round": integer(meta.get("round")),
        "day": integer(meta.get("day")),
        "meet": integer(meta.get("meet")),
        "meet_nm": MEETS.get(integer(meta.get("meet")), {}).get("name", ""),
        "race_no": integer(meta.get("race_no")),
        "results": results,
        "odds": odds,
        "refund": bool(meta.get("refund", False) or cancelled),
        "source_url": source_url,
    }
    normalized["status"] = race_status(results, odds, cancelled)
    return normalized


def enumerate_races(entries: Iterable[dict]) -> list[dict]:
    """출주표 행을 KCYCLE 상세 URL에 필요한 고유 경주 메타데이터로 바꾼다."""
    races: dict[tuple, dict] = {}
    for row in entries:
        date = date_key(row.get("race_ymd"))
        meet = meet_code(row)
        race_no = integer(row.get("race_no"))
        if not date or meet not in MEETS or not race_no:
            continue
        key = (date, meet, race_no)
        races[key] = {
            "date": date,
            "year": integer(row.get("stnd_yr"), int(date[:4])),
            "round": integer(row.get("period_no") or row.get("tms")),
            "day": integer(row.get("day_tcnt") or row.get("day_ord")),
            "meet": meet,
            "race_no": race_no,
        }
    return sorted(races.values(), key=lambda race: (race["date"], race["meet"], race["race_no"]))


def join_entries(entries: Iterable[dict], official_races: Iterable[dict]) -> tuple[list[dict], list[dict]]:
    """출주 전 정보와 경기 후 정보를 분리한 경주 레코드를 만든다."""
    grouped: dict[tuple[str, int, int], list[dict]] = defaultdict(list)
    for row in entries:
        key = (date_key(row.get("race_ymd")), meet_code(row), integer(row.get("race_no")))
        if key[0] and key[1] and key[2]:
            grouped[key].append(row)

    official = {
        (date_key(race.get("date")), integer(race.get("meet")), integer(race.get("race_no"))): race
        for race in official_races
    }
    joined, failures = [], []
    for key in sorted(set(grouped) | set(official)):
        race = official.get(key)
        pre_rows = sorted(grouped.get(key, []), key=lambda row: integer(row.get("back_no")))
        result_by_back = {
            integer(result.get("back_no")): result for result in (race or {}).get("results", [])
        }
        riders = []
        for row in pre_rows:
            back_no = integer(row.get("back_no"))
            result = result_by_back.get(back_no)
            riders.append(
                {
                    "back_no": back_no,
                    "racer_no": clean((result or {}).get("racer_no")),
                    "racer_nm": clean((result or {}).get("racer_nm") or row.get("racer_nm")),
                    "pre_race": row,
                    "result": result,
                }
            )
            if result is None:
                failures.append(
                    {"date": key[0], "meet": key[1], "race_no": key[2], "back_no": back_no,
                     "reason": "result_not_found"}
                )
        unmatched = sorted(set(result_by_back) - {rider["back_no"] for rider in riders})
        for back_no in unmatched:
            failures.append(
                {"date": key[0], "meet": key[1], "race_no": key[2], "back_no": back_no,
                 "reason": "entry_not_found"}
            )
        joined.append(
            {
                "date": key[0],
                "year": int(key[0][:4]),
                "meet": key[1],
                "meet_nm": MEETS[key[1]]["name"],
                "race_no": key[2],
                "pre_race": {"riders": riders},
                "post_race": {
                    "status": (race or {}).get("status", "missing"),
                    "odds": (race or {}).get("odds", {field: {} for field in ODDS_FIELDS}),
                    "refund": bool((race or {}).get("refund", False)),
                    "source_url": (race or {}).get("source_url", ""),
                },
            }
        )
    return joined, failures


def write_json(path: Path, value: object, *, indent: int | None = None) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_suffix(path.suffix + ".tmp")
    temporary.write_text(
        json.dumps(value, ensure_ascii=False, indent=indent, separators=None if indent else (",", ":")),
        encoding="utf-8",
    )
    temporary.replace(path)
