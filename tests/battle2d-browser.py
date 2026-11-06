"""Dev-only Board fixture: real legal captures and real composited 2D fights.
Start DISABLE_HMR=true PORT=3030 node --import tsx server.ts, then run this file.
"""
import os,json
from pathlib import Path
from datetime import datetime,timezone
from playwright.sync_api import sync_playwright,expect
BASE=os.environ.get('BASE_URL','http://localhost:3030');OUT=Path('artifacts/battle2d');OUT.mkdir(parents=True,exist_ok=True)
results=[];errors=[]

def position(role,target,side='w'):
 start='d4' if side=='w' else 'd5'
 end=({'p':'e5','n':'f5','r':'d5','b':'e5','q':'e5','k':'e5'} if side=='w' else {'p':'e4','n':'f4','r':'d4','b':'e4','q':'e4','k':'e4'})[role]
 pieces={'a1':'K','h8':'k'}
 if role=='k':del pieces['a1' if side=='w' else 'h8']
 pieces[start]=role.upper() if side=='w' else role;pieces[end]=target if side=='w' else target.upper()
 rows=[]
 for rank in range(8,0,-1):
  row='';empty=0
  for f in 'abcdefgh':
   unit=pieces.get(f+str(rank))
   if unit:
    if empty:row+=str(empty);empty=0
    row+=unit
   else:empty+=1
  if empty:row+=str(empty)
  rows.append(row)
 return '/'.join(rows)+' '+side+' - - 0 1',start,end

