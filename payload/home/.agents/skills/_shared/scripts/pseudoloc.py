#!/usr/bin/env python3
"""Pseudolocalization generator for i18n and RTL validation.

Produces the two pseudo-locales described in the RTL/i18n reference so you can
expose truncation, overflow, hardcoded strings and un-mirrored layout before
any real translation exists.

Modes:
  accent  Accent every ASCII letter, expand length per the skill's expansion
          table, and wrap with [!!! ... !!!] boundary markers. Reveals
          truncation/overflow and, because unwrapped output means a string was
          never sent through translation, hardcoded strings.
  rtl     Force right-to-left: accent + expand, then wrap the value in a
          Unicode RTL isolate (U+2067 ... U+2069). Reveals physical left/right
          leftovers and icons/layout that fail to mirror.
  both    Print accent then rtl for each input (default).

Input (in priority order):
  --file PATH        Read from a file. With --json it is parsed as JSON and
                     every string leaf value is transformed, keys preserved.
  positional TEXT..  Transform each argument as a standalone string.
  stdin              If neither is given, read stdin. With --json the whole
                     stream is parsed as JSON.

Zero dependencies (Python 3 standard library only).
"""

import argparse
import json
import math
import sys

# Precomposed single-codepoint accents keep width predictable.
_ACCENT = {
    "a": "á", "b": "ƀ", "c": "ç", "d": "ð", "e": "é", "f": "ƒ", "g": "ĝ",
    "h": "ĥ", "i": "í", "j": "ĵ", "k": "ķ", "l": "ĺ", "m": "ɱ", "n": "ñ",
    "o": "ó", "p": "þ", "q": "q̃", "r": "ŕ", "s": "š", "t": "ŧ", "u": "ú",
    "v": "ṽ", "w": "ŵ", "x": "ẋ", "y": "ý", "z": "ž",
    "A": "Á", "B": "Ɓ", "C": "Ç", "D": "Ð", "E": "É", "F": "Ƒ", "G": "Ĝ",
    "H": "Ĥ", "I": "Í", "J": "Ĵ", "K": "Ķ", "L": "Ĺ", "M": "Ṁ", "N": "Ñ",
    "O": "Ó", "P": "Þ", "Q": "Q̃", "R": "Ŕ", "S": "Š", "T": "Ŧ", "U": "Ú",
    "V": "Ṽ", "W": "Ŵ", "X": "Ẋ", "Y": "Ý", "Z": "Ž",
}

# Expansion multipliers (lower bound of each range in the skill's table).
def _target_multiplier(letter_count):
    if letter_count <= 10:
        return 2.0   # +100%
    if letter_count <= 20:
        return 1.8   # +80%
    if letter_count <= 50:
        return 1.6   # +60%
    return 1.3       # +30%

_PAD_CYCLE = "áéíóú"  # readable, obviously-padding accented vowels

RLI = "\u2067"  # right-to-left isolate
PDI = "\u2069"  # pop directional isolate


def _accent_text(text):
    return "".join(_ACCENT.get(ch, ch) for ch in text)


def _expand(accented, letter_count):
    """Pad accented text with a marked run to hit the target length."""
    if letter_count == 0:
        return accented
    target = math.ceil(letter_count * _target_multiplier(letter_count))
    pad_needed = target - letter_count
    if pad_needed <= 0:
        return accented
    pad = "".join(_PAD_CYCLE[i % len(_PAD_CYCLE)] for i in range(pad_needed))
    return accented + " " + pad


def pseudo_accent(text):
    if text == "":
        return text
    letters = sum(1 for ch in text if ch.isalpha() and ch.isascii())
    body = _expand(_accent_text(text), letters)
    return "[!!! " + body + " !!!]"


def pseudo_rtl(text):
    if text == "":
        return text
    return RLI + pseudo_accent(text) + PDI


_TRANSFORM = {"accent": pseudo_accent, "rtl": pseudo_rtl}


def transform_json(node, fn):
    if isinstance(node, str):
        return fn(node)
    if isinstance(node, list):
        return [transform_json(v, fn) for v in node]
    if isinstance(node, dict):
        return {k: transform_json(v, fn) for k, v in node.items()}
    return node  # numbers, bools, null pass through untouched


def _emit_string(text, mode, out):
    if mode == "both":
        out.write(pseudo_accent(text) + "\n")
        out.write(pseudo_rtl(text) + "\n")
    else:
        out.write(_TRANSFORM[mode](text) + "\n")


def main(argv=None):
    parser = argparse.ArgumentParser(
        description="Pseudolocalize strings for RTL and locale validation.")
    parser.add_argument("--mode", choices=["accent", "rtl", "both"],
                        default="both", help="pseudo-locale to emit (default: both)")
    parser.add_argument("--json", action="store_true",
                        help="treat input as JSON; transform string leaves, keep keys")
    parser.add_argument("--file", help="read input from a file instead of args/stdin")
    parser.add_argument("text", nargs="*", help="strings to transform")
    args = parser.parse_args(argv)

    if args.json:
        raw = (open(args.file, encoding="utf-8").read() if args.file
               else sys.stdin.read())
        try:
            data = json.loads(raw)
        except json.JSONDecodeError as exc:
            parser.error(f"invalid JSON: {exc}")
        if args.mode == "both":
            parser.error("--json requires --mode accent or --mode rtl")
        result = transform_json(data, _TRANSFORM[args.mode])
        json.dump(result, sys.stdout, ensure_ascii=False, indent=2)
        sys.stdout.write("\n")
        return

    if args.file:
        with open(args.file, encoding="utf-8") as fh:
            lines = fh.read().splitlines()
    elif args.text:
        lines = args.text
    else:
        lines = sys.stdin.read().splitlines()

    for line in lines:
        _emit_string(line, args.mode, sys.stdout)


if __name__ == "__main__":
    main()
