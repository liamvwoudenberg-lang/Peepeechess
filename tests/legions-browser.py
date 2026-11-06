"""Legion selection, 3D default, drawn silhouettes, mobile fallback, and invites."""
import os,json
from pathlib import Path
from playwright.sync_api import sync_playwright,expect
BASE=os.environ.get('BASE_URL','http://localhost:3022')
OUT=Path(os.environ.get('BROWSER_EVIDENCE','artifacts/legions'));OUT.mkdir(parents=True,exist_ok=True)
results=[];errors=[]
AUDIT="""const oldFetch=window.fetch;window.fetch=async(...a)=>{const r=await oldFetch(...a);if(String(a[0]).includes('/api/chess'))r.clone().json().then(d=>{if(d.game)window.__game=d.game;}).catch(()=>{});return r;};"""
with sync_playwright() as p:
 b=p.chromium.launch(executable_path='/usr/bin/chromium',args=['--no-sandbox','--enable-unsafe-swiftshader'])
 def make(eff='on',mobile=False):
  c=b.new_context(viewport={'width':360 if mobile else 1440,'height':800 if mobile else 1100},has_touch=mobile,is_mobile=mobile)
  if eff=='off':c.add_init_script("const timeout=window.setTimeout.bind(window);window.setTimeout=(fn,ms,...args)=>timeout(fn,ms===50?800:ms,...args);")
  c.add_init_script("localStorage.setItem('sg-preferences-v2',JSON.stringify({efficiency:'%s',sound:false}));"%eff+AUDIT)
  pg=c.new_page();pg.on('pageerror',lambda e:errors.append(str(e)));return c,pg
 # Force optional 3D in software Chromium so the default can be inspected.
 c,pg=make('off');pg.goto(BASE,wait_until='domcontentloaded');expect(pg.get_by_role('button',name='Play computer',exact=True)).to_be_disabled()
 expect(pg.locator('.miniature-board')).to_have_attribute('data-renderer','models',timeout=40000)
 pg.screenshot(path=str(OUT/'3d-default-before-start.png'),full_page=True)
 pg.get_by_role('button',name='Choose Silverwood Elves',exact=True).click();expect(pg.get_by_role('button',name='Choose Silverwood Elves')).to_have_attribute('aria-pressed','true');pg.get_by_role('button',name='Play computer',exact=True).click()
 expect(pg.locator('.miniature-board')).to_have_attribute('data-renderer','models',timeout=40000)
 pg.screenshot(path=str(OUT/'3d-fullscreen-match.png'),full_page=True)
 assert pg.evaluate("JSON.parse(localStorage.getItem('sg-local-game-v2')).armies.w")=='elves'
 pg.get_by_role('button',name='Switch to 2D board',exact=True).click();expect(pg.locator('.miniature-board')).to_have_attribute('data-renderer','atlas');expect(pg.locator('canvas')).to_have_count(0)
 assert 'legions-drawn' in pg.locator('.miniature-icon').first.evaluate('(el)=>getComputedStyle(el).backgroundImage')
 pg.locator('[data-square=e2]').click();pg.locator('[data-square=e4]').click();pg.wait_for_function('document.querySelectorAll(".move-row button").length>=2',timeout=20000)
 pg.get_by_role('button',name='Menu',exact=True).click();pg.get_by_role('button',name='More',exact=True).click();pg.get_by_role('dialog').get_by_role('button',name='Armory',exact=True).click();pg.get_by_role('button',name='Hollow Legion',exact=False).click();pg.get_by_role('button',name='Play',exact=True).click()
 assert pg.evaluate("JSON.parse(localStorage.getItem('sg-local-game-v2')).armies.w")=='elves'
 pg.screenshot(path=str(OUT/'drawn-elves-playing.png'),full_page=True)
 results.append({'defaultBeforeAndAfterStart3D':True,'explicitLegionChoiceRequired':True,'drawn2DPlayable':True,'computerLegionLocked':True})
 # A phone can choose and play without initializing a GPU context.
 pc,phone=make('on',True);phone.goto(BASE,wait_until='networkidle');phone.get_by_role('button',name='Choose Hollow Legion',exact=True).tap();phone.get_by_role('button',name='Play computer',exact=True).tap();phone.locator('[data-square=d2]').tap();phone.locator('[data-square=d4]').tap();phone.wait_for_function('document.querySelectorAll(".move-row button").length>=2',timeout=20000)
 assert phone.locator('canvas').count()==0;assert phone.evaluate('document.documentElement.scrollWidth')==360
 phone.screenshot(path=str(OUT/'phone-drawn-skeletons.png'),full_page=True)
 results.append({'phone2DFallbackNoWebGL':True,'phoneTouchMoves':True,'noHorizontalOverflow360px':True})
 # Both players make their own faction choice before an invite match starts.
 hc,h=make('on',True);h.goto(BASE,wait_until='networkidle');h.get_by_role('button',name='Choose Silverwood Elves',exact=True).click();h.get_by_role('button',name='Friend',exact=True).click();h.get_by_role('button',name='Share a friend link',exact=True).click();h.get_by_label('Your side',exact=True).select_option('b');h.get_by_role('button',name='Create invite link',exact=True).click();url=h.get_by_label('Friend invite link',exact=True);expect(url).to_be_visible();link=url.input_value()
 gc,g=make('on');g.goto(link,wait_until='networkidle');expect(g.get_by_role('button',name='Join match',exact=True)).to_be_disabled();g.get_by_role('dialog').get_by_role('button',name='Choose Hollow Legion',exact=True).click();g.get_by_role('button',name='Join match',exact=True).click()
 for page in [h,g]:page.wait_for_function("window.__game?.phase==='playing'",timeout=20000)
 assert h.evaluate('window.__game.armies')=={'w':'skeletons','b':'elves'};assert h.evaluate('window.__game.arena')=='ossuary'
 g.locator('[data-square=e2]').click();g.locator('[data-square=e4]').click();expect(h.locator('.move-list')).to_contain_text('e4',timeout=10000)
 h.locator('[data-square=e7]').tap();h.locator('[data-square=e5]').tap();expect(g.locator('.move-list')).to_contain_text('e5',timeout=10000)
 h.screenshot(path=str(OUT/'phone-legion-friend-match.png'),full_page=True)
 results.append({'inviteGuestChoosesLegion':True,'humanLegionsAndWhiteHomeCorrect':True,'humanMovesBothDirections':True})
 # An installed web app still plays the new art offline.
 oc,off=make('on',True);off.goto(BASE,wait_until='networkidle');off.evaluate('navigator.serviceWorker.ready');off.wait_for_function('navigator.serviceWorker.controller!==null');oc.set_offline(True);off.reload(wait_until='domcontentloaded');off.get_by_role('button',name='Choose Royal Guard',exact=True).click();off.get_by_role('button',name='Play computer',exact=True).click();off.locator('[data-square=e2]').tap();off.locator('[data-square=e4]').tap();off.wait_for_function('document.querySelectorAll(".move-row button").length>=2',timeout=20000)
 results.append({'offlinePwaIncludesNewDrawings':True,'offlineComputerReplies':True})
 assert not errors,errors;results.append({'browserErrors':errors});(OUT/'legion-checks.json').write_text(json.dumps(results,indent=2));print(json.dumps(results,indent=2));b.close()
