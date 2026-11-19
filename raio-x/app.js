import * as THREE from "three";
import { GLTFLoader } from "./lib/jsm/loaders/GLTFLoader.js";
import { MeshoptDecoder } from "./lib/jsm/libs/meshopt_decoder.module.js";

// ============================================================ settings
const DEF = { layers:{skull:true,brain:true,muscles:false,eyes:true,outline:true,hands:true}, labels:true, look:"xray", bright:0.85, through:0.35,
  size:1, w:1, h:1, dx:0, dy:0, dz:0, track:false };
let S = JSON.parse(JSON.stringify(DEF));
try { const s = JSON.parse(localStorage.getItem("xray3d")||"null"); if (s) S = Object.assign(S, s, {layers:Object.assign({},DEF.layers,s.layers||{})}); } catch(e){}
const save = () => { try { localStorage.setItem("xray3d", JSON.stringify(S)); } catch(e){} };

const $ = id => document.getElementById(id);
const video = $("video"), glc = $("gl"), ov = $("overlay"), ctx = ov.getContext("2d");
const statusEl = $("status");
const setStatus = (t, hide) => { statusEl.textContent = t; statusEl.style.opacity = hide ? 0 : 1; };
let W = innerWidth, H = innerHeight, DPR = Math.min(devicePixelRatio||1, 2);

// ============================================================ UI
function syncUI(){
  document.querySelectorAll("[data-l]").forEach(el => el.checked = !!S.layers[el.dataset.l]);
  $("ckLabels").checked = S.labels; $("ckTrack").checked = S.track;
  document.querySelectorAll("[data-look]").forEach(b => b.classList.toggle("on", b.dataset.look === S.look));
  for (const [id,k] of [["rBright","bright"],["rThrough","through"],["rSize","size"],["rW","w"],["rH","h"],["rDx","dx"],["rDy","dy"],["rDz","dz"]]) $(id).value = S[k];
  $("vSize").textContent = Math.round(S.size*100)+"%"; $("vW").textContent = Math.round(S.w*100)+"%"; $("vH").textContent = Math.round(S.h*100)+"%";
  $("vDx").textContent = S.dx.toFixed(1)+" cm"; $("vDy").textContent = S.dy.toFixed(1)+" cm"; $("vDz").textContent = S.dz.toFixed(1)+" cm";
  const L = S.layers, p = L.skull&&!L.brain&&!L.muscles ? "skull" : !L.skull&&L.brain&&!L.muscles ? "brain" : !L.skull&&!L.brain&&L.muscles ? "muscles" : L.skull&&L.brain&&L.muscles ? "all" : "";
  document.querySelectorAll("[data-preset]").forEach(b => b.classList.toggle("on", b.dataset.preset === p));
  glc.classList.toggle("xray", S.look === "xray");
  if (S.look === "xray") {
    video.style.filter = "grayscale(1) contrast(1.15) brightness(" + (0.5 + S.through*0.7).toFixed(2) + ")";
    $("tint").style.opacity = (1 - S.through).toFixed(2); glc.style.opacity = 1;
  } else {
    video.style.filter = "none"; $("tint").style.opacity = 0;
    glc.style.opacity = (1 - S.through*0.75).toFixed(2);
  }
  applyLook();
  save();
}
document.querySelectorAll("[data-l]").forEach(el => el.onchange = () => { S.layers[el.dataset.l] = el.checked; syncUI(); });
document.querySelectorAll("[data-preset]").forEach(b => b.onclick = () => { const p = b.dataset.preset;
  S.layers.skull = p==="skull"||p==="all"; S.layers.brain = p==="brain"||p==="all"; S.layers.muscles = p==="muscles"||p==="all"; syncUI(); });
document.querySelectorAll("[data-look]").forEach(b => b.onclick = () => { S.look = b.dataset.look; syncUI(); });
$("ckLabels").onchange = e => { S.labels = e.target.checked; syncUI(); };
$("ckTrack").onchange = e => { S.track = e.target.checked; syncUI(); };
for (const [id,k] of [["rBright","bright"],["rThrough","through"],["rSize","size"],["rW","w"],["rH","h"],["rDx","dx"],["rDy","dy"],["rDz","dz"]])
  $(id).oninput = e => { S[k] = parseFloat(e.target.value); syncUI(); };
$("btnReset").onclick = () => { Object.assign(S,{size:1,w:1,h:1,dx:0,dy:0,dz:0}); syncUI(); };
$("btnSet").onclick = () => $("sheet").classList.toggle("open");
$("stage").onclick = () => $("sheet").classList.remove("open");

