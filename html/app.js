const RES = typeof GetParentResourceName === 'function' ? GetParentResourceName() : 'ks-vehicleshop';
const $ = (s) => document.querySelector(s);

let vehicles = [];
let categories = [];
let currency = '₺';
let testDriveEnabled = true;
let paintEnabled = true;
let finCfg = null;
let stockOn = true;
let finDebts = [];
let finRepo = [];
let activeCat = 'all';
let selected = null;

function fmt(n) { return Number(n || 0).toLocaleString(locale === 'en' ? 'en-US' : 'tr-TR'); }

// Dil: server her açılışta aktif dili gönderir
let LANG = {};
let locale = 'tr';
function T(k, ...args) {
  let s = LANG[k];
  if (s == null) return k;
  let i = 0;
  return String(s).replace(/%[sd]/g, () => {
    i++;
    return args[i - 1] != null ? args[i - 1] : '';
  });
}
function applyLang() {
  document.documentElement.lang = locale;
  document.querySelectorAll('[data-i18n]').forEach(el => { el.textContent = T(el.dataset.i18n); });
  document.querySelectorAll('[data-i18n-ph]').forEach(el => { el.placeholder = T(el.dataset.i18nPh); });
  document.querySelectorAll('[data-i18n-title]').forEach(el => { el.title = T(el.dataset.i18nTitle); });
}
function catName(c) {
  if (!c) return '';
  if (c.id === 'all') return T('cat_all');
  const v = T('cat_' + c.id);
  return v === 'cat_' + c.id ? c.label : v;
}
// Öncelik: admin panelindeki özel URL > html/img/<model>.png (şeffaf PNG) > fivem docs
function imgFor(v) {
  if (v.image) return v.image;
  return `img/${v.model}.png`;
}
// Zincir: yerel png yoksa docs'a düş, o da yoksa resmi gizle (boş kutu kalmaz)
function imgFallback(el, model) {
  if (!el.dataset.fbk) {
    el.dataset.fbk = 'docs';
    el.src = `https://docs.fivem.net/vehicles/${model}.webp`;
  } else {
    el.dataset.fbk = 'done';
    el.onerror = null;
    el.style.display = 'none';
  }
}
async function post(cb, data = {}) {
  const r = await fetch(`https://${RES}/${cb}`, {
    method: 'POST', headers: { 'Content-Type': 'application/json; charset=UTF-8' },
    body: JSON.stringify(data)
  });
  try { return await r.json(); } catch { return {}; }
}

// Oyun-içi pencere: tarayıcı confirm/alert kutusu açılmaz, her şey temada olur
let modalResolve = null;
function setBtnText(btn, txt) {
  const sp = btn.querySelector('span');
  if (sp) sp.textContent = txt; else btn.textContent = txt;
}
function uiModal(msg, okText, showCancel) {
  return new Promise(res => {
    modalResolve = res;
    $('#m-msg').textContent = msg;
    setBtnText($('#m-ok'), okText || T('ok'));
    $('#m-cancel').style.display = showCancel ? '' : 'none';
    $('#modal').classList.remove('hidden');
  });
}
function uiConfirm(msg, okText) { return uiModal(msg, okText || T('yes'), true); }
function uiAlert(msg) { return uiModal(msg, T('ok'), false); }
function closeModal(val) {
  if (modalResolve) { const r = modalResolve; modalResolve = null; r(val); }
  $('#modal').classList.add('hidden');
}

