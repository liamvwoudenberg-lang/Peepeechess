"""Real app computer pacing, pause cancellation, and two-client capture checks.
Run against a fresh local server with BASE_URL=http://localhost:3030.
"""
import json, os
from pathlib import Path
from playwright.sync_api import sync_playwright, expect

BASE = os.environ.get('BASE_URL', 'http://localhost:3030')
OUT = Path('artifacts/battle2d')
OUT.mkdir(parents=True, exist_ok=True)
results, errors = [], []
FEN = '7k/8/8/4b3/3P4/8/8/K7 w - - 0 1'

with sync_playwright() as p:
    browser = p.chromium.launch(executable_path='/usr/bin/chromium', headless=True,
                               args=['--no-sandbox'])

    def page(seed=False, mobile=False):
        ctx = browser.new_context(viewport={'width': 360 if mobile else 1200, 'height': 800},
                                  is_mobile=mobile, has_touch=mobile)
        game = dict(id='capture-qa', mode='computer', initialFen=FEN, fen=FEN, history=[],
                    white=dict(id='local', name='You', rating=1200),
                    black=dict(id='computer', name='Computer', rating=400), yourColor='w',
                    status='active', timeControl='untimed', feedback=False, elo=400,
                    armies=dict(w='royal', b='skeletons'), arena='citadel', rated=False,
                    spectators=0, clocks=dict(w=0, b=0, turn='w', updatedAt=0, increment=0))
        ctx.add_init_script("""(() => {
          localStorage.setItem('sg-preferences-v2', JSON.stringify({pieceSet:'royal',opponentSet:'skeletons',efficiency:'on',sound:false,battleAnimations:'cinematic'}));
          const seed = %s; if(seed && !sessionStorage.getItem('seeded')) {localStorage.setItem('sg-local-game-v2',JSON.stringify(seed));sessionStorage.setItem('seeded','1');}
          window.__trace=[]; window.__game=null;
          const store=Storage.prototype.setItem;
          Storage.prototype.setItem=function(k,v){ if(k==='sg-local-game-v2') {const g=JSON.parse(v);window.__trace.push({kind:'position',at:performance.now(),length:g?.history.length,fen:g?.fen});} return store.call(this,k,v);};
          const fetcher=window.fetch; window.fetch=async(...a)=>{const r=await fetcher(...a);if(String(a[0]).includes('/api/chess'))r.clone().json().then(d=>{if(d.game)window.__game=d.game;}).catch(()=>{});return r;};
          let last;new MutationObserver(()=>{const layer=document.querySelector('.battle-2d');if(layer&&layer!==last){last=layer;window.__trace.push({kind:'battle',at:performance.now(),duration:Number(layer.dataset.duration),capture:layer.dataset.capture});}}).observe(document,{subtree:true,childList:true});
        })()""" % json.dumps(game if seed else None))
        pg = ctx.new_page()
        pg.on('pageerror', lambda e: errors.append(str(e)))
        pg.goto(BASE, wait_until='networkidle')
        return ctx, pg

    # The real worker can calculate during the fight, but its move waits in untimed play.
    ctx, pg = page(seed=True, mobile=True)
    ctx.new_cdp_session(pg).send('Emulation.setCPUThrottlingRate', {'rate': 6})
    pg.locator('[data-square=d4]').tap()
    pg.locator('[data-square=e5]').tap()
    pg.wait_for_function("window.__trace.some(e=>e.kind==='position'&&e.length===2)", timeout=20000)
    trace = pg.evaluate('window.__trace')
    capture = next(e for e in trace if e['kind']=='position' and e['length']==1)
    reply = next(e for e in trace if e['kind']=='position' and e['length']==2)
    battle = next(e for e in trace if e['kind']=='battle')
    assert reply['at']-capture['at'] >= 340, trace
    assert battle['duration']==340 and battle['capture']=='royal/p>skeletons/b'
    expect(pg.locator('.battle-2d')).to_have_count(0)
    assert pg.evaluate('document.documentElement.scrollWidth')==360
    assert pg.locator('canvas').count()==0
    results.append(dict(untimedWorkerReplyAfterFight=True, cpuThrottle=6,
                        replyAfterMs=round(reply['at']-capture['at']), phoneWidth=360))
    ctx.close()

    # Pause cancels a pending response; resume recomputes the legal reply.
    ctx, pg = page(seed=True)
    pg.get_by_role('button', name='Moves and game options', exact=True).click()
    pg.locator('[data-square=d4]').click()
    pg.locator('[data-square=e5]').click()
    pg.get_by_role('button', name='Pause', exact=True).click()
    expect(pg.get_by_text('Your computer game is paused.', exact=True)).to_be_visible()
    pg.wait_for_timeout(650)
    assert pg.evaluate("JSON.parse(localStorage.getItem('sg-local-game-v2')).history.length")==1
    pg.get_by_role('button', name='Resume game', exact=True).click()
    pg.wait_for_function("JSON.parse(localStorage.getItem('sg-local-game-v2')).history.length===2", timeout=20000)
    results.append(dict(pauseCancelsPendingReply=True, resumeWorkerReply=True))
    ctx.close()

    if os.environ.get('PRODUCTION_QA') == '1':
        ctx, pg = page(seed=True, mobile=True)
        pg.evaluate('navigator.serviceWorker.ready')
        pg.wait_for_function('navigator.serviceWorker.controller!==null')
        cached = pg.evaluate("""async()=>{for(const key of await caches.keys()){const r=await (await caches.open(key)).match('/pieces/legions-battle-body.webp');if(r)return {ok:r.ok,bytes:(await r.arrayBuffer()).byteLength};}return null;}""")
        assert cached and cached['ok'] and cached['bytes']>100000, cached
        ctx.set_offline(True)
        pg.reload(wait_until='domcontentloaded')
        pg.locator('[data-square=d4]').tap(); pg.locator('[data-square=e5]').tap()
        pg.wait_for_function("window.__trace.some(e=>e.kind==='battle')&&JSON.parse(localStorage.getItem('sg-local-game-v2')).history.length===2", timeout=20000)
        results.append(dict(offlineCaptureAndWorker=True, offlineBattleBodyBytes=cached['bytes']))
        ctx.close()

    # Real invite and authority: the capture reaches both players while the cosmetic fight runs.
    hc, host = page(mobile=True)
    expect(host.locator('.connection-status')).to_have_text('Connected')
    host.get_by_role('button', name='Choose Royal Guard', exact=True).click()
    host.get_by_role('button', name='Friend', exact=True).click()
    host.get_by_role('button', name='Share a friend link', exact=True).click()
    host.get_by_label('Your side', exact=True).select_option('w')
    host.get_by_role('button', name='Create invite link', exact=True).click()
    url = host.get_by_label('Friend invite link', exact=True).input_value()
    gc, guest = page()
    guest.goto(url, wait_until='networkidle')
    guest.get_by_role('dialog').get_by_role('button', name='Choose Hollow Legion', exact=True).click()
    guest.get_by_role('button', name='Join match', exact=True).click()
    for client in [host,guest]:
        client.wait_for_function("window.__game?.phase==='playing'", timeout=25000)
    host.locator('[data-square=e2]').tap(); host.locator('[data-square=e4]').tap()
    guest.wait_for_function('window.__game?.history.length===1')
    guest.locator('[data-square=d7]').click(); guest.locator('[data-square=d5]').click()
    host.wait_for_function('window.__game?.history.length===2')
    host.locator('[data-square=e4]').tap(); host.locator('[data-square=d5]').tap()
    for client in [host,guest]:
        client.wait_for_function("window.__game?.history.length===3&&window.__trace.some(e=>e.kind==='battle')", timeout=10000)
        event=client.evaluate("window.__trace.find(e=>e.kind==='battle')")
        assert event['duration']<=500 and event['capture']=='royal/p>skeletons/p', event
        expect(client.locator('[data-square=d5] [data-piece=wp]')).to_have_count(1)
        assert client.locator('.coach-panel').count()==0
    host.screenshot(path=str(OUT/'phone-online-capture.png'))
    results.append(dict(realTwoClientInviteCapture=True, onlineFightUnder500ms=True,
                        logicalMovesImmediate=True, noOnlineCoach=True))
    assert not errors, errors
    results.append(dict(browserErrors=errors))
    (OUT/'app-checks.json').write_text(json.dumps(results, indent=2))
    print(json.dumps(results, indent=2))
    browser.close()
