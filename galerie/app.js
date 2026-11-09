// Galerie 3D d'ÉCLATS : liste + recherche + filtres, vue 3D (rotation, zoom, recentrage), chargement à la demande.
import * as THREE from 'three';
import { GLTFLoader } from 'three/addons/loaders/GLTFLoader.js';
import { OrbitControls } from 'three/addons/controls/OrbitControls.js';

const $ = (id) => document.getElementById(id);
const FAMILLES = { tous: 'Tous', precuit: 'Précuits', genere: 'Générés', exemple: 'Exemples', manuel: 'Manuels', personnage: 'Personnages' };
const FAMILLE_DE = { personnage: 'personnage', precuit: 'precuit', enregistre: 'precuit', genere: 'genere', exemple: 'exemple', manuel: 'manuel' };

const etat = { catalogue: null, modeles: [], q: '', famille: 'tous', categorie: '', selection: null, chargements: 0, charges: [], erreur: '' };
window.galerieEtat = etat; // lecture seule, utile aux tests automatiques

// ---------------------------------------------------------------- utilitaires
const norm = (s) => String(s ?? '').toLowerCase().normalize('NFD').replace(/[̀-ͯ]/g, '');
const fmtM = (v) => (Math.round(v * 100) / 100).toLocaleString('fr-FR', { minimumFractionDigits: 0, maximumFractionDigits: 2 });
const fmtKo = (ko) => (ko >= 1024 ? (ko / 1024).toLocaleString('fr-FR', { maximumFractionDigits: 1 }) + ' Mo' : ko + ' Ko');
const dims = (m) => (m.dimensions_m ? `${fmtM(m.dimensions_m[0])} × ${fmtM(m.dimensions_m[1])} × ${fmtM(m.dimensions_m[2])} m` : 'non renseignées');
const famille = (m) => FAMILLE_DE[m.famille] || 'precuit';
const el = (tag, attrs = {}, ...kids) => {
	const e = document.createElement(tag);
	for (const [k, v] of Object.entries(attrs)) {
		if (k === 'class') e.className = v; else if (k.startsWith('on')) e.addEventListener(k.slice(2), v); else if (v !== false && v != null) e.setAttribute(k, v === true ? '' : v);
	}
	for (const kid of kids) e.append(kid instanceof Node ? kid : document.createTextNode(String(kid)));
	return e;
};

function hauteurEntete() {
	document.documentElement.style.setProperty('--haut-h', document.querySelector('.haut').offsetHeight + 'px');
}
addEventListener('resize', hauteurEntete);

// ---------------------------------------------------------------- vue 3D
const toile = $('toile');
const renderer = new THREE.WebGLRenderer({ canvas: toile, antialias: true, alpha: true, powerPreference: 'default' });
renderer.setPixelRatio(Math.min(devicePixelRatio || 1, 2));
renderer.outputColorSpace = THREE.SRGBColorSpace;
renderer.toneMapping = THREE.ACESFilmicToneMapping;
renderer.toneMappingExposure = 1.05;
const scene = new THREE.Scene();
const camera = new THREE.PerspectiveCamera(38, 1, 0.05, 500);
const controls = new OrbitControls(camera, toile);
controls.enableDamping = true;
controls.dampingFactor = 0.12;
controls.screenSpacePanning = true;
controls.maxPolarAngle = Math.PI * 0.98;

scene.add(new THREE.HemisphereLight(0xdfe8ff, 0x6b5a45, 1.15));
const soleil = new THREE.DirectionalLight(0xfff1d6, 2.6);
soleil.position.set(4, 8, 5);
scene.add(soleil);
const contre = new THREE.DirectionalLight(0x9db8ff, 0.7);
contre.position.set(-5, 3, -4);
scene.add(contre);

const sol = new THREE.Group();
scene.add(sol);
let objet = null;
let cadrage = { cible: new THREE.Vector3(), position: new THREE.Vector3(), taille: 1 };

function majSol(taille) {
	sol.clear();
	const demi = Math.max(taille * 1.4, 1.5);
	const grille = new THREE.GridHelper(demi * 2, Math.round(demi * 2), 0x8a8f96, 0x8a8f96);
	grille.material.transparent = true;
	grille.material.opacity = 0.35;
	grille.material.depthWrite = false;
	sol.add(grille);
}