// ============================================================ three.js
const renderer = new THREE.WebGLRenderer({ canvas: glc, alpha: true, antialias: true, preserveDrawingBuffer: true });
renderer.setClearColor(0x000000, 0);
const scene = new THREE.Scene();
const camera = new THREE.OrthographicCamera(0, 1, 0, -1, 1, 40000);
camera.position.set(0, 0, 20000);
scene.add(new THREE.HemisphereLight(0xffffff, 0x554433, 1.4));
const dl = new THREE.DirectionalLight(0xffffff, 1.6); dl.position.set(0.3, 0.6, 1); scene.add(dl);

const xrayMat = (color, base, rim, pow) => new THREE.ShaderMaterial({
  uniforms: { color: { value: new THREE.Color(color) }, base: { value: base }, rim: { value: rim }, pw: { value: pow }, gain: { value: 1 } },
  vertexShader: `varying vec3 vN; void main(){ vN = normalize(normalMatrix * normal); gl_Position = projectionMatrix * modelViewMatrix * vec4(position,1.0); }`,
  fragmentShader: `uniform vec3 color; uniform float base, rim, pw, gain; varying vec3 vN;
    void main(){ float f = 1.0 - abs(normalize(vN).z); float a = base + rim * pow(f, pw); gl_FragColor = vec4(color * a * gain, 1.0); }`,
  transparent: true, depthWrite: false, depthTest: false, blending: THREE.AdditiveBlending, side: THREE.DoubleSide
});
const MATS = {
  xray: {
    bone: xrayMat(0xbfe2ff, 0.045, 0.55, 2.2), teeth: xrayMat(0xffffff, 0.12, 0.6, 1.6), brain: xrayMat(0xff7ab8, 0.05, 0.5, 2.0),
    stem: xrayMat(0xff9ccc, 0.05, 0.5, 2.0), muscle: xrayMat(0xff4a4a, 0.05, 0.45, 1.8), eye: xrayMat(0xffe28a, 0.06, 0.5, 2.0), hand: xrayMat(0xcfeaff, 0.07, 0.6, 2.0)
  },
  solid: {
    bone: new THREE.MeshStandardMaterial({ color: 0xe9dfc6, roughness: 0.75, metalness: 0 }),
    teeth: new THREE.MeshStandardMaterial({ color: 0xfbf8ef, roughness: 0.4 }),
    brain: new THREE.MeshStandardMaterial({ color: 0xe8a3ae, roughness: 0.6 }),
    stem: new THREE.MeshStandardMaterial({ color: 0xd98d9b, roughness: 0.6 }),
    muscle: new THREE.MeshStandardMaterial({ color: 0xb8323a, roughness: 0.55 }),
    eye: new THREE.MeshStandardMaterial({ color: 0xf5f2ea, roughness: 0.3 }),
    hand: new THREE.MeshStandardMaterial({ color: 0xece2c8, roughness: 0.7 })
  }
};
const MATKEY = { skull:"bone", mandible:"bone", teeth_up:"teeth", teeth_lo:"teeth", brain:"brain", brainstem:"stem", muscles:"muscle", eyes:"eye" };
const ORDER = { brain:1, brainstem:1, eyes:2, skull:3, mandible:3, teeth_up:4, teeth_lo:4, muscles:5 };

const headRoot = new THREE.Group(); headRoot.matrixAutoUpdate = false; scene.add(headRoot);
const fitGroup = new THREE.Group(); fitGroup.matrixAutoUpdate = false; headRoot.add(fitGroup);
const jaw = new THREE.Group(); jaw.matrixAutoUpdate = false; fitGroup.add(jaw);
const parts = {};      // name -> Object3D
const handSlots = [];  // [{root, palm, bones:{name:obj}}]
let ANAT = null;
const allMeshes = [];

function setMat(obj, key){ obj.traverse(o => { if (o.isMesh) { o.userData.mk = key; allMeshes.push(o); } }); }
function applyLook(){
  const M = MATS[S.look === "xray" ? "xray" : "solid"];
  for (const m of allMeshes) { m.material = M[m.userData.mk]; m.renderOrder = m.userData.ro || 0; }
  for (const k in MATS.xray) MATS.xray[k].uniforms.gain.value = S.bright * 1.25;
  renderer.toneMappingExposure = 1;
}
function prepGeom(root){ root.traverse(o => { if (o.isMesh) { if (!o.geometry.attributes.normal) o.geometry.computeVertexNormals(); o.frustumCulled = false; } }); }

