"""Rasterize the editable full figures and their independently armed battle bodies."""
import base64
from pathlib import Path
from playwright.sync_api import sync_playwright
with sync_playwright() as p:
 b=p.chromium.launch(executable_path='/usr/bin/chromium',args=['--no-sandbox'])
 pg=b.new_page();pg.set_content('<html><body></body></html>')
 for name in ['legions-drawn','legions-battle-body']:
  source=base64.b64encode(Path('public/pieces/'+name+'.svg').read_bytes()).decode()
  result=pg.evaluate("""async source=>{const img=new Image();img.src='data:image/svg+xml;base64,'+source;await img.decode();const c=document.createElement('canvas');c.width=c.height=1152;c.getContext('2d').drawImage(img,0,0);return {png:c.toDataURL('image/png'),webp:c.toDataURL('image/webp',.95)};}""",source)
  for ext,data in result.items():
   f=Path('public/pieces/'+name+'.'+ext);f.write_bytes(base64.b64decode(data.split(',',1)[1]));print(f,f.stat().st_size)
 b.close()
