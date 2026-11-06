"""Production UI: actual player inputs, actual 3D rendering and authoritative private rooms."""
import os,json,time
from pathlib import Path
from playwright.sync_api import sync_playwright,expect
BASE=os.environ.get('BASE_URL','http://localhost:3041');OUT=Path('artifacts/battle-chess');OUT.mkdir(parents=True,exist_ok=True)
results=[];errors=[]
with sync_playwright() as p:
 b=p.chromium.launch(executable_path='/usr/bin/chromium',args=['--no-sandbox','--enable-unsafe-swiftshader'])
 def page(width=960,height=640,touch=False):
  c=b.new_context(viewport={'width':width,'height':height},is_mobile=touch,has_touch=touch)
  c.add_init_script("""localStorage.setItem('sg-preferences-v2',JSON.stringify({efficiency:'on',sound:false}));const NativeWS=window.WebSocket;window.WebSocket=class extends NativeWS{constructor(...args){super(...args);this.addEventListener('message',e=>{try{const d=JSON.parse(e.data);if(d.type==='state'&&d.snapshot?.version===1){window.__battleSnapshot=d.snapshot;if(d.snapshot.combat?.winner)window.__lastBattleResult=d.snapshot.combat;}}catch{}});}};""")
  pg=c.new_page();pg.on('pageerror',lambda e:errors.append(str(e)));pg.goto(BASE,wait_until='networkidle');return c,pg
 def open_mode(pg):pg.get_by_role('button',name='Battle Chess — 3D Combat',exact=False).first.click();expect(pg.get_by_role('button',name='Start Battle Chess',exact=True)).to_be_visible()
 def move(pg,a,z):pg.locator(f'[data-square={a}]').click();pg.locator(f'[data-square={z}]').click()
 def ready(pg):expect(pg.locator('.combat-canvas canvas')).to_have_count(1,timeout=20000);expect(pg.locator('.combat-announcement:not(.combat-victory)')).to_have_count(0,timeout=20000)
 def finish(pg,color):
  for n in range(14):
   if pg.locator('.combat-stage').count()==0:break
   button=pg.get_by_role('button',name=f'{color} heavy attack',exact=True)
   if not button.count():break
   print('Attack',color,n,pg.locator('.fighter-meter').evaluate_all('(es)=>es.map(e=>({color:e.dataset.fighter,hp:e.dataset.hp,state:e.dataset.state}))'),flush=True);button.click();pg.wait_for_timeout(1000)
   if pg.locator('.combat-victory').count():
    break
  expect(pg.locator('.combat-stage')).to_have_count(0,timeout=15000)
 # Full shared-device loop, with two real independently controlled third-person views.
 c,pg=page();open_mode(pg);pg.screenshot(path=str(OUT/'mode-setup.png'));pg.get_by_role('button',name='Start Battle Chess',exact=True).click()
 move(pg,'e2','e4');assert pg.locator('.combat-stage').count()==0;move(pg,'d7','d5');pg.locator('[data-square=e4]').click();expect(pg.locator('[data-square=d5]')).to_have_class(__import__('re').compile('battle-capture-ready'));pg.locator('[data-square=d5]').click();ready(pg)
 assert pg.locator('.combat-view').count()==2;assert pg.locator('.combat-canvas').get_attribute('data-fighters')=='2'
 pg.keyboard.down('w');pg.keyboard.down('ArrowUp');pg.wait_for_timeout(1000);pg.keyboard.up('w');pg.keyboard.up('ArrowUp')
 pg.keyboard.down('u');pg.get_by_role('button',name='White heavy attack',exact=True).click();pg.wait_for_timeout(650);pg.keyboard.up('u')
 pg.screenshot(path=str(OUT/'local-third-person-fight.png'));finish(pg,'White')
 expect(pg.locator('[data-square=d5] [data-piece=wp]')).to_have_count(1);expect(pg.locator('[data-square=e4] .miniature-icon')).to_have_count(0);assert pg.locator('canvas').count()==0
 move(pg,'c7','c6');expect(pg.locator('[data-square=c6] [data-piece=bp]')).to_have_count(1)
 pg.get_by_role('button',name='Match options',exact=True).click();pg.get_by_role('button',name='White resigns',exact=True).click();expect(pg.get_by_role('region',name='Battle Chess results')).to_contain_text('Black wins')
 pg.get_by_role('button',name='Return to Classic Chess',exact=True).click();expect(pg.locator('.chess-mode-choice')).to_contain_text('Classic Chess');assert pg.evaluate("localStorage.getItem('sg-local-game-v2')") in [None,'null']
 pg.get_by_role('button',name='Choose Royal Guard',exact=True).click();pg.get_by_role('button',name='Play computer',exact=True).click();classic_id=pg.evaluate("JSON.parse(localStorage.getItem('sg-local-game-v2')).id");pg.goto(BASE+'/?battle=abcdefabcdef',wait_until='networkidle');expect(pg.locator('.game-focus-bar')).to_be_visible();assert pg.locator('.battle-page').count()==0;assert pg.evaluate("JSON.parse(localStorage.getItem('sg-local-game-v2')).id")==classic_id
 results.append({'localCompleteChessCombatLoop':True,'independentThirdPersonViews':2,'actualKeyboardMovementAndAttacks':True,'attackerWonAndMoved':True,'continuedChessAfterCombat':True,'arenaUnmounted':True,'dedicatedResults':True,'classicStateUnaffected':True,'activeClassicSurvivesBattleLink':True});print('Local loop passed',flush=True);c.close()
 # Private rooms: separate real clients and server-run combat, with a defender victory.
 hc,h=page();open_mode(h);h.get_by_role('button',name='Create Battle room',exact=True).click();field=h.get_by_label('Battle room invite link',exact=True);expect(field).to_be_visible();url=field.input_value()
 gc,g=page();g.goto(url,wait_until='networkidle');g.get_by_role('button',name='Join Battle room',exact=True).click();expect(h.locator('.battle-turn')).to_contain_text('White to move');expect(g.locator('.battle-turn')).to_contain_text('White to move')
 move(h,'e2','e4');expect(g.locator('.battle-turn')).to_contain_text('Black to move');move(g,'d7','d5');expect(h.locator('.battle-turn')).to_contain_text('White to move');move(h,'e4','d5');ready(g)
 expect(h.locator('.combat-stage')).to_have_count(1);assert h.locator('.combat-view').count()==g.locator('.combat-view').count()==1
 assert h.locator('.combat-view').get_attribute('data-player')=='w';assert g.locator('.combat-view').get_attribute('data-player')=='b'
 g.keyboard.down('w');g.wait_for_function("window.__battleSnapshot?.combat&&Math.hypot(window.__battleSnapshot.combat.fighters.w.x-window.__battleSnapshot.combat.fighters.b.x,window.__battleSnapshot.combat.fighters.w.z-window.__battleSnapshot.combat.fighters.b.z)<1.3",timeout=12000);g.keyboard.up('w');g.screenshot(path=str(OUT/'server-guest-third-person.png'));finish(g,'Black')
 assert g.evaluate('window.__lastBattleResult.reason')=='Knockout'
 for client in [h,g]:
  expect(client.locator('[data-square=d5] [data-piece=bp]')).to_have_count(1,timeout=15000);expect(client.locator('[data-square=e4] .miniature-icon')).to_have_count(0);expect(client.locator('.battle-turn')).to_contain_text('Black to move')
 move(g,'d5','d4');expect(h.locator('[data-square=d4] [data-piece=bp]')).to_have_count(1,timeout=10000)
 g.get_by_role('button',name='Match options',exact=True).click();g.get_by_role('button',name='Resign Battle Chess',exact=True).click();expect(h.get_by_role('region',name='Battle Chess results')).to_contain_text('White wins',timeout=10000)
 results.append({'privateRoomTwoBrowsers':True,'oneOwnedFighterPerClient':True,'serverDefenderWon':True,'positionsAgreeAfterReturn':True,'continuedAuthoritativeMoves':True});print('Private room loop passed',flush=True);hc.close();gc.close()
 assert not errors,errors;results.append({'browserErrors':errors});(OUT/'browser-checks.json').write_text(json.dumps(results,indent=2));print(json.dumps(results,indent=2));b.close()