async function loadModels(){
  const loader = new GLTFLoader(); loader.setMeshoptDecoder(MeshoptDecoder);
  const [anat, head, hand] = await Promise.all([
    fetch("models/anat.json").then(r => r.json()),
    loader.loadAsync("models/head.glb"),
    loader.loadAsync("models/hand.glb")
  ]);
  ANAT = anat;
  CANON = anat.pts.map(p => new THREE.Vector3(p[0], p[1], p[2]));
  prepGeom(head.scene); prepGeom(hand.scene);
  for (const name of Object.keys(MATKEY)) {
    const n = head.scene.getObjectByName(name); if (!n) continue;
    (name === "mandible" || name === "teeth_lo" ? jaw : fitGroup).add(n);
    setMat(n, MATKEY[name]); n.traverse(o => { if (o.isMesh) o.userData.ro = ORDER[name]; });
    parts[name] = n;
  }
  const PV = anat.head.pivot; PIVOT.set(PV[0], PV[1], PV[2]);
  for (let k = 0; k < 2; k++) {
    const root = new THREE.Group(); scene.add(root); root.visible = false;
    const slot = { root, bones:{} };
    hand.scene.children.slice().forEach(n => {
      const c = n.clone(true); c.matrixAutoUpdate = false; root.add(c); slot.bones[n.name] = c;
      c.traverse(o => { if (o.isMesh) { o.userData.mk = "hand"; o.userData.ro = 6; allMeshes.push(o); } });
    });
    handSlots.push(slot);
  }
  applyLook();
}

// ============================================================ math: similarity fit (Horn / quaternion)
let CANON = null;
const PIVOT = new THREE.Vector3();
function jacobiEig4(A){ // symmetric 4x4 -> largest eigenvector
  const a = A.map(r => r.slice()), v = [[1,0,0,0],[0,1,0,0],[0,0,1,0],[0,0,0,1]];
  for (let sweep = 0; sweep < 30; sweep++) {
    let off = 0; for (let i=0;i<4;i++) for (let j=i+1;j<4;j++) off += a[i][j]*a[i][j];
    if (off < 1e-18) break;
    for (let p=0;p<3;p++) for (let q=p+1;q<4;q++) {
      if (Math.abs(a[p][q]) < 1e-20) continue;
      const th = (a[q][q]-a[p][p])/(2*a[p][q]); const t = Math.sign(th||1)/(Math.abs(th)+Math.sqrt(th*th+1));
      const c = 1/Math.sqrt(t*t+1), s = t*c;
      for (let k=0;k<4;k++){ const akp=a[k][p], akq=a[k][q]; a[k][p]=c*akp-s*akq; a[k][q]=s*akp+c*akq; }
      for (let k=0;k<4;k++){ const apk=a[p][k], aqk=a[q][k]; a[p][k]=c*apk-s*aqk; a[q][k]=s*apk+c*aqk; }
      for (let k=0;k<4;k++){ const vkp=v[k][p], vkq=v[k][q]; v[k][p]=c*vkp-s*vkq; v[k][q]=s*vkp+c*vkq; }
    }
  }
  let bi = 0; for (let i=1;i<4;i++) if (a[i][i] > a[bi][bi]) bi = i;
  return [v[0][bi], v[1][bi], v[2][bi], v[3][bi]];
}
const _q = new THREE.Quaternion();
function fitSimilarity(src, dst){ // returns {s, q, t} with dst ≈ s R src + t
  const n = src.length; const cs = new THREE.Vector3(), cd = new THREE.Vector3();
  for (let i=0;i<n;i++){ cs.add(src[i]); cd.add(dst[i]); } cs.multiplyScalar(1/n); cd.multiplyScalar(1/n);
  let Sxx=0,Sxy=0,Sxz=0,Syx=0,Syy=0,Syz=0,Szx=0,Szy=0,Szz=0, ss=0;
  for (let i=0;i<n;i++){ const ax=src[i].x-cs.x, ay=src[i].y-cs.y, az=src[i].z-cs.z, bx=dst[i].x-cd.x, by=dst[i].y-cd.y, bz=dst[i].z-cd.z;
    Sxx+=ax*bx;Sxy+=ax*by;Sxz+=ax*bz;Syx+=ay*bx;Syy+=ay*by;Syz+=ay*bz;Szx+=az*bx;Szy+=az*by;Szz+=az*bz; ss+=ax*ax+ay*ay+az*az; }
  const N = [[Sxx+Syy+Szz, Syz-Szy, Szx-Sxz, Sxy-Syx],[Syz-Szy, Sxx-Syy-Szz, Sxy+Syx, Szx+Sxz],[Szx-Sxz, Sxy+Syx, -Sxx+Syy-Szz, Syz+Szy],[Sxy-Syx, Szx+Sxz, Syz+Szy, -Sxx-Syy+Szz]];
  const e = jacobiEig4(N); const q = new THREE.Quaternion(e[1], e[2], e[3], e[0]).normalize();
  let sd = 0; const r = new THREE.Vector3();
  for (let i=0;i<n;i++){ r.set(src[i].x-cs.x, src[i].y-cs.y, src[i].z-cs.z).applyQuaternion(q); sd += r.x*(dst[i].x-cd.x)+r.y*(dst[i].y-cd.y)+r.z*(dst[i].z-cd.z); }
  const s = sd/ss; const t = cd.clone().sub(cs.clone().applyQuaternion(q).multiplyScalar(s));
  return { s, q, t };
}

