"""Use the skill renderer with native Word and PDFium on this Windows host.

The stock renderer was attempted first and reported missing LibreOffice.
Native Word is installed. This adapter leaves the managed renderer unchanged.
"""
from pathlib import Path
import importlib.util
import subprocess
import pypdfium2 as pdfium

skill = Path("C:/Users/sheha/.codex/plugins/cache/openai-primary-runtime/documents/26.1025.11240/skills/documents/render_docx.py")
spec = importlib.util.spec_from_file_location("skill_render_docx", skill)
renderer = importlib.util.module_from_spec(spec)
spec.loader.exec_module(renderer)

def convert(doc_path, user_profile, convert_tmp_dir, stem, verbose=False):
    pdf_path = str(Path(convert_tmp_dir) / (stem + ".pdf"))
    helper = Path(__file__).with_name("export_guide_word.ps1")
    result = subprocess.run(["powershell", "-NoProfile", "-ExecutionPolicy", "Bypass",
        "-File", str(helper), "-InputPath", doc_path, "-OutputPath", pdf_path],
        capture_output=True, text=True, timeout=90)
    log = result.stdout + result.stderr
    return (pdf_path if result.returncode == 0 and Path(pdf_path).is_file() else "", log)

def rasterize_pdf(pdf_path, dpi=180, output_folder=None, **kwargs):
    document = pdfium.PdfDocument(pdf_path)
    paths = []
    try:
        for index in range(len(document)):
            page = document[index]
            bitmap = page.render(scale=dpi / 72)
            image = bitmap.to_pil()
            output = Path(output_folder) / f"native-page-{index + 1}.png"
            image.save(output)
            paths.append(str(output))
            image.close()
            bitmap.close()
            page.close()
    finally:
        document.close()
    return paths

renderer.convert_to_pdf = convert
renderer.convert_from_path = rasterize_pdf
renderer.main()
