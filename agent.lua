-- ============================================================
--  agent.lua — gateway-агент для litegui-monitor
--
--  Запускается на компьютере с прикрученными к нему компонентами
--  (реакторы, flux-плаги, ME-контроллеры и т.д.).
--  Что делает:
--    1. Подгружает все драйверы из /lib/lgm/drivers/.
--    2. Раз в pollInterval (на каждый драйвер свой):
--         · находит все компоненты нужных типов
--         · читает snapshot через driver.read(proxy)
--         · broadcast'ит один пакет на всю пачку по modem'у
--    3. Главный комп (с listen.lua / dashboard.lua) собирает.
--
--  Запуск:  lua agent.lua
--  Выход:   Q / Esc / Ctrl+Alt+C
-- ============================================================
local component = require("component")
local computer  = require("computer")
local event     = require("event")
local proto     = require("lgm.protocol")

-- ── Drivers ──────────────────────────────────────────────
local drivers = {}
local function registerDriver(d)
  drivers[d.id] = d
  d._lastPoll = 0
end

registerDriver(require("lgm.drivers.reactor"))
registerDriver(require("lgm.drivers.flux"))

-- ── Modem ────────────────────────────────────────────────
if not component.isAvailable("modem") then
  error("agent: no modem component (insert a Network Card)")
end
local modem = component.modem
if modem.setStrength then modem.setStrength(400) end
local NODE_ID = modem.address

print(("agent: node=%s, port=%d"):format(NODE_ID:sub(1, 8), proto.PORT))
for id, d in pairs(drivers) do
  print(("  driver: %-10s poll=%ds"):format(id, d.pollInterval))
end

-- ── Discovery + poll ─────────────────────────────────────
local function listAddresses(driver)
  local out = {}
  for _, ctype in ipairs(driver.componentTypes) do
    for address in component.list(ctype, true) do
      out[#out+1] = address
    end
  end
  return out
end

local function pollAndBroadcast(driver)
  local batch = {}
  local count = 0
  for _, addr in ipairs(listAddresses(driver)) do
    local proxy = component.proxy(addr)
    local ok, snap = pcall(driver.read, proxy)
    -- Ключ в батче: по умолчанию адрес компонента; драйвер может
    -- переопределить (см. flux.lua — дедуп по netId).
    local key = addr
    if ok and driver.batchKey then
      local kok, k = pcall(driver.batchKey, addr, snap)
      if kok and k ~= nil then key = tostring(k) end
    end
    if not batch[key] then
      if ok then
        batch[key] = snap
      else
        batch[key] = { _error = tostring(snap) }
      end
      count = count + 1
    end
  end
  if count > 0 then
    modem.broadcast(proto.PORT, proto.encode(driver.id, NODE_ID, batch))
    print(("  → [%s] %d entr%s"):format(driver.id, count, count == 1 and "y" or "ies"))
  end
end

-- ── Main loop ────────────────────────────────────────────
print("agent: running. press Q/Esc to stop.")
while true do
  local now = computer.uptime()
  for _, d in pairs(drivers) do
    if (now - d._lastPoll) >= d.pollInterval then
      d._lastPoll = now
      local ok, err = pcall(pollAndBroadcast, d)
      if not ok then
        print(("  ! driver [%s] crashed: %s"):format(d.id, tostring(err)))
      end
    end
  end

  local ev = { event.pull(0.5) }
  local name = ev[1]
  if name == "interrupted" then break end
  if name == "key_down" and (ev[3] == 113 or ev[3] == 27) then break end
end

print("agent: stopped.")