// ============================================================ tracking -> pose
let vw = 1280, vh = 720, mirror = true;
let face2D = null, pose = null, jawAngle = 0, jawBase = null;
let handsData = [];
const toVP = l => new THREE.Vector3(l.x*vw, -l.y*vh, -l.z*vw);
const poseState = { s:0, q:new THREE.Quaternion(), t:new THREE.Vector3(), init:false };
const _m = new THREE.Matrix4(), _m2 = new THREE.Matrix4();

function updateFace(lms){
  if (!lms) { pose = null; face2D = null; return; }
  const dst = ANAT.idx.map(i => toVP(lms[i]));
  const f = fitSimilarity(CANON, dst);
  // smoothing
  const a = 0.55;
  if (!poseState.init) { poseState.s = f.s; poseState.q.copy(f.q); poseState.t.copy(f.t); poseState.init = true; }
  else { poseState.s += (f.s - poseState.s)*a; poseState.q.slerp(f.q, a); poseState.t.lerp(f.t, a); }
  pose = poseState;
  headRoot.matrix.compose(pose.t, pose.q, new THREE.Vector3(pose.s, pose.s, pose.s));
  headRoot.matrixWorldNeedsUpdate = true;
  // jaw: chin landmark in canonical space
  const chin = toVP(lms[152]).sub(pose.t).applyQuaternion(pose.q.clone().invert()).multiplyScalar(1/pose.s);
  const C0 = ANAT.chin;
  const ang = Math.atan2(chin.z - PIVOT.z, chin.y - PIVOT.y) - Math.atan2(C0[2] - PIVOT.z, C0[1] - PIVOT.y);
  // ang: rotation about +X; opening the mouth (chin down and back) is positive
  const open = ang;
  if (jawBase === null) jawBase = open;
  if (open < jawBase) jawBase = open; else jawBase += (open - jawBase) * 0.003;
  const target = Math.max(0, Math.min(0.6, (open - jawBase) * 1.15));
  jawAngle += (target - jawAngle) * 0.6;
  // face 2D (screen) for outline
  face2D = lms;
}

function updateFit(){
  const sc = new THREE.Vector3(S.size*S.w, S.size*S.h, S.size);
  fitGroup.matrix.compose(new THREE.Vector3(S.dx, S.dy, S.dz), new THREE.Quaternion(), sc);
  // jaw rotation about pivot (axis X), opening = chin goes down & back
  _m.makeTranslation(PIVOT.x, PIVOT.y, PIVOT.z);
  _m2.makeRotationX(jawAngle);
  jaw.matrix.copy(_m).multiply(_m2).multiply(_m.clone().makeTranslation(-PIVOT.x, -PIVOT.y, -PIVOT.z));
}