function redim() {
	const r = $('vue').getBoundingClientRect();
	const w = Math.max(1, Math.round(r.width)), h = Math.max(1, Math.round(r.height));
	renderer.setSize(w, h, false);
	camera.aspect = w / h;
	camera.updateProjectionMatrix();
}
new ResizeObserver(redim).observe($('vue'));

function recentrer(immediat = true) {
	camera.position.copy(cadrage.position);
	controls.target.copy(cadrage.cible);
	controls.minDistance = cadrage.taille * 0.25;
	controls.maxDistance = cadrage.taille * 8;
	camera.near = Math.max(cadrage.taille / 500, 0.01);
	camera.far = cadrage.taille * 60;
	camera.updateProjectionMatrix();
	controls.update();
}

const horloge = new THREE.Clock();
let mixeur = null, actions = new Map(), clipActif = '';

function jouer(id) {
	clipActif = id;
	for (const [k, a] of actions) {
		if (k === id) { a.reset().fadeIn(0.2).play(); } else a.fadeOut(0.2);
	}
	for (const b of $('anims').querySelectorAll('button')) b.setAttribute('aria-pressed', String(b.dataset.clip === id));
	etat.clip = id;
}

function animations(m, racine, clips) {
	mixeur?.stopAllAction(); mixeur = null; actions = new Map(); clipActif = '';
	const zone = $('anims');
	zone.replaceChildren();
	const liste = m.animations || [];
	zone.hidden = !liste.length;
	if (!liste.length) return;
	mixeur = new THREE.AnimationMixer(racine);
	for (const a of liste) {
		const clip = clips.find((c) => c.name === a.id);
		if (!clip) continue;
		actions.set(a.id, mixeur.clipAction(clip));
		zone.append(el('button', { type: 'button', 'data-clip': a.id, 'aria-pressed': 'false', title: `${a.nom} (boucle de ${a.duree_s} s)`, onclick: () => jouer(a.id) }, a.nom));
	}
	zone.append(el('button', { type: 'button', 'data-clip': '', 'aria-pressed': 'false', title: 'Pose de repos', onclick: () => { mixeur.stopAllAction(); clipActif = ''; etat.clip = ''; for (const b of zone.querySelectorAll('button')) b.setAttribute('aria-pressed', String(b.dataset.clip === '')); } }, 'Repos'));
	if (actions.has('idle')) jouer('idle'); else jouer(actions.keys().next().value);
}

function boucle() {
	if (mixeur) mixeur.update(horloge.getDelta()); else horloge.getDelta();
	controls.update();
	renderer.render(scene, camera);
	requestAnimationFrame(boucle);
}

// --- matériaux : couleur du jeu + occlusion (COLOR_0), émission / rugosité / métal (UV) ---
const materiaux = new Map();
function materielJeu(nom) {
	if (!materiaux.has(nom)) {
		const m = new THREE.MeshStandardMaterial({ vertexColors: true, roughness: 0.9, metalness: 0, side: THREE.FrontSide });
		m.name = nom;
		m.onBeforeCompile = (s) => {
			s.vertexShader = s.vertexShader
				.replace('#include <common>', '#include <common>\nattribute vec3 aMat;\nvarying vec3 vMat;')
				.replace('#include <begin_vertex>', '#include <begin_vertex>\nvMat = aMat;');
			s.fragmentShader = s.fragmentShader
				.replace('#include <common>', '#include <common>\nvarying vec3 vMat;')
				.replace('#include <roughnessmap_fragment>', 'float roughnessFactor = clamp(vMat.y, 0.05, 1.0);')
				.replace('#include <metalnessmap_fragment>', 'float metalnessFactor = clamp(vMat.z, 0.0, 1.0);')
				.replace('#include <emissivemap_fragment>', 'totalEmissiveRadiance = diffuseColor.rgb * min(vMat.x, 3.0) * 0.9;');
		};
		materiaux.set(nom, m);
	}
	return materiaux.get(nom);
}

