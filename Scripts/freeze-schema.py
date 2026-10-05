#!/usr/bin/env python3
"""Fige la version courante du schéma SwiftData dans une copie immuable.

Une migration étagée a besoin d'une description **stable** de l'état d'où
elle part. Si les modèles figés suivaient l'évolution des modèles courants,
l'étape « v4 → v5 » décrirait un v5 qui n'a jamais existé, et la migration
d'un store réel échouerait ou perdrait des données.

Ce script extrait les `@Model final class` des modèles vivants, les réindente
dans une `enum VersionedSchema`, et **remplace les valeurs par défaut
calculées par des littéraux** : un défaut qui pointe vers un `rawValue` d'enum
suivrait le code au lieu de rester fixe.

Usage :
    Scripts/freeze-schema.py 5      # fige l'état courant en MuscuSchemaV5
"""
import pathlib
import re
import sys

MODELS_DIR = pathlib.Path("App/Sources/Models")
OUTPUT_DIR = MODELS_DIR / "SchemaVersions"

# Valeurs par défaut a inliner : elles doivent rester fixes dans la copie.
LITERALS = {
    "MassUnit.kilograms.rawValue": '"kg"',
    "LengthUnit.centimeters.rawValue": '"cm"',
}
ENUM_DEFAULT = re.compile(r"\b([A-Z]\w+)\.(\w+)\.rawValue")


def inline_defaults(line: str) -> str:
    """Remplace `Kind.case.rawValue` par son littéral.

    Les cas connus sont explicites ; pour les autres, le nom du cas est la
    valeur brute (`RawRepresentable` synthétisé par Swift).
    """
    for source, literal in LITERALS.items():
        line = line.replace(source, literal)
    return ENUM_DEFAULT.sub(lambda m: f'"{m.group(2)}"', line)


def model_blocks(text: str) -> list[str]:
    """Blocs `@Model final class …` complets, accolades équilibrées."""
    blocks: list[str] = []
    lines = text.split("\n")
    index = 0
    while index < len(lines):
        if lines[index].strip() != "@Model":
            index += 1
            continue
        start = index
        depth = 0
        started = False
        while index < len(lines):
            depth += lines[index].count("{") - lines[index].count("}")
            if lines[index].count("{"):
                started = True
            if started and depth <= 0:
                break
            index += 1
        blocks.append("\n".join(lines[start:index + 1]))
        index += 1
    return blocks


def main() -> int:
    if len(sys.argv) != 2 or not sys.argv[1].isdigit():
        print(__doc__)
        return 2
    version = int(sys.argv[1])
    output = OUTPUT_DIR / f"MuscuSchemaV{version}.swift"
    if output.exists():
        print(f"{output} existe déjà : une version figée ne se réécrit jamais.")
        return 1

    blocks: list[str] = []
    for path in sorted(MODELS_DIR.glob("*.swift")):
        blocks += model_blocks(path.read_text())

    names = [
        re.search(r"final class (\w+)", block).group(1)
        for block in blocks
    ]

    body = [
        "import Foundation",
        "import SwiftData",
        "",
        f"/// Version {version} du schéma, FIGÉE.",
        "///",
        "/// Ces copies ne doivent JAMAIS suivre l'évolution des modèles",
        "/// courants : une migration étagée a besoin d'une description stable",
        "/// de l'état d'où elle part. Les valeurs brutes par défaut sont",
        "/// écrites en littéral pour la même raison.",
        "///",
        "/// Généré par `Scripts/freeze-schema.py`.",
        f"enum MuscuSchemaV{version}: VersionedSchema {{",
        f"    static let versionIdentifier = Schema.Version({version}, 0, 0)",
        "",
        "    static var models: [any PersistentModel.Type] {",
        "        [",
    ]
    body += [f"            {name}.self," for name in sorted(names)]
    body += ["        ]", "    }", ""]

    for block in blocks:
        for line in block.split("\n"):
            body.append(("    " + inline_defaults(line)).rstrip())
        body.append("")

    body.append("}")
    output.write_text("\n".join(body) + "\n")
    print(f"{output} écrit — {len(names)} modèles figés.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