// ---- hands
const _X = new THREE.Vector3(), _Y = new THREE.Vector3(), _Z = new THREE.Vector3();
function setSeg(obj, p0, p1, nrm, right){
  _Y.subVectors(p1, p0); const L = _Y.length(); if (L < 1e-3) { obj.visible = false; return; } obj.visible = true;
  _Y.multiplyScalar(1/L);
  _Z.copy(nrm).addScaledVector(_Y, -nrm.dot(_Y)).normalize();
  _X.crossVectors(_Y, _Z); if (!right) _X.negate();
  obj.matrix.set(_X.x*L, _Y.x*L, _Z.x*L, p0.x,  _X.y*L, _Y.y*L, _Z.y*L, p0.y,  _X.z*L, _Y.z*L, _Z.z*L, p0.z,  0,0,0,1);
  obj.matrixWorldNeedsUpdate = true;
}
function updateHands(list){
  handSlots.forEach((sl, k) => {
    const h = list[k];
    if (!h || !S.layers.hands) { sl.root.visible = false; return; }
    sl.root.visible = true;
    const P = h.lm.map(toVP), right = h.right;
    const O = P[0], u = P[9].clone().sub(O); const s = u.length(); u.normalize();
    const side = P[5].clone().sub(P[17]); side.addScaledVector(u, -side.dot(u)).normalize();
    const n = new THREE.Vector3().crossVectors(u, side);
    const nn = right ? n : n.clone().negate();
    const palmPt = p => O.clone().addScaledVector(u, p[0]*s).addScaledVector(side, p[1]*s).addScaledVector(nn, p[2]*s);
    const pm = sl.bones.palm;
    pm.matrix.set(u.x*s, side.x*s, nn.x*s, O.x,  u.y*s, side.y*s, nn.y*s, O.y,  u.z*s, side.z*s, nn.z*s, O.z,  0,0,0,1);
    pm.matrixWorldNeedsUpdate = true;
    const B = ANAT.hand.bones;
    // thumb: metacarpal L1->L2, proximal L2->L3, distal L3->L4
    setSeg(sl.bones.f1_0, P[1], P[2], n, right); setSeg(sl.bones.f1_1, P[2], P[3], n, right); setSeg(sl.bones.f1_2, P[3], P[4], n, right);
    const MCP = [5, 9, 13, 17];
    for (let fi = 2; fi <= 5; fi++) {
      const b = MCP[fi-2];
      setSeg(sl.bones[`f${fi}_0`], palmPt(B[`f${fi}_0`].p0palm), P[b], n, right);
      setSeg(sl.bones[`f${fi}_1`], P[b], P[b+1], n, right);
      setSeg(sl.bones[`f${fi}_2`], P[b+1], P[b+2], n, right);
      setSeg(sl.bones[`f${fi}_3`], P[b+2], P[b+3], n, right);
    }
    h.P = P; h.palmPt = palmPt;
  });
}

// ============================================================ view / projection
let disp = { s:1, ox:0, oy:0 };
function layout(){
  W = innerWidth; H = innerHeight; DPR = Math.min(devicePixelRatio||1, 2);
  renderer.setPixelRatio(DPR); renderer.setSize(W, H, false);
  ov.width = Math.round(W*DPR); ov.height = Math.round(H*DPR);
  const s = Math.max(W/vw, H/vh); disp = { s, ox:(W - vw*s)/2, oy:(H - vh*s)/2 };
  camera.left = -disp.ox/s; camera.right = (W - disp.ox)/s; camera.top = disp.oy/s; camera.bottom = -(H - disp.oy)/s;
  camera.updateProjectionMatrix();
}
addEventListener("resize", () => { layout(); render(); });
const vpToScreen = v => { let x = disp.ox + v.x*disp.s; if (mirror) x = W - x; return [x, disp.oy - v.y*disp.s]; };
const lmToScreen = l => { let x = disp.ox + l.x*vw*disp.s; if (mirror) x = W - x; return [x, disp.oy + l.y*vh*disp.s]; };

// ============================================================ render
const GROUP_OF = { skull:"skull", mandible:"skull", teeth_up:"skull", teeth_lo:"skull", brain:"brain", brainstem:"brain", muscles:"muscles", eyes:"eyes" };
function render(){
  const haveFace = !!pose;
  headRoot.visible = haveFace;
  for (const k in parts) parts[k].visible = !!S.layers[GROUP_OF[k]];
  if (haveFace) updateFit();
  glc.classList.toggle("mirror", mirror);
  renderer.render(scene, camera);
  // 2D overlay
  ctx.setTransform(1,0,0,1,0,0); ctx.clearRect(0,0,ov.width,ov.height); ctx.setTransform(DPR,0,0,DPR,0,0);
  if (haveFace && S.layers.outline && face2D) drawOutline();
  if (S.track) drawTrack();
  if (S.labels) drawLabels();
}

