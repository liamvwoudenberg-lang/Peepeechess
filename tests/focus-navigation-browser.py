"""The match fills the viewport, while every tool stays reachable in submenus."""
import os,json,re
from pathlib import Path
from playwright.sync_api import sync_playwright,expect
BASE=os.environ.get('BASE_URL','http://localhost:3022');OUT=Path('artifacts/legions');OUT.mkdir(exist_ok=True,parents=True)
results=[];errors=[]
with sync_playwright() as p:
 b=p.chromium.launch(executable_path='/usr/bin/chromium',args=['--no-sandbox'])
 for width,height in [(320,640),(360,800),(390,844),(844,390),(1440,1000)]:
  print('Checking viewport',width,height,flush=True)
  c=b.new_context(viewport={'width':width,'height':height},has_touch=width<900,is_mobile=width<900)
  c.add_init_script("localStorage.setItem('sg-preferences-v2',JSON.stringify({efficiency:'on',sound:false}));")
  pg=c.new_page();pg.on('pageerror',lambda e:errors.append(str(e)));pg.goto(BASE,wait_until='networkidle')
  expect(pg.locator('.match-settings')).not_to_have_attribute('open','')
  expect(pg.locator('.match-settings summary')).to_contain_text('Simulated 1200 Elo');expect(pg.locator('.match-settings summary')).to_contain_text('Feedback on')
  pg.locator('.match-settings summary').click();pg.get_by_label('Computer strength',exact=True).focus();pg.get_by_label('Computer strength',exact=True).press('Home');pg.get_by_label('Computer strength',exact=True).press('ArrowRight');pg.get_by_label('Computer strength',exact=True).press('ArrowRight');pg.get_by_label('Move feedback',exact=False).uncheck();pg.locator('.match-settings summary').click();expect(pg.locator('.match-settings summary')).to_contain_text('Simulated 800 Elo');expect(pg.locator('.match-settings summary')).to_contain_text('Feedback off')
  pg.get_by_role('button',name='Choose Hollow Legion',exact=True).click();pg.get_by_role('button',name='Play computer',exact=True).click();expect(pg.locator('.app')).to_have_class(re.compile('focus-game'))
  rect=pg.locator('.chessboard').bounding_box();assert rect['x']>=0 and rect['y']>=0;assert rect['x']+rect['width']<=width+1 and rect['y']+rect['height']<=height+1,(width,height,rect)
  assert abs(rect['width']-rect['height'])<1
  assert pg.evaluate('document.documentElement.scrollWidth')==width
  assert pg.locator('nav[aria-label="Mobile navigation"]').is_hidden();assert pg.locator('.game-panel-column').is_hidden()
  pg.get_by_role('button',name='Moves and game options',exact=True).click();expect(pg.get_by_role('button',name='Resign',exact=True)).to_be_visible();expect(pg.get_by_role('button',name='Pause',exact=True)).to_be_visible();pg.get_by_role('button',name='Close match details',exact=True).click();expect(pg.locator('.game-panel-column')).to_be_hidden()
  if width==360:pg.screenshot(path=str(OUT/'phone-fullscreen-match.png'),full_page=True)
  if width==1440:
   pg.screenshot(path=str(OUT/'desktop-focus-match.png'),full_page=True)
   pg.get_by_role('button',name='Enter fullscreen',exact=True).click();pg.wait_for_function('document.fullscreenElement!==null');pg.get_by_role('button',name='Exit fullscreen',exact=True).click();pg.wait_for_function('document.fullscreenElement===null')
  pg.get_by_role('button',name='Menu',exact=True).click();expect(pg.locator('.game-focus-bar')).to_have_count(0);pg.get_by_role('button',name='More',exact=True).click()
  for name in ['Puzzles','Armory']:expect(pg.get_by_role('dialog').get_by_role('button',name=name,exact=True)).to_be_visible()
  expect(pg.get_by_role('dialog').get_by_role('button',name='Appearance and preferences',exact=False)).to_be_visible();expect(pg.get_by_role('dialog').get_by_role('button',name='Import PGN / FEN',exact=False)).to_be_visible()
  if width==360:pg.screenshot(path=str(OUT/'phone-more-menu.png'),full_page=True)
  pg.get_by_role('dialog').get_by_role('button',name='Armory',exact=True).click();expect(pg.get_by_role('heading',name='Choose your army.',exact=True)).to_be_visible()
  results.append({'viewport':[width,height],'squareBoardWithinScreen':True,'optionsDrawerAccessible':True,'matchSettingsRetained':True,'secondaryPagesInMoreMenu':True});c.close()
 assert not errors,errors;results.append({'errors':errors});(OUT/'focus-navigation-checks.json').write_text(json.dumps(results,indent=2));print(json.dumps(results,indent=2));b.close()
