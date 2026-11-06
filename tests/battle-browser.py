"""Art and animation QA against a built, running production server.
Run npm run build, PORT=3004 npm start, then python tests/battle-browser.py.
The controller hook exists only inside this browser test, never in the app.
"""
import os,json
from pathlib import Path
from playwright.sync_api import sync_playwright,expect
BASE=os.environ.get('BASE_URL','http://localhost:3004')
OUT=Path(os.environ.get('ART_EVIDENCE','artifacts/battles'));OUT.mkdir(parents=True,exist_ok=True)
CHUNK='/assets/'+next(Path('dist/assets').glob('ChessSceneController-*.js')).name
observations=[]
with sync_playwright() as p:
 b=p.chromium.launch(executable_path='/usr/bin/chromium',headless=True,args=['--no-sandbox','--enable-unsafe-swiftshader'])
 ctx=b.new_context(viewport={'width':1440,'height':1100})
 ctx.add_init_script("""window.__audio={starts:0,stops:0};for(const C of [OscillatorNode,AudioBufferSourceNode])for(const method of ['start','stop']){const old=C.prototype[method];C.prototype[method]=function(...args){window.__audio[method==='start'?'starts':'stops']++;return old.apply(this,args);};}localStorage.setItem('sg-preferences-v2',JSON.stringify({pieceSet:'royal',opponentSet:'skeletons',arena:'citadel',battleAnimations:'cinematic',efficiency:'off',reducedMotion:false,sound:true,coordinates:true}));""")
 pg=ctx.new_page();errors=[];pg.on('pageerror',lambda e:errors.append(str(e)));pg.on('console',lambda m:errors.append(m.text) if m.type=='error' else None)
 pg.goto(BASE,wait_until='networkidle')
 resources=pg.evaluate('performance.getEntriesByType("resource").map(r=>r.name)')
 assert not any('ChessSceneController-' in r or 'BattleShowcase-' in r or '.jpg' in r for r in resources)
 observations.append({'default2DLoadsNo3DOrPhotographs':True})
 pg.evaluate("""async path=>{const mod=await import(path),C=Object.values(mod).find(v=>typeof v==='function'&&v.prototype.previewCapture);window.__Controller=C;const old=C.prototype.syncBoardPieces;C.prototype.syncBoardPieces=function(...a){window.__scene=this;return old.apply(this,a);};window.__pause=()=>{const c=window.__scene;cancelAnimationFrame(c.frame);clearTimeout(c.frame);};window.__advance=(seconds)=>{const c=window.__scene;for(let t=0;t<seconds;t+=.025){c.elapsed+=.025;for(const ch of c.characters.values())c.update(ch,.025);for(let i=c.victims.length-1;i>=0;i--)if(c.updateVictim(c.victims[i],.025)){c.removeCharacter(c.victims[i]);c.victims.splice(i,1);}c.effects.update(.025);}return c.getPerformanceStats();};window.__render=()=>{const c=window.__scene;c.camera.position.copy(c.cameraGoal);c.controls.target.copy(c.targetGoal);c.controls.update();c.renderer.render(c.scene,c.camera);};}""",CHUNK)
 # WebGL with a discarded drawing buffer must keep painting during screenshots.
 def paint_for_snapshot():
  pg.evaluate("window.__paint=()=>{window.__render();window.__paintRAF=requestAnimationFrame(window.__paint)};window.__paint()")
 def end_snapshot():
  pg.evaluate("cancelAnimationFrame(window.__paintRAF)")
 pg.get_by_role('button',name='Armory',exact=True).click();pg.get_by_role('button',name='Open battle showcase').click();pg.locator('.showcase-stage canvas').wait_for();pg.wait_for_timeout(1000);pg.evaluate('window.__pause()')
 assert pg.evaluate('window.__scene.getPerformanceStats().lastCapture')=='royal/n>skeletons/r'
 pg.get_by_role('button',name='Mute preview sound',exact=True).click();before=pg.evaluate('window.__audio.starts');pg.get_by_role('button',name='Replay encounter',exact=True).or_(pg.get_by_role('button',name='Preview encounter',exact=True)).click();pg.evaluate('window.__advance(4)');assert pg.evaluate('window.__audio.starts')==before
 pg.get_by_role('button',name='Enable preview sound',exact=True).click();pg.get_by_role('button',name='Replay encounter',exact=True).or_(pg.get_by_role('button',name='Preview encounter',exact=True)).click();pg.evaluate('window.__advance(4)');assert pg.evaluate('window.__audio.starts')>before
 observations.append({'weaponSoundsScheduleAndMuteStopsScheduling':True})
 matrix=pg.evaluate("""()=>{const c=window.__scene,armies=['royal','elves','skeletons'],roles=['p','n','r','b','q','k'];c.setAnimationOptions({mode:'cinematic',sound:false,reducedMotion:false,competitive:false});let count=0;for(const army of armies)for(const enemy of armies)for(const role of roles)for(const target of roles){const id=`${army}/${role}>${enemy}/${target}`;c.previewCapture(role,target,army,enemy,++count+1000);if(c.getPerformanceStats().lastCapture!==id)throw Error(id);window.__advance(4);const stats=c.getPerformanceStats(),ch=[...c.characters.values()][0];if(stats.activeAnimations!==0||stats.victims!==0||stats.characters!==1||ch.root.position.distanceTo(ch.targetPos)>.001)throw Error('Unsettled '+id+JSON.stringify(stats));}c.previewCapture('q','r','elves','skeletons',2000);c.setAnimationOptions({mode:'off',sound:false,reducedMotion:false,competitive:false});if(c.getPerformanceStats().activeAnimations!==0||c.getPerformanceStats().victims!==0)throw Error('Off');c.setAnimationOptions({mode:'cinematic',sound:false,reducedMotion:true,competitive:false});c.previewCapture('q','r','elves','skeletons',2001);if(c.getPerformanceStats().activeAnimations!==0)throw Error('Reduced motion');c.setAnimationOptions({mode:'cinematic',sound:false,reducedMotion:false,competitive:true});c.previewCapture('k','q','skeletons','elves',2002);window.__advance(.6);if(c.getPerformanceStats().activeAnimations!==0)throw Error('Competitive');return {encounters:count,off:true,reducedMotion:true,competitiveUnder600ms:true};}""")
 observations.append(matrix);print('All 324 capture animations settled correctly',flush=True)
 for army,enemy,arena,attacker,defender,name in [('royal','skeletons','Dawn Citadel','n','r','royal-charge'),('elves','skeletons','Silverwood Sanctuary','q','n','elven-moonblades'),('skeletons','elves','Ossuary Keep','b','q','skeleton-soul-drain')]:
  card={'royal':'Royal Guard','elves':'Silverwood Elves','skeletons':'Hollow Legion'}[army]
  pg.get_by_role('button',name=card,exact=False).click();pg.get_by_label('Opposing army').select_option(enemy);pg.get_by_label('Attacking unit').select_option(attacker);pg.get_by_label('Defending unit').select_option(defender);pg.get_by_role('button',name=arena,exact=False).click();pg.wait_for_timeout(500);pg.evaluate('window.__pause()');pg.evaluate("window.__scene.setAnimationOptions({mode:'cinematic',sound:false,reducedMotion:false,competitive:false})")
  pg.get_by_role('button',name='Replay encounter',exact=True).or_(pg.get_by_role('button',name='Preview encounter',exact=True)).click();pg.evaluate('window.__advance(.95);window.__render()');pg.locator('.battle-showcase').screenshot(path=str(OUT/(name+'.png')))
  expected=f'{army}/{attacker}>{enemy}/{defender}';assert pg.evaluate('window.__scene.getPerformanceStats().lastCapture')==expected
  observations.append({'matchup':expected,'arena':arena,'drawCalls':pg.evaluate('window.__scene.getPerformanceStats().drawCalls')})
 pg.screenshot(path=str(OUT/'armory-desktop.png'),full_page=True)
 pg.get_by_role('button',name='Play',exact=True).click();pg.get_by_role('button',name='Import PGN / FEN',exact=True).click();pg.get_by_label('PGN game or FEN position').fill('7k/8/8/4r3/3P4/8/8/7K w - - 0 1');pg.get_by_role('button',name='Open analysis',exact=True).click();pg.get_by_role('button',name='Analyze position',exact=True).click()
 print('Analysis ready',flush=True)
 # The game canvas is tested through actual raycast clicks below.
 pg.get_by_role('button',name='Switch to 3D board',exact=True).click();pg.locator('.scene-mount canvas').wait_for();pg.wait_for_timeout(500);pg.evaluate('window.__pause();window.__render()')
 def square_click(sq):
  point=pg.evaluate("""sq=>{const c=window.__scene,el=c.renderer.domElement,r=el.getBoundingClientRect(),v=c.camera.position.clone();v.set(('abcdefgh'.indexOf(sq[0])-3.5)*1.16,.075,(3.5-(Number(sq[1])-1))*1.16);v.project(c.camera);return {x:r.x+(v.x+1)*r.width/2,y:r.y+(1-v.y)*r.height/2};}""",sq);pg.mouse.click(point['x'],point['y'])
 square_click('d4');square_click('e5');expect(pg.locator('.move-list')).to_contain_text('dxe5');pg.wait_for_timeout(250)
 assert pg.evaluate('window.__scene.getPerformanceStats().lastCapture')=='skeletons/p>elves/r'
 pg.evaluate('window.__advance(4);window.__render()');stats=pg.evaluate('window.__scene.getPerformanceStats()');assert stats['characters']==3 and stats['activeAnimations']==0 and stats['victims']==0
 paint_for_snapshot();pg.screenshot(path=str(OUT/'live-3d-capture.png'),full_page=True);end_snapshot();observations.append({'live3DRaycastCaptureUpdatesChessImmediately':True,'scene':stats})
 pg.get_by_role('button',name='Switch to 2D board',exact=True).click();expect(pg.locator('[data-square="e5"] [data-piece="wp"]')).to_have_count(1)
 pg.get_by_role('button',name='Appearance and preferences',exact=True).click();pg.get_by_label('Performance mode',exact=False).select_option('on');pg.get_by_role('button',name='Close dialog',exact=True).click()
 pg.set_viewport_size({'width':360,'height':780});pg.get_by_role('button',name='Armory',exact=True).click();pg.screenshot(path=str(OUT/'armory-mobile.png'),full_page=True)
 assert pg.evaluate('document.documentElement.scrollWidth')==360
 observations.append({'mobileArmoryNoOverflow':True,'browserErrors':errors});assert not errors,errors
 (OUT/'battle-browser-checks.json').write_text(json.dumps(observations,indent=2));print(json.dumps(observations,indent=2));b.close()
