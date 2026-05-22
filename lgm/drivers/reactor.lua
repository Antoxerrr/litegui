-- ============================================================
--  Driver: htc_reactors_nuclear_reactor (Void Studio)
-- ============================================================
return {
  id             = "reactor",
  componentTypes = { "htc_reactors_nuclear_reactor" },
  pollInterval   = 2,                            -- секунды

  -- Читает один реактор по его proxy, возвращает snapshot.
  -- Любой выброс ловится в agent → snapshot заменяется на {_error=...}.
  read = function(p)
    return {
      active         = p.hasWork(),
      temp           = p.getTemperature(),
      tempMax        = p.getMaxTemperature(),
      gen            = p.getEnergyGeneration(),
      coolant        = p.getFluidCoolant(),
      coolantMax     = p.getMaxFluidCoolant(),
      coolantConsume = p.getFluidCoolantConsume(),
      level          = p.getReactorLevel(),
      liquid         = p.isActiveCooling(),
    }
  end,

  -- Доступные действия. Имя действия → функция(proxy, args).
  -- Агент вызывает их при получении cmd-пакета.
  actions = {
    on  = function(p) p.activate()   end,
    off = function(p) p.deactivate() end,
  },
}
