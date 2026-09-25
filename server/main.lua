-- Framework erişimi Bridge üzerinden (shared/bridge.lua): qb-core ve qbx_core uyumlu
-- Admin kontrolü: Bridge.IsAdmin (sn-bridge mantığı: konsol + framework ace'i)

local function dprint(...)
    if Config.Debug then print('^5[ks-vehicleshop]^7', ...) end
end

local function isAdmin(src)
    return Bridge.IsAdmin(src)
end

exports('IsAdmin', isAdmin)

-- Admin audit: Discord webhook (server.cfg: setr ks_admin_webhook "https://...")
-- qb-log kullanılmaz. Webhook boşsa sessiz geçilir.
local function audit(src, action, details)
    local url = GetConvar('ks_admin_webhook', '')
    if url == '' then return end
    local who = ('ID %s'):format(src)
    local Player = Bridge.GetPlayer(src)
    if Player and Player.PlayerData then
        local ci = Player.PlayerData.charinfo or {}
        who = ('%s %s (%s)'):format(ci.firstname or '?', ci.lastname or '?', Player.PlayerData.citizenid or '?')
    end
    local payload = json.encode({
        username = 'KS VehicleShop',
        embeds = { {
            title = action,
            description = (details or '') .. '\nAdmin: ' .. who,
            color = 15158332,
            footer = { text = os.date('%Y-%m-%d %H:%M:%S') },
        } },
    })
    PerformHttpRequest(url, function() end, 'POST', payload, { ['Content-Type'] = 'application/json' })
end

-- Rate limit: kritik callbacklerde spam koruması (oyuncu başına anahtar+süre)
local Cooldowns = {}
local function cooled(src, key, ms)
    local now = GetGameTimer()
    Cooldowns[src] = Cooldowns[src] or {}
    if Cooldowns[src][key] and (now - Cooldowns[src][key]) < ms then
        return false
    end
    Cooldowns[src][key] = now
    return true
end

AddEventHandler('playerDropped', function()
    Cooldowns[source] = nil
end)

-- Dile göre varsayılan yardım yazıları (DB'deki özel yazılara dokunulmaz)
local function defHelp(kind)
    if Config.Locale == 'en' then
        return (kind == 'finance') and 'View Debts' or 'Enter Gallery'
    end
    return (kind == 'finance') and 'Borçları Gör' or 'Galeriye gir'
end

local knownHelpDefaults = {
    ['Kataloğu aç'] = true, ['Galeriye Eriş'] = true, ['Galeriye gir'] = true,
    ['Enter Gallery'] = true, ['Borçları Gör'] = true, ['View Debts'] = true,
}

-- RUNTIME AYARLAR (restart gerektirmez: DB'de saklanır, Config varsayılanları ezer)
-- Admin NUI'dan değişir, anında geçerli olur.
local Runtime = {}

local function loadRuntime()
    Runtime = {}
    local rows = MySQL.query.await('SELECT name, value FROM ks_gallery_settings')
    for _, r in ipairs(rows or {}) do Runtime[r.name] = r.value end
end

local function effCategories()
    local out = {}
    for _, c in ipairs(Config.Categories or {}) do
        local en = Runtime['cat_' .. c.id]
        local enabled
        if en == nil then enabled = (c.enabled ~= false)
        else enabled = (en == '1') end
        out[#out + 1] = { id = c.id, label = c.label, enabled = enabled }
    end
    return out
end

-- Config'de/RUNTIME'da enabled olan kategoriler (kapalılar katalogda görünmez, DB'ye eklenmez)
local function allowedCategories()
    local set = {}
    for _, c in ipairs(effCategories()) do
        if c.id and c.id ~= 'all' and c.enabled then
            set[c.id] = true
        end
    end
    return set
end

local function effCurrency()
    return Runtime['currency'] or Config.Currency or '₺'
end

-- Stok sistemi açık mı (kapalıysa stok kontrolü ve düşüşü atlanır)
local function stockOn()
    if Runtime['stock_enabled'] == nil then
        return Config.StockSystem ~= false
    end
    return Runtime['stock_enabled'] == '1'
end

local function num(key, def)
    local v = tonumber(Runtime[key])
    if v == nil then return def end
    return v
end

-- NUI + client için efektif ayar paketi
local function buildBundle()
    local td = Config.TestDrive or {}
    local iso = Config.IsolatedPreview or {}
    local hang = Config.HangarPreview or {}
    local rten = Runtime['testdrive_enabled']
    local rrot = Runtime['rotate_enabled']
    local rfin = Runtime['finance_enabled']
    local fin = Config.Finance or {}
    return {
        categories = effCategories(),
        currency = effCurrency(),
        testDrive = (rten == nil) and (td.enabled ~= false) or (rten == '1'),
        testDriveDuration = num('testdrive_duration', td.duration or 60),
        rotate = (rrot == nil) and (Config.PreviewRotateEnabled ~= false) or (rrot == '1'),
        paint = (Runtime['paint_enabled'] == nil) or (Runtime['paint_enabled'] == '1'),
        stock = (Runtime['stock_enabled'] == nil) and (Config.StockSystem ~= false) or (Runtime['stock_enabled'] == '1'),
        drawPos = Runtime['drawtext_pos'] or 'left',
        finance = {
            enabled = (rfin == nil) and (fin.enabled ~= false) or (rfin == '1'),
            downPct = num('finance_downpct', fin.downPct or 30),
            maxInst = num('finance_maxinst', fin.maxInst or 12),
        },
    }
end

-- Finance efektif değerler
local function effFinance()
    local fin = Config.Finance or {}
    local rfin = Runtime['finance_enabled']
    return {
        enabled = (rfin == nil) and (fin.enabled ~= false) or (rfin == '1'),
        downPct = num('finance_downpct', fin.downPct or 30),
        maxInst = num('finance_maxinst', fin.maxInst or 12),
        intervalHours = tonumber(fin.intervalHours) or 24,
        lateFeePct = tonumber(fin.lateFeePct) or 10,
        maxOverdue = tonumber(fin.maxOverdue) or 1,
    }
end

-- Tabloyu garanti altına al + seed
CreateThread(function()
    MySQL.query([[
        CREATE TABLE IF NOT EXISTS ks_gallery_vehicles (
            id INT AUTO_INCREMENT PRIMARY KEY,
            model VARCHAR(50) NOT NULL UNIQUE,
            label VARCHAR(100) NOT NULL DEFAULT '',
            brand VARCHAR(100) NOT NULL DEFAULT '',
            category VARCHAR(50) NOT NULL DEFAULT 'other',
            price INT NOT NULL DEFAULT 0,
            stock INT NOT NULL DEFAULT 1,
            image VARCHAR(255) NOT NULL DEFAULT '',
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
            updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
    ]])
    Wait(1000)
    MySQL.query([[
        CREATE TABLE IF NOT EXISTS ks_gallery_blocklist (
            model VARCHAR(50) PRIMARY KEY
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
    ]])
    MySQL.query([[
        CREATE TABLE IF NOT EXISTS ks_gallery_settings (
            name VARCHAR(64) PRIMARY KEY,
            value VARCHAR(255) NOT NULL DEFAULT ''
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
    ]])
    MySQL.query([[
        CREATE TABLE IF NOT EXISTS ks_gallery_showrooms (
            id INT AUTO_INCREMENT PRIMARY KEY,
            label VARCHAR(100) NOT NULL DEFAULT '',
            x FLOAT NOT NULL, y FLOAT NOT NULL, z FLOAT NOT NULL,
            help VARCHAR(100) NOT NULL DEFAULT 'Galeriye gir',
            blip_sprite INT NOT NULL DEFAULT 326,
            blip_color INT NOT NULL DEFAULT 3,
            blip_scale FLOAT NOT NULL DEFAULT 0.9,
            is_default TINYINT NOT NULL DEFAULT 0
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
    ]])
    loadRuntime()
    -- kind kolonu migrasyonu (eski kurulumlar için)
    local hasKind = MySQL.scalar.await("SELECT COUNT(*) FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'ks_gallery_showrooms' AND COLUMN_NAME = 'kind'")
    if hasKind == 0 then
        MySQL.query.await("ALTER TABLE ks_gallery_showrooms ADD COLUMN kind VARCHAR(20) NOT NULL DEFAULT 'gallery'")
    end
    MySQL.query([[
        CREATE TABLE IF NOT EXISTS ks_finance (
            id INT AUTO_INCREMENT PRIMARY KEY,
            citizenid VARCHAR(50) NOT NULL,
            plate VARCHAR(10) NOT NULL,
            model VARCHAR(50) NOT NULL DEFAULT '',
            label VARCHAR(100) NOT NULL DEFAULT '',
            price INT NOT NULL DEFAULT 0,
            down_paid INT NOT NULL DEFAULT 0,
            installment INT NOT NULL DEFAULT 0,
            installments_total INT NOT NULL DEFAULT 0,
            installments_left INT NOT NULL DEFAULT 0,
            interval_secs INT NOT NULL DEFAULT 86400,
            next_due_playtime INT NOT NULL DEFAULT 0,
            overdue_count INT NOT NULL DEFAULT 0,
            late_fee INT NOT NULL DEFAULT 0,
            status VARCHAR(20) NOT NULL DEFAULT 'active',
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
            UNIQUE KEY uniq_plate (plate)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
    ]])
    MySQL.query([[
        CREATE TABLE IF NOT EXISTS ks_finance_playtime (
            citizenid VARCHAR(50) PRIMARY KEY,
            seconds INT NOT NULL DEFAULT 0
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
    ]])
    MySQL.query([[
        CREATE TABLE IF NOT EXISTS deleted_player_vehicles (
            id INT AUTO_INCREMENT PRIMARY KEY,
            citizenid VARCHAR(50) NOT NULL,
            license VARCHAR(50) NOT NULL DEFAULT '',
            vehicle VARCHAR(50) NOT NULL DEFAULT '',
            hash INT NOT NULL DEFAULT 0,
            mods TEXT,
            plate VARCHAR(10) NOT NULL,
            garage VARCHAR(50) NOT NULL DEFAULT '',
            owed INT NOT NULL DEFAULT 0,
            finance_id INT NOT NULL DEFAULT 0,
            deleted_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
    ]])
    -- Eski varsayılan yazılar dile göre normalize edilir (özel yazılara dokunulmaz)
    local hrows = MySQL.query.await('SELECT id, kind, help FROM ks_gallery_showrooms') or {}
    for _, hr in ipairs(hrows) do
        if knownHelpDefaults[hr.help] and hr.help ~= defHelp(hr.kind) then
            MySQL.update.await('UPDATE ks_gallery_showrooms SET help = ? WHERE id = ?', { defHelp(hr.kind), hr.id })
        end
    end
    -- Varsayılan konumu yeni yerine taşı + adını düzelt (sadece eski değerlerde, bir kez)
    MySQL.query.await("UPDATE ks_gallery_showrooms SET label = 'Galeri Katalog', x = -33.38, y = -1100.44, z = 26.42 WHERE is_default = 1 AND label = 'Premium Deluxe Motorsport'")
    -- Showroom seed: tablo boşsa config'deki konum varsayılan olarak eklenir
    local scount = MySQL.scalar.await('SELECT COUNT(*) FROM ks_gallery_showrooms')
    if scount == 0 then
        for i, s in ipairs(Config.Showrooms or {}) do
            local b = s.blip or {}
            MySQL.insert.await(
                'INSERT INTO ks_gallery_showrooms (label, x, y, z, help, blip_sprite, blip_color, blip_scale, is_default, kind) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
                { s.label or 'Galeri', s.coords.x, s.coords.y, s.coords.z, defHelp('gallery'),
                  b.sprite or 326, b.color or 3, b.scale or 0.9, (i == 1) and 1 or 0, 'gallery' }
            )
        end
        print('^2[ks-vehicleshop]^7 ' .. L('log_default_showroom'))
    end
    -- Borç ofisi seed: finance türünde kayıt yoksa config'den eklenir
    local fcount = MySQL.scalar.await("SELECT COUNT(*) FROM ks_gallery_showrooms WHERE kind = 'finance'")
    if fcount == 0 and Config.FinanceOffice and Config.FinanceOffice.coords then
        local fc, fb = Config.FinanceOffice.coords, Config.FinanceOffice.blip or {}
        MySQL.insert.await(
            'INSERT INTO ks_gallery_showrooms (label, x, y, z, help, blip_sprite, blip_color, blip_scale, is_default, kind) VALUES (?, ?, ?, ?, ?, ?, ?, ?, 1, ?)',
            { fb.name or 'Galeri Borç Ofisi', fc.x, fc.y, fc.z, defHelp('finance'),
              fb.sprite or 108, fb.color or 2, fb.scale or 0.8, 'finance' }
        )
        print('^2[ks-vehicleshop]^7 ' .. L('log_default_office'))
    end
    -- Marker kalıcılığı: admin ekledikleri/taşıdıkları restartta KORUNUR.
    -- NPC konumu sadece ilk kurulumda baz alınır (aşağıdaki seed/güvenlik blokları).
    -- Güvenlik: her türden bir varsayılan mutlaka kalsın (yoksa NPC konumuna eklenir)
    local gdef = MySQL.scalar.await("SELECT COUNT(*) FROM ks_gallery_showrooms WHERE kind = 'gallery' AND is_default = 1")
    if gdef == 0 and Config.CatalogPed and Config.CatalogPed.coords then
        local cp2 = Config.CatalogPed.coords
        MySQL.insert.await(
            'INSERT INTO ks_gallery_showrooms (label, x, y, z, help, blip_sprite, blip_color, blip_scale, is_default, kind) VALUES (?, ?, ?, ?, ?, 326, 3, 0.9, 1, ?)',
            { 'Galeri Katalog', cp2.x, cp2.y, cp2.z, defHelp('gallery'), 'gallery' }
        )
    end
    local fdef = MySQL.scalar.await("SELECT COUNT(*) FROM ks_gallery_showrooms WHERE kind = 'finance' AND is_default = 1")
    if fdef == 0 and Config.DebtPed and Config.DebtPed.coords then
        local dp2 = Config.DebtPed.coords
        local fb2 = (Config.FinanceOffice and Config.FinanceOffice.blip) or {}
        MySQL.insert.await(
            'INSERT INTO ks_gallery_showrooms (label, x, y, z, help, blip_sprite, blip_color, blip_scale, is_default, kind) VALUES (?, ?, ?, ?, ?, ?, ?, ?, 1, ?)',
            { fb2.name or 'Galeri Borç Ofisi', dp2.x, dp2.y, dp2.z, 'Borçları Gör',
              fb2.sprite or 108, fb2.color or 2, fb2.scale or 0.8, 'finance' }
        )
    end
    -- Kaldırılan kamera ayarlarının eski kayıtlarını temizle (config varsayılanları geçerli olur)
    MySQL.query.await("DELETE FROM ks_gallery_settings WHERE name LIKE 'cam%'")
    -- Config tek kaynaktır: her başlatmada config listesi DB ile eşitlenir
    -- (fiyat/marka/kategori güncellenir, eksikler eklenir, stok korunur)
    -- Bloklistedekiler (oyunda modeli olmayanlar) tekrar eklenmez.
    local blocked = {}
    for _, m in ipairs(Config.Blocklist or {}) do blocked[tostring(m):lower()] = true end
    local brows = MySQL.query.await('SELECT model FROM ks_gallery_blocklist')
    for _, r in ipairs(brows or {}) do blocked[tostring(r.model):lower()] = true end
    local cfgList = Config.Vehicles or Config.SeedVehicles
    local allowed = allowedCategories()
    if cfgList and #cfgList > 0 then
        local added, updated, skipped = 0, 0, 0
        for _, v in ipairs(cfgList) do
            if blocked[v.model:lower()] or not allowed[v.category] then
                skipped = skipped + 1
            else
                local exists = MySQL.scalar.await('SELECT 1 FROM ks_gallery_vehicles WHERE model = ?', { v.model:lower() })
                if exists then
                    MySQL.update.await(
                        'UPDATE ks_gallery_vehicles SET label = ?, brand = ?, category = ?, price = ?, image = ? WHERE model = ?',
                        { v.label, v.brand, v.category, v.price, v.image or '', v.model:lower() }
                    )
                    updated = updated + 1
                else
                    MySQL.insert.await(
                        'INSERT INTO ks_gallery_vehicles (model, label, brand, category, price, stock, image) VALUES (?, ?, ?, ?, ?, ?, ?)',
                        { v.model:lower(), v.label, v.brand, v.category, v.price, v.stock, v.image or '' }
                    )
                    added = added + 1
                end
            end
        end
        print('^2[ks-vehicleshop]^7 ' .. L('log_sync', added, updated, skipped))
    end
end)

local function sanitizeVehicle(row)
    return {
        id = row.id,
        model = row.model,
        label = row.label,
        brand = row.brand,
        category = row.category,
        price = tonumber(row.price) or 0,
        stock = tonumber(row.stock) or 0,
        image = row.image or '',
    }
end

-- KATALOG: herkes okuyabilir (kapalı kategoriler filtrelenir)
Bridge.RegisterServerCallback('ks-gallery:server:GetVehicles', function(_, cb)
    local allowed = allowedCategories()
    local rows = MySQL.query.await('SELECT * FROM ks_gallery_vehicles ORDER BY brand ASC, label ASC')
    local out = {}
    for _, r in ipairs(rows or {}) do
        if allowed[r.category] then out[#out + 1] = sanitizeVehicle(r) end
    end
    cb(out)
end)

Bridge.RegisterServerCallback('ks-gallery:server:IsAdmin', function(src, cb)
    cb(isAdmin(src))
end)

-- Efektif ayar paketi (NUI + client, restartsız güncel)
Bridge.RegisterServerCallback('ks-gallery:server:GetUIData', function(_, cb)
    cb(buildBundle())
end)

-- Admin ayar kaydı (restartsız): ödeme türü, para birimi, test, döndürme, kameralar, kategoriler
Bridge.RegisterServerCallback('ks-gallery:server:SaveSettings', function(src, cb, data)
    if not isAdmin(src) then cb({ ok = false, msg = L('no_perm') }) return end
    if not cooled(src, 'settings', 3000) then cb({ ok = false, msg = L('cooldown') }) return end
    if type(data) ~= 'table' then cb({ ok = false, msg = L('bad_data') }) return end
    local function save(key, val)
        Runtime[key] = val
        MySQL.query.await('INSERT INTO ks_gallery_settings (name, value) VALUES (?, ?) ON DUPLICATE KEY UPDATE value = VALUES(value)', { key, val })
    end
    local function saveNum(key, v, mn, mx)
        v = tonumber(v)
        if v == nil then return end
        if mn and v < mn then v = mn end
        if mx and v > mx then v = mx end
        save(key, tostring(v))
    end
    local function saveBool(key, v)
        if v == true or v == 1 or v == '1' or v == 'true' then save(key, '1')
        elseif v == false or v == 0 or v == '0' or v == 'false' then save(key, '0') end
    end
    if type(data.currency) == 'string' and #data.currency >= 1 and #data.currency <= 8 then
        save('currency', data.currency)
    end
    saveBool('testdrive_enabled', data.testEnabled)
    saveNum('testdrive_duration', data.testDuration, 10, 600)
    saveBool('rotate_enabled', data.rotate)
    saveBool('paint_enabled', data.paint)
    saveBool('stock_enabled', data.stock)
    if data.drawPos == 'left' or data.drawPos == 'top' or data.drawPos == 'right' then
        save('drawtext_pos', data.drawPos)
    end
    saveBool('finance_enabled', data.financeEnabled)
    saveNum('finance_downpct', data.financeDownPct, 0, 95)
    saveNum('finance_maxinst', data.financeMaxInst, 1, 60)
    if type(data.cats) == 'table' then
        local valid = {}
        for _, c in ipairs(Config.Categories or {}) do valid[c.id] = true end
        for id, en in pairs(data.cats) do
            if valid[id] and id ~= 'all' then saveBool('cat_' .. id, en) end
        end
    end
    local bundle = buildBundle()
    TriggerClientEvent('ks-gallery:client:SyncSettings', src, bundle)
    audit(src, L('audit_settings'), 'runtime settings')
    cb({ ok = true, msg = L('settings_saved'), bundle = bundle })
end)

-- SATIN ALMA
Bridge.RegisterServerCallback('ks-gallery:server:BuyVehicle', function(src, cb, data)
    if not cooled(src, 'buy', 5000) then cb({ ok = false, msg = L('cooldown') }) return end
    local Player = Bridge.GetPlayer(src)
    if not Player then cb({ ok = false, msg = L('player_not_found') }) return end
    if type(data) ~= 'table' or not data.model then cb({ ok = false, msg = L('bad_request') }) return end

    local model = tostring(data.model):lower()
    -- Ödeme türünü oyuncu seçer (doğrulanmış), zorunluluk yok
    local account = tostring(data.account or 'bank')
    if account ~= 'bank' and account ~= 'cash' then account = 'bank' end

    local row = MySQL.single.await('SELECT * FROM ks_gallery_vehicles WHERE model = ?', { model })
    if not row then cb({ ok = false, msg = L('not_in_catalog') }) return end
    local price = tonumber(row.price) or 0
    local stock = tonumber(row.stock) or 0
    if stockOn() and stock <= 0 then cb({ ok = false, msg = L('out_of_stock') }) return end
    if price <= 0 then cb({ ok = false, msg = L('bad_price') }) return end

    local money = Player.PlayerData.money[account] or 0
    if money < price then
        cb({ ok = false, msg = L('insufficient', price, effCurrency()) })
        return
    end

    if not Player.Functions.RemoveMoney(account, price, 'galeri-arac-satin-alma') then
        cb({ ok = false, msg = L('pay_failed') })
        return
    end

    -- Plaka üret
    local plate = nil
    for _ = 1, 20 do
        local p = (Config.PlatePrefix .. ' ' .. Bridge.RandomInt(4)):upper():gsub('%s+', ' '):sub(1, 8)
        local exists = MySQL.scalar.await('SELECT 1 FROM player_vehicles WHERE plate = ?', { p })
        if not exists then plate = p break end
        Wait(0)
    end
    if not plate then
        Player.Functions.AddMoney(account, price, 'galeri-plaka-hata-iade')
        cb({ ok = false, msg = L('plate_failed') })
        return
    end

    local hash = joaat(model)
    local mods = '{}'
    local okInsert = MySQL.insert.await(
        'INSERT INTO player_vehicles (license, citizenid, vehicle, hash, mods, plate, garage, state) VALUES (?, ?, ?, ?, ?, ?, ?, ?)',
        { Player.PlayerData.license, Player.PlayerData.citizenid, model, hash, mods, plate, Config.Garage, 1 }
    )
    if not okInsert then
        Player.Functions.AddMoney(account, price, 'galeri-db-hata-iade')
        cb({ ok = false, msg = L('db_failed') })
        return
    end

    if stockOn() then
        -- Atomik düşürme: aynı tickte iki alım olursa biri elenir (oversell yok)
        local aff = MySQL.update.await('UPDATE ks_gallery_vehicles SET stock = stock - 1 WHERE model = ? AND stock > 0', { model })
        if aff == 0 then
            MySQL.update.await('DELETE FROM player_vehicles WHERE plate = ?', { plate })
            Player.Functions.AddMoney(account, price, 'galeri-stok-hata-iade')
            cb({ ok = false, msg = L('out_of_stock') })
            return
        end
    end
    TriggerEvent('qb-log:server:CreateLog', 'shops', L('log_sale_title'),
        L('log_sale_body',
            Player.PlayerData.charinfo.firstname .. ' ' .. Player.PlayerData.charinfo.lastname,
            Player.PlayerData.citizenid, model, price, effCurrency(), plate
        ), true)

    dprint(('SATIŞ: %s -> %s (%s)'):format(src, model, plate))
    -- Anahtar client tarafından verilir (Bridge.GiveVehicleKeys: qb'de server exportu, qbx'te bridge event).
    cb({ ok = true, msg = L('bought_ok'), plate = plate, garage = Config.Garage })
end)

-- ADMIN: araç ekle / güncelle (upsert)
Bridge.RegisterServerCallback('ks-gallery:server:AdminUpsert', function(src, cb, data)
    if not isAdmin(src) then cb({ ok = false, msg = L('no_perm') }) return end
    if not cooled(src, 'admin', 1500) then cb({ ok = false, msg = L('cooldown') }) return end
    if type(data) ~= 'table' then cb({ ok = false, msg = L('bad_data') }) return end

    local model = tostring(data.model or ''):lower():gsub('%s+', ''):sub(1, 50)
    local label = tostring(data.label or model):sub(1, 100)
    local brand = tostring(data.brand or ''):sub(1, 100)
    local category = tostring(data.category or 'other'):lower()
    local price = math.floor(tonumber(data.price) or 0)
    local stock = math.floor(tonumber(data.stock) or 0)
    local image = tostring(data.image or ''):sub(1, 255)

    if model == '' or #model < 2 then cb({ ok = false, msg = L('model_required') }) return end
    if price < 0 then cb({ ok = false, msg = L('price_neg') }) return end
    if stock < 0 then cb({ ok = false, msg = L('stock_neg') }) return end
    if label == '' then label = model end

    local validCat = false
    for _, c in ipairs(Config.Categories) do if c.id == category then validCat = true break end end
    if not validCat then category = 'other' end

    MySQL.query.await([[
        INSERT INTO ks_gallery_vehicles (model, label, brand, category, price, stock, image)
        VALUES (?, ?, ?, ?, ?, ?, ?)
        ON DUPLICATE KEY UPDATE label=VALUES(label), brand=VALUES(brand), category=VALUES(category),
        price=VALUES(price), stock=VALUES(stock), image=VALUES(image)
    ]], { model, label, brand, category, price, stock, image })

    audit(src, L('audit_upsert'), ('%s | %s | %s | %s'):format(model, label, price, stock))
    cb({ ok = true, msg = L('upsert_ok', model) })
end)

-- ADMIN: fiyat hızlı güncelle
Bridge.RegisterServerCallback('ks-gallery:server:AdminSetPrice', function(src, cb, data)
    if not isAdmin(src) then cb({ ok = false, msg = L('no_perm') }) return end
    if not cooled(src, 'admin', 1500) then cb({ ok = false, msg = L('cooldown') }) return end
    local model = tostring(data and data.model or ''):lower()
    local price = math.floor(tonumber(data and data.price) or -1)
    if model == '' then cb({ ok = false, msg = L('model_missing') }) return end
    if price < 0 then cb({ ok = false, msg = L('price_invalid') }) return end
    local affected = MySQL.update.await('UPDATE ks_gallery_vehicles SET price = ? WHERE model = ?', { price, model })
    if affected == 0 then cb({ ok = false, msg = L('not_found') }) return end
    audit(src, L('audit_price'), ('%s -> %s'):format(model, price))
    cb({ ok = true, msg = L('price_updated') })
end)

-- ADMIN: stok hızlı güncelle
Bridge.RegisterServerCallback('ks-gallery:server:AdminSetStock', function(src, cb, data)
    if not isAdmin(src) then cb({ ok = false, msg = L('no_perm') }) return end
    if not cooled(src, 'admin', 1500) then cb({ ok = false, msg = L('cooldown') }) return end
    local model = tostring(data and data.model or ''):lower()
    local stock = math.floor(tonumber(data and data.stock) or -1)
    if model == '' then cb({ ok = false, msg = L('model_missing') }) return end
    if stock < 0 then cb({ ok = false, msg = L('stock_invalid') }) return end
    local affected = MySQL.update.await('UPDATE ks_gallery_vehicles SET stock = ? WHERE model = ?', { stock, model })
    if affected == 0 then cb({ ok = false, msg = L('not_found') }) return end
    audit(src, L('audit_stock'), ('%s -> %s'):format(model, stock))
    cb({ ok = true, msg = L('stock_updated') })
end)

-- ADMIN: sil
Bridge.RegisterServerCallback('ks-gallery:server:AdminDelete', function(src, cb, model)
    if not isAdmin(src) then cb({ ok = false, msg = L('no_perm') }) return end
    if not cooled(src, 'admin', 1500) then cb({ ok = false, msg = L('cooldown') }) return end
    model = tostring(model or ''):lower()
    if model == '' then cb({ ok = false, msg = L('model_missing') }) return end
    local affected = MySQL.update.await('DELETE FROM ks_gallery_vehicles WHERE model = ?', { model })
    if affected == 0 then cb({ ok = false, msg = L('not_found') }) return end
    audit(src, L('audit_delete'), model)
    cb({ ok = true, msg = L('deleted_ok', model) })
end)

local function getShowrooms()
    local rows = MySQL.query.await('SELECT * FROM ks_gallery_showrooms ORDER BY is_default DESC, id ASC')
    local out = {}
    for _, r in ipairs(rows or {}) do
        out[#out + 1] = {
            id = r.id,
            label = r.label,
            x = tonumber(r.x), y = tonumber(r.y), z = tonumber(r.z),
            help = r.help ~= '' and r.help or defHelp(r.kind),
            sprite = tonumber(r.blip_sprite) or 326,
            color = tonumber(r.blip_color) or 3,
            scale = tonumber(r.blip_scale) or 0.9,
            is_default = tonumber(r.is_default) == 1,
            kind = (r.kind == 'finance') and 'finance' or 'gallery',
        }
    end
    return out
end

-- Herkes okuyabilir (blip/marker kurulumu)
Bridge.RegisterServerCallback('ks-gallery:server:GetShowrooms', function(_, cb)
    cb(getShowrooms())
end)

local function broadcastShowrooms()
    local rows = getShowrooms()
    TriggerClientEvent('ks-gallery:client:ShowroomsUpdated', -1, rows)
    print('^2[ks-vehicleshop]^7 ' .. L('log_showrooms_pub', #rows))
end

-- ADMIN: marker ekle (konum client'tan gelir = menüye girilen yer, tür seçilir)
Bridge.RegisterServerCallback('ks-gallery:server:AdminAddShowroom', function(src, cb, data)
    if not isAdmin(src) then cb({ ok = false, msg = L('no_perm') }) return end
    if not cooled(src, 'admin', 1500) then cb({ ok = false, msg = L('cooldown') }) return end
    if type(data) ~= 'table' then cb({ ok = false, msg = L('bad_data') }) return end
    local x, y, z = tonumber(data.x), tonumber(data.y), tonumber(data.z)
    if not x or not y or not z then cb({ ok = false, msg = L('show_noloc') }) return end
    local kind = (data.kind == 'finance') and 'finance' or 'gallery'
    local label = tostring(data.label or (kind == 'finance' and 'Borç Ofisi' or 'Galeri')):sub(1, 100)
    if label == '' then label = 'Galeri' end
    local help = tostring(data.help or defHelp(kind)):sub(1, 100)
    if help == '' then help = defHelp(kind) end
    local sp, cl, sc = 326, 3, 0.9
    if kind == 'finance' then
        local fb = (Config.FinanceOffice and Config.FinanceOffice.blip) or {}
        sp, cl, sc = fb.sprite or 108, fb.color or 2, fb.scale or 0.8
    end
    MySQL.insert.await(
        'INSERT INTO ks_gallery_showrooms (label, x, y, z, help, blip_sprite, blip_color, blip_scale, is_default, kind) VALUES (?, ?, ?, ?, ?, ?, ?, ?, 0, ?)',
        { label, x, y, z, help, sp, cl, sc, kind }
    )
    broadcastShowrooms()
    audit(src, L('audit_show_add'), ('%s (%s)'):format(label, kind))
    cb({ ok = true, msg = (kind == 'finance') and L('show_added_finance') or L('show_added_gallery') })
end)

-- ADMIN: blip düzenle (etiket + yardım yazısı)
Bridge.RegisterServerCallback('ks-gallery:server:AdminSetShowroom', function(src, cb, data)
    if not isAdmin(src) then cb({ ok = false, msg = L('no_perm') }) return end
    if not cooled(src, 'admin', 1500) then cb({ ok = false, msg = L('cooldown') }) return end
    local id = math.floor(tonumber(data and data.id) or 0)
    if id <= 0 then cb({ ok = false, msg = L('bad_record') }) return end
    local label = tostring(data.label or ''):sub(1, 100)
    local help = tostring(data.help or ''):sub(1, 100)
    if label == '' or help == '' then cb({ ok = false, msg = L('show_empty') }) return end
    local x, y, z = tonumber(data.x), tonumber(data.y), tonumber(data.z)
    local affected
    if x and y and z then
        affected = MySQL.update.await('UPDATE ks_gallery_showrooms SET label = ?, help = ?, x = ?, y = ?, z = ? WHERE id = ?', { label, help, x, y, z, id })
    else
        affected = MySQL.update.await('UPDATE ks_gallery_showrooms SET label = ?, help = ? WHERE id = ?', { label, help, id })
    end
    if affected == 0 then cb({ ok = false, msg = L('record_not_found') }) return end
    broadcastShowrooms()
    audit(src, L('audit_show_edit'), ('id %s | %s'):format(id, label))
    cb({ ok = true, msg = L('show_saved') })
end)

-- ADMIN: blip sil (varsayılan silinemez)
Bridge.RegisterServerCallback('ks-gallery:server:AdminDeleteShowroom', function(src, cb, id)
    if not isAdmin(src) then cb({ ok = false, msg = L('no_perm') }) return end
    if not cooled(src, 'admin', 1500) then cb({ ok = false, msg = L('cooldown') }) return end
    id = math.floor(tonumber(id) or 0)
    if id <= 0 then cb({ ok = false, msg = L('bad_record') }) return end
    local row = MySQL.single.await('SELECT is_default FROM ks_gallery_showrooms WHERE id = ?', { id })
    if not row then cb({ ok = false, msg = L('record_not_found') }) return end
    if tonumber(row.is_default) == 1 then cb({ ok = false, msg = L('show_nodelete') }) return end
    MySQL.update.await('DELETE FROM ks_gallery_showrooms WHERE id = ?', { id })
    broadcastShowrooms()
    audit(src, L('audit_show_del'), ('id %s'):format(id))
    cb({ ok = true, msg = L('show_deleted') })
end)

-- İZOLE ÖNİZLEME: routing bucket izolasyonu
-- Her izleyici kendine özel bucket'a alınır, çıkınca 0'a döner.
-- Böylece önizleme aracı ve oyuncu diğer oyuncularca görülmez / çarpışmaz.
-- Sunucu, kimlerin galeride/testte olduğunu takip eder; izinsiz bucket événementleri yok sayılır.
local galleryIn = {}
local testActive = {}
local testGen = {}

AddEventHandler('playerDropped', function()
    local src = source
    galleryIn[src] = nil
    testActive[src] = nil
end)

RegisterNetEvent('ks-gallery:server:SetPreviewBucket', function(inPreview)
    local src = source
    if not Config.IsolatedPreview or not Config.IsolatedPreview.enabled then return end
    if not Config.IsolatedPreview.useRoutingBucket then return end
    if inPreview then
        galleryIn[src] = true
        SetPlayerRoutingBucket(src, 1000 + src)
        dprint(('BUCKET: %s izole bucket %s'):format(src, 1000 + src))
    else
        galleryIn[src] = nil
        SetPlayerRoutingBucket(src, 0)
        dprint(('BUCKET: %s normale döndü'):format(src))
    end
end)


-- Satın alınan aracın güncel modlarını kaydet (seçili renk garajda da yaşasın)
-- Sahiplik citizenid ile doğrulanır, başkası adına kayıt atılamaz.
RegisterNetEvent('ks-gallery:server:SaveMods', function(plate, props)
    local src = source
    local Player = Bridge.GetPlayer(src)
    if not Player then return end
    if type(plate) ~= 'string' or plate == '' then return end
    if type(props) ~= 'table' then return end
    local encoded = json.encode(props)
    if #encoded > 8192 then return end -- şişirilmiş mod verisini reddet
    MySQL.update.await('UPDATE player_vehicles SET mods = ? WHERE plate = ? AND citizenid = ?',
        { encoded, plate, Player.PlayerData.citizenid })
end)
-- Sürüş bitince client bucket 0'a döndürür; güvenlik için server da zaman aşımı koyar.
-- TEST SÜRÜŞÜ BUCKET (bucketBase + server id: id 1 -> 5001, id 100 -> 5100, id 1000 -> 6000)
-- Sürüş bitince client bucket 0'a döndürür; güvenlik için server da zaman aşımı koyar.
local function testBucket(src)
    local base = (Config.TestDrive and Config.TestDrive.bucketBase) or 5000
    return base + src
end

RegisterNetEvent('ks-gallery:server:TestDriveBucket', function(active)
    local src = source
    if active then
        testActive[src] = true
        galleryIn[src] = nil
        local gen = (testGen[src] or 0) + 1
        testGen[src] = gen
        SetPlayerRoutingBucket(src, testBucket(src))
        dprint(('TEST BUCKET: %s -> %s'):format(src, testBucket(src)))
        local ms = (((Config.TestDrive and Config.TestDrive.duration) or 60) * 1000) + 15000
        SetTimeout(ms, function()
            if testGen[src] ~= gen then return end -- arada yeni sürüş başladıysa dokunma
            testActive[src] = nil
            if GetPlayerPing(src) > 0 then
                SetPlayerRoutingBucket(src, 0)
                dprint(('TEST BUCKET timeout: %s -> 0'):format(src))
            end
        end)
    else
        testActive[src] = nil
        SetPlayerRoutingBucket(src, 0)
        dprint(('TEST BUCKET: %s -> 0'):format(src))
    end
end)

-- Test aracının entity bucket'ını sürücüsüyle eşitle
-- Doğrulama: sürüş aktif mi + entity araç mı + oyuncuya yakın mı (grief engeli)
RegisterNetEvent('ks-gallery:server:TestDriveEntity', function(netId)
    local src = source
    if not testActive[src] then return end
    netId = tonumber(netId) or 0
    if netId == 0 then return end
    local ent = NetworkGetEntityFromNetworkId(netId)
    if ent == 0 or not DoesEntityExist(ent) then return end
    if GetEntityType(ent) ~= 2 then return end
    local ped = GetPlayerPed(src)
    if ped == 0 then return end
    if #(GetEntityCoords(ent) - GetEntityCoords(ped)) > 25.0 then return end
    SetEntityRoutingBucket(ent, testBucket(src))
    dprint(('TEST ENTITY %s bucket %s'):format(ent, testBucket(src)))
end)

-- ================= TAKSİT SİSTEMİ =================
-- Aralık citizenid bazlı OYUN süresine göre işler: 60 sn'de bir çevrimiçi
-- oyuncuların süresi DB'ye eklenir, vadesi gelen taksit bankadan çekilir.
-- Ödenemezse gecikme sayılır, limite ulaşınca araç haczedilir.

local function getPlaytime(cid)
    return tonumber(MySQL.scalar.await('SELECT seconds FROM ks_finance_playtime WHERE citizenid = ?', { cid })) or 0
end

local function genPlate()
    for _ = 1, 20 do
        local p = (Config.PlatePrefix .. ' ' .. Bridge.RandomInt(4)):upper():gsub('%s+', ' '):sub(1, 8)
        local exists = MySQL.scalar.await('SELECT 1 FROM player_vehicles WHERE plate = ?', { p })
        if not exists then return p end
        Wait(0)
    end
    return nil
end

local function repossess(src, fin)
    local owed = (fin.overdue_count * fin.installment) + (fin.overdue_count * fin.late_fee)
    local row = MySQL.single.await('SELECT license, vehicle, hash, mods, garage FROM player_vehicles WHERE plate = ? AND citizenid = ?', { fin.plate, fin.citizenid })
    if row then
        MySQL.insert.await('INSERT INTO deleted_player_vehicles (citizenid, license, vehicle, hash, mods, plate, garage, owed, finance_id) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)',
            { fin.citizenid, row.license, row.vehicle, row.hash, row.mods, fin.plate, row.garage, owed, fin.id })
        MySQL.update.await('DELETE FROM player_vehicles WHERE plate = ? AND citizenid = ?', { fin.plate, fin.citizenid })
    end
    MySQL.update.await("UPDATE ks_finance SET status = 'repossessed' WHERE id = ?", { fin.id })
    Bridge.Notify(src, L('repo_notify', fin.plate), 'error')
    print('^3[ks-vehicleshop]^7 ' .. L('log_repossess', fin.plate, fin.citizenid, owed))
end

CreateThread(function()
    while true do
        Wait(60000)
        local fin = effFinance()
        for _, pid in ipairs(GetPlayers() or {}) do
            local src = tonumber(pid)
            local Player = src and Bridge.GetPlayer(src)
            if Player then
                local cid = Player.PlayerData.citizenid
                MySQL.update.await('INSERT INTO ks_finance_playtime (citizenid, seconds) VALUES (?, 60) ON DUPLICATE KEY UPDATE seconds = seconds + 60', { cid })
                local pt = getPlaytime(cid)
                local rows = MySQL.query.await("SELECT * FROM ks_finance WHERE citizenid = ? AND status = 'active'", { cid }) or {}
                for _, r in ipairs(rows) do
                    local guard = 0
                    while r.installments_left > 0 and pt >= r.next_due_playtime and guard < 12 do
                        guard = guard + 1
                        if Player.Functions.RemoveMoney('bank', r.installment, 'galeri-taksit-otomatik') then
                            r.installments_left = r.installments_left - 1
                            r.next_due_playtime = r.next_due_playtime + r.interval_secs
                            if r.installments_left <= 0 then
                                MySQL.update.await("UPDATE ks_finance SET installments_left = 0, next_due_playtime = ?, status = 'paid' WHERE id = ?", { r.next_due_playtime, r.id })
                                Bridge.Notify(src, L('fin_done_notify', r.plate), 'success')
                            else
                                MySQL.update.await('UPDATE ks_finance SET installments_left = ?, next_due_playtime = ? WHERE id = ?', { r.installments_left, r.next_due_playtime, r.id })
                            end
                        else
                            r.overdue_count = r.overdue_count + 1
                            r.next_due_playtime = r.next_due_playtime + r.interval_secs
                            MySQL.update.await('UPDATE ks_finance SET overdue_count = ?, next_due_playtime = ? WHERE id = ?', { r.overdue_count, r.next_due_playtime, r.id })
                            if r.overdue_count >= fin.maxOverdue then
                                repossess(src, r)
                                break
                            else
                                Bridge.Notify(src, L('fin_missed', r.plate, r.late_fee, effCurrency()), 'error')
                            end
                        end
                    end
                end
            end
        end
    end
end)

-- Taksitli satın alma
Bridge.RegisterServerCallback('ks-gallery:server:BuyFinance', function(src, cb, data)
    if not cooled(src, 'buy', 5000) then cb({ ok = false, msg = L('cooldown') }) return end
    local fin = effFinance()
    if not fin.enabled then cb({ ok = false, msg = L('fin_off') }) return end
    local Player = Bridge.GetPlayer(src)
    if not Player then cb({ ok = false, msg = L('player_not_found') }) return end
    local model = tostring(data and data.model or ''):lower()
    local count = math.floor(tonumber(data and data.count) or 0)
    if model == '' then cb({ ok = false, msg = L('bad_request') }) return end
    if count < 1 or count > fin.maxInst then cb({ ok = false, msg = L('bad_count', fin.maxInst) }) return end
    local allowed = allowedCategories()
    local row = MySQL.single.await('SELECT * FROM ks_gallery_vehicles WHERE model = ?', { model })
    if not row or not allowed[row.category] then cb({ ok = false, msg = L('not_in_catalog') }) return end
    local price = tonumber(row.price) or 0
    local stock = tonumber(row.stock) or 0
    if stockOn() and stock <= 0 then cb({ ok = false, msg = L('out_of_stock') }) return end
    if price <= 0 then cb({ ok = false, msg = L('bad_price_short') }) return end
    local down = math.ceil(price * fin.downPct / 100)
    if (Player.PlayerData.money['bank'] or 0) < down then
        cb({ ok = false, msg = L('down_short', down, effCurrency()) })
        return
    end
    if not Player.Functions.RemoveMoney('bank', down, 'galeri-pesinat') then
        cb({ ok = false, msg = L('pay_failed') }) return end
    local plate = genPlate()
    if not plate then
        Player.Functions.AddMoney('bank', down, 'galeri-plaka-hata-iade')
        cb({ ok = false, msg = L('plate_failed') }) return end
    local hash = joaat(model)
    local okInsert = MySQL.insert.await(
        'INSERT INTO player_vehicles (license, citizenid, vehicle, hash, mods, plate, garage, state) VALUES (?, ?, ?, ?, ?, ?, ?, ?)',
        { Player.PlayerData.license, Player.PlayerData.citizenid, model, hash, '{}', plate, Config.Garage, 1 }
    )
    if not okInsert then
        Player.Functions.AddMoney('bank', down, 'galeri-db-hata-iade')
        cb({ ok = false, msg = L('db_failed') }) return end
    if stockOn() then
        local aff = MySQL.update.await('UPDATE ks_gallery_vehicles SET stock = stock - 1 WHERE model = ? AND stock > 0', { model })
        if aff == 0 then
            MySQL.update.await('DELETE FROM player_vehicles WHERE plate = ?', { plate })
            Player.Functions.AddMoney('bank', down, 'galeri-stok-hata-iade')
            cb({ ok = false, msg = L('out_of_stock') })
            return
        end
    end
    local debt = price - down
    local inst = math.ceil(debt / count)
    local pt = getPlaytime(Player.PlayerData.citizenid)
    local lateFee = math.ceil(price * fin.lateFeePct / 100)
    MySQL.insert.await('INSERT INTO ks_finance (citizenid, plate, model, label, price, down_paid, installment, installments_total, installments_left, interval_secs, next_due_playtime, overdue_count, late_fee, status) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 0, ?, ?)',
        { Player.PlayerData.citizenid, plate, model, row.label, price, down, inst, count, count, fin.intervalHours * 3600, pt + fin.intervalHours * 3600, lateFee, 'active' })
    -- Anahtar client tarafından verilir (Bridge.GiveVehicleKeys).
    TriggerEvent('qb-log:server:CreateLog', 'shops', L('log_fin_title'),
        L('log_fin_body',
            Player.PlayerData.charinfo.firstname .. ' ' .. Player.PlayerData.charinfo.lastname,
            Player.PlayerData.citizenid, model, down, count, inst, plate), true)
    cb({ ok = true, msg = L('fin_bought_ok'), plate = plate, down = down, count = count, inst = inst })
end)

-- Borçlarım + hacizliler
Bridge.RegisterServerCallback('ks-gallery:server:GetMyFinance', function(src, cb)
    local Player = Bridge.GetPlayer(src)
    if not Player then cb({ debts = {}, repossessed = {}, playtime = 0, currency = effCurrency() }) return end
    local cid = Player.PlayerData.citizenid
    local debts = MySQL.query.await("SELECT * FROM ks_finance WHERE citizenid = ? AND status = 'active' ORDER BY id ASC", { cid }) or {}
    local rep = MySQL.query.await('SELECT * FROM deleted_player_vehicles WHERE citizenid = ? ORDER BY id ASC', { cid }) or {}
    cb({ debts = debts, repossessed = rep, playtime = getPlaytime(cid), currency = effCurrency() })
end)

-- Elden taksit öde (gecikmiş varsa önce onu kapatır)
Bridge.RegisterServerCallback('ks-gallery:server:PayInstallment', function(src, cb, id)
    if not cooled(src, 'pay', 3000) then cb({ ok = false, msg = L('cooldown') }) return end
    local Player = Bridge.GetPlayer(src)
    if not Player then cb({ ok = false, msg = L('player_not_found') }) return end
    id = math.floor(tonumber(id) or 0)
    local row = MySQL.single.await("SELECT * FROM ks_finance WHERE id = ? AND citizenid = ? AND status = 'active'", { id, Player.PlayerData.citizenid })
    if not row then cb({ ok = false, msg = L('debt_not_found') }) return end
    if (row.installments_left or 0) <= 0 then
        MySQL.update.await("UPDATE ks_finance SET status = 'paid' WHERE id = ?", { id })
        cb({ ok = false, msg = L('debt_closed') }) return end
    if (Player.PlayerData.money['bank'] or 0) < row.installment then
        cb({ ok = false, msg = L('insufficient', row.installment, effCurrency()) }) return end
    if not Player.Functions.RemoveMoney('bank', row.installment, 'galeri-taksit-elden') then
        cb({ ok = false, msg = L('pay_failed') }) return end
    local left = row.installments_left - 1
    local over = row.overdue_count or 0
    local nextdue = row.next_due_playtime
    if over > 0 then over = over - 1 else nextdue = nextdue + row.interval_secs end
    local status = (left <= 0) and 'paid' or 'active'
    MySQL.update.await('UPDATE ks_finance SET installments_left = ?, overdue_count = ?, next_due_playtime = ?, status = ? WHERE id = ?',
        { left, over, nextdue, status, id })
    cb({ ok = true, msg = status == 'paid' and L('fin_paid_closed') or L('fin_paid') })
end)

-- Toplu kapatma: kalan taksitlerin tamamını tek seferde öde
Bridge.RegisterServerCallback('ks-gallery:server:PayAllInstallments', function(src, cb, id)
    if not cooled(src, 'pay', 3000) then cb({ ok = false, msg = L('cooldown') }) return end
    local Player = Bridge.GetPlayer(src)
    if not Player then cb({ ok = false, msg = L('player_not_found') }) return end
    id = math.floor(tonumber(id) or 0)
    local row = MySQL.single.await("SELECT * FROM ks_finance WHERE id = ? AND citizenid = ? AND status = 'active'", { id, Player.PlayerData.citizenid })
    if not row then cb({ ok = false, msg = L('debt_not_found') }) return end
    local left = tonumber(row.installments_left) or 0
    if left <= 0 then
        MySQL.update.await("UPDATE ks_finance SET status = 'paid' WHERE id = ?", { id })
        cb({ ok = false, msg = L('debt_closed') }) return end
    local total = left * (tonumber(row.installment) or 0)
    if (Player.PlayerData.money['bank'] or 0) < total then
        cb({ ok = false, msg = L('insufficient', total, effCurrency()) }) return end
    if not Player.Functions.RemoveMoney('bank', total, 'galeri-taksit-toplu') then
        cb({ ok = false, msg = L('pay_failed') }) return end
    MySQL.update.await("UPDATE ks_finance SET installments_left = 0, overdue_count = 0, status = 'paid' WHERE id = ?", { id })
    cb({ ok = true, msg = L('fin_paid_closed') })
end)

-- Hacizli aracı geri al (geciken taksitler + cezalar ödenir, kalan vade devam eder)
Bridge.RegisterServerCallback('ks-gallery:server:ReclaimVehicle', function(src, cb, id)
    if not cooled(src, 'pay', 3000) then cb({ ok = false, msg = L('cooldown') }) return end
    local Player = Bridge.GetPlayer(src)
    if not Player then cb({ ok = false, msg = L('player_not_found') }) return end
    id = math.floor(tonumber(id) or 0)
    local drow = MySQL.single.await('SELECT * FROM deleted_player_vehicles WHERE id = ? AND citizenid = ?', { id, Player.PlayerData.citizenid })
    if not drow then cb({ ok = false, msg = L('record_not_found') }) return end
    if (Player.PlayerData.money['bank'] or 0) < (drow.owed or 0) then
        cb({ ok = false, msg = L('insufficient', drow.owed, effCurrency()) }) return end
    if not Player.Functions.RemoveMoney('bank', drow.owed, 'galeri-haciz-geri-alim') then
        cb({ ok = false, msg = L('pay_failed') }) return end
    MySQL.insert.await('INSERT INTO player_vehicles (license, citizenid, vehicle, hash, mods, plate, garage, state) VALUES (?, ?, ?, ?, ?, ?, ?, ?)',
        { drow.license, drow.citizenid, drow.vehicle, drow.hash, drow.mods or '{}', drow.plate, drow.garage, 1 })
    MySQL.update.await('DELETE FROM deleted_player_vehicles WHERE id = ?', { id })
    if drow.finance_id and drow.finance_id > 0 then
        local frow = MySQL.single.await('SELECT * FROM ks_finance WHERE id = ?', { drow.finance_id })
        if frow then
            local paidOver = math.min(frow.overdue_count or 0, frow.installments_left or 0)
            local left = (frow.installments_left or 0) - paidOver
            local pt = getPlaytime(Player.PlayerData.citizenid)
            local status = (left <= 0) and 'paid' or 'active'
            MySQL.update.await("UPDATE ks_finance SET installments_left = ?, overdue_count = 0, next_due_playtime = ?, status = ? WHERE id = ?",
                { left, pt + (frow.interval_secs or 86400), status, drow.finance_id })
        end
    end
    -- Anahtar client tarafından verilir (Bridge.GiveVehicleKeys).
    cb({ ok = true, msg = L('reclaim_ok'), plate = drow.plate })
end)
