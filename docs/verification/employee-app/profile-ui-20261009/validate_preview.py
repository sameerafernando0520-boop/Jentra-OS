"""Verify that the downloadable UI preview contains the current PNG renders."""
import base64
import hashlib
import io
import json
from html.parser import HTMLParser
from pathlib import Path

from PIL import Image


class PreviewParser(HTMLParser):
    def __init__(self):
        super().__init__()
        self.images = []
        self.external_assets = []

    def handle_starttag(self, tag, attributes):
        attributes = dict(attributes)
        if tag == "img":
            self.images.append(attributes["src"])
        for attribute in ("src", "href"):
            value = attributes.get(attribute)
            if value and not value.startswith(("data:", "#")):
                self.external_assets.append(value)


folder = Path(__file__).resolve().parent
html = (folder / "employee-app-preview.html").read_bytes()
parser = PreviewParser()
parser.feed(html.decode("utf-8"))
renders = {
    hashlib.sha256(path.read_bytes()).hexdigest(): path.name
    for path in (folder / "previews").glob("*.png")
}
decoded = []
for source in parser.images:
    assert source.startswith("data:image/png;base64,"), "Image is not embedded"
    payload = base64.b64decode(source.split(",", 1)[1], validate=True)
    digest = hashlib.sha256(payload).hexdigest()
    assert digest in renders, "Embedded image does not match a current render"
    with Image.open(io.BytesIO(payload)) as picture:
        dimensions = picture.size
        picture.verify()
    decoded.append({"file": renders[digest], "pixels": dimensions})
assert len(decoded) == 17 == len(renders)
assert len({item["file"] for item in decoded}) == len(renders)
assert not parser.external_assets
print(json.dumps({
    "embedded_images": len(decoded),
    "decoded_images": len(decoded),
    "external_assets": len(parser.external_assets),
    "all_match_current_renders": True,
    "html_bytes": len(html),
    "html_sha256": hashlib.sha256(html).hexdigest(),
    "screens": decoded,
}, indent=2))