with sync_playwright() as p:
 b=p.chromium.launch(executable_path='/usr/bin/chromium',args=['--no-sandbox'])
 pg=b.new_page(viewport={'width':720,'height':780});pg.on('pageerror',lambda e:errors.append(str(e)));pg.goto(BASE+'/tests/fixtures/battle-2d.html',wait_until='networkidle');pg.wait_for_function('Boolean(window.battleQA)')
 pg.evaluate("async()=>{const i=new Image();i.src='/pieces/legions-battle-body.webp';await i.decode()}")
 pg.clock.install();pg.clock.pause_at(datetime.fromtimestamp((pg.evaluate('Date.now()')+2000)/1000,timezone.utc))
 def reset(fen,army='royal',enemy='skeletons',orientation='w',**options):
  data={'fen':fen,'orientation':orientation,'armies':{'w':army,'b':enemy},'mode':'cinematic','competitive':False,'lightweight':False,'reducedMotion':False,'sound':False};data.update(options)
  serial=pg.evaluate('(d)=>battleQA.reset(d)',data);pg.clock.run_for(32);expect(pg.locator('[data-qa-serial]')).to_have_attribute('data-qa-serial',str(serial))
 def move(src,dst,promotion='q'):
  fen=pg.evaluate('(d)=>battleQA.move(d[0],d[1],d[2])',[src,dst,promotion]);pg.clock.run_for(12);expect(pg.locator('[data-qa-fen]')).to_have_attribute('data-qa-fen',fen);return fen
 def inspect_stage(progress):
  return pg.evaluate('''progress=>{const layer=document.querySelector('.battle-2d'),duration=Number(layer.dataset.duration),animations=layer.getAnimations({subtree:true});animations.forEach(a=>{a.pause();a.currentTime=duration*progress;});return {duration,animations:animations.length,weapon:layer.dataset.weapon,motion:layer.dataset.motion,capture:layer.dataset.capture,pointer:getComputedStyle(layer).pointerEvents,defender:getComputedStyle(layer.querySelector('.duel-defender')).opacity,actorTransform:getComputedStyle(layer.querySelector('.duel-attacker')).transform,nodes:layer.querySelectorAll('*').length};}''',progress)
 motions=set();weapons=set()
 for i,(army,role) in enumerate((a,r) for a in ['royal','elves','skeletons'] for r in ['p','n','b','r','q','k']):
  enemy=['skeletons','royal','elves'][i%3];target=['p','n','b','r','q'][i%5];fen,src,dst=position(role,target);reset(fen,army,enemy)
  if i==0:pg.locator(f'[data-square={src}]').click();pg.locator(f'[data-square={dst}]').click();pg.clock.run_for(12)
  else:move(src,dst)
  layer=pg.locator('.battle-2d');expect(layer).to_have_count(1);expect(layer).to_have_attribute('data-capture',f'{army}/{role}>{enemy}/{target}')
  details=inspect_stage(.56);motions.add(details['motion']);weapons.add(details['weapon']);assert details['animations']>=6 and details['pointer']=='none';assert details['nodes']<100;assert 'NaN' not in details['actorTransform']
  if (army,role) in [('royal','r'),('elves','r'),('skeletons','q')]:
   pg.screenshot(path=str(OUT/f'{army}-{role}-strike.png'));inspect_stage(.86);pg.screenshot(path=str(OUT/f'{army}-{role}-defeat.png'))
  pg.clock.run_for(details['duration']+40);expect(layer).to_have_count(0);expect(pg.locator(f'.chessboard [data-square={dst}] [data-piece=w{role}]')).to_be_visible()
 assert len(motions)==len(weapons)==18
 results.append({'all18UnitStylesRendered':True,'independentWeapons':True,'actualLegalCaptures':18,'particleNodeBudgetBelow100':True})
 # En passant attacks the pawn's square, then lands on the empty destination.
 for orientation in ['w','b']:
  reset('7k/8/8/3pP3/8/8/8/7K w - d6 0 1',orientation=orientation);move('e5','d6');expect(pg.locator('.battle-2d')).to_have_attribute('data-impact','d5');inspect_stage(0)
  alignment=pg.evaluate("()=>{const a=document.querySelector('.duel-attacker').getBoundingClientRect(),s=document.querySelector('[data-square=e5]').getBoundingClientRect();return Math.hypot(a.x+a.width/2-s.x-s.width/2,a.y+a.height/2-s.y-s.height/2)}")
  assert alignment<3,alignment;pg.clock.run_for(1400);expect(pg.locator('.chessboard [data-square=d6] [data-piece=wp]')).to_be_visible();assert pg.locator('.chessboard [data-square=d5] .miniature-icon').count()==0
 # Capture underpromotion settles into the selected knight, not a queen.
 reset('1r5k/P7/8/8/8/8/8/7K w - - 0 1');move('a7','b8','n');pg.clock.run_for(1400);expect(pg.locator('.chessboard [data-square=b8] [data-piece=wn]')).to_be_visible()
 # Both castling actors move together and stay on their legal squares.
 reset('4k3/8/8/8/8/8/8/R3K2R w KQ - 0 1');move('e1','g1');expect(pg.locator('.moving-miniature')).to_have_count(2);pg.clock.run_for(180);expect(pg.locator('.chessboard [data-square=f1] [data-piece=wr]')).to_be_visible()
 # New moves interrupt cosmetics immediately, without stale victims or deferred board updates.
 fen,src,dst=position('p','b');reset(fen);move(src,dst);move('h8','g8');expect(pg.locator('.battle-2d')).to_have_count(0);pg.clock.run_for(1400);assert pg.locator('.duel-defender').count()==0
 # Checkmate does not capture, remove, or animate a king's death.
 reset('7k/5Q2/6K1/8/8/8/8/8 w - - 0 1');move('f7','g7');expect(pg.locator('.battle-2d')).to_have_count(0);expect(pg.locator('.chessboard [data-square=h8] [data-piece=bk]')).to_be_visible()
 results.append({'enPassantBothOrientations':True,'underpromotion':True,'castlingBothActors':True,'interruptedBattleSettles':True,'checkmateKingSurvives':True})
 # Off, both reduced-motion sources, light mode, and online timing.
 fen,src,dst=position('r','q')
 for options in [{'mode':'off'},{'reducedMotion':True}]:reset(fen,**options);move(src,dst);expect(pg.locator('.battle-2d')).to_have_count(0)
 pg.emulate_media(reduced_motion='reduce');reset(fen);move(src,dst);expect(pg.locator('.battle-2d')).to_have_count(0);pg.emulate_media(reduced_motion='no-preference')
 reset(fen,lightweight=True);move(src,dst);details=inspect_stage(.55);assert details['duration']<=350;assert pg.locator('.duel-fleck-cell').count()==0;assert pg.locator('.battle-2d').is_visible();pg.clock.run_for(400)
 reset(fen,competitive=True);move(src,dst);assert inspect_stage(.55)['duration']<=500;pg.clock.run_for(550);expect(pg.locator('.battle-2d')).to_have_count(0)
 results.append({'offAndReducedMotionImmediate':True,'lightModeStillHasShortFight':True,'onlineDurationUnder500ms':True})
 assert not errors,errors;results.append({'browserErrors':errors});(OUT/'battle2d-checks.json').write_text(json.dumps(results,indent=2));print(json.dumps(results,indent=2));b.close()
