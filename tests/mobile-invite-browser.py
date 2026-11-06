"""Production friend-link, installable web app, and native offline-mode checks.
BASE_URL=http://localhost:3010 python tests/mobile-invite-browser.py
"""
import os,json
from pathlib import Path
from playwright.sync_api import sync_playwright,expect
BASE=os.environ.get('BASE_URL','http://localhost:3010')
OUT=Path(os.environ.get('BROWSER_EVIDENCE','artifacts/mobile'));OUT.mkdir(parents=True,exist_ok=True)
results=[];errors=[]
with sync_playwright() as p:
 b=p.chromium.launch(executable_path='/usr/bin/chromium',headless=True,args=['--no-sandbox','--enable-unsafe-swiftshader'])
 def context(faction='royal',mobile=False,native=False):
  ctx=b.new_context(viewport={'width':360 if mobile else 1440,'height':800 if mobile else 1000},is_mobile=mobile,has_touch=mobile)
  ctx.add_init_script("""localStorage.setItem('sg-preferences-v2',JSON.stringify({pieceSet:'%s',opponentSet:'skeletons',efficiency:'on',sound:false}));window.__game=null;window.__api=0;const old=window.fetch;window.fetch=async(...a)=>{if(String(a[0]).includes('/api/chess'))window.__api++;const r=await old(...a);if(String(a[0]).includes('/api/chess'))r.clone().json().then(d=>{if(d.game)window.__game=d.game;}).catch(()=>{});return r;};%s"""%(faction,"window.Capacitor={isNativePlatform:()=>true,getPlatform:()=>'android'};" if native else ''))
  pg=ctx.new_page();pg.on('pageerror',lambda e:errors.append(str(e)));return ctx,pg
 hostctx,host=context('elves',True);host.goto(BASE,wait_until='networkidle');expect(host.locator('.connection-status')).to_have_text('Connected')
 assert host.locator('canvas').count()==0
 assert host.locator('.miniature-board').get_attribute('data-renderer')=='atlas'
 host.get_by_role('button',name='Friend',exact=True).click();host.get_by_role('button',name='Share a friend link',exact=True).click()
 host.get_by_label('Your side',exact=True).select_option('b');host.get_by_role('button',name='Create invite link',exact=True).click()
 field=host.get_by_label('Friend invite link',exact=True);expect(field).to_be_visible();url=field.input_value();assert '?play=' in url
 assert host.evaluate('document.documentElement.scrollWidth')==360
 host.screenshot(path=str(OUT/'phone-create-invite.png'),full_page=True)
 guestctx,guest=context('skeletons');guest.goto(url,wait_until='networkidle');expect(guest.get_by_role('button',name='Join match',exact=True)).to_be_enabled();guest.screenshot(path=str(OUT/'friend-join.png'),full_page=True);guest.get_by_role('button',name='Join match',exact=True).click()
 for pg in [host,guest]:pg.wait_for_function("window.__game?.phase==='playing'",timeout=25000)
 hg,gg=[pg.evaluate('window.__game') for pg in [host,guest]]
 assert hg['yourColor']=='b' and gg['yourColor']=='w';assert hg['arena']==gg['arena']=='ossuary';assert hg['armies']==gg['armies']=={'w':'skeletons','b':'elves'};assert hg['rated']==False
 guest.locator('[data-square=e2]').click();guest.locator('[data-square=e4]').click();expect(host.locator('.move-list')).to_contain_text('e4',timeout=10000)
 host.locator('[data-square=e7]').tap();host.locator('[data-square=e5]').tap();expect(guest.locator('.move-list')).to_contain_text('e5',timeout=10000)
 assert host.locator('.board-frame.orientation-b').count()==1
 transform=host.locator('[data-piece=bn].miniature-icon').first.evaluate('(el)=>getComputedStyle(el).transform');assert transform=='none',transform
 host.screenshot(path=str(OUT/'phone-friend-match.png'),full_page=True)
 for pg in [host,guest]:assert pg.locator('.coach-panel').count()==0
 host.reload(wait_until='networkidle');expect(host.locator('.move-list')).to_contain_text('e5')
 _,third=context();third.goto(url,wait_until='networkidle');expect(third.get_by_role('dialog')).to_contain_text('already been used');assert third.get_by_role('button',name='Join match',exact=True).count()==0
 results.append({'privateLinkTwoBrowsers':True,'phoneTapMoves':True,'fixedSidesAndWhiteHome':True,'usedLinkRejected':True,'reconnect':True,'blackPiecesStayUpright':True,'phoneWidth':360})
 # Installable shell is fetched on HTTPS/localhost; reload and play without the network.
 offctx,offline=context(mobile=True);offline.goto(BASE,wait_until='networkidle');offline.evaluate('navigator.serviceWorker.ready');offline.wait_for_function('navigator.serviceWorker.controller!==null')
 manifest=offline.evaluate("fetch('/manifest.webmanifest').then(r=>r.json())");assert manifest['display']=='standalone'
 offctx.new_cdp_session(offline).send('Emulation.setCPUThrottlingRate',{'rate':6});offctx.set_offline(True);offline.reload(wait_until='domcontentloaded');offline.get_by_role('button',name='Play computer',exact=True).click();offline.locator('[data-square=e2]').tap();offline.locator('[data-square=e4]').tap();offline.wait_for_function('document.querySelectorAll(".move-row button").length>=2',timeout=20000)
 assert offline.locator('canvas').count()==0;offline.screenshot(path=str(OUT/'phone-offline-computer.png'),full_page=True)
 results.append({'installedWebShellOffline':True,'offlineComputerWorkerReplies':True,'default2DNoWebGL':True,'cpuThrottle6x':True})
 # The APK serves the bundled web build and uses this same native-platform branch.
 nativectx,native=context(mobile=True,native=True);native.goto(BASE,wait_until='networkidle');expect(native.locator('.connection-status')).to_have_text('Offline ready');assert native.evaluate('window.__api')==0
 native.get_by_role('button',name='Play computer',exact=True).click();native.locator('[data-square=d2]').tap();native.locator('[data-square=d4]').tap();native.wait_for_function('document.querySelectorAll(".move-row button").length>=2',timeout=20000)
 assert native.evaluate('window.__api')==0
 native.get_by_role('button',name='Appearance and preferences',exact=True).click();expect(native.get_by_label('Game website address',exact=True)).to_be_visible();native.screenshot(path=str(OUT/'android-online-settings.png'),full_page=True)
 results.append({'nativeModeNoHostNoApiCalls':True,'nativeModeComputerReplies':True,'nativeWebsiteSettingAvailable':True,'nativeRuntimeEmulatedNotPhysicalDevice':True})
 assert not errors,errors;results.append({'browserErrors':errors});(OUT/'mobile-invite-checks.json').write_text(json.dumps(results,indent=2));print(json.dumps(results,indent=2));b.close()
