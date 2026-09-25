-- Locale seçimi (sadece config'den: 'tr' veya 'en')
Locales = Locales or {}
LocaleStrings = Locales[Config.Locale] or Locales['tr'] or {}

-- NOT: L global olmalı (client/server dosyalarından erişilir), local YAPMA!
function L(key, ...)
    local s = LocaleStrings[key]
    if s == nil then return key end
    local args = { ... }
    if #args == 0 then return s end
    local i = 0
    return (s:gsub('%%[sd]', function()
        i = i + 1
        return tostring(args[i] ~= nil and args[i] or '')
    end))
end
