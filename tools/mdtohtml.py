#!/usr/bin/env python3
# Minimal, dependency-free markdown -> HTML for the SA-Sur manual, and the
# renderer behind the PDF that ships with the app and the help bundle.
#
# Handles exactly the constructs docs/MANUAL.md uses: ATX headings, paragraphs,
# ordered and unordered lists, pipe tables, fenced code, blockquotes, rules and
# inline bold / italic / code. Stdlib only, so it can live in tools/.
#
# Two repo-specific hooks, both driven from the markdown source:
#   **Figure 1** - caption       -> the window snapshot with numbered callouts
#   <!-- APPENDIX-TABLE: ... --> -> the note table, generated from note-table.csv
# so the frequency values are never retyped into the manual.
import base64
import html
import os
import re
import sys

TITLE = "SA-Sur : Note to Frequency - User Manual"

# Callout positions in the committed snapshot's own pixel space (1460 x 474,
# identical in ui-snapshot-light.png and ui-snapshot-dark.png). The numbers are
# the "#" column of the control table, which is the figure's legend.
SNAPSHOT_SIZE = (1460, 474)
CALLOUTS = [
    (1, 1408, 58),    # note buttons, right of the row
    (2, 1062, 155),   # octave buttons, right of the row
    (3, 250, 208),    # readout, above it
    (4, 525, 288),    # copy icon, right of it
    (5, 1366, 204),   # company marks, above them
    (6, 120, 376),    # Play / Stop
    (7, 370, 376),    # level slider
    (8, 900, 376),    # Concert A
    (9, 1246, 376),   # Decimals
    (10, 1400, 376),  # appearance
]

CSS = """
@page { size: A4; margin: 20mm 18mm 18mm 18mm; }
* { box-sizing: border-box; }
html { -webkit-print-color-adjust: exact; print-color-adjust: exact; }
body { margin: 0; font: 10.5pt/1.5 -apple-system, "Helvetica Neue", Arial, sans-serif;
       color: #16181d; }
h1 { font-size: 21pt; line-height: 1.15; margin: 0 0 4pt; letter-spacing: -0.2pt; }
h1 + h2 { font-size: 12pt; font-weight: 500; color: #5c6370; margin: 0 0 10pt; }
h2 { font-size: 13.5pt; margin: 18pt 0 6pt; padding-top: 6pt; border-top: 0.6pt solid #d9dce2;
     page-break-after: avoid; break-after: avoid; }
h3 { font-size: 11pt; margin: 12pt 0 4pt;
     page-break-after: avoid; break-after: avoid; }
p { margin: 0 0 6pt; orphans: 2; widows: 2; }
ol, ul { margin: 0 0 8pt; padding-left: 16pt; }
li { margin: 0 0 3pt; }
code { font: 9.5pt/1.4 ui-monospace, "SF Mono", Menlo, monospace; background: #f2f3f5;
       padding: 0.5pt 1.2pt; border-radius: 2pt; white-space: nowrap; }
pre { background: #f2f3f5; border-left: 2.5pt solid #c9ced6; padding: 6pt 8pt;
      margin: 0 0 8pt; }
pre code { background: none; padding: 0; }
table { border-collapse: collapse; width: 100%; margin: 0 0 8pt; font-size: 9.5pt; }
th, td { text-align: left; vertical-align: top; padding: 3.5pt 6pt;
         border-bottom: 0.5pt solid #e2e5ea; }
th { font-weight: 600; border-bottom: 0.8pt solid #b9bfc9; }
blockquote { margin: 0 0 8pt; padding: 6pt 8pt; background: #fdf3f2;
             border-left: 2.5pt solid #dd3938; }
blockquote p { margin: 0; }
hr { border: 0; border-top: 0.6pt solid #d9dce2; margin: 14pt 0; }
a { color: #16181d; }
figure { margin: 0 0 10pt; page-break-inside: avoid; }
figure .frame { position: relative; line-height: 0; }
figure img { width: 100%; height: auto; display: block; border: 0.5pt solid #d9dce2; }
figure .callout { position: absolute; width: 4.2mm; height: 4.2mm; margin: -2.1mm 0 0 -2.1mm;
                  border-radius: 50%; background: #16181d; color: #ffffff;
                  font: 600 2.4mm/4.2mm -apple-system, Arial, sans-serif; text-align: center; }
figcaption { font-size: 8.5pt; color: #5c6370; margin-top: 3pt; }
table.notes { font-size: 8.5pt; line-height: 1.35; page-break-inside: avoid; }
table.notes td, table.notes th { padding: 1.2pt 5pt; }
table.notes td.hz { font-variant-numeric: tabular-nums; }
"""


def inline(text):
    out = html.escape(text, quote=False)
    out = re.sub(r"`([^`]+)`", r"<code>\1</code>", out)
    out = re.sub(r"\*\*([^*]+)\*\*", r"<strong>\1</strong>", out)
    out = re.sub(r"(?<![\w*])\*([^*]+)\*(?![\w*])", r"<em>\1</em>", out)
    return out


def figure_block(caption, image_path):
    with open(image_path, "rb") as fh:
        data = base64.b64encode(fh.read()).decode("ascii")
    mime = "image/png" if image_path.lower().endswith(".png") else "image/jpeg"
    marks = "".join(
        '<span class="callout" style="left:%.2f%%;top:%.2f%%">%d</span>'
        % (x / SNAPSHOT_SIZE[0] * 100.0, y / SNAPSHOT_SIZE[1] * 100.0, n)
        for n, x, y in CALLOUTS)
    return ('<figure><div class="frame"><img alt="%s" src="data:%s;base64,%s">%s</div>'
            '<figcaption>%s</figcaption></figure>'
            % (html.escape(caption, quote=True), mime, data, marks, inline(caption)))