const FACE_OVAL = [10,338,297,332,284,251,389,356,454,323,361,288,397,365,379,378,400,377,152,148,176,149,150,136,172,58,132,93,234,127,162,21,54,103,67,109];
function drawOutline(){
  const pts = FACE_OVAL.map(i => lmToScreen(face2D[i]));
  const i0 = FACE_OVAL.indexOf(454), i1 = FACE_OVAL.indexOf(234);
  const jawLine = pts.slice(i0, i1+1);
  ctx.save(); ctx.strokeStyle = S.look === "xray" ? "rgba(70,130,255,0.95)" : "rgba(60,120,255,0.85)"; ctx.lineWidth = 3; ctx.lineJoin = ctx.lineCap = "round";
  ctx.shadowColor = "rgba(60,120,255,0.8)"; ctx.shadowBlur = 8;
  ctx.beginPath(); ctx.moveTo(jawLine[0][0], jawLine[0][1]);
  for (let i=1;i<jawLine.length-1;i++){ const m = [(jawLine[i][0]+jawLine[i+1][0])/2,(jawLine[i][1]+jawLine[i+1][1])/2]; ctx.quadraticCurveTo(jawLine[i][0],jawLine[i][1],m[0],m[1]); }
  ctx.stroke();
  // circle around head like the reference
  const top = canonToScreen([0, 17.5, -3]), mid = canonToScreen([0, 3, -3]);
  const r = Math.hypot(top[0]-mid[0], top[1]-mid[1]) * 1.02;
  ctx.shadowBlur = 0; ctx.strokeStyle = "rgba(200,220,255,0.35)"; ctx.lineWidth = 1;
  ctx.beginPath(); ctx.arc(mid[0], mid[1], r, 0, 7); ctx.stroke();
  ctx.restore();
}
const _v = new THREE.Vector3();
function canonToScreen(p, jawPt){
  _v.set(p[0], p[1], p[2]);
  if (jawPt) _v.applyMatrix4(jaw.matrix);
  _v.applyMatrix4(fitGroup.matrix).applyMatrix4(headRoot.matrix);
  return vpToScreen(_v);
}

function drawTrack(){
  ctx.fillStyle = "rgba(120,255,200,0.85)";
  if (face2D) for (const l of face2D) { const p = lmToScreen(l); ctx.fillRect(p[0]-.8,p[1]-.8,1.6,1.6); }
  ctx.fillStyle = "rgba(255,220,120,0.95)";
  for (const h of handsData) for (const l of h.lm) { const p = lmToScreen(l); ctx.beginPath(); ctx.arc(p[0],p[1],2.2,0,7); ctx.fill(); }
}

function drawLabels(){
  const items = [];
  let cx = W/2, minX = W, maxX = 0;
  if (pose && ANAT) {
    const c = canonToScreen([0,3,0]); cx = c[0];
    for (const sx of [-7.5, 7.5]) { const p = canonToScreen([sx, 3, 0]); minX = Math.min(minX, p[0]); maxX = Math.max(maxX, p[0]); }
    for (const L of ANAT.head.labels) {
      if (!S.layers[L.g]) continue;
      if (L.d) { _v.set(L.d[0], L.d[1], L.d[2]).applyQuaternion(pose.q); if (_v.z < -0.2) continue; }
      items.push({ p: canonToScreen(L.p, L.jaw), t: L.t });
    }
  }
  handsData.forEach((h, k) => {
    if (k > 0 || !h.P || !S.layers.hands) return;
    const P = h.P, mid = (a,b) => vpToScreen(P[a].clone().lerp(P[b], .5));
    items.push({p: mid(7,8), t:"Falange distal"}, {p: mid(6,7), t:"Falange média"}, {p: mid(5,6), t:"Falange proximal"},
      {p: vpToScreen(h.palmPt([0.55, 0.15, 0])), t:"Metacarpo"}, {p: vpToScreen(h.palmPt([0.12, 0, 0])), t:"Carpo"},
      {p: vpToScreen(h.palmPt([-0.35, 0.25, 0])), t:"Rádio"}, {p: vpToScreen(h.palmPt([-0.35, -0.3, 0])), t:"Ulna"});
    for (const pp of items.slice(-7)) { minX = Math.min(minX, pp.p[0]); maxX = Math.max(maxX, pp.p[0]); }
  });
  if (!items.length) return;
  ctx.font = "600 10.5px -apple-system,BlinkMacSystemFont,Segoe UI,Roboto,sans-serif"; ctx.textBaseline = "middle";
  const left = [], right = [];
  for (const l of items) { if (l.p[0] < -40 || l.p[0] > W+40 || l.p[1] < -40 || l.p[1] > H+40) continue; (l.p[0] < cx ? left : right).push(l); }
  const top = 64, bottom = H - 16, gap = 15;
  const lay = arr => { arr.sort((a,b)=>a.p[1]-b.p[1]); let y = top; for (const l of arr) { l.y = Math.max(y, Math.min(bottom, l.p[1])); y = l.y + gap; }
    for (let i = arr.length-1; i >= 0; i--) { const lim = i === arr.length-1 ? bottom : arr[i+1].y - gap; if (arr[i].y > lim) arr[i].y = lim; } };
  lay(left); lay(right);
  const pad = 6;
  const draw = (arr, isLeft) => { for (const l of arr) {
    const tw = ctx.measureText(l.t).width;
    let x = isLeft ? Math.min(minX - 12, l.p[0] - 16) : Math.max(maxX + 12, l.p[0] + 16);
    x = isLeft ? Math.max(pad + tw, x) : Math.min(W - pad - tw, x);
    ctx.strokeStyle = "rgba(220,235,255,0.7)"; ctx.lineWidth = 0.8;
    ctx.beginPath(); ctx.moveTo(l.p[0], l.p[1]); ctx.lineTo(isLeft ? x + 4 : x - 4, l.y); ctx.stroke();
    ctx.fillStyle = "#fff"; ctx.beginPath(); ctx.arc(l.p[0], l.p[1], 1.8, 0, 7); ctx.fill();
    ctx.fillStyle = "rgba(4,8,16,0.6)"; ctx.fillRect(isLeft ? x - tw - 4 : x - 4, l.y - 7.5, tw + 8, 15);
    ctx.fillStyle = "#f2f7ff"; ctx.textAlign = isLeft ? "right" : "left"; ctx.fillText(l.t, x, l.y + .5);
  } };
  draw(left, true); draw(right, false);
}

