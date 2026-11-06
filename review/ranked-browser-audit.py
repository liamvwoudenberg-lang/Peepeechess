from playwright.sync_api import sync_playwright
import json

out = '/workspace/castle-chess-review/evidence/'
with sync_playwright() as p:
    b = p.chromium.launch(executable_path='/usr/bin/chromium', headless=True,
                          args=['--no-sandbox', '--enable-unsafe-swiftshader'])
    page = b.new_page(viewport={'width': 1440, 'height': 900})
    page.add_init_script("""
      localStorage.setItem('sovereigns_gambit_onboarded','true');
      window.__auditSockets=[]; window.__auditMessages=[];
      const Base=window.WebSocket;
      window.WebSocket=class extends Base {
        constructor(...a) {
          super(...a);
          if(this.url.endsWith('/ws')) {
            window.__auditSockets.push(this);
            this.addEventListener('message',e=>window.__auditMessages.push(JSON.parse(e.data)));
          }
        }
      };
    """)
    page.goto('http://localhost:3000', wait_until='networkidle')
    page.wait_for_function('window.__auditSockets.some(s=>s.readyState===1)')
    page.evaluate("window.__auditSockets.find(s=>s.readyState===1).send(JSON.stringify({type:'queue:join',isSiegeIncrement:false}))")
    page.wait_for_function("window.__auditMessages.some(m=>m.type==='match:start')")
    page.wait_for_timeout(900)
    hint = page.get_by_role('button', name='Ask Aldric for Recommended Move', exact=True)
    print(json.dumps({'probe': 'ranked-in-app-assistance', 'hintVisible': hint.is_visible(),
                      'hintEnabled': hint.is_enabled(), 'bodyBeforeHint': page.locator('body').inner_text()}), flush=True)
    hint.click()
    page.wait_for_timeout(500)
    page.screenshot(path=out+'ranked-with-coach.png')
    print(json.dumps({'probe': 'ranked-hint-click', 'coachDrawerVisible': page.locator('aside').is_visible()}), flush=True)
    page.evaluate("window.__auditSockets[0].send(JSON.stringify({type:'match:resign',matchId:window.__auditMessages.find(m=>m.type==='match:start').match.matchId}))")
    page.wait_for_timeout(200)
    b.close()

with sync_playwright() as p:
    b = p.chromium.launch(executable_path='/usr/bin/chromium', headless=True,
                          args=['--no-sandbox', '--enable-unsafe-swiftshader'])
    page = b.new_page(viewport={'width': 390, 'height': 844}, is_mobile=True, has_touch=True)
    page.add_init_script("localStorage.setItem('sovereigns_gambit_onboarded','true')")
    page.goto('http://localhost:3000/?autostart=1', wait_until='networkidle')
    page.get_by_role('button', name='2D Top', exact=True).click()
    page.wait_for_timeout(1500)
    page.screenshot(path=out+'mobile-2d-top.png')
    b.close()
