-- ============================================================
--  Driver: Flux Networks (flux_plug)
--
--  Каждый плаг возвращает ГЛОБАЛЬНУЮ информацию по своей сети
--  (energyInput/Output одинаковые у всех плагов одной сети).
--  Главный дедуплицирует по netId — здесь шлём как есть.
-- ============================================================
return {
  id             = "flux",
  componentTypes = { "flux_plug" },
  pollInterval   = 5,

  -- Несколько плагов одной сети дают одинаковые данные.
  -- Группируем по netId — в батче останется по одной записи на сеть.
  batchKey = function(addr, snap) return "net:" .. tostring(snap.netId) end,

  read = function(p)
    local info = p.getEnergyInfo()
    local net  = p.getNetworkInfo()
    return {
      energyInput  = info.energyInput,
      energyOutput = info.energyOutput,
      totalEnergy  = info.totalEnergy,
      totalBuffer  = info.totalBuffer,
      netName      = net.name,
      netId        = net.id,
      energyType   = net.energyType,
    }
  end,
}
