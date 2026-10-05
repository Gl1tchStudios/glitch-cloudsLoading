Huds = {
    ['tuff-hud'] = function(visible)
        if visible then exports['tuff-hud']:Show() else exports['tuff-hud']:Hide() end
    end,

    ['jg-hud'] = function(visible)
        exports['jg-hud']:toggleHud(visible)
    end,

    ['esx_hud'] = function(visible)
        exports['esx_hud']:HudToggle(visible)
    end,

    ['codem-blackhudv2'] = function(visible)
        TriggerEvent('codem-blackhudv2:SetForceHide', not visible, not visible)
    end,
}