window.addEventListener('message', (e) => {
  const d = e.data || {};
  if (d.action === 'open') {
    vehicles = d.vehicles || [];
    categories = d.categories || [];
    currency = d.currency || '₺';
    if (d.lang) LANG = d.lang;
    if (d.locale) locale = d.locale;
    applyLang();
    testDriveEnabled = d.testDrive !== false;
    paintEnabled = d.paint !== false;
    stockOn = d.stock !== false;
    finCfg = d.finance || null;
    selected = null;
    rowCache.clear();
    $('#vehList').innerHTML = '';
    $('#app').classList.remove('hidden');
    buildCats(); render();
    // Tüm thumb'ları önden indir: seçimde/kaydırmada boşluk kalmaz
    vehicles.forEach(v => { const im = new Image(); im.src = imgFor(v); });
    $('#panel').classList.add('mode-catalog');
    $('#panel').classList.remove('mode-admin');
    $('#app').classList.add('catalog');
    $('#app').classList.remove('admin');
    $('#tab-catalog').classList.remove('hidden');
    $('#tab-admin').classList.add('hidden');
    $('#tab-finance').classList.add('hidden');
    $('#tdBtn').style.display = testDriveEnabled ? '' : 'none';
    updateViewport();
    // ilk aracı otomatik seç ki sağda 3D belirsin
    const first = filtered()[0];
    if (first) select(first);
  }
  if (d.action === 'close') {
    $('#app').classList.add('hidden');
    $('#app').classList.remove('catalog');
    $('#app').classList.remove('admin');
  }
  if (d.action === 'openAdmin') {
    AVehicles = d.vehicles || [];
    ABundle = d.bundle || null;
    if (d.lang) LANG = d.lang;
    if (d.locale) locale = d.locale;
    applyLang();
    if (ABundle) {
      categories = ABundle.categories || [];
      currency = ABundle.currency || currency;
      catState = {};
      ABundle.categories.forEach(c => { if (c.id !== 'all') catState[c.id] = c.enabled !== false; });
    }
    $('#app').classList.remove('hidden');
    $('#panel').classList.add('mode-admin');
    $('#panel').classList.remove('mode-catalog');
    $('#app').classList.add('admin');
    $('#app').classList.remove('catalog');
    $('#tab-catalog').classList.add('hidden');
    $('#tab-admin').classList.remove('hidden');
    $('#tab-finance').classList.add('hidden');
    switchATab('vehicles');
    buildCatOptions(); renderAdminList(); renderCatToggles(); fillSettings(); loadShowrooms();
    if (!$('#ns-help').value) $('#ns-help').value = T('default_help_gallery');
  }
  if (d.action === 'openFinance') {
    finDebts = d.debts || [];
    finRepo = d.repossessed || [];
    if (d.currency) currency = d.currency;
    if (d.lang) LANG = d.lang;
    if (d.locale) locale = d.locale;
    applyLang();
    $('#app').classList.remove('hidden');
    $('#panel').classList.add('mode-admin');
    $('#panel').classList.remove('mode-catalog');
    $('#app').classList.add('admin');
    $('#app').classList.remove('catalog');
    $('#tab-catalog').classList.add('hidden');
    $('#tab-admin').classList.add('hidden');
    $('#tab-finance').classList.remove('hidden');
    renderFinance();
  }
  if (d.action === 'reload') {
    post('refresh').then(fresh => {
      if (!Array.isArray(fresh)) return;
      vehicles = fresh;
      selected = selected && fresh.find(x => x.model === selected.model) || null;
      if (!selected) $('#detail').classList.add('hidden');
      render();
      updateViewport();
    });
  }
});

document.addEventListener('keydown', (e) => {
  if (e.key === 'Escape') {
    if (modalResolve) closeModal(false);
    else post('close');
  }
});
$('#m-ok').addEventListener('click', () => closeModal(true));
$('#m-cancel').addEventListener('click', () => closeModal(false));

$('#closeBtn').addEventListener('click', () => post('close'));
$('#search').addEventListener('input', () => { render(); updateViewport(); });

function buildCats() {
  const box = $('#catList'); box.innerHTML = '';
  const visible = categories.filter(c => c.id === 'all' || c.enabled !== false);
  const all = [{ id: 'all', label: catName({ id: 'all' }) }, ...visible.filter(c => c.id !== 'all')];
  $('#catLabel').textContent = catName(all.find(c => c.id === activeCat) || all[0]);
  all.forEach(c => {
    const b = document.createElement('button');
    b.className = 'cat-opt' + (c.id === activeCat ? ' active' : '');
    b.textContent = catName(c);
    b.onclick = (e) => { e.stopPropagation(); activeCat = c.id; buildCats(); render(); closeCatCard(); };
    box.appendChild(b);
  });
}
function closeCatCard() { $('#catCard').classList.add('hidden'); }
$('#catBtn').addEventListener('click', (e) => { e.stopPropagation(); $('#catCard').classList.toggle('hidden'); });
document.addEventListener('click', (e) => {
  const card = $('#catCard');
  if (!card || card.classList.contains('hidden')) return;
  if (!card.contains(e.target) && !(e.target.closest && e.target.closest('#catBtn'))) closeCatCard();
});
function filtered() {
  const q = ($('#search').value || '').toLowerCase();
  return vehicles.filter(v => {
    if (activeCat !== 'all' && v.category !== activeCat) return false;
    if (!q) return true;
    return (v.model + ' ' + v.label + ' ' + v.brand).toLowerCase().includes(q);
  });
}

