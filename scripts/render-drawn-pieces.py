"""Rasterize our editable SVG illustrations for inexpensive phone rendering."""
import os,base64
from pathlib import Path
from playwright.sync_api import sync_playwright
with sync_playwright() as p:
 b=p.chromium.launch(executable_path='/usr/bin/chromium',args=['--no-sandbox'])
 pg=b.new_page();pg.goto(os.environ.get('BASE_URL','http://localhost:3021')+'/pieces/legions-drawn.svg')
 result=pg.evaluate('''async()=>{const img=new Image();img.src='/pieces/legions-drawn.svg';await img.decode();const c=document.createElementNS('http://www.w3.org/1999/xhtml','canvas');c.width=c.height=1152;c.getContext('2d').drawImage(img,0,0);return {png:c.toDataURL('image/png'),webp:c.toDataURL('image/webp',.95)};}''')
 for ext,data in result.items():
  f=Path('public/pieces/legions-drawn.'+ext);f.write_bytes(base64.b64decode(data.split(',',1)[1]));print(f,f.stat().st_size)
 b.close()
