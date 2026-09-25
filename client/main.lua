-- Framework erişimi Bridge üzerinden (shared/bridge.lua): qb-core ve qbx_core uyumlu

local inGallery = false
local inAdmin = false -- admin NUI açık mı (marker thread de kullanır)
local inFinance = false -- borç ofisi NUI açık mı (marker thread de kullanır)
local previewVeh = 0
local previewCam = nil
local previewHeading = 0.0
local previewFov = 50.0
local camOrbit = 0.0 -- kameranın araç etrafındaki yatay yörünge açısı (araç sabit durur)
local camPitch = 0.0 -- dikey yörünge farkı (yukarı/aşağı bakış)
local lastManualRotate = 0
local currentShowroom = 1
local testDriving = false
local returnCoords = nil -- galeriden çıkınca dönülecek konum
local UI = nil -- server efektif ayar paketi (restartsız güncel, yoksa Config kullanılır)
local drawPos = 'left' -- DrawText konumu, admin menüsünden değişir (sol/üst/sağ)

-- Server admin değişikliği iterse anında al
RegisterNetEvent('ks-gallery:client:SyncSettings', function(bundle)
    if type(bundle) == 'table' then
        UI = bundle
        if bundle.drawPos then drawPos = bundle.drawPos end
    end
end)

local function dprint(...)
    if Config.Debug then print('^5[ks-vehicleshop]^7', ...) end
end

-- Showroom listesi DB'den gelir (admin menüsünden yönetilir, restartsız güncellenir)
local Showrooms = {}
local blipHandles = {}
local targetBuilt = false

