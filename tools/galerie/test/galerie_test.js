// Test navigateur de la galerie : node tools/galerie/test/galerie_test.js <url> <dossier-captures>
const { chromium } = require('playwright');
const url = process.argv[2] || 'http://localhost:8765/';
const out = process.argv[3] || '/tmp/galerie_caps';
require('fs').mkdirSync(out, { recursive: true });
let echecs = 0;
const ok = (c, m) => { console.log((c ? 'OK   ' : 'ÉCHEC ') + m); if (!c) echecs++; };
(async () => {
	const browser = await chromium.launch({ args: ['--use-gl=swiftshader', '--enable-unsafe-swiftshader', '--ignore-gpu-blocklist'] });
	for (const [nom, opts] of [['bureau', { viewport: { width: 1280, height: 800 } }], ['mobile', { viewport: { width: 390, height: 844 }, deviceScaleFactor: 2, isMobile: true, hasTouch: true }]]) {
		const ctx = await browser.newContext(opts);
		const page = await ctx.newPage();
		const erreurs = [];
		page.on('pageerror', (e) => erreurs.push(String(e)));
		page.on('console', (m) => { if (m.type() === 'error') erreurs.push(m.text()); });
		const glb = [];
		page.on('request', (r) => { if (r.url().includes('/modeles/')) glb.push(r.url()); });
		await page.goto(url, { waitUntil: 'networkidle' });
		await page.waitForSelector('.item');
		const total = await page.evaluate(() => window.galerieEtat.modeles.length);
		ok(total > 100, `${nom} : catalogue chargé (${total} modèles)`);
		ok(glb.length === 0, `${nom} : aucun modèle téléchargé au démarrage`);
		const choisir = async (id) => {
			await page.click(`.item[data-id="${id}"]`);
			await page.waitForFunction((i) => window.galerieEtat.charges.includes(i) && document.getElementById('etat').hidden, id, { timeout: 60000 });
			await page.waitForTimeout(700);
		};
		const ids = [['precuit_arbre', 'tree_oak_1'], ['bat', 'batiment_house_small_g1'], ['rocher', 'nature_rocher_boulder_g2'], ['bateau', 'bateau_g1'], ['hab', 'habitation_en_L_g1'], ['objet', 'forge']];
		for (const [court, id] of ids) {
			await page.fill('#q', '');
			await page.evaluate((i) => { location.hash = i; }, id);
			await page.waitForFunction((i) => window.galerieEtat.selection === i && window.galerieEtat.charges.includes(i) && document.getElementById('etat').hidden, id, { timeout: 60000 });
			await page.waitForTimeout(800);
			await page.screenshot({ path: `${out}/${nom}_${court}.png` });
			ok(true, `${nom} : ${id} affiché`);
		}
		ok(glb.length === ids.length, `${nom} : chargement à la demande (${glb.length} fichiers pour ${ids.length} modèles ouverts)`);
		// recherche + filtre
		await page.fill('#q', 'chêne graine 7');
		const n = await page.locator('.item').count();
		ok(n >= 1 && n < 10, `${nom} : recherche « chêne graine 7 » → ${n} résultat(s)`);
		await page.fill('#q', '');
		await page.click('#categories .puce:has-text("Rochers")');
		const cats = await page.evaluate(() => [...document.querySelectorAll('.item')].length);
		ok(cats === 29, `${nom} : filtre Rochers et ruines → ${cats}`);
		await page.screenshot({ path: `${out}/${nom}_filtre.png` });
		// recentrer / rotation
		await page.click('#recentrer');
		await page.click('#tourner');
		ok((await page.getAttribute('#tourner', 'aria-pressed')) === 'true', `${nom} : rotation automatique`);
		ok(erreurs.length === 0, `${nom} : aucune erreur console ${erreurs.slice(0, 3).join(' | ')}`);
		await ctx.close();
	}
	await browser.close();
	process.exit(echecs ? 1 : 0);
})();
