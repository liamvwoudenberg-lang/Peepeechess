"""Render readable 2D illustrations from the shared 3D character designs.
Start Vite with npm run dev, then run python scripts/render-pieces.py.
"""
from pathlib import Path
import os,base64
from playwright.sync_api import sync_playwright
with sync_playwright() as p:
 browser=p.chromium.launch(executable_path=os.environ.get('CHROMIUM','/usr/bin/chromium'),headless=True,args=['--no-sandbox','--enable-unsafe-swiftshader'])
 page=browser.new_page(viewport={'width':900,'height':900})
 page.goto(os.environ.get('BASE_URL','http://localhost:3000'),wait_until='domcontentloaded')
 result=page.evaluate('''async()=>{
 const THREE=await import('/node_modules/.vite/deps/three.js'),{buildArticulatedCharacter,createFactionMaterialRigs}=await import('/src/three/fantasyCharacters.ts');
 const renderer=new THREE.WebGLRenderer({alpha:true,antialias:true,preserveDrawingBuffer:true}),cell=192;renderer.setSize(cell*6,cell*6);renderer.setPixelRatio(1);renderer.setClearColor(0,0);renderer.outputColorSpace=THREE.SRGBColorSpace;renderer.setScissorTest(true);
 const scene=new THREE.Scene();scene.add(new THREE.HemisphereLight(0xfffbf1,0x8b8392,2));const sun=new THREE.DirectionalLight(0xffffff,2.5);sun.position.set(-3,7,8);scene.add(sun);
 const gradient=new THREE.DataTexture(new Uint8Array([105,105,105,255,180,180,180,255,230,230,230,255,255,255,255,255]),4,1);gradient.magFilter=THREE.NearestFilter;gradient.minFilter=THREE.NearestFilter;gradient.needsUpdate=true;
 const camera=new THREE.OrthographicCamera(-1,1,1,-1,.1,30),roles=['p','n','b','r','q','k'];let row=0;
 for(const army of ['royal','elves','skeletons']){const rigs=createFactionMaterialRigs(true,army);for(const color of ['w','b']){const mats=new Map();for(const [col,type] of roles.entries()){
  const actor=buildArticulatedCharacter('atlas',type,color,rigs[color],false);actor.shadowDisc.visible=false;actor.dangerAuraMesh.visible=false;actor.root.rotation.y=type==='n'?-Math.PI/2:-.12;
  const parts=[];actor.root.traverse(obj=>{if(obj.isMesh&&obj.visible){const original=obj.material;if(!mats.has(original)){const material=new THREE.MeshToonMaterial({color:original.color,gradientMap:gradient,side:original.side});if(original.emissive){material.emissive.copy(original.emissive);material.emissiveIntensity=.24;}mats.set(original,material);}obj.material=mats.get(original);parts.push(obj);}});
  const outline=new THREE.MeshBasicMaterial({color:color==='w'?0x3f453d:0x10131c,side:THREE.BackSide});for(const part of parts){const shell=new THREE.Mesh(part.geometry,outline);shell.position.copy(part.position);shell.rotation.copy(part.rotation);shell.scale.copy(part.scale).multiplyScalar(1.025);part.parent.add(shell);}
  scene.add(actor.root);const bounds=new THREE.Box3().setFromObject(actor.root),size=bounds.getSize(new THREE.Vector3()),center=bounds.getCenter(new THREE.Vector3()),height={p:.75,n:.87,b:.89,r:.82,q:.92,k:.96}[type],extent=Math.max(size.y/(height*2),size.x/1.78);camera.left=-extent;camera.right=extent;camera.top=extent;camera.bottom=-extent;camera.position.set(center.x,center.y,10);camera.up.set(0,1,0);camera.lookAt(center.x,center.y,0);camera.updateProjectionMatrix();
  const y=(5-row)*cell;renderer.setViewport(col*cell,y,cell,cell);renderer.setScissor(col*cell,y,cell,cell);renderer.clear();renderer.render(scene,camera);scene.remove(actor.root);
 }row++;}}
 const png=renderer.domElement.toDataURL('image/png'),webp=renderer.domElement.toDataURL('image/webp',.94);renderer.dispose();return {png,webp};}''')
 for kind in ['png','webp']:
  path=Path('public/pieces/miniatures-front.'+kind);path.parent.mkdir(parents=True,exist_ok=True);path.write_bytes(base64.b64decode(result[kind].split(',',1)[1]));print(path,path.stat().st_size)
 browser.close()
