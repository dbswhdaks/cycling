"""KCYCLE 낙차부상 게시판의 목록·상세를 ID 기준으로 수집한다."""

from __future__ import annotations

import argparse
import html
import json
import random
import re
import time
import urllib.request
from pathlib import Path

from kcycle_data import _tables, clean, write_json

DATA_DIR = Path(__file__).resolve().parent / "data"
BASE_URL = "https://www.kcycle.or.kr/racer/state/fallinjury"
USER_AGENT = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) CyclingBacktest/1.0"


def download(url: str, retries: int = 3) -> str:
    request = urllib.request.Request(
        url,
        headers={"Accept": "text/html,application/xhtml+xml", "User-Agent": USER_AGENT},
    )
    for attempt in range(retries + 1):
        try:
            with urllib.request.urlopen(request, timeout=30) as response:
                charset = response.headers.get_content_charset() or "utf-8"
                return response.read().decode(charset, errors="replace")
        except Exception:
            if attempt >= retries:
                raise
            time.sleep(min(2 ** attempt, 16) + random.random())
    return ""


def parse_listing(source: str) -> list[dict]:
    posts = []
    for table in _tables(source):
        for row in table:
            link = next(
                (
                    attrs
                    for cell in row
                    for attrs in cell["attrs"].get("a", [])
                    if "fnMoveDetail" in (attrs.get("onclick") or "")
                ),
                None,
            )
            if link is None:
                continue
            matched = re.search(r"\d+", html.unescape(link.get("onclick") or ""))
            row_text = [cell["text"] for cell in row]
            published = next(
                (value for value in row_text if re.fullmatch(r"20\d{2}\.\d{2}\.\d{2}", value)),
                "",
            )
            title = next((value for value in row_text if "낙차부상" in value), "")
            if matched and published:
                posts.append(
                    {
                        "seq_id": matched.group(),
                        "title": title,
                        "published_date": published.replace(".", ""),
                        "url": f"{BASE_URL}/{matched.group()}",
                    }
                )
    return posts


def _header_key(value: str) -> str:
    return clean(value).replace(" ", "")


def parse_detail(source: str, post: dict) -> dict:
    injuries = []
    for table in _tables(source):
        matrix = [[cell["text"] for cell in row] for row in table]
        header_index = next(
            (
                index
                for index, row in enumerate(matrix)
                if any("선수" in _header_key(value) for value in row)
                and any("부상" in _header_key(value) for value in row)
            ),
            None,
        )
        if header_index is None:
            continue
        headers = [_header_key(value) for value in matrix[header_index]]
        name_index = next(
            (i for i, value in enumerate(headers) if "선수" in value),
            None,
        )
        race_index = next(
            (i for i, value in enumerate(headers) if "경주" in value),
            None,
        )
        injury_indexes = [
            i for i, value in enumerate(headers) if "부상" in value
        ]
        status_indexes = [
            i for i, value in enumerate(headers) if value in {"비고", "출전여부"}
        ]
        if name_index is None:
            continue
        for row_index, row in enumerate(matrix[header_index + 1:], 1):
            if name_index >= len(row):
                continue
            racer_name = clean(row[name_index])
            if not racer_name:
                continue
            injury_text = " / ".join(
                clean(row[index]) for index in injury_indexes
                if index < len(row) and clean(row[index])
            )
            status = " / ".join(
                clean(row[index]) for index in status_indexes
                if index < len(row) and clean(row[index])
            )
            combined = f"{injury_text} {status}"
            severity = (
                "unavailable"
                if "출전불가" in combined
                else "hospital"
                if any(word in combined for word in ("병원", "후송", "입원"))
                else "infirmary"
                if "의무실" in combined
                else "unknown"
            )
            injuries.append(
                {
                    "row_index": row_index,
                    "racer_name_raw": racer_name,
                    "racer_name_normalized": racer_name.replace(" ", ""),
                    "race_text": clean(row[race_index]) if race_index is not None and race_index < len(row) else "",
                    "injury_text": injury_text,
                    "status": status,
                    "severity": severity,
                    "headers": headers,
                }
            )
    return {**post, "injuries": injuries}


def discover(min_year: int, delay: float) -> list[dict]:
    posts: dict[str, dict] = {}
    for page in range(1, 201):
        source = download(f"{BASE_URL}?pagination.currentPage={page}")
        batch = parse_listing(source)
        if not batch:
            break
        for post in batch:
            posts[post["seq_id"]] = post
        years = [int(post["published_date"][:4]) for post in batch]
        print(f"목록 {page}페이지: {len(batch)}건")
        if years and max(years) < min_year:
            break
        time.sleep(delay)
    return sorted(posts.values(), key=lambda post: post["published_date"])


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--min-year", type=int, default=2021)
    parser.add_argument("--delay", type=float, default=0.25)
    parser.add_argument("--refresh", action="store_true")
    parser.add_argument("--keep-html", action="store_true")
    args = parser.parse_args()

    checkpoint = DATA_DIR / "checkpoints" / "fall_injuries.json"
    state = (
        json.loads(checkpoint.read_text(encoding="utf-8"))
        if checkpoint.exists() and not args.refresh
        else {"completed": {}, "failures": {}}
    )
    manifest = discover(args.min_year, args.delay)
    write_json(DATA_DIR / "reports" / "fall_injury_manifest.json", manifest, indent=2)

    for index, post in enumerate(manifest, 1):
        if int(post["published_date"][:4]) < args.min_year:
            continue
        seq_id = post["seq_id"]
        if seq_id in state["completed"]:
            continue
        try:
            source = download(post["url"])
            state["completed"][seq_id] = parse_detail(source, post)
            state["failures"].pop(seq_id, None)
            if args.keep_html:
                raw = DATA_DIR / "raw" / "fall_injuries" / f"{seq_id}.html"
                raw.parent.mkdir(parents=True, exist_ok=True)
                raw.write_text(source, encoding="utf-8")
            label = f"{len(state['completed'][seq_id]['injuries'])}명"
        except Exception as error:
            state["failures"][seq_id] = f"{type(error).__name__}: {error}"
            label = "실패"
        write_json(checkpoint, state)
        print(f"[{index}/{len(manifest)}] {seq_id}: {label}")
        time.sleep(args.delay)

    records = sorted(
        state["completed"].values(),
        key=lambda record: (record["published_date"], record["seq_id"]),
    )
    write_json(DATA_DIR / "fall_injuries.json", records)
    write_json(
        DATA_DIR / "reports" / "fall_injuries.json",
        {
            "posts": len(records),
            "injury_rows": sum(len(record["injuries"]) for record in records),
            "failures": state["failures"],
        },
        indent=2,
    )


if __name__ == "__main__":
    main()
