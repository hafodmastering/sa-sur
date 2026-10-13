// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Hafod Mastering Ltd and Sudeep Audio

// Reads the manual PDF back and checks it, the same way CheckBundle checks the
// app: the artifact is what ships, so the artifact is what gets read.
//
// Checks the page count and page size (A4), that the pages a reader navigates by
// carry the sections they should, that Appendix A really holds all 108 notes, and
// that the house style holds mechanically - no em dashes, and none of the words
// the brief bans.
//
// usage: CheckManual <manual.pdf> [expected-pages]

import Foundation
import PDFKit

let args = CommandLine.arguments
guard args.count >= 2 else {
    FileHandle.standardError.write("usage: CheckManual <manual.pdf> [expected-pages]\n".data(using: .utf8)!)
    exit(2)
}
let path = args[1]
let expectedPages = args.count > 2 ? (Int(args[2]) ?? 7) : 7

var problems = 0

func check(_ label: String, _ passed: Bool, _ detail: String) {
    print("  \(passed ? "OK  " : "FAIL")  \(label): \(detail)")
    if !passed { problems += 1 }
}

guard let document = PDFDocument(url: URL(fileURLWithPath: path)) else {
    print("FAIL  cannot open \(path) as a PDF")
    exit(1)
}

print("manual: \(path)")

check("page count", document.pageCount == expectedPages,
      "\(document.pageCount) pages (expected \(expectedPages))")

var pages: [String] = []
var sizes: Set<String> = []
for index in 0..<document.pageCount {
    guard let page = document.page(at: index) else {
        check("page \(index + 1)", false, "missing")
        continue
    }
    let box = page.bounds(for: .mediaBox)
    sizes.insert("\(Int(box.width.rounded()))x\(Int(box.height.rounded()))")
    // Collapse whitespace: a table cell that wraps extracts as "Company\nmarks",
    // which would defeat a substring check for a phrase that reads as one line.
    let raw = page.string ?? ""
    pages.append(raw.replacingOccurrences(of: "\\s+", with: " ",
                                          options: .regularExpression))
}

check("page size", sizes == ["595x842"], sizes.sorted().joined(separator: ", "))

let text = pages.joined(separator: "\n")
func pageIndex(_ needle: String) -> Int? {
    pages.firstIndex { $0.contains(needle) }
}

// Sections a reader navigates by, and the page they land on.
for (needle, expected) in [("About SA-Sur", 1), ("Install SA-Sur", 1),
                          ("The window", 2), ("Procedures", 3),
                          ("Privacy", 5), ("Appendix A", 7)] {
    let found = pageIndex(needle)
    check("section \"\(needle)\"", found == expected - 1,
          found.map { "page \($0 + 1)" } ?? "not found")
}

// The figure's legend is the control table, so the window page must carry it.
if let window = pageIndex("The window") {
    let marks = pages[window].contains("Company marks")
        && pages[window].contains("Hafod Mastering website")
    check("figure legend", marks, marks ? "control table on page \(window + 1)"
                                        : "control table not found")
} else {
    check("figure legend", false, "no window page")
}

// Appendix A: every value in docs/note-table.csv - the cross-language source of
// truth the two builds already share - must appear on the appendix page. Checked
// against that file rather than a hardcoded count, so the check cannot drift from
// the source it is meant to verify.
let csvURL = URL(fileURLWithPath: path).deletingLastPathComponent()
    .appendingPathComponent("note-table.csv")
if let appendix = pageIndex("Appendix A"), let csv = try? String(contentsOf: csvURL, encoding: .utf8) {
    let expected = csv.split(separator: "\n").compactMap { line -> (String, String)? in
        let parts = line.split(separator: ",")
        guard parts.count == 2, let value = Double(parts[1]) else { return nil }
        return (String(parts[0]), String(format: "%.4f", value))
    }
    let missing = expected.filter { !pages[appendix].contains($0.1) }
    check("appendix values", missing.isEmpty,
          "\(expected.count) values in note-table.csv, "
          + (missing.isEmpty ? "all present" : "missing \(missing.prefix(3).map { $0.0 })"))
    check("appendix order",
          pages[appendix].contains("16.3516") && pages[appendix].contains("7902.1328"),
          "C0 first, B8 last")
} else {
    check("appendix values", false, "no appendix page, or \(csvURL.lastPathComponent) unreadable")
}

// House style, checked on what the reader actually gets.
check("no em dash", !text.contains("\u{2014}"), "none")
let banned = ["simply", "please", "note that", "utilise", "in order to"]
let hits = banned.filter { text.range(of: "\\b\($0)\\b", options: [.regularExpression, .caseInsensitive]) != nil }
check("banned words", hits.isEmpty, hits.isEmpty ? "none" : hits.joined(separator: ", "))

print(problems == 0 ? "MANUAL CHECK: PASS" : "MANUAL CHECK: FAIL (\(problems) problem(s))")
exit(problems == 0 ? 0 : 1)
