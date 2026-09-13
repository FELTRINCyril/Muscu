import Foundation

public enum CSVParseError: Error, Equatable, Sendable {
    case empty
    /// Un guillemet ouvert n'est jamais referme : le reste du fichier serait
    /// avale silencieusement. On refuse plutot que de deviner.
    case unterminatedQuote(line: Int)
    case tooManyRows(limit: Int)
}

/// Lecteur CSV conforme a RFC 4180, etendu a ce que produisent reellement les
/// tableurs : separateur `,` `;` ou tabulation, fins de ligne LF/CRLF/CR,
/// BOM UTF-8, guillemets doubles a l'interieur d'un champ, retours a la ligne
/// dans un champ cite.
public struct CSVParser: Sendable {
    public let delimiter: Character
    /// Borne dure : un fichier de plusieurs millions de lignes ne doit pas
    /// pouvoir epuiser la memoire de l'appareil.
    public let rowLimit: Int

    /// Swift considere CR+LF comme un seul `Character` : il faut donc le
    /// traiter explicitement, sinon aucun fichier Windows n'est decoupe.
    private let crlf: Character = "\r\n"

    public init(delimiter: Character = ",", rowLimit: Int = 200_000) {
        self.delimiter = delimiter
        self.rowLimit = rowLimit
    }

    /// Devine le separateur a partir de la premiere ligne non vide, en
    /// comptant les occurrences HORS guillemets.
    public static func detectDelimiter(in text: String) -> Character {
        let candidates: [Character] = [",", ";", "\t"]
        // CR+LF est un seul `Character` en Swift : on decoupe sur les
        // scalaires pour isoler reellement la premiere ligne.
        let firstLine = text.unicodeScalars
            .split(whereSeparator: { $0 == "\n" || $0 == "\r" })
            .first
            .map { String(String.UnicodeScalarView($0)) } ?? ""

        var counts: [Character: Int] = [:]
        var insideQuotes = false
        for character in firstLine {
            if character == "\"" { insideQuotes.toggle(); continue }
            guard !insideQuotes, candidates.contains(character) else { continue }
            counts[character, default: 0] += 1
        }
        // A egalite, la virgule gagne : c'est le separateur de la norme.
        return counts.max { left, right in
            left.value == right.value ? right.key == "," : left.value < right.value
        }?.key ?? ","
    }

    public func parse(_ text: String) throws -> [[String]] {
        var input = Substring(text)
        if input.hasPrefix("\u{FEFF}") { input = input.dropFirst() }
        guard !input.isEmpty else { throw CSVParseError.empty }

        var rows: [[String]] = []
        var field = ""
        var row: [String] = []
        var insideQuotes = false
        var lineNumber = 1
        var index = input.startIndex

        func endField() {
            row.append(field)
            field = ""
        }

        func endRow() throws {
            endField()
            // Une ligne entierement vide est un artefact de fin de fichier,
            // pas une donnee : l'ignorer evite une ligne fantome par import.
            if !(row.count == 1 && row[0].isEmpty) {
                rows.append(row)
                if rows.count > rowLimit { throw CSVParseError.tooManyRows(limit: rowLimit) }
            }
            row = []
        }

        while index < input.endIndex {
            let character = input[index]

            if insideQuotes {
                if character == "\"" {
                    let next = input.index(after: index)
                    if next < input.endIndex, input[next] == "\"" {
                        field.append("\"")
                        index = input.index(after: next)
                        continue
                    }
                    insideQuotes = false
                } else if character == crlf {
                    // Swift regroupe CR+LF en UN SEUL caractere : sans ce cas,
                    // un fichier Windows ne serait jamais decoupe en lignes.
                    lineNumber += 1
                    field.append("\n")
                } else {
                    if character == "\n" { lineNumber += 1 }
                    field.append(character)
                }
                index = input.index(after: index)
                continue
            }

            switch character {
            case "\"" where field.isEmpty:
                insideQuotes = true
            case delimiter:
                endField()
            case "\r", crlf:
                try endRow()
                lineNumber += 1
            case "\n":
                try endRow()
                lineNumber += 1
            default:
                field.append(character)
            }
            index = input.index(after: index)
        }

        if insideQuotes { throw CSVParseError.unterminatedQuote(line: lineNumber) }
        if !field.isEmpty || !row.isEmpty { try endRow() }

        guard !rows.isEmpty else { throw CSVParseError.empty }
        return rows
    }
}