-- Blip ismi: varsayılan satırlarda dile göre otomatik (veya manuel override),
-- özel satırlarda kendi etiketi. Öncelik: manuel > dil > etiket.
-- (buildBlips'ten ÖNCE tanımlı olmalı: Lua lexical scope.)
local function blipName(s)
    local over = Config.BlipNames or {}
    if s.is_default then
        if s.kind == 'finance' then
            if over.finance and over.finance ~= '' then return over.finance end
            return L('blip_finance')
        end
        if over.gallery and over.gallery ~= '' then return over.gallery end
        return L('blip_gallery')
    end
    return s.label or 'Galeri'
end

local function buildBlips()
    for _, b in ipairs(blipHandles) do
        if DoesBlipExist(b) then RemoveBlip(b) end
    end
    blipHandles = {}
    if not Config.UseBlip then return end
    for _, s in ipairs(Showrooms) do
        local b = AddBlipForCoord(s.x, s.y, s.z)
        SetBlipSprite(b, s.sprite or 326)
        SetBlipColour(b, s.color or 3)
        SetBlipScale(b, s.scale or 0.9)
        SetBlipAsShortRange(b, true)
        BeginTextCommandSetBlipName('STRING')
        AddTextComponentString(blipName(s))
        EndTextCommandSetBlipName(b)
        blipHandles[#blipHandles + 1] = b
    end
end

local function buildTargets()
    if not Config.UseTarget then return end
    -- eski zonları temizle
    if targetBuilt then
        if GetResourceState('ox_target') == 'started' then
            pcall(function() exports.ox_target:removeZone('ks-gallery') end)
        elseif GetResourceState('qb-target') == 'started' then
            for _, s in ipairs(Showrooms) do
                pcall(function() exports['qb-target']:RemoveZone('ks-gallery-' .. s.id) end)
            end
        end
    end
    targetBuilt = true
    for _, s in ipairs(Showrooms) do
        local c = vector3(s.x, s.y, s.z)
        local opts = {
            {
                name = 'ks-gallery-open-' .. s.id,
                icon = 'fas fa-car',
                label = (s.kind == 'finance') and 'Borçları Gör' or 'Galeriyi Aç',
                action = function()
                    if s.kind == 'finance' then OpenFinance() else OpenGallery(1, false) end
                end,
            }
        }
        if GetResourceState('ox_target') == 'started' then
            exports.ox_target:addSphereZone({
                name = 'ks-gallery',
                coords = c, radius = 2.5,
                options = opts,
            })
        elseif GetResourceState('qb-target') == 'started' then
            exports['qb-target']:AddBoxZone('ks-gallery-' .. s.id, c, 2.5, 2.5,
                { name = 'ks-gallery-' .. s.id, heading = 0.0, debugPoly = false, minZ = c.z - 2, maxZ = c.z + 2 },
                { options = opts, distance = 2.5 })
        end
    end
end

local function refreshShowrooms()
    Bridge.TriggerServerCallback('ks-gallery:server:GetShowrooms', function(rows)
        Showrooms = rows or {}
        buildBlips()
        buildTargets()
    end)
end

CreateThread(function()
    Wait(1500) -- qb-core + oxmysql otursun
    for i = 1, 6 do
        refreshShowrooms()
        Wait(2000)
        if #Showrooms > 0 then break end
    end
end)

-- Admin değişikliğinde blip/marker anında güncellenir (liste server'dan push ile gelir, ekstra sorgu yok)
RegisterNetEvent('ks-gallery:client:ShowroomsUpdated', function(rows)
    Showrooms = rows or {}
    buildBlips()
    buildTargets()
    print(('^2[ks-vehicleshop]^7 Showroom listesi güncellendi (%d kayıt).'):format(#Showrooms))
end)

-- Marker + E ile açma (liste dinamik, yardım yazısı DB'den)
-- qb-shops ile aynı sistem: qb-core NUI promptu (yuvarlak kutulu, temalı)
local promptRow = nil

CreateThread(function()
    Wait(3000)
    Bridge.TriggerServerCallback('ks-gallery:server:GetUIData', function(bundle)
        if bundle then
            UI = bundle
            if bundle.drawPos then drawPos = bundle.drawPos end
        end
    end)
end)

CreateThread(function()
    while true do
        local sleep = 1000
        local anyNear = false
        if not inGallery and not inAdmin and not inFinance and not Config.UseTarget then
            local ped = PlayerPedId()
            local pc = GetEntityCoords(ped)
            for _, s in ipairs(Showrooms) do
                local c = vector3(s.x, s.y, s.z)
                local dist = #(pc - c)
                if dist < 20.0 then
                    sleep = 0
                    if dist < 2.0 then
                        anyNear = true
                        if promptRow ~= s.id then
                            promptRow = s.id
                            Bridge.ShowText('[E] ' .. (s.help or L('default_help_gallery')), drawPos)
                        end
                        if IsControlJustReleased(0, Config.OpenKey) then
                            Bridge.HideText()
                            promptRow = nil
                            if s.kind == 'finance' then OpenFinance() else OpenGallery(1, false) end
                        end
                    end
                end
            end
        end
        if not anyNear and promptRow then
            promptRow = nil
            Bridge.HideText()
        end
        Wait(sleep)
    end
end)

function OpenGallery(showroomIndex, asAdmin)
    if inGallery then return end
    currentShowroom = showroomIndex or 1
    inGallery = true
    SetNuiFocus(true, true)
    local s = Config.Showrooms[currentShowroom]
    local iso = Config.IsolatedPreview

    -- Dönüş konumunu kaydet
    returnCoords = GetEntityCoords(PlayerPedId())

    -- İzole garaja ışınlan (diğer oyunculara zarar gelmez, araç orada spawnlanır)
    if iso and iso.enabled then
        local vc = iso.vehicleCoords
        RequestCollisionAtCoord(vc.x, vc.y, vc.z)
        SetEntityCoords(PlayerPedId(), vc.x + 2.0, vc.y, vc.z + 0.5, false, false, false, false)
        -- routing bucket izolasyonu (server tarafı)
        TriggerServerEvent('ks-gallery:server:SetPreviewBucket', true)
        Wait(300) -- bucket + collision otursun
    end

    -- Kamerayı önizleme noktasına al (araç spawn olunca araca kilitlenecek)
    previewCam = CreateCam('DEFAULT_SCRIPTED_CAMERA', true)
    if iso and iso.enabled then
        local vc = iso.vehicleCoords
        previewFov = iso.fov or 50.0
        SetCamCoord(previewCam, vc.x + 5.0, vc.y - 5.0, vc.z + 2.0)
        PointCamAtCoord(previewCam, vc.x, vc.y, vc.z + 0.6)
    elseif s and s.preview and s.preview.vehicleCoords then
        local vc = s.preview.vehicleCoords
        previewFov = 50.0
        SetCamCoord(previewCam, vc.x + 5.0, vc.y - 5.0, vc.z + 2.0)
        PointCamAtCoord(previewCam, vc.x, vc.y, vc.z + 0.6)
    end
    SetCamFov(previewCam, previewFov)
    SetCamActive(previewCam, true)
    RenderScriptCams(true, false, 0, true, false)
    -- RADAR / HUD kamerayı bozmasın
    DisplayRadar(false)

    -- Oyuncuyu dondur + gizle ki showroom kamerasını kapatmasın
    FreezeEntityPosition(PlayerPedId(), true)
    SetEntityVisible(PlayerPedId(), false, false)
    SetEntityInvincible(PlayerPedId(), true)

    Bridge.TriggerServerCallback('ks-gallery:server:GetVehicles', function(vehicles)
        Bridge.TriggerServerCallback('ks-gallery:server:GetUIData', function(bundle)
            UI = bundle
            SendNUIMessage({
                action = 'open',
                vehicles = vehicles or {},
                categories = bundle.categories,
                currency = bundle.currency,
                testDrive = bundle.testDrive,
                paint = bundle.paint,
                finance = bundle.finance,
                stock = bundle.stock,
                lang = LocaleStrings,
                locale = Config.Locale,
            })
        end)
    end)
end
exports('OpenGallery', OpenGallery)

-- ADMIN NUI (konum bağımsız /adminvehicleshop, 3D önizleme yok, yönetim paneli)

function OpenAdmin()
    if inGallery or inAdmin then return end
    Bridge.TriggerServerCallback('ks-gallery:server:IsAdmin', function(ok)
        if not ok then
            Bridge.Notify(L('no_perm'), 'error')
            return
        end
        inAdmin = true
        SetNuiFocus(true, true)
        FreezeEntityPosition(PlayerPedId(), true)
        Bridge.TriggerServerCallback('ks-gallery:server:GetVehicles', function(vehicles)
            Bridge.TriggerServerCallback('ks-gallery:server:GetUIData', function(bundle)
                UI = bundle
                SendNUIMessage({ action = 'openAdmin', vehicles = vehicles or {}, bundle = bundle, lang = LocaleStrings, locale = Config.Locale })
            end)
        end)
    end)
end
exports('OpenAdmin', OpenAdmin)

function CloseAdmin()
    if not inAdmin then return end
    inAdmin = false
    SetNuiFocus(false, false)
    SendNUIMessage({ action = 'close' })
    FreezeEntityPosition(PlayerPedId(), false)
end
exports('CloseAdmin', CloseAdmin)

-- KATALOG NPC (ölümsüz + hasar almaz, E/target ile katalog açar)
local catalogPed = 0
local npcPrompt = false

RegisterNetEvent('ks-vehicleshop:client:OpenCatalog', function()
    OpenGallery(1, false)
end)

local function spawnCatalogPed()
    local cfg = Config.CatalogPed
    if not cfg or not cfg.model then return end
    if catalogPed ~= 0 and DoesEntityExist(catalogPed) then return end
    local hash = joaat(cfg.model)
    RequestModel(hash)
    local t = GetGameTimer() + 8000
    while not HasModelLoaded(hash) and GetGameTimer() < t do Wait(10) end
    if not HasModelLoaded(hash) then return end
    local c = cfg.coords
    catalogPed = CreatePed(4, hash, c.x, c.y, c.z, c.w, false, true)
    SetEntityAsMissionEntity(catalogPed, true, true)
    SetEntityInvincible(catalogPed, true)
    SetPedCanRagdoll(catalogPed, false)
    SetBlockingOfNonTemporaryEvents(catalogPed, true)
    FreezeEntityPosition(catalogPed, true)
    SetEntityHealth(catalogPed, 200)
    SetModelAsNoLongerNeeded(hash)
    if Config.UseTarget then
        if GetResourceState('ox_target') == 'started' then
            exports.ox_target:addLocalEntity(catalogPed, {
                { name = 'ks-vs-npc', icon = 'fas fa-car', label = L('target_catalog'), action = function() OpenGallery(1, false) end }
            })
        elseif GetResourceState('qb-target') == 'started' then
            exports['qb-target']:AddTargetEntity(catalogPed, {
                options = { { type = 'client', event = 'ks-vehicleshop:client:OpenCatalog', icon = 'fas fa-car', label = L('target_catalog') } },
                distance = 2.5,
            })
        end
    end
end

-- BORÇ OFİSİ NPC (katalog NPC ile aynı kurallar, borç ekranı açar)
local debtPed = 0
local debtPrompt = false

RegisterNetEvent('ks-vehicleshop:client:OpenFinancePed', function()
    OpenFinance()
end)

local function spawnDebtPed()
    local cfg = Config.DebtPed
    if not cfg or not cfg.model then return end
    if debtPed ~= 0 and DoesEntityExist(debtPed) then return end
    local hash = joaat(cfg.model)
    RequestModel(hash)
    local t = GetGameTimer() + 8000
    while not HasModelLoaded(hash) and GetGameTimer() < t do Wait(10) end
    if not HasModelLoaded(hash) then return end
    local c = cfg.coords
    debtPed = CreatePed(4, hash, c.x, c.y, c.z, c.w, false, true)
    SetEntityAsMissionEntity(debtPed, true, true)
    SetEntityInvincible(debtPed, true)
    SetPedCanRagdoll(debtPed, false)
    SetBlockingOfNonTemporaryEvents(debtPed, true)
    FreezeEntityPosition(debtPed, true)
    SetEntityHealth(debtPed, 200)
    SetModelAsNoLongerNeeded(hash)
    if Config.UseTarget then
        if GetResourceState('ox_target') == 'started' then
            exports.ox_target:addLocalEntity(debtPed, {
                { name = 'ks-vs-npc-debt', icon = 'fas fa-file-invoice-dollar', label = L('target_finance'), action = function() OpenFinance() end }
            })
        elseif GetResourceState('qb-target') == 'started' then
            exports['qb-target']:AddTargetEntity(debtPed, {
                options = { { type = 'client', event = 'ks-vehicleshop:client:OpenFinancePed', icon = 'fas fa-file-invoice-dollar', label = L('target_finance') } },
                distance = 2.5,
            })
        end
    end
end

CreateThread(function()
    Wait(2000)
    spawnCatalogPed()
    spawnDebtPed()
    while true do
        Wait(30000) -- silinirse geri getir
        if catalogPed == 0 or not DoesEntityExist(catalogPed) then
            spawnCatalogPed()
        elseif GetEntityHealth(catalogPed) < 200 then
            SetEntityHealth(catalogPed, 200)
        end
        if debtPed == 0 or not DoesEntityExist(debtPed) then
            spawnDebtPed()
        elseif GetEntityHealth(debtPed) < 200 then
            SetEntityHealth(debtPed, 200)
        end
    end
end)

CreateThread(function()
    while true do
        local sleep = 1000
        if not inGallery and not inAdmin and not inFinance and not testDriving and not Config.UseTarget then
            local pc = GetEntityCoords(PlayerPedId())
            if catalogPed ~= 0 and DoesEntityExist(catalogPed) then
                local nc = GetEntityCoords(catalogPed)
                if #(pc - nc) < 2.5 then
                    sleep = 0
                    if not npcPrompt then
                        npcPrompt = true
                        Bridge.ShowText(L('prompt_gallery'), drawPos)
                    end
                    if IsControlJustReleased(0, Config.OpenKey) then
                        Bridge.HideText()
                        npcPrompt = false
                        OpenGallery(1, false)
                    end
                elseif npcPrompt then
                    npcPrompt = false
                    Bridge.HideText()
                end
            end
            if debtPed ~= 0 and DoesEntityExist(debtPed) then
                local dc = GetEntityCoords(debtPed)
                if #(pc - dc) < 2.5 then
                    sleep = 0
                    if not debtPrompt then
                        debtPrompt = true
                        Bridge.ShowText(L('prompt_finance'), drawPos)
                    end
                    if IsControlJustReleased(0, Config.OpenKey) then
                        Bridge.HideText()
                        debtPrompt = false
                        OpenFinance()
                    end
                elseif debtPrompt then
                    debtPrompt = false
                    Bridge.HideText()
                end
            elseif debtPrompt then
                debtPrompt = false
                Bridge.HideText()
            end
        elseif npcPrompt or debtPrompt then
            npcPrompt = false
            debtPrompt = false
            Bridge.HideText()
        end
        Wait(sleep)
    end
end)

-- BORÇ OFİSİ (taksit borçlarını gör/öde, hacizli aracı geri al)

function OpenFinance()
    if inGallery or inAdmin or inFinance or testDriving then return end
    inFinance = true
    SetNuiFocus(true, true)
    FreezeEntityPosition(PlayerPedId(), true)
    Bridge.TriggerServerCallback('ks-gallery:server:GetMyFinance', function(data)
        Bridge.TriggerServerCallback('ks-gallery:server:GetUIData', function(bundle)
            UI = bundle
            SendNUIMessage({
                action = 'openFinance',
                debts = (data and data.debts) or {},
                repossessed = (data and data.repossessed) or {},
                playtime = (data and data.playtime) or 0,
                currency = bundle.currency,
                lang = LocaleStrings,
                locale = Config.Locale,
            })
        end)
    end)
end
exports('OpenFinance', OpenFinance)

function CloseFinance()
    if not inFinance then return end
    inFinance = false
    SetNuiFocus(false, false)
    SendNUIMessage({ action = 'close' })
    FreezeEntityPosition(PlayerPedId(), false)
end
exports('CloseFinance', CloseFinance)

-- NOT: Borç ofisi de showroom listesinden gelir (kind='finance'), ayrı thread yok.

function CloseGallery()
    if not inGallery then return end
    inGallery = false
    SetNuiFocus(false, false)
    SendNUIMessage({ action = 'close' })
    DeletePreview()
    FreezeEntityPosition(PlayerPedId(), false)
    SetEntityVisible(PlayerPedId(), true, false)
    SetEntityInvincible(PlayerPedId(), false)
    DisplayRadar(true)
    -- İzolasyondan çık: bucket sıfırla + eski konuma dön
    TriggerServerEvent('ks-gallery:server:SetPreviewBucket', false)
    if returnCoords then
        RequestCollisionAtCoord(returnCoords.x, returnCoords.y, returnCoords.z)
        SetEntityCoords(PlayerPedId(), returnCoords.x, returnCoords.y, returnCoords.z, false, false, false, false)
        returnCoords = nil
    end
    if previewCam then
        RenderScriptCams(false, false, 0, true, false)
        DestroyCam(previewCam, false)
        previewCam = nil
    end
end
exports('CloseGallery', CloseGallery)

function DeletePreview()
    if previewVeh ~= 0 and DoesEntityExist(previewVeh) then
        DeleteEntity(previewVeh)
    end
    previewVeh = 0
end

-- Aktif önizleme noktası (araç kategorisine göre interior veya hangar)
local currentSpot = nil

-- Kategoriye göre doğru mekanı seç: military/planes/helicopters -> hangar, diğerleri -> interior
-- Kamera ölçüleri her zaman Config'den gelir (sabit, sorunsuz açı)
local function resolveSpot(category)
    local iso = Config.IsolatedPreview
    local hang = Config.HangarPreview
    category = tostring(category or 'other'):lower()
    if hang and hang.enabled then
        for _, hc in ipairs(hang.categories or {}) do
            if hc == category then
                local vc = hang.vehicleCoords
                return {
                    x = vc.x, y = vc.y, z = vc.z, w = vc.w,
                    dist = hang.camDistance or 9.0,
                    height = hang.camHeight or 3.0,
                    side = hang.camSide or 1.5,
                    lookH = hang.lookAtHeight or 1.0,
                    fov = hang.fov or 55.0,
                    name = 'hangar',
                }
            end
        end
    end
    if iso and iso.enabled then
        local vc = iso.vehicleCoords
        return {
            x = vc.x, y = vc.y, z = vc.z, w = vc.w,
            dist = iso.camDistance or 6.5,
            height = iso.camHeight or 2.0,
            side = iso.camSide or 1.2,
            lookH = iso.lookAtHeight or 0.6,
            fov = iso.fov or 50.0,
            name = 'interior',
        }
    end
    local vc = Config.Showrooms[currentShowroom].preview.vehicleCoords
    return { x = vc.x, y = vc.y, z = vc.z, w = vc.w, dist = 6.5, height = 2.0, side = 1.2, lookH = 0.6, fov = 50.0, name = 'showroom' }
end

local function focusCamOnPreview()
    if not previewCam then return end
    local iso = Config.IsolatedPreview
    if previewVeh ~= 0 and DoesEntityExist(previewVeh) then
        -- SABİT araç, YÖRÜNGE kamera: kamera heading + orbit açısıyla daire çizer
        local spot = currentSpot or resolveSpot('other')
        local vx, vy, vz = table.unpack(GetEntityCoords(previewVeh))
        local dist = spot.dist
        local height = spot.height
        local side = spot.side
        local lookH = spot.lookH
        -- Küresel yörünge: yatay (orbit) + dikey (pitch), zemin altına inmez
        local baseEl = math.deg(math.atan((height - lookH) / dist))
        local el = baseEl + camPitch
        if el < 3.0 then el = 3.0 end
        if el > 85.0 then el = 85.0 end
        camPitch = el - baseEl
        local elr = math.rad(el)
        local rad = math.rad(previewHeading + camOrbit)
        local fx, fy = math.sin(rad), math.cos(rad)
        local rh = dist * math.cos(elr)
        local cx = vx + (fx * rh) + (fy * side)
        local cy = vy + (fy * rh) - (fx * side)
        local cz = vz + lookH + (dist * math.sin(elr))
        SetCamCoord(previewCam, cx, cy, cz)
        PointCamAtCoord(previewCam, vx, vy, vz + lookH)
        SetCamFov(previewCam, previewFov)
        SetCamActive(previewCam, true)
        RenderScriptCams(true, false, 0, true, false)
    else
        local s = Config.Showrooms[currentShowroom]
        if iso and iso.enabled then
            local vc = iso.vehicleCoords
            SetCamCoord(previewCam, vc.x + 5.0, vc.y - 5.0, vc.z + 2.0)
            PointCamAtCoord(previewCam, vc.x, vc.y, vc.z + 0.6)
        elseif s and s.preview and s.preview.vehicleCoords then
            local vc = s.preview.vehicleCoords
            SetCamCoord(previewCam, vc.x + 5.0, vc.y - 5.0, vc.z + 2.0)
            PointCamAtCoord(previewCam, vc.x, vc.y, vc.z + 0.6)
        end
    end
end

-- Önizleme boyası (NUI renk paneli; seçim araçlar arası korunur, spawn'da uygulanır)
local pendingPaint = nil

local function spawnPreview(model, category)
    model = tostring(model or ''):lower()
    if model == '' then return end
    local hash = joaat(model)
    -- ÖNCE doğrula + yükle: model bozuksa mevcut önizlemeye hiç dokunma, eski araç ekranda kalsın
    if not IsModelInCdimage(hash) then
        Bridge.Notify(L('model_not_found', model), 'error')
        return
    end
    RequestModel(hash)
    local t = GetGameTimer() + 8000
    while not HasModelLoaded(hash) and GetGameTimer() < t do Wait(10) end
    if not HasModelLoaded(hash) then
        Bridge.Notify(L('model_load_fail', model), 'error')
        SetModelAsNoLongerNeeded(hash)
        return
    end
    -- Model sağlam, şimdi mekanı kur (hangar veya interior)
    DeletePreview()
    -- Kategoriye göre mekan: hangar (askeri/uçak/helikopter) veya interior (diğerleri)
    currentSpot = resolveSpot(category)
    local c = currentSpot
    previewFov = c.fov
    camOrbit = 0.0 -- her yeni araçta yörüngeyi sıfırla, aynı net açıdan başla
    camPitch = 0.0
    -- Oyuncuyu aktif mekana al (donmuş+görünmez, kimseye zarar gelmez)
    RequestCollisionAtCoord(c.x, c.y, c.z)
    SetEntityCoords(PlayerPedId(), c.x + 2.0, c.y, c.z + 0.5, false, false, false, false)
    previewHeading = c.w + 0.0
    previewVeh = CreateVehicle(hash, c.x, c.y, c.z, c.w, false, false)
    SetEntityAsMissionEntity(previewVeh, true, true)
    SetVehicleDoorsLocked(previewVeh, 2)
    SetEntityInvincible(previewVeh, true)
    FreezeEntityPosition(previewVeh, true)
    SetEntityHeading(previewVeh, previewHeading)
    -- zemine oturt + temizle (siyah/gömük görünümü engelle)
    SetVehicleOnGroundProperly(previewVeh)
    WashDecalsFromVehicle(previewVeh, 1.0)
    SetVehicleDirtLevel(previewVeh, 0.0)
    SetVehicleEngineOn(previewVeh, false, false, true)
    SetVehicleLights(previewVeh, 2)
    SetVehicleInteriorlight(previewVeh, true)
    -- Seçili renk varsa önizlemeye uygula (panelden önce seçilmiş olabilir)
    if pendingPaint then
        SetVehicleCustomPrimaryColour(previewVeh, pendingPaint.r, pendingPaint.g, pendingPaint.b)
        SetVehicleCustomSecondaryColour(previewVeh, pendingPaint.r, pendingPaint.g, pendingPaint.b)
    end
    SetModelAsNoLongerNeeded(hash)
    -- kamerayı araca kilitle
    focusCamOnPreview()
end

-- Önizleme boyası (NUI renk paneli)
RegisterNUICallback('paint', function(data, cb)
    if UI ~= nil and not UI.paint then cb('ok') return end
    local r = math.floor(tonumber(data and data.r) or -1)
    local g = math.floor(tonumber(data and data.g) or -1)
    local b = math.floor(tonumber(data and data.b) or -1)
    if r >= 0 and r <= 255 and g >= 0 and g <= 255 and b >= 0 and b <= 255 then
        pendingPaint = { r = r, g = g, b = b }
        if previewVeh ~= 0 and DoesEntityExist(previewVeh) then
            SetVehicleCustomPrimaryColour(previewVeh, r, g, b)
            SetVehicleCustomSecondaryColour(previewVeh, r, g, b)
        end
    end
    cb('ok')
end)

-- Önizleme aracını aydınlat (kapalı showroom'da siyah kalmasın)
CreateThread(function()
    while true do
        if inGallery and previewVeh ~= 0 and DoesEntityExist(previewVeh) then
            local x, y, z = table.unpack(GetEntityCoords(previewVeh))
            DrawLightWithRange(x, y, z + 3.0, 255, 255, 255, 12.0, 1.0)
            Wait(0)
        else
            Wait(500)
        end
    end
end)

-- Oto-döndürme (şu an kapalı: Config.PreviewAutoRotate = false, araç sabit)
CreateThread(function()
    while true do
        Wait(0)
        if Config.PreviewAutoRotate
            and inGallery and previewVeh ~= 0 and DoesEntityExist(previewVeh) then
            if GetGameTimer() - lastManualRotate > 3000 then
                previewHeading = (previewHeading + 0.25) % 360.0
                SetEntityHeading(previewVeh, previewHeading)
            end
        else
            Wait(500)
        end
    end
end)

-- Güvenli bindirme: oyuncuyu dondur + dokunulmaz yap, aynı tick'te yanına alıp bindir,
-- bindirme bitene kadar çözme. Düşme/hasar imkansız hale gelir.
local function warpIntoVehicle(veh)
    local ped = PlayerPedId()
    FreezeEntityPosition(ped, true)
    SetEntityInvincible(ped, true)
    local vx, vy, vz = table.unpack(GetEntityCoords(veh))
    SetEntityCoords(ped, vx + 2.0, vy, vz + 1.0, false, false, false, false)
    TaskWarpPedIntoVehicle(ped, veh, -1)
    local t = GetGameTimer() + 5000
    while GetVehiclePedIsIn(ped, false) ~= veh and GetGameTimer() < t do Wait(100) end
    FreezeEntityPosition(ped, false)
    SetEntityInvincible(ped, false)
end
-- Boş teslim noktası bul (sabit teslim noktası + showroom yedekleri)
local function getFreeSpawnPoint()
    local spots = {}
    if Config.DeliverySpot then spots[#spots + 1] = Config.DeliverySpot end
    local s = Config.Showrooms[currentShowroom]
    if s and s.spawnPoints then
        for _, sp in ipairs(s.spawnPoints) do spots[#spots + 1] = sp end
    end
    for _, sp in ipairs(spots) do
        local veh = GetClosestVehicle(sp.x, sp.y, sp.z, 3.0, 0, 71)
        if veh == 0 or not DoesEntityExist(veh) then
            return sp
        end
    end
    return nil
end

-- Test sürüşü (havaalanı + 5000+id bucket)
local testVeh = 0

-- TEST plakalı tüm araçları sil (yetim kalanlar dahil süpürülür)
local function deleteTestVehicles()
    local handle, veh = FindFirstVehicle()
    if handle == -1 then return end
    local ok = true
    while ok do
        if veh ~= 0 and DoesEntityExist(veh) then
            local plate = tostring(Bridge.GetPlate(veh) or '')
            if plate:sub(1, 4) == 'TEST' then
                SetEntityAsMissionEntity(veh, true, true)
                DeleteEntity(veh)
            end
        end
        Wait(0)
        ok, veh = FindNextVehicle(handle)
    end
    EndFindVehicle(handle)
end

local function endTestDrive(silent)
    if testVeh ~= 0 and DoesEntityExist(testVeh) then
        DeleteEntity(testVeh)
    end
    testVeh = 0
    testDriving = false
    deleteTestVehicles() -- inme/atlama/süre sonu fark etmez, TEST artığı kalmasın
    -- Bucket 0'a dön
    TriggerServerEvent('ks-gallery:server:TestDriveBucket', false)
    if not silent then
        Bridge.Notify(L('test_ended'), 'primary')
    end
end

local function startTestDrive(model)
    if testDriving then
        Bridge.Notify(L('already_testing'), 'error')
        return
    end
    local tdOn = Config.TestDrive.enabled
    local tdDur = Config.TestDrive.duration or 60
    if UI ~= nil then tdOn, tdDur = UI.testDrive, (UI.testDriveDuration or tdDur) end
    if not tdOn then return end
    model = tostring(model or ''):lower()
    if model == '' then return end
    -- E'ye basılan konumu sakla (galeri marker): çıkışta buraya dönülecek
    local backTo = returnCoords
    if not backTo then
        backTo = Config.Showrooms[currentShowroom].coords
    end
    -- ÖNCE galeriyi kapat (katalog bucket 0'a döner), sonra test bucket'ına geç
    CloseGallery()
    testDriving = true
    TriggerServerEvent('ks-gallery:server:TestDriveBucket', true)
    Wait(600) -- bucket geçişi otursun
    local sp = Config.TestDrive.spawn
    local hash = joaat(model)
    RequestModel(hash)
    local t = GetGameTimer() + 8000
    while not HasModelLoaded(hash) and GetGameTimer() < t do Wait(10) end
    if not HasModelLoaded(hash) then
        Bridge.Notify(L('model_load_fail', model), 'error')
        endTestDrive(true)
        return
    end
    RequestCollisionAtCoord(sp.x, sp.y, sp.z)
    testVeh = CreateVehicle(hash, sp.x, sp.y, sp.z + 1.0, sp.w, true, false)
    FreezeEntityPosition(testVeh, true) -- zemin yüklenene kadar araç düşmesin
    SetEntityAsMissionEntity(testVeh, true, true)
    local ct = GetGameTimer() + 5000
    while not HasCollisionLoadedAroundEntity(testVeh) and GetGameTimer() < ct do Wait(100) end
    SetVehicleOnGroundProperly(testVeh)
    FreezeEntityPosition(testVeh, false)
    -- Seçili renk varsa test aracına da uygula
    if pendingPaint then
        SetVehicleCustomPrimaryColour(testVeh, pendingPaint.r, pendingPaint.g, pendingPaint.b)
        SetVehicleCustomSecondaryColour(testVeh, pendingPaint.r, pendingPaint.g, pendingPaint.b)
    end
    SetModelAsNoLongerNeeded(hash)
    -- Test aracını da aynı bucket'a al (server tarafı)
    local netId = NetworkGetNetworkIdFromEntity(testVeh)
    local tries = 0
    while not NetworkDoesEntityExistWithNetworkId(netId) and tries < 50 do
        Wait(100)
        tries = tries + 1
    end
    TriggerServerEvent('ks-gallery:server:TestDriveEntity', netId)
    SetVehicleNumberPlateText(testVeh, ('TEST%03d'):format(math.random(100, 999)))
    warpIntoVehicle(testVeh)
    Bridge.GiveTempKeys(Bridge.GetPlate(testVeh))
    Bridge.Notify(L('test_started', tdDur), 'success')
    local endTime = GetGameTimer() + (tdDur * 1000)
    local entered = false
    CreateThread(function()
        while testDriving and GetGameTimer() < endTime do
            Wait(500)
            -- Araçtan inildi/atlandı mı? (bindikten sonra kontrol başlar, erken tetiklenmez)
            if entered and GetVehiclePedIsIn(PlayerPedId(), false) ~= testVeh then
                endTestDrive(false)
                Bridge.Notify(L('test_exited'), 'primary')
                if backTo then
                    RequestCollisionAtCoord(backTo.x, backTo.y, backTo.z)
                    SetEntityCoords(PlayerPedId(), backTo.x, backTo.y, backTo.z, false, false, false, false)
                end
                return
            end
            if testVeh ~= 0 and DoesEntityExist(testVeh)
                and GetVehiclePedIsIn(PlayerPedId(), false) == testVeh then
                entered = true
            end
            local left = math.floor((endTime - GetGameTimer()) / 1000)
            if left == 10 then Bridge.Notify(L('test_10s'), 'primary') end
        end
        if testDriving then
            endTestDrive(false)
            if backTo then
                RequestCollisionAtCoord(backTo.x, backTo.y, backTo.z)
                SetEntityCoords(PlayerPedId(), backTo.x, backTo.y, backTo.z, false, false, false, false)
            end
        end
    end)
end

-- Komutlar
-- Açılışta eski TEST artıklarını temizle (crash/restart yetimleri)
CreateThread(function()
    Wait(5000)
    deleteTestVehicles()
end)

-- Admin NUI: konum bağımsız, her yerden açılır (yetki kontrolü OpenAdmin içinde)
RegisterCommand(Config.AdminNUICommand, function() OpenAdmin() end, false)

-- NUI callbackler
RegisterNUICallback('close', function(_, cb)
    if inAdmin then CloseAdmin()
    elseif inFinance then CloseFinance()
    else CloseGallery() end
    cb('ok')
end)

RegisterNUICallback('preview', function(data, cb)
    spawnPreview(data.model, data.category)
    cb('ok')
end)

-- Mouse ile 3D kontrol: ARAÇ SABİT, KAMERA yörüngede döner (runtime rotate izni)
RegisterNUICallback('rotate', function(data, cb)
    local rotEnabled = Config.PreviewRotateEnabled
    if UI ~= nil then rotEnabled = UI.rotate end
    if not rotEnabled then cb('ok') return end
    local dx = tonumber(data and data.dx) or 0.0
    local dy = tonumber(data and data.dy) or 0.0
    -- NUI'dan gelen piksel farkını yörünge açısına çevir, kamerayı yeniden konumlandır
    if previewVeh ~= 0 and DoesEntityExist(previewVeh) then
        camOrbit = (camOrbit + (dx * 0.4)) % 360.0
        camPitch = camPitch + (dy * 0.25) -- yukarı sürükle = kamera alçalır (ters eksen)
        focusCamOnPreview()
        lastManualRotate = GetGameTimer()
    end
    cb('ok')
end)

RegisterNUICallback('refresh', function(_, cb)
    Bridge.TriggerServerCallback('ks-gallery:server:GetVehicles', function(vehicles)
        cb(vehicles or {})
    end)
end)

RegisterNUICallback('buy', function(data, cb)
    local model = tostring(data and data.model or ''):lower()
    if model == '' or not IsModelInCdimage(joaat(model)) then
        cb({ ok = false, msg = L('model_not_found', model) })
        return
    end
    Bridge.TriggerServerCallback('ks-gallery:server:BuyVehicle', function(res)
        if res.ok then
            -- ÖNCE galeriyi kapat: bucket 0'a dön + showroom'a geri ışınlan.
            -- (Önizlemedeyken oyuncu izole bucket'tadır, araç bucket 0'da doğar; kapatmadan bindirme tutmaz.)
            -- Anahtar server tarafında verildi, başarı yazısı gösterilmez: araç önünde belirir, içine bindirilir.
            CloseGallery()
            Wait(500)
            local sp = getFreeSpawnPoint()
            if not sp then
                Bridge.Notify(L('delivery_full'), 'error')
                cb(res)
                return
            end
            local hash = joaat(tostring(data.model):lower())
            RequestModel(hash)
            local t = GetGameTimer() + 8000
            while not HasModelLoaded(hash) and GetGameTimer() < t do Wait(10) end
            if not HasModelLoaded(hash) then
                Bridge.Notify(L('model_fail_garage'), 'error')
                cb(res)
                return
            end
            RequestCollisionAtCoord(sp.x, sp.y, sp.z)
            local veh = CreateVehicle(hash, sp.x, sp.y, sp.z, sp.w, true, false)
            SetVehicleNumberPlateText(veh, res.plate or 'GALERI')
            SetEntityAsMissionEntity(veh, true, true)
            SetVehicleOnGroundProperly(veh)
            -- Seçili renk varsa uygula + garajda da yaşaması için modlara işle
            if pendingPaint then
                SetVehicleCustomPrimaryColour(veh, pendingPaint.r, pendingPaint.g, pendingPaint.b)
                SetVehicleCustomSecondaryColour(veh, pendingPaint.r, pendingPaint.g, pendingPaint.b)
            end
            SetModelAsNoLongerNeeded(hash)
            TriggerServerEvent('ks-gallery:server:SaveMods', res.plate, Bridge.GetVehicleProperties(veh))
            -- Oyuncuyu aracın yanına al, bindir, anahtarı ver
            warpIntoVehicle(veh)
            Bridge.GiveVehicleKeys(res.plate)
        else
            Bridge.Notify(res.msg or L('buy_failed'), 'error')
        end
        cb(res)
    end, data)
end)

-- Taksitli satın alma (peşin akışla aynı teslim: kapat, spawn, boya, bindir, anahtar serverdan)
RegisterNUICallback('buyFinance', function(data, cb)
    local model = tostring(data and data.model or ''):lower()
    if model == '' or not IsModelInCdimage(joaat(model)) then
        cb({ ok = false, msg = L('model_not_found', model) })
        return
    end
    Bridge.TriggerServerCallback('ks-gallery:server:BuyFinance', function(res)
        if res.ok then
            CloseGallery()
            Wait(500)
            local sp = getFreeSpawnPoint()
            if not sp then
                Bridge.Notify(L('delivery_full'), 'error')
                cb(res)
                return
            end
            local hash = joaat(tostring(data.model):lower())
            RequestModel(hash)
            local t = GetGameTimer() + 8000
            while not HasModelLoaded(hash) and GetGameTimer() < t do Wait(10) end
            if not HasModelLoaded(hash) then
                Bridge.Notify(L('model_fail_garage'), 'error')
                cb(res)
                return
            end
            RequestCollisionAtCoord(sp.x, sp.y, sp.z)
            local veh = CreateVehicle(hash, sp.x, sp.y, sp.z, sp.w, true, false)
            SetVehicleNumberPlateText(veh, res.plate or 'GALERI')
            SetEntityAsMissionEntity(veh, true, true)
            SetVehicleOnGroundProperly(veh)
            if pendingPaint then
                SetVehicleCustomPrimaryColour(veh, pendingPaint.r, pendingPaint.g, pendingPaint.b)
                SetVehicleCustomSecondaryColour(veh, pendingPaint.r, pendingPaint.g, pendingPaint.b)
            end
            SetModelAsNoLongerNeeded(hash)
            TriggerServerEvent('ks-gallery:server:SaveMods', res.plate, Bridge.GetVehicleProperties(veh))
            warpIntoVehicle(veh)
            Bridge.GiveVehicleKeys(res.plate)
        else
            Bridge.Notify(res.msg or L('fin_failed'), 'error')
        end
        cb(res)
    end, data)
end)

-- Borç ofisi: liste yenile / taksit öde / hacizli geri al (sonuçla taze liste döner)
RegisterNUICallback('getFinance', function(_, cb)
    Bridge.TriggerServerCallback('ks-gallery:server:GetMyFinance', function(data)
        cb(data or { debts = {}, repossessed = {} })
    end)
end)

RegisterNUICallback('payFinance', function(data, cb)
    Bridge.TriggerServerCallback('ks-gallery:server:PayInstallment', function(res)
        Bridge.Notify(res.msg or L('fin_paid'), res.ok and 'success' or 'error')
        Bridge.TriggerServerCallback('ks-gallery:server:GetMyFinance', function(data2)
            res.debts = (data2 and data2.debts) or {}
            res.repossessed = (data2 and data2.repossessed) or {}
            res.playtime = (data2 and data2.playtime) or 0
            cb(res)
        end)
    end, data and data.id)
end)

RegisterNUICallback('payAllFinance', function(data, cb)
    Bridge.TriggerServerCallback('ks-gallery:server:PayAllInstallments', function(res)
        Bridge.Notify(res.msg or L('fin_paid_closed'), res.ok and 'success' or 'error')
        Bridge.TriggerServerCallback('ks-gallery:server:GetMyFinance', function(data2)
            res.debts = (data2 and data2.debts) or {}
            res.repossessed = (data2 and data2.repossessed) or {}
            res.playtime = (data2 and data2.playtime) or 0
            cb(res)
        end)
    end, data and data.id)
end)

RegisterNUICallback('reclaimVehicle', function(data, cb)
    Bridge.TriggerServerCallback('ks-gallery:server:ReclaimVehicle', function(res)
        Bridge.Notify(res.msg or L('reclaim_ok'), res.ok and 'success' or 'error')
        if res.ok and res.plate then
            Bridge.GiveVehicleKeys(res.plate)
        end
        Bridge.TriggerServerCallback('ks-gallery:server:GetMyFinance', function(data2)
            res.debts = (data2 and data2.debts) or {}
            res.repossessed = (data2 and data2.repossessed) or {}
            res.playtime = (data2 and data2.playtime) or 0
            cb(res)
        end)
    end, data and data.id)
end)

RegisterNUICallback('testdrive', function(data, cb)
    local tdOn = Config.TestDrive.enabled
    if UI ~= nil then tdOn = UI.testDrive end
    if not tdOn then cb({ ok = false }) return end
    startTestDrive(data.model)
    cb({ ok = true })
end)

-- Admin NUI köprüleri (sunucu callbackleri permission kontrollüdür)
RegisterNUICallback('adminUpsert', function(data, cb)
    Bridge.TriggerServerCallback('ks-gallery:server:AdminUpsert', function(res)
        Bridge.Notify(res.msg, res.ok and 'success' or 'error')
        cb(res)
    end, data)
end)

RegisterNUICallback('adminSetPrice', function(data, cb)
    Bridge.TriggerServerCallback('ks-gallery:server:AdminSetPrice', function(res)
        Bridge.Notify(res.msg, res.ok and 'success' or 'error')
        cb(res)
    end, data)
end)

RegisterNUICallback('adminSetStock', function(data, cb)
    Bridge.TriggerServerCallback('ks-gallery:server:AdminSetStock', function(res)
        Bridge.Notify(res.msg, res.ok and 'success' or 'error')
        cb(res)
    end, data)
end)

RegisterNUICallback('adminDelete', function(data, cb)
    Bridge.TriggerServerCallback('ks-gallery:server:AdminDelete', function(res)
        Bridge.Notify(res.msg, res.ok and 'success' or 'error')
        cb(res)
    end, data.model)
end)

-- Admin blip/konum köprüleri (eklemede konum = menüye girilen anlık konum)
RegisterNUICallback('adminGetShowrooms', function(_, cb)
    Bridge.TriggerServerCallback('ks-gallery:server:GetShowrooms', function(rows)
        cb(rows or {})
    end)
end)

RegisterNUICallback('adminAddShowroom', function(data, cb)
    local pc = GetEntityCoords(PlayerPedId())
    data = data or {}
    data.x, data.y, data.z = pc.x, pc.y, pc.z
    Bridge.TriggerServerCallback('ks-gallery:server:AdminAddShowroom', function(res)
        Bridge.Notify(res.msg, res.ok and 'success' or 'error')
        cb(res)
    end, data)
end)

RegisterNUICallback('adminSetShowroom', function(data, cb)
    Bridge.TriggerServerCallback('ks-gallery:server:AdminSetShowroom', function(res)
        Bridge.Notify(res.msg, res.ok and 'success' or 'error')
        cb(res)
    end, data)
end)

RegisterNUICallback('adminDeleteShowroom', function(data, cb)
    Bridge.TriggerServerCallback('ks-gallery:server:AdminDeleteShowroom', function(res)
        Bridge.Notify(res.msg, res.ok and 'success' or 'error')
        cb(res)
    end, data and data.id)
end)

RegisterNUICallback('adminSaveSettings', function(data, cb)
    Bridge.TriggerServerCallback('ks-gallery:server:SaveSettings', function(res)
        if type(res) == 'table' and res.bundle then UI = res.bundle end
        Bridge.Notify(res.msg or L('saved'), res.ok and 'success' or 'error')
        cb(res)
    end, data)
end)

-- NOT: Yönetim /adminvehicleshop NUI panelinden yapılır.

-- ESC / kapanma güvenliği
AddEventHandler('onResourceStop', function(res)
    if res == GetCurrentResourceName() then
        Bridge.HideText()
        promptRow = nil
        if catalogPed ~= 0 and DoesEntityExist(catalogPed) then
            DeleteEntity(catalogPed)
        end
        catalogPed = 0
        if debtPed ~= 0 and DoesEntityExist(debtPed) then
            DeleteEntity(debtPed)
        end
        debtPed = 0
        DeletePreview()
        if testVeh ~= 0 and DoesEntityExist(testVeh) then
            DeleteEntity(testVeh)
        end
        testVeh = 0
        testDriving = false
        TriggerServerEvent('ks-gallery:server:TestDriveBucket', false)
        SetNuiFocus(false, false)
        FreezeEntityPosition(PlayerPedId(), false)
        SetEntityVisible(PlayerPedId(), true, false)
        SetEntityInvincible(PlayerPedId(), false)
        DisplayRadar(true)
        TriggerServerEvent('ks-gallery:server:SetPreviewBucket', false)
        if returnCoords then
            RequestCollisionAtCoord(returnCoords.x, returnCoords.y, returnCoords.z)
            SetEntityCoords(PlayerPedId(), returnCoords.x, returnCoords.y, returnCoords.z, false, false, false, false)
            returnCoords = nil
        end
        if previewCam then
            RenderScriptCams(false, false, 0, true, false)
            DestroyCam(previewCam, false)
        end
    end
end)
