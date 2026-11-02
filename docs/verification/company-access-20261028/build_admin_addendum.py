"""Build the new addendum while preserving the existing ten-page manual."""
from pathlib import Path
import re
from docx import Document
from docx.shared import Inches, Pt, RGBColor
from docx.oxml import OxmlElement
from docx.oxml.ns import qn

root = Path(__file__).resolve().parents[3]
source = root / "docs/user-guide/company-access-administration.md"
target = root / "docs/user-guide/Jentra OS Company Access Administration Addendum.docx"
identity = "jentra-company-access-addendum-20261028"
if target.exists() and Document(target).core_properties.identifier != identity:
    raise RuntimeError("The target is not this task's addendum; refusing overwrite")
doc = Document()
doc.core_properties.title = "Jentra OS Company and Access Administration"
doc.core_properties.subject = "Administrator instructions for the additive candidate"
doc.core_properties.author = "Codex"
doc.core_properties.identifier = identity
section = doc.sections[0]
section.page_width, section.page_height = Inches(8.5), Inches(11)
section.top_margin = section.bottom_margin = Inches(.7)
section.left_margin = section.right_margin = Inches(.75)
section.header_distance = section.footer_distance = Inches(.3)
for name, size in [("Normal", 11), ("Title", 22), ("Heading 1", 14), ("Heading 2", 12)]:
    style = doc.styles[name]
    style.font.name = "Calibri"
    style.font.size = Pt(size)
    style.font.color.rgb = RGBColor(0, 0, 0)
    style.paragraph_format.space_after = Pt(7)
    style.paragraph_format.line_spacing = 1.08
    if name.startswith("Heading"):
        style.paragraph_format.space_before = Pt(10)
        style.paragraph_format.keep_with_next = True
    # Word's template Title must not contribute a decorative paragraph rule.
    ppr = style.element.find(qn("w:pPr"))
    if ppr is not None:
        for border in list(ppr.findall(qn("w:pBdr"))):
            ppr.remove(border)
header = section.header.paragraphs[0]
header.text = "JENTRA OS  |  ADMINISTRATOR ADDENDUM  |  28 OCTOBER 2026"
header.runs[0].font.size = Pt(8)
header.runs[0].font.color.rgb = RGBColor(0, 0, 0)
footer = section.footer.paragraphs[0]
footer.alignment = 2
footer.add_run("Company and access administration  |  ").font.size = Pt(8)
field = OxmlElement("w:fldSimple")
field.set(qn("w:instr"), "PAGE")
footer._p.append(field)

def paragraph(text, style=None):
    text = re.sub(r"\[([^\]]+)\]\([^)]*\)", r"\1", text)
    p = doc.add_paragraph(style=style)
    for i, part in enumerate(re.split(r"\*\*(.*?)\*\*", text)):
        run = p.add_run(part.replace("`", ""))
        run.bold = i % 2 == 1
    p.paragraph_format.widow_control = True
    return p

doc.add_paragraph("Jentra OS Company and Access Administration", "Title")
blocks = re.split(r"\n\s*\n", source.read_text(encoding="utf-8"))
for block in blocks:
    block = block.strip()
    if not block or block.startswith("# "):
        continue
    if block.startswith("## "):
        title = block[3:].replace("&", "and").replace(":", "").replace("/", " and ")
        doc.add_paragraph(title, "Heading 1")
    elif re.match(r"^\d+\. ", block):
        steps = re.split(r"\n(?=\d+\. )", block)
        for step in steps:
            p = paragraph(re.sub(r"\s*\n\s*", " ", step))
            p.paragraph_format.left_indent = Inches(.2)
            p.paragraph_format.first_line_indent = Inches(-.2)
    else:
        paragraph(re.sub(r"\s*\n\s*", " ", block))
doc.add_paragraph("Sales release decisions", "Heading 1")
paragraph("For the separate Jentra Sales release, the owner selected discount requests with company approval and verified email links for customer order acceptance and delivery acknowledgement. Those three facts remain separate. The Sales app and email confirmation implementation are still pending; this selection does not activate email or push sending.")
doc.save(target)
print(target)
