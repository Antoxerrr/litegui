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