// SOL LİSTE — satırlar önbellekte tutulur: kategori/arama değişiminde resimler
// yeniden yüklenmez, mevcut düğümler taşınır/güncellenir (kırpışma yok)
const rowCache = new Map();
function setRowInfo(el, v) {
  el.querySelector('.rinfo').innerHTML = `
      <div><h4>${v.label}</h4><small>${v.brand || ''}</small>
      <div class="pr"><span class="price">${fmt(v.price)}${currency}</span>${stockOn ? `
      <span class="stock ${v.stock <= 2 ? 'low' : ''}"> • ${T('stock_short', v.stock)}</span>` : ''}</div></div>`;
}
function render() {
  const list = filtered();
  $('#count').textContent = T('vehicles_count', list.length);
  const box = $('#vehList');
  const seen = new Set();
  list.forEach(v => {
    let el = rowCache.get(v.model);
    if (!el) {
      el = document.createElement('div');
      el.className = 'vrow';
      el.dataset.model = v.model;
      el.innerHTML = `<img src="${imgFor(v)}" onerror="imgFallback(this,'${v.model}')"><div class="rinfo"></div>`;
      el.onclick = () => select(v);
      rowCache.set(v.model, el);
    }
    setRowInfo(el, v);
    el.classList.toggle('sel', !!(selected && selected.model === v.model));
    box.appendChild(el);
    seen.add(v.model);
  });
  for (const [model, el] of rowCache) {
    if (!seen.has(model)) { el.remove(); rowCache.delete(model); }
  }
}

function select(v) {
  selected = v;
  post('preview', { model: v.model, category: v.category });
  // Listeyi baştan çizme (resimler yeniden yüklenirdi): sadece seçili satırı vurgula
  document.querySelectorAll('#vehList .vrow').forEach(r => {
    r.classList.toggle('sel', r.dataset.model === v.model);
  });
  $('#detail').classList.remove('hidden');
  $('#d-label').textContent = v.label;
  $('#d-brand').textContent = (v.brand || '');
  $('#d-price').textContent = fmt(v.price) + currency;
  $('#d-stock').textContent = v.stock;
  $('#d-stockrow').style.display = stockOn ? '' : 'none';
  updateFinBox();
  updateViewport();
}

// Katalog detayındaki taksit kutusu (kapalıysa hiç görünmez)
function updateFinBox() {
  const box = $('#finBox');
  const on = !!(finCfg && finCfg.enabled) && selected && selected.price > 0;
  box.classList.toggle('hidden', !on);
  if (!on) return;
  const pct = finCfg.downPct || 0;
  const max = Math.max(1, finCfg.maxInst || 1);
  const down = Math.ceil(selected.price * pct / 100);
  const sel = $('#f-count');
  sel.innerHTML = '';
  for (let i = 2; i <= max; i++) {
    const o = document.createElement('option');
    o.value = i; o.textContent = T('n_installments', i);
    sel.appendChild(o);
  }
  if (max < 2) { const o = document.createElement('option'); o.value = 1; o.textContent = T('n_installments', 1); sel.appendChild(o); }
  const upd = () => {
    const c = Number(sel.value) || 2;
    const inst = Math.ceil((selected.price - down) / c);
    $('#f-pct').textContent = '%' + pct;
    $('#f-down').textContent = fmt(down) + currency;
    $('#f-inst').textContent = `${c} x ${fmt(inst)}${currency}`;
  };
  sel.onchange = upd;
  upd();
}

$('#finBtn').addEventListener('click', async () => {
  if (!selected || !finCfg || !finCfg.enabled) return;
  if (stockOn && selected.stock <= 0) { uiAlert(T('out_of_stock')); return; }
  const c = Number($('#f-count').value) || 2;
  const down = Math.ceil(selected.price * (finCfg.downPct || 0) / 100);
  const inst = Math.ceil((selected.price - down) / c);
  if (!await uiConfirm(T('fin_confirm', selected.label, fmt(down), currency, c, fmt(inst), currency), T('buy_finance'))) return;
  const res = await post('buyFinance', { model: selected.model, count: c });
  if (res && res.ok) {
    const fresh = await post('refresh');
    if (Array.isArray(fresh)) { vehicles = fresh; render(); updateViewport(); }
  } else {
    uiAlert((res && res.msg) || T('fin_failed'));
  }
});

