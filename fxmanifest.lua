fx_version 'cerulean'
game 'gta5'
lua54 'yes'
name 'ks-vehicleshop'
author 'KS Development'
description 'qb-core ve qbx_core uyumlu gelistirilebilir vehicle shop + katalog'
version '2.0.0'

ui_page 'html/index.html'

shared_scripts {
    '@ox_lib/init.lua',
    'config.lua',
    'locales/tr.lua',
    'locales/en.lua',
    'locales/init.lua',
    'shared/bridge.lua',
}

client_scripts {
    'client/*.lua',
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server/*.lua',
}

files {
    'html/index.html',
    'html/style.css',
    'html/app.js',
    'html/img/*.png',
}

dependencies {
    'oxmysql',
    'ox_lib',
}

escrow_ignore {
    'config.lua',
    'client/*.lua',
    'server/*.lua',
    'shared/*.lua',
    'locales/*.lua',
    'html/*',
    'sql/*.sql',
}
