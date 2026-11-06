import os
BASE_URL=os.environ.get("BASE_URL","http://localhost:3000")
from playwright.sync_api import sync_playwright, expect
from pathlib import Path
import json

OUT=Path(os.environ.get('BROWSER_EVIDENCE','artifacts/browser'))
OUT.mkdir(parents=True,exist_ok=True)
observations=[]
def show_options(pg):
 if pg.locator('.game-focus-bar').count() and not pg.locator('.game-panel-column').is_visible():pg.get_by_role('button',name='Moves and game options',exact=True).click()
with sync_playwright() as p:
 b=p.chromium.launch(executable_path='/usr/bin/chromium',headless=True,args=['--no-sandbox','--enable-unsafe-swiftshader'])
 contexts=[];pages=[];errors=[]
 for name in ['Elowen','Aldric','Rowan']:
  ctx=b.new_context(viewport={'width':1440,'height':960})
  ctx.add_init_script("""localStorage.setItem('sg-preferences-v2',JSON.stringify({...JSON.parse(localStorage.getItem('sg-preferences-v2')||'{}'),efficiency:'on'}));window.__audit={workers:[],game:null};const originalFetch=window.fetch;window.fetch=async(...args)=>{const response=await originalFetch(...args);if(String(args[0]).includes('/api/chess'))response.clone().json().then(data=>{if(data.game)window.__audit.game=data.game;}).catch(()=>{});return response;}; const OldWorker=window.Worker; window.Worker=class extends OldWorker {constructor(...a){super(...a);window.__audit.workers.push(String(a[0]));}}; const OldWS=window.WebSocket; window.WebSocket=class extends OldWS {constructor(...a){super(...a);if(this.url.endsWith('/ws'))this.addEventListener('message',e=>{const d=JSON.parse(e.data);if(d.type==='game:state')window.__audit.game=d.game;});}};""")
  page=ctx.new_page();page.on('pageerror',lambda e:errors.append(str(e)))
  page.goto(BASE_URL,wait_until='networkidle');expect(page.locator('.connection-status')).to_have_text('Connected')
  page.get_by_role('button',name='Choose Royal Guard',exact=True).click()
  page.locator('.profile-button').click();page.get_by_label('Player name').fill(name);page.get_by_role('button',name='Save profile',exact=True).click()
  page.locator('nav[aria-label="Main navigation"]').get_by_role('button',name='Friends',exact=True).click()
  pages.append(page);contexts.append(ctx)
 a,bb,c=pages
 codes=[page.get_by_test_id('friend-code').inner_text() for page in pages]
 def add_friend(sender,recipient,code,name):
  sender.get_by_role('button',name='Add your first friend',exact=True).click()
  sender.get_by_label('Enter a friend code').fill(code)
  sender.get_by_role('button',name='Add',exact=True).click()
  recipient.get_by_role('button',name=f'Accept friend request from {name}',exact=True).click()
 add_friend(a,bb,codes[1],'Elowen')
 add_friend(c,a,codes[0],'Rowan')
 a.get_by_role('button',name='Chat with Aldric',exact=True).click()
 a.get_by_label('Message Aldric').fill('A friendly match? <script>Never HTML</script>')
 a.get_by_role('button',name='Send message',exact=True).click()
 bb.get_by_role('button',name='Chat with Elowen',exact=True).click()
 expect(bb.locator('.chat-bubble')).to_contain_text('<script>Never HTML</script>')
 a.screenshot(path=str(OUT/'friends-and-chat.png'),full_page=True)
 a.locator('.friend-actions').get_by_role('button',name='Challenge Aldric',exact=True).click()
 a.get_by_role('button',name='Send challenge',exact=True).click()
 a.get_by_role('dialog').get_by_role('button',name='Send challenge',exact=True).click()
 bb.get_by_role('button',name='Accept',exact=True).click()
 bb.get_by_role('button',name='Accept challenge',exact=True).click()
 expect(a.locator('.game-focus-bar')).to_be_visible()
 expect(bb.locator('.game-focus-bar')).to_be_visible()
 c.get_by_role('button',name='Watch Elowen',exact=True).click()
 expect(c.locator('.game-focus-bar')).to_be_visible()
 a.wait_for_function("window.__audit.game?.phase==='playing'",timeout=20000)
 bb.wait_for_function("window.__audit.game?.phase==='playing'",timeout=20000)
 game=a.evaluate('window.__audit.game')
 white=a if game['yourColor']=='w' else bb
 black=bb if white==a else a
 white.locator('[data-square="e2"]').click();white.locator('[data-square="e4"]').click()
 expect(c.locator('.move-list')).to_contain_text('e4')
 expect(a.locator('.coach-panel')).to_have_count(0)
 expect(bb.locator('.coach-panel')).to_have_count(0)
 assert a.evaluate('window.__audit.workers.length')==0
 assert bb.evaluate('window.__audit.workers.length')==0
 white.get_by_role('button',name='Send an emote',exact=True).click();white.get_by_role('button',name='Well played!',exact=True).click()
 expect(black.locator('.emote-bubble')).to_contain_text('Well played!')
 expect(c.locator('.emote-bubble')).to_contain_text('Well played!')
 a.screenshot(path=str(OUT/'friendly-game.png'),full_page=True)
 c.screenshot(path=str(OUT/'spectating.png'),full_page=True)
 a.reload(wait_until='networkidle');expect(a.locator('.move-list')).to_contain_text('e4')
 observations.append({'friendsChatChallengeSpectatingEmotesReconnect':'passed','onlineWorkerCount':0})
 show_options(a)
 a.get_by_role('button',name='Resign',exact=True).click();a.get_by_role('button',name='Resign game',exact=True).click()
 expect(a.locator('.result-panel')).to_be_visible();expect(bb.locator('.result-panel')).to_be_visible();expect(c.locator('.result-panel')).to_be_visible()
 a.get_by_role('button',name='New game',exact=True).click()
 a.get_by_role('button',name='Choose Royal Guard',exact=True).click()
 a.locator('.match-settings summary').click()
 a.get_by_label('Computer strength').focus()
 a.get_by_label('Computer strength').press('End')
 a.get_by_label('Computer strength').press('ArrowLeft')
 a.get_by_label('Computer strength').press('ArrowLeft')
 a.get_by_label('Move feedback',exact=False).uncheck()
 a.get_by_role('button',name='Play computer',exact=True).click()
 show_options(a)
 expect(a.locator('.unassisted-note')).to_be_visible();expect(a.locator('.coach-panel')).to_have_count(0)
 a.locator('[data-square="d2"]').click();a.locator('[data-square="d4"]').click()
 expect(a.locator('.move-list')).to_contain_text('d4')
 a.wait_for_function('document.querySelectorAll(".move-row button").length>=2')
 observations.append({'computerFeedbackOff':'passed','simulatedElo1600':a.locator('.player-details').all_text_contents()})
 show_options(a)
 a.get_by_role('button',name='Set up a new game',exact=True).click()
 a.get_by_role('button',name='More',exact=True).click();a.get_by_role('dialog').get_by_role('button',name='Armory',exact=True).click()
 a.get_by_role('button',name='Silverwood Elves',exact=False).click();expect(a.locator('.set-elves')).not_to_have_count(0)
 a.screenshot(path=str(OUT/'armory-elves.png'),full_page=True)
 a.get_by_role('button',name='Hollow Legion',exact=False).click();a.reload(wait_until='networkidle')
 assert a.evaluate("JSON.parse(localStorage.getItem('sg-preferences-v2')).pieceSet")=='skeletons'
 a.get_by_role('button',name='More',exact=True).click();a.get_by_role('dialog').get_by_role('button',name='Puzzles',exact=True).click()
 a.get_by_role('button',name='The last rank',exact=False).click()
 a.locator('[data-square="e1"]').click();a.locator('[data-square="e8"]').click()
 expect(a.locator('.exercise-message')).to_contain_text('checkmate')
 observations.append({'verifiedPuzzleOnBoard':'passed','pieceSetPersistence':'passed'})
 for width,height in [(320,640),(360,740),(390,844),(768,1024),(1440,900)]:
  ctx=b.new_context(viewport={'width':width,'height':height},is_mobile=width<800,has_touch=width<800)
  ctx.add_init_script("Object.defineProperty(navigator,'hardwareConcurrency',{get:()=>4});Object.defineProperty(navigator,'deviceMemory',{get:()=>2});")
  pg=ctx.new_page();pg.on('pageerror',lambda e:errors.append(str(e)))
  pg.goto(BASE_URL,wait_until='networkidle')
  pg.get_by_role('button',name='Choose Royal Guard',exact=True).click();pg.get_by_role('button',name='Play computer',exact=True).click();pg.wait_for_timeout(100)
  rect=pg.locator('.chessboard').bounding_box()
  assert pg.evaluate('document.documentElement.scrollWidth')==width
  assert abs(rect['width']-rect['height'])<1
  assert rect['x']>=0 and rect['x']+rect['width']<=width
  if width<650: assert rect['y']+rect['height']<height-65, str(rect)
  assert pg.locator('canvas').count()==0
  resources=pg.evaluate('performance.getEntriesByType("resource").map(r=>r.name)')
  assert not any('Scene-' in r or '.jpg' in r or 'three' in r for r in resources)
  observations.append({'viewport':[width,height],'board':rect,'horizontalOverflow':False,'webglLoaded':False})
  if width in [390,1440]:pg.screenshot(path=str(OUT/f'playing-{width}.png'),full_page=True)
  if width==390:
   pg.locator('[data-square="e2"]').click();pg.locator('[data-square="e4"]').click();pg.wait_for_function('document.querySelectorAll(".move-row button").length>=2')
   pg.get_by_role('button',name='Menu',exact=True).click();pg.get_by_role('button',name='Appearance and preferences',exact=True).click()
   pg.get_by_label('Performance mode').select_option('on')
   pg.get_by_role('button',name='Close dialog',exact=True).click()
   assert 'efficient' in pg.locator('.app').get_attribute('class')
   pg.screenshot(path=str(OUT/'mobile-efficient.png'),full_page=True)
  ctx.close()
 assert not errors,errors
 observations.append({'browserErrors':errors})
 (OUT/'browser-checks.json').write_text(json.dumps(observations,indent=2))
 print(json.dumps(observations,indent=2))
 b.close()
