fx_version 'cerulean'
game 'gta5'

author 'Samuel#0008'
description 'Physical waypoint markers displayed in 3D world via DUI'
version '1.0.0'

shared_script '@ox_lib/init.lua'

client_scripts {
    'client.lua'
}

files {
    'config.lua',
    'locales/*.json',
    'web/build/index.html',
    'web/build/assets/*.css',
    'web/build/assets/*.js'
}

lua54 'yes'