// ============================================================ MediaPipe + camera
const MP = "https://cdn.jsdelivr.net/npm/@mediapipe/tasks-vision@0.10.14";
let faceLm = null, handLm = null, running = false, lastVT = -1, frameN = 0, slow = false, faceSeen = 0, handsSeen = 0;
async function loadTrackers(){
  const { FilesetResolver, FaceLandmarker, HandLandmarker } = await import(MP + "/vision_bundle.mjs");
  const fs = await FilesetResolver.forVisionTasks(MP + "/wasm");
  const mk = async delegate => {
    faceLm = await FaceLandmarker.createFromOptions(fs, { baseOptions:{ modelAssetPath:"https://storage.googleapis.com/mediapipe-models/face_landmarker/face_landmarker/float16/1/face_landmarker.task", delegate }, runningMode:"VIDEO", numFaces:1 });
    handLm = await HandLandmarker.createFromOptions(fs, { baseOptions:{ modelAssetPath:"https://storage.googleapis.com/mediapipe-models/hand_landmarker/hand_landmarker/float16/1/hand_landmarker.task", delegate }, runningMode:"VIDEO", numHands:2 });
  };
  try { await mk("GPU"); } catch(e) { console.warn("GPU falhou, usando CPU", e); await mk("CPU"); }
}
let stream = null, facing = "user";
async function startCamera(){
  if (stream) stream.getTracks().forEach(t => t.stop());
  stream = await navigator.mediaDevices.getUserMedia({ audio:false, video:{ facingMode:facing, width:{ideal:1280}, height:{ideal:720} } });
  video.srcObject = stream; await video.play().catch(()=>{});
  await new Promise(r => { if (video.videoWidth) r(); else video.onloadedmetadata = () => r(); });
  vw = video.videoWidth; vh = video.videoHeight;
  mirror = facing === "user"; video.classList.toggle("mirror", mirror);
  poseState.init = false; pose = null; jawBase = null; layout();
}
let fpsT = performance.now(), fpsN = 0;
function loop(){
  if (!running) return;
  requestAnimationFrame(loop);
  if (video.videoWidth && (video.videoWidth !== vw || video.videoHeight !== vh)) { vw = video.videoWidth; vh = video.videoHeight; layout(); }
  if (video.readyState >= 2 && video.currentTime !== lastVT && faceLm) {
    lastVT = video.currentTime; frameN++;
    const t0 = performance.now();
    try {
      const fr = faceLm.detectForVideo(video, t0);
      if (fr.faceLandmarks && fr.faceLandmarks.length) { updateFace(fr.faceLandmarks[0]); faceSeen = t0; }
      else if (t0 - faceSeen > 300) { updateFace(null); poseState.init = false; }
      if (S.layers.hands && (!slow || frameN % 2 === 0)) {
        const hr = handLm.detectForVideo(video, t0 + 0.1);
        const nh = (hr.landmarks || []).map((lm, i) => {
          const lab = ((hr.handedness || hr.handednesses || [])[i] || [])[0];
          // MediaPipe assumes a mirrored image; our frame is not mirrored, so its label is swapped
          const right = lab ? lab.categoryName === "Left" : true;
          return { lm: smoothHand(i, lm), right };
        });
        if (nh.length) { handsData = nh; handsSeen = t0; } else if (t0 - handsSeen > 300) handsData = [];
      }
      updateHands(handsData);
    } catch(e) { console.error(e); }
    slow = performance.now() - t0 > 34;
    fpsN++; const now = performance.now(); if (now - fpsT > 1000) { $("fps").textContent = fpsN + " fps"; fpsN = 0; fpsT = now; }
    if (!pose && !handsData.length) setStatus("Procurando seu rosto…"); else setStatus("", true);
  }
  render();
}
const handPrev = [];
function smoothHand(i, lm){
  const p = handPrev[i]; const out = lm.map(l => ({x:l.x, y:l.y, z:l.z}));
  if (p && p.length === out.length) for (let k=0;k<out.length;k++){ out[k].x = p[k].x + (out[k].x-p[k].x)*.65; out[k].y = p[k].y + (out[k].y-p[k].y)*.65; out[k].z = p[k].z + (out[k].z-p[k].z)*.5; }
  handPrev[i] = out; return out;
}