// ================= BORÇ OFİSİ =================
function renderFinance() {
  const db = $('#debtList'); db.innerHTML = '';
  if (finDebts.length === 0) db.innerHTML = `<p class="empty-note">${T('no_debts')}</p>`;
  finDebts.forEach(d => {
    const left = Number(d.installments_left) || 0;
    const total = Number(d.installments_total) || 0;
    const over = Number(d.overdue_count) || 0;
    const el = document.createElement('div');
    el.className = 'frow';
    el.innerHTML = `
      <div><b>${d.label} • ${d.plate}</b>
        <small>${T('debt_left', left, total, fmt(d.installment), currency)}${over > 0 ? ` • <span class="stock low">${T('debt_overdue', over)}</span>` : ''}</small>
        <div class="price">${T('debt_total', fmt(left * Number(d.installment)), currency)}</div>
      </div>
      <div class="fbtns"><button class="paybtn" data-a="one">${T('pay_installment')}</button><button class="paybtn ghostbtn" data-a="all">${T('pay_all')}</button></div>`;
    el.querySelector('[data-a="one"]').onclick = async () => {
      const res = await post('payFinance', { id: d.id });
      if (res) { finDebts = res.debts || []; finRepo = res.repossessed || []; renderFinance(); }
    };
    el.querySelector('[data-a="all"]').onclick = async () => {
      const total = left * Number(d.installment);
      if (!await uiConfirm(T('payall_confirm', fmt(total), currency), T('pay_all'))) return;
      const res = await post('payAllFinance', { id: d.id });
      if (res) { finDebts = res.debts || []; finRepo = res.repossessed || []; renderFinance(); }
    };
    db.appendChild(el);
  });
  const rb = $('#repoList'); rb.innerHTML = '';
  if (finRepo.length === 0) rb.innerHTML = `<p class="empty-note">${T('no_repo')}</p>`;
  finRepo.forEach(d => {
    const el = document.createElement('div');
    el.className = 'frow';
    el.innerHTML = `
      <div><b>${d.vehicle} • ${d.plate}</b>
        <small>${T('repo_total')}</small>
        <div class="price">${fmt(d.owed)}${currency}</div>
      </div>
      <button class="paybtn">${T('reclaim')}</button>`;
    el.querySelector('button').onclick = async () => {
      if (!await uiConfirm(T('reclaim_confirm', d.plate, fmt(d.owed), currency), T('reclaim'))) return;
      const res = await post('reclaimVehicle', { id: d.id });
      if (res) { finDebts = res.debts || []; finRepo = res.repossessed || []; renderFinance(); }
    };
    rb.appendChild(el);
  });
}

function updateViewport() {
  const has = !!selected;
  $('#viewEmpty').style.display = has ? 'none' : '';
  $('#paintPanel').classList.toggle('hidden', !has || !paintEnabled);
}

