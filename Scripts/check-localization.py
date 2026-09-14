#!/usr/bin/env python3
"""Verifie que chaque catalogue de chaines est reellement traduit.

Trois controles, tous eliminatoires :

1. chaque cle possede une traduction anglaise ;
2. cette traduction n'est pas restee a l'etat `new` ou `needs_review` ;
3. les specificateurs de format sont IDENTIQUES entre la source francaise et
   la traduction — une `%@` oubliee ne se voit pas a la relecture mais fait
   planter le formatage a l'execution.

Le catalogue n'est PAS regenere ici : la synchronisation avec le code est
faite par Xcode (ou `xcstringstool sync`) et commitee. Ce script constate.
"""
import json
import re
import sys
from pathlib import Path

CATALOGS = [
    Path("App/Resources/Localizable.xcstrings"),
    Path("Widgets/Localizable.xcstrings"),
    Path("Watch/Localizable.xcstrings"),
]
LANGUAGES = ["en"]
SPECIFIER = re.compile(r"%(?:\d+\$)?[.0-9]*[@a-zA-Z]+|%%")
ACCEPTED_STATES = {"translated"}


def check(path: Path) -> list[str]:
    if not path.exists():
        return [f"{path} : catalogue introuvable"]
    catalog = json.loads(path.read_text())
    problems: list[str] = []
    for key, entry in sorted(catalog.get("strings", {}).items()):
        # Une chaine explicitement marquee « ne pas traduire » est legitime.
        if entry.get("shouldTranslate") is False:
            continue
        localizations = entry.get("localizations", {})
        for language in LANGUAGES:
            unit = localizations.get(language, {}).get("stringUnit")
            if unit is None:
                problems.append(f"{path} : aucune traduction {language} pour {key!r}")
                continue
            if unit.get("state") not in ACCEPTED_STATES:
                problems.append(
                    f"{path} : traduction {language} a l'etat "
                    f"{unit.get('state')!r} pour {key!r}"
                )
                continue
            if SPECIFIER.findall(key) != SPECIFIER.findall(unit.get("value", "")):
                problems.append(
                    f"{path} : specificateurs differents en {language}\n"
                    f"    source : {key!r}\n"
                    f"    {language:>6} : {unit.get('value')!r}"
                )
    return problems


def main() -> int:
    problems: list[str] = []
    total = 0
    for path in CATALOGS:
        problems += check(path)
        if path.exists():
            total += len(json.loads(path.read_text()).get("strings", {}))
    if problems:
        print(f"Localisation : {len(problems)} probleme(s)")
        for problem in problems:
            print(" -", problem)
        return 1
    print(f"Localisation : {total} chaines, {', '.join(LANGUAGES)} complet.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
