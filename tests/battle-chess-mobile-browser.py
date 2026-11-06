"""Offline real touch/multitouch combat, saved-duel resume and portrait controls."""
import json,os
from pathlib import Path
from playwright.sync_api import sync_playwright,expect
BASE=os.environ.get('BASE_URL','http://localhost:3042');OUT=Path('artifacts/battle-chess');OUT.mkdir(parents=True,exist_ok=True)
results=[];errors=[]
with sync_playwright() as p:
 b=p.chromium.launch(executable_path='/usr/bin/chromium',args=['--no-sandbox','--enable-unsafe-swiftshader'])
 c=b.new_context(viewport={'width':844,'height':390},has_touch=True,is_mobile=True)
 c.add_init_script("localStorage.setItem('sg-preferences-v2',JSON.stringify({efficiency:'on',sound:false}));window.__battleStamina={w:120,b:120};const save=Storage.prototype.setItem;Storage.prototype.setItem=function(k,v){if(k==='sg-battle-local-v1'){const s=JSON.parse(v);if(s.combat)for(const c of ['w','b'])window.__battleStamina[c]=Math.min(window.__battleStamina[c],s.combat.fighters[c].stamina);}return save.call(this,k,v);};window.structuredClone=undefined;Object.defineProperty(navigator,'getGamepads',{value:()=>{throw new DOMException('Gamepads blocked','SecurityError')}});")
 pg=c.new_page();pg.on('pageerror',lambda e:errors.append(str(e)));pg.goto(BASE,wait_until='networkidle');pg.evaluate('navigator.serviceWorker.ready');pg.wait_for_function('navigator.serviceWorker.controller!==null');c.set_offline(True);pg.reload(wait_until='domcontentloaded')
 pg.get_by_role('button',name='Battle Chess — 3D Combat',exact=False).first.tap();pg.get_by_role('button',name='Start Battle Chess',exact=True).tap()
 for a,z in [('e2','e4'),('d7','d5'),('e4','d5')]:pg.locator(f'[data-square={a}]').tap();pg.locator(f'[data-square={z}]').tap()
 expect(pg.locator('.combat-canvas canvas')).to_have_count(1);expect(pg.locator('.combat-announcement:not(.combat-victory)')).to_have_count(0,timeout=20000)
 cdp=c.new_cdp_session(pg);cdp.send('Emulation.setCPUThrottlingRate',{'rate':6})
 def point(selector,id,dy=0):
  r=pg.locator(selector).bounding_box();return {'x':r['x']+r['width']/2,'y':r['y']+r['height']/2+dy,'id':id,'radiusX':3,'radiusY':3,'force':1}
 pts=[point('[data-player=w] .combat-stick',1,-30),point('[data-player=b] .combat-stick',2,-30)]
 cdp.send('Input.dispatchTouchEvent',{'type':'touchStart','touchPoints':pts});pg.wait_for_timeout(900);cdp.send('Input.dispatchTouchEvent',{'type':'touchEnd','touchPoints':[]});pg.wait_for_timeout(550)
 state=pg.evaluate("JSON.parse(localStorage.getItem('sg-battle-local-v1'))")
 assert state['combat']['fighters']['w']['z']>-2.2 and state['combat']['fighters']['b']['z']<2.2,state['combat']['fighters']
 hp0=state['combat']['fighters']['w']['hp'];pts=[point('button[aria-label="White heavy attack"]',3),point('button[aria-label="Black dodge"]',4)]
 cdp.send('Input.dispatchTouchEvent',{'type':'touchStart','touchPoints':pts});cdp.send('Input.dispatchTouchEvent',{'type':'touchEnd','touchPoints':[]});pg.wait_for_timeout(700)
 pg.screenshot(path=str(OUT/'mobile-touch-combat.png'))
 state=pg.evaluate("JSON.parse(localStorage.getItem('sg-battle-local-v1'))")
 assert state['combat']['fighters']['w']['seen']['heavy']>=1;assert state['combat']['fighters']['b']['seen']['dodge']>=1
 spent=pg.evaluate('window.__battleStamina');assert spent['w']<120 and spent['b']<120,spent
 assert pg.evaluate('document.documentElement.scrollWidth')==844
 for selector in ['.combat-actions button','.combat-lock']:
  for item in pg.locator(selector).all():
   r=item.bounding_box();assert r and r['x']>=0 and r['y']>=0 and r['x']+r['width']<=845 and r['y']+r['height']<=391,(selector,r)
 pg.get_by_role('button',name='Open combat menu',exact=True).tap();pg.get_by_role('button',name='Save and exit to Classic Chess',exact=True).tap();assert pg.locator('canvas').count()==0
 saved=pg.evaluate("JSON.parse(localStorage.getItem('sg-battle-local-v1'))");assert saved['paused']
 pg.reload(wait_until='domcontentloaded');pg.get_by_role('button',name='Battle Chess — 3D Combat',exact=False).first.tap();pg.get_by_role('button',name='Resume saved Battle Chess',exact=True).tap();expect(pg.get_by_role('dialog',name='Battle Chess match')).to_be_visible();pg.get_by_role('button',name='Resume Battle Chess',exact=True).tap()
 pg.set_viewport_size({'width':390,'height':844});pg.wait_for_timeout(500)
 assert pg.locator('.combat-view').count()==2
 for view in pg.locator('.combat-view').all():
  r=view.bounding_box()
  for button in view.locator('.combat-actions button').all():
   a=button.bounding_box();assert a and a['height']>=44 and a['width']>=44 and a['x']>=r['x'] and a['x']+a['width']<=r['x']+r['width']+1 and a['y']+a['height']<=r['y']+r['height']+1,(r,a)
 pg.screenshot(path=str(OUT/'portrait-split-combat.png'))
 state=pg.evaluate("JSON.parse(localStorage.getItem('sg-battle-local-v1'))");assert state['combat']['id']==saved['combat']['id'];assert state['combat']['fighters']['w']['hp']==saved['combat']['fighters']['w']['hp']
 results.append({'offlineArenaLoaded':True,'olderWebViewCloneFallback':True,'cpuThrottle6x':True,'gamepadPolicyDoesNotBlockTouch':True,'twoSimultaneousTouchJoysticks':True,'simultaneousAttackAndDodge':True,'staminaCostsApplied':True,'landscapeControlsFit':True,'portraitControls44px':True,'savedDuelResumed':True,'arenaDisposedOnExit':True,'browserErrors':errors})
 assert not errors,errors;(OUT/'mobile-checks.json').write_text(json.dumps(results,indent=2));print(json.dumps(results,indent=2));b.close()