// ---- RENK PANELİ (fırça + özel palet, 3D önizlemeyi anında boyar) ----
let palH = 0, palS = 1, palV = 1, lastPaintPost = 0;
function hsvToRgb(h, s, v) {
  h = ((h % 360) + 360) % 360;
  const c = v * s, x = c * (1 - Math.abs(((h / 60) % 2) - 1)), m = v - c;
  let r, g, b;
  if (h < 60) { r = c; g = x; b = 0; }
  else if (h < 120) { r = x; g = c; b = 0; }
  else if (h < 180) { r = 0; g = c; b = x; }
  else if (h < 240) { r = 0; g = x; b = c; }
  else if (h < 300) { r = x; g = 0; b = c; }
  else { r = c; g = 0; b = x; }
  return [Math.round((r + m) * 255), Math.round((g + m) * 255), Math.round((b + m) * 255)];
}
function paintUI(apply) {
  const [r, g, b] = hsvToRgb(palH, palS, palV);
  const sv = $('#svBox');
  sv.style.background = `linear-gradient(to top,#000,transparent),linear-gradient(to right,#fff,hsl(${palH},100%,50%))`;
  $('#svCur').style.left = (palS * 100) + '%';
  $('#svCur').style.top = ((1 - palV) * 100) + '%';
  $('#hueCur').style.left = (palH / 360 * 100) + '%';
  $('#palPrev').style.background = `rgb(${r},${g},${b})`;
  $('#palHex').textContent = '#' + [r, g, b].map(v => v.toString(16).padStart(2, '0')).join('');
  if (apply) {
    const now = Date.now();
    if (now - lastPaintPost > 80) {
      lastPaintPost = now;
      post('paint', { r, g, b });
    }
  }
}
(function initPaint() {
  const pal = $('#palette'), sv = $('#svBox'), hue = $('#hueBar');
  const pos = (e, el) => {
    const r = el.getBoundingClientRect();
    return [Math.min(1, Math.max(0, (e.clientX - r.left) / r.width)),
            Math.min(1, Math.max(0, (e.clientY - r.top) / r.height))];
  };
  let dragSV = false, dragH = false;
  sv.addEventListener('pointerdown', (e) => { dragSV = true; const [x, y] = pos(e, sv); palS = x; palV = 1 - y; paintUI(true); });
  hue.addEventListener('pointerdown', (e) => { dragH = true; const [x] = pos(e, hue); palH = x * 360; paintUI(true); });
  window.addEventListener('pointermove', (e) => {
    if (dragSV) { const [x, y] = pos(e, sv); palS = x; palV = 1 - y; paintUI(true); }
    if (dragH) { const [x] = pos(e, hue); palH = x * 360; paintUI(true); }
  });
  window.addEventListener('pointerup', () => {
    if (dragSV || dragH) {
      dragSV = dragH = false;
      const [r, g, b] = hsvToRgb(palH, palS, palV);
      lastPaintPost = 0;
      post('paint', { r, g, b });
    }
  });
  $('#brushBtn').onclick = (e) => {
    e.stopPropagation();
    pal.classList.toggle('hidden');
    paintUI(false);
  };
  // panele tıklamak/sürüklemek kamerayı döndürmesin
  $('#paintPanel').addEventListener('pointerdown', (e) => e.stopPropagation());
})();

$('#buyBtn').addEventListener('click', async () => {
  if (!selected) return;
  if (stockOn && selected.stock <= 0) { uiAlert(T('out_of_stock')); return; }
  if (!await uiConfirm(T('buy_confirm', selected.label, fmt(selected.price), currency), T('buy'))) return;
  const acct = $('#payAccount').value;
  const res = await post('buy', { model: selected.model, account: acct });
  if (res && res.ok) {
    const fresh = await post('refresh');
    if (Array.isArray(fresh)) { vehicles = fresh; render(); updateViewport(); }
  } else {
    uiAlert((res && res.msg) || T('buy_failed'));
  }
});

$('#tdBtn').addEventListener('click', () => {
  if (!selected) return;
  post('testdrive', { model: selected.model });
});

// ---- SAĞ VIEWPORT: mouse ile 3D kontrol (pointer events, capture yok) ----
(function initDrag() {
  const vp = document.getElementById('viewport');
  if (!vp) return;
  let dragging = false, lastX = 0, lastY = 0;
  vp.addEventListener('pointerdown', (e) => {
    if (e.button !== undefined && e.button !== 0) return;
    dragging = true; lastX = e.clientX; lastY = e.clientY;
    vp.classList.add('dragging');
  });
  window.addEventListener('pointerup', () => { dragging = false; vp.classList.remove('dragging'); });
  window.addEventListener('pointercancel', () => { dragging = false; vp.classList.remove('dragging'); });
  vp.addEventListener('pointermove', (e) => {
    if (!dragging || !selected) return;
    const dx = e.clientX - lastX;
    const dy = e.clientY - lastY;
    lastX = e.clientX; lastY = e.clientY;
    if (dx !== 0 || dy !== 0) post('rotate', { dx, dy });
  });
})();

// ================= ADMIN (/adminvehicleshop) =================
let ABundle = null;
let AVehicles = [];
let catState = {};

