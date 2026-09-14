#!/usr/bin/env python3
"""Convert MIND behaviors.tsv rows into three-conjunct MeTTa expressions.

Each clicked or not-clicked news item becomes one expression, for example:

    (Clicked U13740 N55689)

Only the latest row for each user is used. The history in that row contributes
clicked facts, and the current impression contributes clicked or not-clicked
facts. Current impression labels take precedence over history if they overlap.
"""

from __future__ import annotations

import argparse
import re
import sys
from collections.abc import Iterable
from datetime import datetime
from typing import TextIO


SAFE_ATOM = re.compile(r"^[A-Za-z0-9_]+$")


def metta_atom(value: str, field_name: str) -> str:
    """Return a safe unquoted MeTTa atom or reject malformed input."""
    if not SAFE_ATOM.fullmatch(value):
        raise ValueError(f"invalid {field_name}: {value!r}")
    return value


def parse_impression(token: str, line_number: int) -> tuple[str, str]:
    """Split a MIND impression token into news ID and click label."""
    try:
        news_id, clicked = token.rsplit("-", 1)
    except ValueError as error:
        raise ValueError(
            f"line {line_number}: impression {token!r} must end in -0 or -1"
        ) from error

    if clicked not in {"0", "1"} or not news_id:
        raise ValueError(
            f"line {line_number}: impression {token!r} must end in -0 or -1"
        )
    return metta_atom(news_id, "news ID"), clicked


def convert_rows(rows: Iterable[str]) -> Iterable[str]:
    """Yield facts from the latest behavior row for each user."""
    latest_by_user: dict[str, tuple[datetime, int, str, str, str, str]] = {}

    for line_number, line in enumerate(rows, start=1):
        if not line.strip():
            continue

        fields = line.rstrip("\r\n").split("\t")
        if len(fields) != 5:
            raise ValueError(
                f"line {line_number}: expected 5 tab-separated fields, "
                f"got {len(fields)}"
            )

        impression_id, user_id, timestamp, history, impressions = fields
        impression_id = metta_atom(impression_id, "impression ID")
        user_id = metta_atom(user_id, "user ID")
        try:
            parsed_timestamp = datetime.strptime(timestamp, "%m/%d/%Y %I:%M:%S %p")
        except ValueError as error:
            raise ValueError(
                f"line {line_number}: invalid timestamp {timestamp!r}; "
                'expected "MM/DD/YYYY HH:MM:SS AM/PM"'
            ) from error

        for news_id in history.split():
            metta_atom(news_id, "history news ID")

        # The line number makes equal timestamps deterministic: the later row wins.
        previous = latest_by_user.get(user_id)
        if previous is None or (parsed_timestamp, line_number) >= (
            previous[0],
            previous[1],
        ):
            latest_by_user[user_id] = (
                parsed_timestamp,
                line_number,
                impression_id,
                user_id,
                history,
                impressions,
            )

    for _, line_number, _, user_id, history, impressions in latest_by_user.values():
        facts: dict[str, str] = {
            news_id: "Clicked" for news_id in history.split()
        }
        for token in impressions.split():
            news_id, clicked = parse_impression(token, line_number)
            facts[news_id] = "Clicked" if clicked == "1" else "NotClicked"

        for news_id, predicate in facts.items():
            yield f"({predicate} {user_id} {news_id})"


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description="Convert MIND behaviors.tsv to MeTTa click facts."
    )
    parser.add_argument(
        "input",
        nargs="?",
        help="behaviors.tsv path; read stdin when omitted",
    )
    parser.add_argument(
        "-o",
        "--output",
        help="output path; write stdout when omitted",
    )
    return parser


def main() -> int:
    args = build_parser().parse_args()
    input_stream: TextIO
    output_stream: TextIO
    input_file = None
    output_file = None

    try:
        if args.input:
            input_file = open(args.input, encoding="utf-8")
            input_stream = input_file
        else:
            input_stream = sys.stdin

        if args.output:
            output_file = open(args.output, "w", encoding="utf-8")
            output_stream = output_file
        else:
            output_stream = sys.stdout

        for expression in convert_rows(input_stream):
            print(expression, file=output_stream)
    except (OSError, ValueError) as error:
        print(f"error: {error}", file=sys.stderr)
        return 1
    finally:
        if input_file is not None:
            input_file.close()
        if output_file is not None:
            output_file.close()

    return 0


if __name__ == "__main__":
    raise SystemExit(main())