function preparer(racine) {
	racine.traverse((o) => {
		if (!o.isMesh) return;
		const g = o.geometry;
		const c = g.getAttribute('color');
		const n = g.attributes.position.count;
		if (c) {
			const rgb = new Float32Array(n * 3);
			for (let i = 0; i < n; i++) {
				const a = c.itemSize === 4 ? c.getW(i) : 1; // alpha = occlusion ambiante dans le jeu
				const k = 0.55 + 0.45 * a;
				rgb[i * 3] = c.getX(i) * k; rgb[i * 3 + 1] = c.getY(i) * k; rgb[i * 3 + 2] = c.getZ(i) * k;
			}
			g.setAttribute('color', new THREE.BufferAttribute(rgb, 3));
			const uv = g.getAttribute('uv'), uv1 = g.getAttribute('uv1');
			if (uv) {
				const mat = new Float32Array(n * 3);
				for (let i = 0; i < n; i++) {
					mat[i * 3] = uv.getX(i); mat[i * 3 + 1] = uv.getY(i); mat[i * 3 + 2] = uv1 ? uv1.getY(i) : 0;
				}
				g.setAttribute('aMat', new THREE.BufferAttribute(mat, 3));
				g.deleteAttribute('uv'); if (uv1) g.deleteAttribute('uv1');
				o.material = materielJeu(o.material?.name || 'props');
			} else {
				o.material = materielJeu('props');
			}
		} // sinon : matériau glTF d'origine (habitations, constructions d'exemple)
		o.frustumCulled = true;
	});
}

function liberer(racine) {
	racine?.traverse((o) => {
		if (o.isMesh) {
			o.geometry.dispose();
			if (!materiaux.has(o.material?.name) || materiaux.get(o.material.name) !== o.material) o.material?.dispose?.();
		}
	});
}

const chargeur = new GLTFLoader();
const cache = new Map(); // id -> racine (les 6 derniers)
let jeton = 0;

async function afficher(m) {
	const moi = ++jeton;
	etat.erreur = '';
	$('etat').hidden = false;
	$('etat').textContent = `Chargement de « ${m.nom} » (${fmtKo(m.taille_ko)})…`;
	let racine = cache.get(m.id);
	try {
		if (!racine) {
			etat.chargements++;
			const rep = await fetch(new URL(m.fichier, document.baseURI));
			if (!rep.ok) throw new Error('HTTP ' + rep.status);
			let tampon;
			if (m.fichier.endsWith('.gz')) {
				const flux = rep.body.pipeThrough(new DecompressionStream('gzip'));
				tampon = await new Response(flux).arrayBuffer();
			} else tampon = await rep.arrayBuffer();
			const gltf = await chargeur.parseAsync(tampon, '');
			racine = gltf.scene;
			racine.userData.clips = gltf.animations || [];
			preparer(racine);
			cache.set(m.id, racine);
			etat.charges.push(m.id);
			while (cache.size > 6) {
				const [k, v] = cache.entries().next().value;
				cache.delete(k);
				liberer(v);
			}
		}
	} catch (e) {
		if (moi === jeton) {
			etat.erreur = String(e?.message || e);
			$('etat').textContent = `Impossible de charger « ${m.nom} » (${m.fichier}).`;
		}
		return;
	}
	if (moi !== jeton) return; // une sélection plus récente a pris le relais
	if (objet) scene.remove(objet);
	cache.delete(m.id); cache.set(m.id, racine); // récent en dernier
	objet = racine;
	// pose au sol, centré
	racine.position.set(0, 0, 0);
	racine.updateMatrixWorld(true);
	const boite = new THREE.Box3().setFromObject(racine);
	const centre = boite.getCenter(new THREE.Vector3());
	racine.position.set(-centre.x, -boite.min.y, -centre.z);
	scene.add(racine);
	animations(m, racine, racine.userData.clips || []);
	const taille = boite.getSize(new THREE.Vector3());
	const diag = Math.max(taille.length(), 0.5);
	const d = diag * 1.25;
	cadrage = { cible: new THREE.Vector3(0, taille.y * 0.45, 0), position: new THREE.Vector3(d * 0.75, taille.y * 0.45 + d * 0.38, d * 0.9), taille: diag };
	majSol(Math.max(taille.x, taille.z, 1));
	recentrer();
	$('etat').hidden = true;
}