def note_table(csv_path, columns, decimals):
    rows = []
    with open(csv_path, encoding="utf-8") as fh:
        for line in fh:
            if not line.strip():
                continue
            name, value = line.strip().split(",")
            rows.append((name, "%.*f" % (decimals, float(value))))
    per = -(-len(rows) // columns)
    chunks = [rows[i * per:(i + 1) * per] for i in range(columns)]
    head = "".join("<th>Note</th><th>Hz</th>" for _ in range(columns))
    body = []
    for i in range(per):
        cells = []
        for chunk in chunks:
            if i < len(chunk):
                name, value = chunk[i]
                cells.append('<td>%s</td><td class="hz">%s</td>' % (name, value))
            else:
                cells.append("<td></td><td></td>")
        body.append("<tr>%s</tr>" % "".join(cells))
    return ('<table class="notes"><thead><tr>%s</tr></thead><tbody>%s</tbody></table>'
            % (head, "".join(body)))


def convert(lines, base_dir, figure):
    out, i = [], 0
    while i < len(lines):
        line = lines[i].rstrip("\n")
        stripped = line.strip()

        if not stripped:
            i += 1
            continue

        m = re.match(r"^<!--\s*APPENDIX-TABLE:\s*(\S+)\s+columns=(\d+)\s+decimals=(\d+)\s*-->$",
                     stripped)
        if m:
            path = m.group(1)
            if not os.path.isabs(path):
                path = os.path.join(base_dir, path)
            out.append(note_table(path, int(m.group(2)), int(m.group(3))))
            i += 1
            continue

        m = re.match(r"^\*\*(Figure \d+)\*\*\s*-\s*(.*)$", stripped)
        if m:
            caption = "%s - %s" % (m.group(1), m.group(2))
            if figure:
                out.append(figure_block(caption, figure))
            else:
                out.append("<p><strong>%s</strong></p>" % inline(caption))
            i += 1
            continue

        if stripped.startswith("```"):
            i += 1
            block = []
            while i < len(lines) and not lines[i].strip().startswith("```"):
                block.append(html.escape(lines[i].rstrip("\n")))
                i += 1
            i += 1
            out.append("<pre><code>%s</code></pre>" % "\n".join(block))
            continue

        m = re.match(r"^(#{1,4})\s+(.*)$", stripped)
        if m:
            level = len(m.group(1))
            text = m.group(2)
            # An appendix starts on a fresh page: its table is long enough that a
            # heading at the foot of the previous page would be stranded.
            style = ' style="page-break-before: always"' if text.startswith("Appendix") else ""
            out.append("<h%d%s>%s</h%d>" % (level, style, inline(text), level))
            i += 1
            continue

        if re.match(r"^(-{3,}|\*{3,})$", stripped):
            out.append("<hr>")
            i += 1
            continue

        if stripped.startswith("|"):
            rows = []
            while i < len(lines) and lines[i].strip().startswith("|"):
                rows.append([c.strip() for c in lines[i].strip().strip("|").split("|")])
                i += 1
            body = [r for r in rows if not all(re.fullmatch(r":?-{2,}:?", c) for c in r)]
            if body:
                head, rest = body[0], body[1:]
                out.append("<table><thead><tr>%s</tr></thead><tbody>%s</tbody></table>" % (
                    "".join("<th>%s</th>" % inline(c) for c in head),
                    "".join("<tr>%s</tr>" % "".join("<td>%s</td>" % inline(c) for c in r)
                            for r in rest)))
            continue

        if stripped.startswith(">"):
            block = []
            while i < len(lines) and lines[i].strip().startswith(">"):
                block.append(lines[i].strip().lstrip(">").strip())
                i += 1
            out.append("<blockquote>%s</blockquote>" % " ".join(inline(b) for b in block))
            continue

        m = re.match(r"^(\d+)\.\s+(.*)$", stripped)
        if m:
            items = []
            while i < len(lines) and re.match(r"^\s*\d+\.\s+", lines[i]):
                items.append(re.sub(r"^\s*\d+\.\s+", "", lines[i]).strip())
                i += 1
            out.append("<ol>%s</ol>" % "".join("<li>%s</li>" % inline(x) for x in items))
            continue

        if re.match(r"^[-*]\s+", stripped):
            items = []
            while i < len(lines) and re.match(r"^\s*[-*]\s+", lines[i]):
                items.append(re.sub(r"^\s*[-*]\s+", "", lines[i]).strip())
                i += 1
            out.append("<ul>%s</ul>" % "".join("<li>%s</li>" % inline(x) for x in items))
            continue

        para = [stripped]
        i += 1
        while i < len(lines) and lines[i].strip() and not re.match(
                r"^(#{1,4}\s|```|\||>|\d+\.\s|[-*]\s|-{3,}$|<!--)", lines[i].strip()):
            para.append(lines[i].strip())
            i += 1
        out.append("<p>%s</p>" % " ".join(inline(p) for p in para))
    return "\n".join(out)


def main():
    args = sys.argv[1:]
    figure = None
    if "--figure" in args:
        k = args.index("--figure")
        figure = args[k + 1]
        del args[k:k + 2]
    src, dst = args[0], args[1]
    with open(src, encoding="utf-8") as fh:
        body = convert(fh.readlines(), os.path.dirname(os.path.abspath(src)), figure)
    with open(dst, "w", encoding="utf-8") as fh:
        fh.write("<!DOCTYPE html>\n<html lang=\"en\">\n<head>\n<meta charset=\"utf-8\">\n"
                 "<title>%s</title>\n<style>%s</style>\n</head>\n<body>\n%s\n</body>\n</html>\n"
                 % (html.escape(TITLE), CSS, body))
    print("wrote %s" % dst)


if __name__ == "__main__":
    main()