function switchATab(t) {
  document.querySelectorAll('.atab').forEach(b => b.classList.toggle('active', b.dataset.atab === t));
  document.querySelectorAll('.atabpage').forEach(p => p.classList.toggle('hidden', p.id !== 'atab-' + t));
}
document.querySelectorAll('.atab').forEach(b => b.addEventListener('click', () => switchATab(b.dataset.atab)));

function buildCatOptions() {
  const s = $('#f-cat'); if (!s) return; s.innerHTML = '';
  (ABundle ? ABundle.categories : categories).filter(c => c.id !== 'all').forEach(c => {
    const o = document.createElement('option'); o.value = c.id; o.textContent = catName(c); s.appendChild(o);
  });
}

function renderAdminList() {
  const q = (($('#adminSearch').value) || '').toLowerCase();
  const box = $('#adminList'); box.innerHTML = '';
  AVehicles.filter(v => !q || (v.model + v.label + v.brand).toLowerCase().includes(q)).forEach(v => {
    const row = document.createElement('div');
    row.className = 'arow';
    row.innerHTML = `
      <div><b>${v.label}</b> <small>${v.model} • ${v.brand}</small>
        <div class="aedit">
          <input type="number" value="${v.price}" data-k="price">
          <input type="number" value="${v.stock}" data-k="stock">
          <button class="save" data-a="saveprice">${T('price')}</button>
          <button class="save" data-a="savestock">${T('stock')}</button>
          <button class="edit" data-a="edit">${T('edit')}</button>
          <button class="del" data-a="del">${T('delete')}</button>
        </div>
      </div>
      <div class="price">${fmt(v.price)}${currency}</div>`;
    const priceInp = row.querySelector('[data-k="price"]');
    const stockInp = row.querySelector('[data-k="stock"]');
    row.querySelector('[data-a="saveprice"]').onclick = async () => {
      await post('adminSetPrice', { model: v.model, price: Number(priceInp.value) });
      AVehicles = await post('refresh'); renderAdminList();
    };
    row.querySelector('[data-a="savestock"]').onclick = async () => {
      await post('adminSetStock', { model: v.model, stock: Number(stockInp.value) });
      AVehicles = await post('refresh'); renderAdminList();
    };
    row.querySelector('[data-a="del"]').onclick = async () => {
      if (!await uiConfirm(T('del_vehicle_confirm', v.model), T('delete'))) return;
      await post('adminDelete', { model: v.model });
      AVehicles = await post('refresh'); renderAdminList();
    };
    row.querySelector('[data-a="edit"]').onclick = () => {
      const f = $('#vehForm');
      f.model.value = v.model; f.label.value = v.label; f.brand.value = v.brand;
      f.category.value = v.category; f.image.value = v.image || '';
      f.price.value = v.price; f.stock.value = v.stock;
    };
    box.appendChild(row);
  });
}

function renderCatToggles() {
  const box = $('#catToggles'); box.innerHTML = '';
  (ABundle ? ABundle.categories : []).filter(c => c.id !== 'all').forEach(c => {
    const on = catState[c.id] !== false;
    const row = document.createElement('div');
    row.className = 'tog ' + (on ? 'on' : 'off');
    row.innerHTML = `<span>${catName(c)}</span><button>${on ? T('on') : T('off')}</button>`;
    row.querySelector('button').onclick = async () => {
      catState[c.id] = !on;
      renderCatToggles();
      const res = await post('adminSaveSettings', collectSettings());
      if (res && res.ok && res.bundle) { ABundle = res.bundle; }
      $('#setStatus').textContent = (res && res.ok) ? T('saved_live') : ((res && res.msg) || T('error_msg'));
    };
    box.appendChild(row);
  });
}

function fillSettings() {
  if (!ABundle) return;
  $('#s-currency').value = ABundle.currency || '';
  $('#s-drawpos').value = ABundle.drawPos || 'left';
  $('#s-test').checked = !!ABundle.testDrive;
  $('#s-testdur').value = ABundle.testDriveDuration || 60;
  $('#s-rotate').checked = !!ABundle.rotate;
  $('#s-paint').checked = ABundle.paint !== false;
  $('#s-stock').checked = ABundle.stock !== false;
  const fin = ABundle.finance || {};
  $('#s-fin').checked = fin.enabled !== false;
  $('#s-down').value = (fin.downPct != null ? fin.downPct : 30);
  $('#s-maxinst').value = (fin.maxInst != null ? fin.maxInst : 12);
  $('#setStatus').textContent = '';
}