$('recentrer').addEventListener('click', () => recentrer());
$('tourner').addEventListener('click', (e) => {
	controls.autoRotate = !controls.autoRotate;
	controls.autoRotateSpeed = 2.2;
	e.currentTarget.setAttribute('aria-pressed', String(controls.autoRotate));
});
$('grille').addEventListener('click', (e) => {
	sol.visible = !sol.visible;
	e.currentTarget.setAttribute('aria-pressed', String(sol.visible));
});

// ---------------------------------------------------------------- liste, recherche, filtres
function filtrer() {
	const mots = norm(etat.q).split(/\s+/).filter(Boolean);
	return etat.modeles.filter((m) => {
		if (etat.famille !== 'tous' && famille(m) !== etat.famille) return false;
		if (etat.categorie && m.categorie !== etat.categorie) return false;
		if (!mots.length) return true;
		const bloc = norm([m.nom, m.id, m.categorie, m.generateur, m.graine != null ? 'graine ' + m.graine : '', Object.values(m.params || {}).join(' ')].join(' '));
		return mots.every((w) => bloc.includes(w));
	});
}

function dessinerPuces() {
	const fam = $('familles');
	fam.replaceChildren();
	const nb = { tous: etat.modeles.length };
	for (const m of etat.modeles) nb[famille(m)] = (nb[famille(m)] || 0) + 1;
	for (const [k, label] of Object.entries(FAMILLES)) {
		if (k !== 'tous' && !nb[k]) continue;
		fam.append(el('button', { class: 'puce', type: 'button', 'aria-pressed': String(etat.famille === k), onclick: () => { etat.famille = k; liste(); } }, label, el('small', {}, nb[k] || 0)));
	}
	const cat = $('categories');
	cat.replaceChildren();
	const cats = new Map();
	for (const m of etat.modeles) {
		if (etat.famille !== 'tous' && famille(m) !== etat.famille) continue;
		cats.set(m.categorie, (cats.get(m.categorie) || 0) + 1);
	}
	cat.append(el('button', { class: 'puce', type: 'button', 'aria-pressed': String(!etat.categorie), onclick: () => { etat.categorie = ''; liste(); } }, 'Toutes catégories'));
	for (const [c, n] of [...cats.entries()].sort((a, b) => a[0].localeCompare(b[0], 'fr'))) {
		cat.append(el('button', { class: 'puce', type: 'button', 'aria-pressed': String(etat.categorie === c), onclick: () => { etat.categorie = etat.categorie === c ? '' : c; liste(); } }, c, el('small', {}, n)));
	}
}

function liste() {
	dessinerPuces();
	const res = filtrer();
	$('compte').textContent = `${res.length} / ${etat.modeles.length} modèles`;
	const ul = $('items');
	ul.replaceChildren();
	if (!res.length) {
		ul.append(el('li', { class: 'vide' }, 'Aucun modèle ne correspond. Essayez un autre mot ou retirez un filtre.'));
		return;
	}
	let derniere = null;
	for (const m of res) {
		if (m.categorie !== derniere) {
			derniere = m.categorie;
			ul.append(el('h3', {}, derniere));
		}
		const btn = el('button', { class: 'item', type: 'button', 'data-id': m.id, 'aria-current': String(etat.selection === m.id), onclick: () => choisir(m.id, true) },
			el('span', { class: 'n' }, m.nom), el('span', { class: 'm' }, `${dims(m)} · ${m.triangles?.toLocaleString('fr-FR') ?? '?'} tri.`));
		ul.append(el('li', {}, btn));
	}
}