$("go").onclick = async () => {
  $("go").disabled = true; $("err").textContent = "";
  try {
    if (!navigator.mediaDevices || !navigator.mediaDevices.getUserMedia) throw new Error("Este navegador não libera a câmera aqui. Abra o link direto no Safari ou Chrome (precisa ser https).");
    $("go").textContent = "Abrindo câmera…";
    await startCamera();
    $("start").style.display = "none";
    setStatus("Carregando modelos 3D…");
    await Promise.all([modelsReady, loadTrackers()]);
    setStatus("Procurando seu rosto…");
    running = true; loop();
  } catch(e) {
    console.error(e); $("go").disabled = false; $("go").textContent = "Tentar de novo"; $("start").style.display = "flex";
    $("err").textContent = (e && e.name === "NotAllowedError") ? "Permissão da câmera negada. Libere a câmera para este site nos ajustes do navegador e tente de novo." : (e.message || String(e));
  }
};
$("btnFlip").onclick = async () => { facing = facing === "user" ? "environment" : "user"; try { await startCamera(); } catch(e) { setStatus("Não foi possível trocar a câmera"); } };

// photo
$("btnShot").onclick = async () => {
  const cv = document.createElement("canvas"); cv.width = Math.round(W*DPR); cv.height = Math.round(H*DPR); const g = cv.getContext("2d");
  const s = disp.s*DPR, ox = disp.ox*DPR, oy = disp.oy*DPR;
  g.save(); if (mirror) { g.translate(cv.width, 0); g.scale(-1, 1); }
  if (S.look === "xray" && "filter" in g) g.filter = video.style.filter;
  if (video.videoWidth) g.drawImage(video, ox, oy, vw*s, vh*s);
  g.filter = "none";
  g.restore();
  g.globalAlpha = parseFloat($("tint").style.opacity || 0); g.fillStyle = "#04080f"; g.fillRect(0,0,cv.width,cv.height); g.globalAlpha = 1;
  render();
  g.save(); if (mirror) { g.translate(cv.width, 0); g.scale(-1, 1); }
  if (S.look === "xray") g.globalCompositeOperation = "screen"; else g.globalAlpha = parseFloat(glc.style.opacity || 1);
  g.drawImage(glc, 0, 0, cv.width, cv.height); g.restore();
  g.globalAlpha = 1; g.globalCompositeOperation = "source-over"; g.drawImage(ov, 0, 0);
  $("flash").style.opacity = .8; setTimeout(() => $("flash").style.opacity = 0, 120);
  const blob = await new Promise(r => cv.toBlob(r, "image/jpeg", 0.92));
  const file = new File([blob], "raio-x.jpg", { type:"image/jpeg" });
  if (navigator.canShare && navigator.canShare({ files:[file] })) { try { await navigator.share({ files:[file], title:"Espelho Raio-X" }); return; } catch(e) { if (e.name === "AbortError") return; } }
  $("shotImg").src = URL.createObjectURL(blob); $("shot").style.display = "flex";
};
$("shotClose").onclick = () => $("shot").style.display = "none";

// ============================================================ boot
const modelsReady = loadModels().catch(e => { console.error(e); $("err").textContent = "Falha ao carregar os modelos 3D: " + e.message; throw e; });
layout(); syncUI();

// test hook (offline rendering checks)
window.__xr = {
  S, syncUI, ready: modelsReady,
  frame(faceLms, hands, w, h){ vw = w; vh = h; layout(); poseState.init = false; jawBase = 0; jawAngle = 0;
    if (faceLms) { updateFace(faceLms); for (let i=0;i<8;i++) updateFace(faceLms); } else updateFace(null);
    handsData = (hands||[]).map(x => ({ lm:x.lm, right:x.right })); updateHands(handsData); render(); }
};
