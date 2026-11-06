from playwright.sync_api import sync_playwright
import json
from pathlib import Path

out = Path('/workspace/castle-chess-review/evidence')
out.mkdir(parents=True, exist_ok=True)

with sync_playwright() as p:
    browser = p.chromium.launch(executable_path='/usr/bin/chromium', headless=True,
                              args=['--no-sandbox', '--enable-unsafe-swiftshader'])
    page = browser.new_page(viewport={'width': 1440, 'height': 900}, device_scale_factor=1)
    errors = []
    page.on('pageerror', lambda e: errors.append(str(e)))
    page.goto('http://localhost:3000', wait_until='networkidle')
    page.get_by_role('button', name='Novice', exact=False).click()
    page.wait_for_timeout(300)
    page.screenshot(path=str(out / 'desktop-menu.png'))
    page.get_by_role('button', name='Untimed', exact=True).click()
    page.get_by_role('button', name='Launch Match', exact=True).click()
    page.wait_for_timeout(1000)
    page.screenshot(path=str(out / 'desktop-game-untimed.png'))
    print(json.dumps({'probe': 'untimed-match', 'body': page.locator('body').inner_text(), 'errors': errors}))
    page.get_by_role('button', name='Settings & Citadel Features', exact=True).click()
    print(json.dumps({'probe': 'game-menu', 'buttons': page.get_by_role('button').all_text_contents()}))
    browser.close()

with sync_playwright() as p:
    browser = p.chromium.launch(executable_path='/usr/bin/chromium', headless=True,
                              args=['--no-sandbox', '--enable-unsafe-swiftshader'])
    page = browser.new_page(viewport={'width': 390, 'height': 844}, device_scale_factor=1,
                            is_mobile=True, has_touch=True)
    page.add_init_script("localStorage.setItem('sovereigns_gambit_onboarded', 'true')")
    page.goto('http://localhost:3000', wait_until='networkidle')
    page.screenshot(path=str(out / 'mobile-menu.png'))
    page.get_by_role('button', name='Launch Match', exact=True).click()
    page.wait_for_timeout(800)
    page.screenshot(path=str(out / 'mobile-game.png'))
    print(json.dumps({'probe': 'mobile-layout', 'viewportWidth': 390,
                      'documentWidth': page.evaluate('document.documentElement.scrollWidth'),
                      'buttons': page.get_by_role('button').evaluate_all('(els) => els.map(el => ({name: el.innerText || el.title, width: el.getBoundingClientRect().width, height: el.getBoundingClientRect().height}))')}))
    browser.close()