function libelleVariante(m) {
	return m.nom.replace(/ du monde| \(bibliothèque d'assets\)/, '');
}

function fiche(m) {
	const f = $('fiche');
	f.replaceChildren();
	const gen = etat.catalogue.generateurs.find((g) => g.id === m.generateur);
	f.append(
		el('h2', {}, m.nom),
		el('p', { class: 'sous' }, `${m.categorie} · ${{ precuit: 'modèle précuit', enregistre: 'enregistré (non précuit)', genere: 'généré', exemple: 'construction d’exemple', manuel: 'ajouté à la main' }[m.famille] || m.famille}`),
		el('div', { class: 'mesures' },
			el('div', {}, el('b', {}, 'Dimensions (L × H × P)'), dims(m)),
			el('div', {}, el('b', {}, 'Triangles'), m.triangles != null ? m.triangles.toLocaleString('fr-FR') : '—'),
			el('div', {}, el('b', {}, 'Fichier'), fmtKo(m.taille_ko)),
			...(m.graine != null ? [el('div', {}, el('b', {}, 'Graine'), String(m.graine))] : []),
			...(m.generateur ? [el('div', {}, el('b', {}, 'Générateur'), gen ? gen.nom : m.generateur)] : []),
		),
	);
	if (m.generateur) {
		const freres = etat.modeles.filter((x) => x.generateur === m.generateur);
		if (freres.length > 1) {
			f.append(el('p', { class: 'var-titre' }, `Variantes reproductibles (${freres.length}) — mêmes graine et paramètres = même modèle`));
			const rang = el('div', { class: 'puces' });
			for (const v of freres) rang.append(el('button', { class: 'puce', type: 'button', 'aria-current': String(v.id === m.id), onclick: () => choisir(v.id, false) }, libelleVariante(v)));
			f.append(rang);
		}
	}
	f.append(el('p', { class: 'source' }, `Identifiant : ${m.id} · source : ${m.source}`));
}

async function choisir(id, defiler) {
	const m = etat.modeles.find((x) => x.id === id);
	if (!m) return;
	etat.selection = id;
	if (location.hash !== '#' + id) history.replaceState(null, '', '#' + id);
	document.querySelectorAll('.item').forEach((b) => b.setAttribute('aria-current', String(b.dataset.id === id)));
	fiche(m);
	if (defiler && matchMedia('(max-width: 820px)').matches) scrollTo({ top: 0, behavior: 'smooth' });
	await afficher(m);
}

function pied() {
	const ne = $('non-exportes');
	const liste = etat.catalogue.non_exportes || [];
	ne.replaceChildren(el('summary', {}, `Éléments non exportés (${liste.length})`));
	const ul = el('ul');
	for (const x of liste) ul.append(el('li', {}, el('b', {}, x.nom), ` — ${x.raison} `, el('em', {}, x.comment)));
	ne.append(el('p', {}, 'Détectés dans le projet mais impossibles à montrer comme un objet isolé, avec la marche à suivre pour les ajouter.'), ul);
	const li = $('limites');
	li.replaceChildren(el('summary', {}, 'Limites du rendu'));
	const ul2 = el('ul');
	for (const t of etat.catalogue.limites || []) ul2.append(el('li', {}, t));
	li.append(ul2, el('p', {}, `Catalogue : ${etat.catalogue.nombre} modèles · moteur ${etat.catalogue.moteur}${etat.catalogue.commit ? ' · version ' + etat.catalogue.commit : ''}.`));
}

// ---------------------------------------------------------------- démarrage
async function demarrer() {
	hauteurEntete();
	redim();
	boucle();
	$('q').addEventListener('input', (e) => { etat.q = e.target.value; liste(); });
	addEventListener('hashchange', () => { const id = decodeURIComponent(location.hash.slice(1)); if (id && id !== etat.selection) choisir(id, false); });
	addEventListener('keydown', (e) => {
		if (e.target.tagName === 'INPUT' || (e.key !== 'ArrowDown' && e.key !== 'ArrowUp')) return;
		const res = filtrer();
		const i = res.findIndex((m) => m.id === etat.selection);
		const j = Math.min(res.length - 1, Math.max(0, i + (e.key === 'ArrowDown' ? 1 : -1)));
		if (res[j]) { e.preventDefault(); choisir(res[j].id, false); document.querySelector(`.item[data-id="${res[j].id}"]`)?.scrollIntoView({ block: 'nearest' }); }
	});
	try {
		const rep = await fetch(new URL('catalogue.json', document.baseURI), { cache: 'no-cache' });
		if (!rep.ok) throw new Error('HTTP ' + rep.status);
		etat.catalogue = await rep.json();
	} catch (e) {
		$('etat').textContent = 'Catalogue introuvable (catalogue.json). Lancez tools/galerie.sh pour le générer.';
		return;
	}
	etat.modeles = etat.catalogue.modeles;
	liste();
	pied();
	const depart = decodeURIComponent(location.hash.slice(1));
	if (depart && etat.modeles.some((m) => m.id === depart)) choisir(depart, false);
	else $('etat').textContent = 'Choisissez un modèle dans la liste.';
}
demarrer();
