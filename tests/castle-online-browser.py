"""Production matchmaking and shared miniature-camera checks. Needs Playwright.
Run a built Node server, then BASE_URL=http://localhost:3006 python tests/castle-online-browser.py.
"""
import os,json
from pathlib import Path
from playwright.sync_api import sync_playwright,expect
BASE=os.environ.get('BASE_URL','http://localhost:3006')
OUT=Path(os.environ.get('BROWSER_EVIDENCE','artifacts/castle-online'));OUT.mkdir(parents=True,exist_ok=True)
observations=[]
with sync_playwright() as p:
 b=p.chromium.launch(executable_path=os.environ.get('CHROMIUM','/usr/bin/chromium'),headless=True,args=['--no-sandbox','--enable-unsafe-swiftshader'])
 pages=[];errors=[]
 for faction in ['royal','elves']:
  ctx=b.new_context(viewport={'width':1440,'height':1000})
  ctx.add_init_script("""localStorage.setItem('sg-preferences-v2',JSON.stringify({pieceSet:'%s',efficiency:'on',sound:false}));window.__rtc=[];const RTC=window.RTCPeerConnection;window.RTCPeerConnection=class extends RTC{constructor(...a){super(...a);window.__rtc.push(this);}};const original=window.fetch;window.fetch=async(...a)=>{const r=await original(...a);if(String(a[0]).includes('/api/chess'))r.clone().json().then(d=>{if(d.game)window.__game=d.game;}).catch(()=>{});return r;};"""%faction)
  pg=ctx.new_page();pg.on('pageerror',lambda e:errors.append(str(e)));pg.goto(BASE,wait_until='networkidle');expect(pg.locator('.connection-status')).to_have_text('Connected',timeout=15000);pg.get_by_role('button',name='Online',exact=True).click();pages.append(pg)
 a,bb=pages
 a.get_by_role('button',name='Play 10 min',exact=True).click();expect(a.get_by_label('Your faction',exact=True)).to_be_disabled();assert a.locator('.time-option:not(:disabled)').count()==0
 a.get_by_role('button',name='Computer',exact=True).click();expect(a.get_by_role('button',name='Cancel search',exact=True)).to_be_visible();a.get_by_role('button',name='Cancel search',exact=True).click();expect(a.get_by_role('button',name='Play 10 min',exact=True)).to_be_visible()
 a.get_by_role('button',name='Play 10 min',exact=True).click();bb.get_by_role('button',name='Play 10 min',exact=True).click()
 for pg in pages:pg.wait_for_function("window.__game?.phase==='playing'",timeout=25000)
 game=a.evaluate('window.__game');white=a if game['yourColor']=='w' else bb;black=bb if white==a else a
 white.locator('[data-square="e2"]').click();white.locator('[data-square="e4"]').click();expect(black.locator('.move-list')).to_contain_text('e4',timeout=10000)
 black.locator('[data-square="e7"]').click();black.locator('[data-square="e5"]').click();expect(white.locator('.move-list')).to_contain_text('e5',timeout=10000)
 white.get_by_role('button',name='Send an emote',exact=True).click();white.get_by_role('button',name='Good luck!',exact=True).click();expect(black.locator('.emote-bubble')).to_contain_text('Good luck!')
 a.wait_for_timeout(4000);games=[pg.evaluate('window.__game') for pg in pages];assert games[0]['armies']==games[1]['armies'];assert games[0]['arena']==games[1]['arena']
 for pg in pages:assert pg.locator('.coach-panel').count()==0
 a.screenshot(path=str(OUT/'online-match.png'),full_page=True)
 observations.append({'queueCancelAndLockedSetup':True,'twoHumansExchangeMoves':True,'sameFactionsAndWhiteHomeOnBothClients':True,'home':games[0]['arena'],'transport':[pg.locator('.transport-pill').inner_text() for pg in pages],'rtc':[pg.evaluate("window.__rtc.map(c=>({ice:c.iceConnectionState,local:c.localDescription?.type,remote:c.remoteDescription?.type,candidates:(c.localDescription?.sdp?.match(/a=candidate:/g)||[]).length}))") for pg in pages]})
 black.reload(wait_until='networkidle');expect(black.locator('.move-list')).to_contain_text('e5',timeout=10000)
 a.get_by_role('button',name='Resign',exact=True).click();a.get_by_role('button',name='Resign game',exact=True).click();expect(bb.locator('.result-panel')).to_be_visible(timeout=10000);observations.append({'reconnectAndServerResult':True})
 # Verify the default illustrated board and optional shared 3D models.
 ctx=b.new_context(viewport={'width':1440,'height':1100});ctx.add_init_script("localStorage.setItem('sg-preferences-v2',JSON.stringify({pieceSet:'royal',opponentSet:'skeletons',efficiency:'off',sound:false}));")
 pg=ctx.new_page();pg.on('pageerror',lambda e:errors.append(str(e)));pg.goto(BASE,wait_until='networkidle')
 chunk='/assets/'+next(Path('dist/assets').glob('ChessSceneController-*.js')).name
 pg.evaluate("""async path=>{const mod=await import(path),C=Object.values(mod).find(v=>typeof v==='function'&&v.prototype.previewCapture),old=C.prototype.syncBoardPieces;C.prototype.syncBoardPieces=function(...a){window.__scene=this;return old.apply(this,a);};window.__pause=()=>{const c=window.__scene;cancelAnimationFrame(c.frame);clearTimeout(c.frame);};window.__advance=seconds=>{const c=window.__scene;for(let t=0;t<seconds;t+=.025){c.elapsed+=.025;for(const ch of c.characters.values())c.update(ch,.025);for(let i=c.victims.length-1;i>=0;i--)if(c.updateVictim(c.victims[i],.025)){c.removeCharacter(c.victims[i]);c.victims.splice(i,1);}c.effects.update(.025);}};window.__render=()=>{const c=window.__scene;if(c.camera.isPerspectiveCamera){c.camera.position.copy(c.cameraGoal);c.controls.target.copy(c.targetGoal);c.controls.update();}c.renderer.render(c.scene,c.camera);};}""",chunk)
 # WebGL with a discarded drawing buffer must keep painting during screenshots.
 def paint_for_snapshot():
  pg.evaluate("window.__paint=()=>{window.__render();window.__paintRAF=requestAnimationFrame(window.__paint)};window.__paint()")
 def end_snapshot():
  pg.evaluate("cancelAnimationFrame(window.__paintRAF)")
 pg.get_by_role('button',name='Open an analysis board',exact=True).click();expect(pg.locator('.miniature-board')).to_have_attribute('data-renderer','atlas');expect(pg.locator('canvas')).to_have_count(0)
 assert '{' not in pg.locator('.section-eyebrow').first.inner_text()
 for src,dst in [('e2','e4'),('d7','d5'),('e4','d5')]:pg.locator(f'[data-square="{src}"]').click();pg.locator(f'[data-square="{dst}"]').click()
 expect(pg.locator('.move-list')).to_contain_text('exd5');pg.screenshot(path=str(OUT/'illustrated-2d-pieces.png'),full_page=True)
 observations.append({'defaultFrontFacingAtlas':True,'default2DNoWebGL':True,'legalCaptureIn2D':True})
 pg.get_by_role('button',name='Switch to 3D board',exact=True).click();expect(pg.locator('.miniature-board')).to_have_attribute('data-renderer','models',timeout=30000);pg.wait_for_timeout(500);pg.evaluate('window.__pause();window.__render()');assert pg.evaluate('window.__scene.camera.isPerspectiveCamera')
 assert pg.evaluate('window.__scene.characters.size')==31
 assert pg.evaluate("[...window.__scene.characters.values()].every(ch=>Boolean(ch.root.getObjectByName('Chess identity '+ch.type)))")
 paint_for_snapshot();pg.screenshot(path=str(OUT/'royal-castle-game.png'),full_page=True);end_snapshot()
 pg.get_by_role('button',name='Armory',exact=True).click();pg.get_by_role('button',name='Open battle showcase',exact=True).click();pg.locator('.showcase-stage canvas').wait_for();pg.wait_for_timeout(500);pg.evaluate('window.__pause();window.__render()')
 for faction,name,castle,file in [('elves','Silverwood Elves','Silverwood Sanctuary','elven-castle'),('skeletons','Hollow Legion','Ossuary Keep','skeleton-castle')]:
  pg.get_by_role('button',name=name,exact=False).click();pg.get_by_label('Attacking unit').select_option('q');pg.get_by_role('button',name=castle,exact=False).click();pg.wait_for_timeout(500);pg.evaluate('window.__pause();window.__render()');paint_for_snapshot();pg.locator('.battle-showcase').screenshot(path=str(OUT/(file+'.png')));end_snapshot()
 pg.get_by_role('button',name='Close battle showcase',exact=True).click();expect(pg.locator('canvas')).to_have_count(0)
 assert not errors,errors;observations.append({'castleCameraAndFactionHalls':True,'closePreviewDisposesCanvas':True,'browserErrors':errors});(OUT/'castle-online-browser.json').write_text(json.dumps(observations,indent=2));print(json.dumps(observations,indent=2));b.close()
