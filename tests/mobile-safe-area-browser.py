"""Inject system-inset values to reproduce standalone notches in Chromium.
This verifies CSS layout and retry recovery, not a physical iOS/Android run.
"""
import os, json
from pathlib import Path
from playwright.sync_api import sync_playwright, expect

BASE=os.environ.get('BASE_URL','http://localhost:3034')
OUT=Path('artifacts/mobile-safe-area');OUT.mkdir(parents=True,exist_ok=True)
results,errors=[],[]
with sync_playwright() as p:
    browser=p.chromium.launch(executable_path='/usr/bin/chromium',args=['--no-sandbox'])
    ctx=browser.new_context(viewport={'width':360,'height':800},is_mobile=True,has_touch=True)
    ctx.add_init_script("localStorage.setItem('sg-preferences-v2',JSON.stringify({efficiency:'on',sound:false}));")
    configured=False
    def api(route):
        if configured:route.continue_()
        else:route.fulfill(status=503,content_type='application/json',body=json.dumps({'code':'ONLINE_NOT_CONFIGURED','error':'Online play is not available on this server yet. You can play the computer while it is being set up.'}))
    ctx.route('**/api/chess',api)
    pg=ctx.new_page();pg.on('pageerror',lambda e:errors.append(str(e)))
    pg.goto(BASE,wait_until='networkidle')
    def insets(top=0,right=0,bottom=0,left=0):
        pg.evaluate("v=>{for(const [k,n] of Object.entries(v))document.documentElement.style.setProperty('--safe-'+k,n+'px')}",dict(top=top,right=right,bottom=bottom,left=left))
    def inside(selector,width,height,top=0,right=0,bottom=0,left=0):
        r=pg.locator(selector).bounding_box();assert r is not None,selector
        assert r['x']>=left-1 and r['y']>=top-1 and r['x']+r['width']<=width-right+1 and r['y']+r['height']<=height-bottom+1,(selector,r,[top,right,bottom,left])
        return r
    insets(top=44,bottom=34)
    expect(pg.locator('.connection-status')).to_have_text('Offline practice')
    expect(pg.locator('.connection-banner')).to_contain_text('Online play is unavailable. Computer games are ready.')
    inside('.topbar',360,800,top=44,bottom=34)
    inside('.topbar .icon-button[aria-label="Appearance and preferences"]',360,800,top=44,bottom=34)
    # A status strip makes the emulated exclusion area visible in review screenshots.
    pg.add_style_tag(content="body::before{content:'13:56                         Wi-Fi  ▰';position:fixed;inset:0 0 auto;height:44px;padding:12px 20px;box-sizing:border-box;color:white;background:#151917;font:600 14px system-ui;z-index:500;pointer-events:none}")
    pg.screenshot(path=str(OUT/'phone-header-safe.png'))
    configured=True
    pg.get_by_role('button',name='Retry online connection',exact=True).tap()
    expect(pg.locator('.connection-status')).to_have_text('Connected')
    expect(pg.locator('.connection-banner')).to_have_count(0)
    results.append(dict(emulatedNotchTop=44,homeIndicator=34,headerBelowStatus=True,retryRecoveredWithRealApi=True))
    pg.get_by_role('button',name='Choose Royal Guard',exact=True).tap()
    pg.get_by_role('button',name='Play computer',exact=True).tap()
    inside('.game-focus-bar',360,800,top=44,bottom=34)
    inside('.chessboard',360,800,top=44,bottom=34)
    inside('.board-toolbar',360,800,top=44,bottom=34)
    inside('.board-status',360,800,top=44,bottom=34)
    pg.get_by_role('button',name='Moves and game options',exact=True).tap()
    inside('.game-panel-column',360,800,top=44,bottom=34)
    inside('.focus-panel-close',360,800,top=44,bottom=34)
    pg.get_by_role('button',name='Close match details',exact=True).tap()
    pg.screenshot(path=str(OUT/'phone-match-safe.png'))
    pg.get_by_role('button',name='Menu',exact=True).tap()
    pg.get_by_role('button',name='Appearance and preferences',exact=True).tap()
    inside('.dialog',360,800,top=44,bottom=34)
    pg.get_by_role('button',name='Close dialog',exact=True).tap()
    results.append(dict(fullscreenGameSafe=True,drawerSafe=True,settingsDialogSafe=True))
    pg.set_viewport_size({'width':844,'height':390});insets(left=44,right=44,bottom=21)
    pg.add_style_tag(content='body::before{display:none}')
    pg.locator('.return-game').click()
    for selector in ['.game-focus-bar','.chessboard','.board-toolbar','.board-status']:
        inside(selector,844,390,left=44,right=44,bottom=21)
    assert pg.evaluate('document.documentElement.scrollWidth')==844
    pg.screenshot(path=str(OUT/'landscape-match-safe.png'))
    results.append(dict(landscapeSideInsets=44,landscapeBottomInset=21,allMatchControlsWithinSafeArea=True))
    assert not errors,errors
    results.append(dict(browserErrors=errors))
    (OUT/'checks.json').write_text(json.dumps(results,indent=2));print(json.dumps(results,indent=2))
    browser.close()
