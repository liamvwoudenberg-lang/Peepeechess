import os
BASE_URL=os.environ.get("BASE_URL","http://localhost:3000")
from playwright.sync_api import sync_playwright,expect
import json
from pathlib import Path
OUT=Path(os.environ.get('BROWSER_EVIDENCE','artifacts/browser'));OUT.mkdir(parents=True,exist_ok=True)
results=[]
with sync_playwright() as p:
 b=p.chromium.launch(executable_path='/usr/bin/chromium',headless=True,args=['--no-sandbox','--enable-unsafe-swiftshader'])
 pg=b.new_page(viewport={'width':1366,'height':900})
 errors=[];pg.on('pageerror',lambda e:errors.append(str(e)))
 pg.goto(BASE_URL,wait_until='domcontentloaded');pg.get_by_role('button',name='Play computer',exact=True).click()
 s=pg.locator('[data-square="e2"]').bounding_box();d=pg.locator('[data-square="e4"]').bounding_box()
 pg.mouse.move(s['x']+s['width']/2,s['y']+s['height']/2);pg.mouse.down();pg.mouse.move(d['x']+d['width']/2,d['y']+d['height']/2,steps=8);pg.mouse.up()
 expect(pg.locator('.move-list')).to_contain_text('e4')
 pg.wait_for_function('document.querySelectorAll(".move-row button").length>=2')
 results.append({'dragAndDrop':'passed'});print('Drag passed',flush=True)
 pg.get_by_role('button',name='Appearance and preferences',exact=True).click();pg.get_by_role('button',name='Edit your profile',exact=True).click()
 name=pg.get_by_label('Player name');name.fill('');name.press_sequentially('A clear name',delay=35);expect(name).to_have_value('A clear name');pg.get_by_role('button',name='Save profile',exact=True).click()
 results.append({'keyboardTextEntryAndDialogFocus':'passed'});print('Dialog passed',flush=True)
 pg.get_by_role('button',name='Set up a new game',exact=True).click();pg.get_by_role('button',name='Import PGN / FEN',exact=True).click()
 pg.get_by_label('PGN game or FEN position').fill('7k/P7/8/8/8/8/8/7K w - - 0 1');pg.get_by_role('button',name='Open analysis',exact=True).click()
 pg.get_by_role('button',name='Analyze position',exact=True).click();pg.locator('[data-square="a7"]').click();pg.locator('[data-square="a8"]').click()
 expect(pg.get_by_role('dialog',name='Choose promotion')).to_be_visible()
 for piece in ['queen','rook','bishop','knight']:expect(pg.get_by_role('button',name=f'Promote to {piece}',exact=True)).to_be_visible()
 pg.get_by_role('button',name='Promote to knight',exact=True).click();expect(pg.locator('[data-square="a8"] [data-piece="wn"]')).to_have_count(1)
 results.append({'allPromotionChoicesAndUnderpromotion':'passed'});print('Promotion passed',flush=True)
 pg.get_by_role('button',name='Close analysis',exact=True).click();pg.locator('nav[aria-label="Main navigation"]').get_by_role('button',name='Puzzles',exact=True).click()
 pg.get_by_role('button',name='One knight, two targets',exact=False).click();pg.locator('[data-square="e5"]').click();pg.locator('[data-square="f7"]').click()
 expect(pg.locator('[data-square="g8"] [data-piece="bk"]')).to_have_count(1)
 pg.locator('[data-square="f7"]').click();pg.locator('[data-square="d8"]').click();expect(pg.locator('.exercise-message')).to_contain_text('wins the rook')
 results.append({'multiMovePuzzleAndDefendingReply':'passed'})
 assert not errors,errors
 results.append({'browserErrors':errors})
 (OUT/'interaction-checks.json').write_text(json.dumps(results,indent=2))
 print(json.dumps(results,indent=2));b.close()