function collectSettings() {
  const n = (id) => Number($(id).value);
  return {
    currency: $('#s-currency').value,
    drawPos: $('#s-drawpos').value,
    testEnabled: $('#s-test').checked,
    testDuration: n('#s-testdur'),
    rotate: $('#s-rotate').checked,
    paint: $('#s-paint').checked,
    stock: $('#s-stock').checked,
    financeEnabled: $('#s-fin').checked,
    financeDownPct: n('#s-down'),
    financeMaxInst: n('#s-maxinst'),
    cats: Object.assign({}, catState),
  };
}

$('#vehForm').addEventListener('submit', async (e) => {
  e.preventDefault();
  const f = new FormData(e.target);
  const data = Object.fromEntries(f.entries());
  const res = await post('adminUpsert', data);
  uiAlert(res.msg || T('saved'));
  if (res.ok) { AVehicles = await post('refresh'); renderAdminList(); }
});
$('#formClear').addEventListener('click', () => $('#vehForm').reset());
$('#adminSearch').addEventListener('input', renderAdminList);
$('#setForm').addEventListener('submit', async (e) => {
  e.preventDefault();
  const res = await post('adminSaveSettings', collectSettings());
  if (res && res.ok && res.bundle) { ABundle = res.bundle; }
  $('#setStatus').textContent = (res && res.ok) ? T('saved_live') : ((res && res.msg) || T('error_msg'));
  uiAlert((res && res.msg) || T('saved'));
});

// ================= BLİP / KONUM YÖNETİMİ =================
let showrooms = [];
function escQ(s) { return String(s || '').replace(/"/g, '&quot;'); }
async function loadShowrooms() {
  showrooms = await post('adminGetShowrooms');
  if (!Array.isArray(showrooms)) showrooms = [];
  renderShowrooms();
}
function renderShowrooms() {
  const box = $('#showList'); box.innerHTML = '';
  showrooms.forEach(s => {
    const row = document.createElement('div');
    row.className = 'arow';
    row.innerHTML = `
      <div><b>${s.label}</b> ${s.is_default ? `<small>${T('show_default')}</small>` : ''} <small>${Number(s.x).toFixed(1)}, ${Number(s.y).toFixed(1)}, ${Number(s.z).toFixed(1)}</small>
        <small>${Number(s.x).toFixed(1)}, ${Number(s.y).toFixed(1)}, ${Number(s.z).toFixed(1)}</small>
        <div class="aedit">
          <input value="${escQ(s.label)}" data-k="label">
          <input value="${escQ(s.help)}" data-k="help">
          <input type="number" step="0.01" value="${s.x}" data-k="x" title="X">
          <input type="number" step="0.01" value="${s.y}" data-k="y" title="Y">
          <input type="number" step="0.01" value="${s.z}" data-k="z" title="Z">
          <button class="save" data-a="save">${T('save')}</button>
          ${s.is_default ? '' : `<button class="del" data-a="del">${T('delete')}</button>`}
        </div>
      </div>`;
    const labInp = row.querySelector('[data-k="label"]');
    const helpInp = row.querySelector('[data-k="help"]');
    row.querySelector('[data-a="save"]').onclick = async () => {
      const res = await post('adminSetShowroom', { id: s.id, label: labInp.value, help: helpInp.value,
        x: row.querySelector('[data-k="x"]').value, y: row.querySelector('[data-k="y"]').value, z: row.querySelector('[data-k="z"]').value });
      uiAlert(res.msg || T('saved'));
      if (res.ok) await loadShowrooms();
    };
    const delBtn = row.querySelector('[data-a="del"]');
    if (delBtn) delBtn.onclick = async () => {
      if (!await uiConfirm(T('show_del_confirm', s.label), T('delete'))) return;
      const res = await post('adminDeleteShowroom', { id: s.id });
      uiAlert(res.msg || T('deleted_msg'));
      if (res.ok) await loadShowrooms();
    };
    box.appendChild(row);
  });
}
$('#ns-add').onclick = async () => {
  const res = await post('adminAddShowroom', { label: $('#ns-label').value, help: $('#ns-help').value, kind: $('#ns-kind').value });
  uiAlert(res.msg || T('added_msg'));
  if (res && res.ok) { $('#ns-label').value = ''; await loadShowrooms(); }
};
