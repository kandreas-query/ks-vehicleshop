-- Framework köprüsü: qb-core ve qbx_core desteği
-- Config.Framework = 'qb-core' | 'qbx_core'
-- qbx modunda DrawText/notify/callback/keys ox_lib + qbx exports üzerinden çalışır.
Bridge = {}
Bridge.isQBX = (Config.Framework == 'qbx_core')

if IsDuplicityVersion() then
    ---------------------------------------------------------------
    -- SERVER
    ---------------------------------------------------------------
    if Bridge.isQBX then
        function Bridge.GetPlayer(src)
            return exports.qbx_core:GetPlayer(src)
        end

        function Bridge.RegisterServerCallback(name, fn)
            lib.callback.register(name, function(source, ...)
                local res = nil
                fn(source, function(...) res = { ... } end, ...)
                return table.unpack(res or {})
            end)
        end

        function Bridge.Notify(src, msg, mtype)
            exports.qbx_core:Notify(src, msg, mtype or 'inform')
        end

        -- Kalıcı anahtar qbx'de client bridge üzerinden verilir (entity gerekir);
        -- bu event yedek/geçiş noktasıdır (qbx modunda işlem yapmaz).
        RegisterNetEvent('ks-gallery:server:GiveKeys', function()
        end)

        function Bridge.RandomInt(n)
            local s = ''
            for _ = 1, (tonumber(n) or 4) do
                s = s .. tostring(math.random(0, 9))
            end
            return s
        end

        -- sn-bridge ile aynı mantık: konsol her zaman admin,
        -- qbx -> 'admin' ace'i, qb-core -> 'command' ace'i (ESX/standalone yok)
        local function validSource(src)
            src = tonumber(src)
            if not src or src < 0 or math.floor(src) ~= src then return nil end
            return src
        end

        -- NOT: IsPlayerAceAllowed bazı buildlerde boolean yerine 1/0 döner.
        -- == true karşılaştırması 1'i elerdi; bu yüzden her iki türe de güvenli bakılır.
        local function aceAllowed(src, ace)
            local r = IsPlayerAceAllowed(src, ace)
            return r == true or r == 1
        end

        function Bridge.IsAdmin(src)
            src = validSource(src)
            if not src then return false end
            if src == 0 then return true end
            if Bridge.isQBX then
                return aceAllowed(src, 'admin')
            end
            return aceAllowed(src, 'command')
        end
    else
        local QBCore = exports['qb-core']:GetCoreObject()
        Bridge.QBCore = QBCore

        function Bridge.GetPlayer(src)
            return QBCore.Functions.GetPlayer(src)
        end

        function Bridge.RegisterServerCallback(name, fn)
            QBCore.Functions.CreateCallback(name, fn)
        end

        function Bridge.Notify(src, msg, mtype)
            TriggerClientEvent('QBCore:Notify', src, msg, mtype or 'primary')
        end

        RegisterNetEvent('ks-gallery:server:GiveKeys', function(plate)
            local src = source
            if type(plate) ~= 'string' or plate == '' then return end
            -- Sahiplik kontrolü: bu plaka gerçekten bu oyuncunun mu?
            local Player = QBCore.Functions.GetPlayer(src)
            if not Player then return end
            local own = MySQL.scalar.await('SELECT 1 FROM player_vehicles WHERE plate = ? AND citizenid = ?', { plate, Player.PlayerData.citizenid })
            if not own then
                print(('^3[ks-vehicleshop]^7 Sahipsiz anahtar isteği reddedildi: %s (%s)'):format(plate, src))
                return
            end
            if GetResourceState('qb-vehiclekeys') == 'started' then
                local ok, err = pcall(function()
                    exports['qb-vehiclekeys']:GiveKeys(src, plate)
                end)
                if not ok then
                    print(('^3[ks-vehicleshop]^7 Anahtar verilemedi (%s): %s'):format(plate, err))
                end
            end
        end)

        function Bridge.RandomInt(n)
            return QBCore.Shared.RandomInt(n)
        end

        -- sn-bridge ile aynı mantık: konsol her zaman admin,
        -- qbx -> 'admin' ace'i, qb-core -> 'command' ace'i (ESX/standalone yok)
        local function validSource(src)
            src = tonumber(src)
            if not src or src < 0 or math.floor(src) ~= src then return nil end
            return src
        end

        -- NOT: IsPlayerAceAllowed bazı buildlerde boolean yerine 1/0 döner.
        local function aceAllowed(src, ace)
            local r = IsPlayerAceAllowed(src, ace)
            return r == true or r == 1
        end

        function Bridge.IsAdmin(src)
            src = validSource(src)
            if not src then return false end
            if src == 0 then return true end
            if Bridge.isQBX then
                return aceAllowed(src, 'admin')
            end
            return aceAllowed(src, 'command')
        end
    end
else
    ---------------------------------------------------------------
    -- CLIENT
    ---------------------------------------------------------------
    if Bridge.isQBX then
        function Bridge.TriggerServerCallback(name, cb, ...)
            lib.callback(name, false, cb, ...)
        end

        local nmap = { success = 'success', error = 'error', primary = 'inform', inform = 'inform' }
        function Bridge.Notify(msg, mtype)
            lib.notify({ description = msg, type = nmap[mtype] or 'inform' })
        end

        local tmap = { left = 'left-center', top = 'top-center', right = 'right-center' }
        function Bridge.ShowText(text, pos)
            lib.showTextUI(text, { position = tmap[pos] or 'left-center' })
        end
        function Bridge.HideText()
            lib.hideTextUI()
        end

        function Bridge.GetPlate(veh)
            return (GetVehicleNumberPlateText(veh) or ''):gsub('^%s*(.-)%s*$', '%1')
        end

        function Bridge.GetVehicleProperties(veh)
            return lib.getVehicleProperties(veh)
        end

        -- Kalıcı anahtar (bridge entity üzerinden çözer, maymuncuk istemez)
        function Bridge.GiveVehicleKeys(plate)
            TriggerEvent('vehiclekeys:client:SetOwner', plate)
        end

        -- Geçici (test) anahtar
        function Bridge.GiveTempKeys(plate)
            TriggerEvent('vehiclekeys:client:SetOwner', plate)
        end
    else
        local QBCore = exports['qb-core']:GetCoreObject()
        Bridge.QBCore = QBCore

        function Bridge.TriggerServerCallback(name, cb, ...)
            QBCore.Functions.TriggerCallback(name, cb, ...)
        end

        function Bridge.Notify(msg, mtype)
            QBCore.Functions.Notify(msg, mtype)
        end

        function Bridge.ShowText(text, pos)
            exports['qb-core']:DrawText(text, pos or 'left')
        end
        function Bridge.HideText()
            exports['qb-core']:HideText()
        end

        function Bridge.GetPlate(veh)
            return QBCore.Functions.GetPlate(veh)
        end

        function Bridge.GetVehicleProperties(veh)
            return QBCore.Functions.GetVehicleProperties(veh)
        end

        function Bridge.GiveVehicleKeys(plate)
            TriggerServerEvent('ks-gallery:server:GiveKeys', plate)
        end

        function Bridge.GiveTempKeys(plate)
            TriggerEvent('qb-vehiclekeys:client:AddKeys', plate)
        end
    end
end
