"""Create a reviewable packet without approving or replacing any baseline."""
from pathlib import Path
import json
import html
import shutil

root = Path.cwd()
report = json.loads((root / 'docs/verification/remaining-wave3/desktop-result-20261006.json').read_text())
dest = root / 'build/remaining-wave3/visual-review-20261006'
dest.mkdir(parents=True, exist_ok=False)
sections = []
for row in report['images']:
    name = row['name']
    for label, source in [('current', row['actual']), ('approved', row['master'])]:
        shutil.copyfile(source, dest / (name + '-' + label + '.png'))
    sections.append('<section><h2>' + html.escape(name) + '</h2><p>' +
        str(round(row.get('pixel_percent', 0), 4)) + '% differing pixels; cause and acceptance require review.</p>' +
        '<div class="pair">' + ''.join('<figure><figcaption>' + label + '</figcaption><img loading="lazy" src="' +
        name + '-' + label + '.png"></figure>' for label in ['approved', 'current']) + '</div></section>')
page = '<!doctype html><meta charset="utf-8"><title>Wave 3 visual comparisons — 2026-10-06</title><style>body{font:16px system-ui;margin:24px;background:#f4f6f8;color:#152b3c}h1{font-size:26px}.pair{display:flex;gap:16px}figure{margin:0;width:50%}img{width:100%;height:auto;border:1px solid #bbc5ce}section{background:white;padding:20px;margin:24px 0}figcaption{font-weight:700;padding:10px}p{max-width:1000px}</style><h1>83 exact image comparisons</h1><p>Completed isolated desktop test: 1,775 passed and 83 pixel golden failures. Approved images match the execution masters. This packet preserves both images; it does not approve current images, change comparisons, or establish authenticated native acceptance. Click an image through its browser context to inspect full resolution.</p>' + ''.join(sections)
(dest / 'index.html').write_text(page, encoding='utf-8')
print(json.dumps({'packet': str(dest / 'index.html'), 'comparisons': len(sections), 'approved_images_changed': False}))
