fx_version 'cerulean'
game 'gta5'

author 'Samuel#0008'
description 'Physical waypoint markers displayed in 3D world via DUI'
version '1.0.0'

client_scripts {
    'client.lua'
}

-- DUI files (not ui_page - DUI is rendered off-screen as a texture)
files {
    'web/build/index.html',
    'web/build/assets/*.css',
    'web/build/assets/*.js'
}

lua54 'yes'
