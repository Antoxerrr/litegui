-- ============================================================
--  agent.lua — gateway-агент для litegui-monitor
--
--  Что делает:
--    1. Подгружает драйверы из /lib/lgm/drivers/.
--    2. Раз в pollInterval (по каждому драйверу свой):
--         · находит компоненты нужных типов
--         · читает snapshot через driver.read(proxy)
--         · broadcast'ит один пакет на драйвер по modem'у
--    3. Слушает modem на тот же порт — принимает команды
--       (включить/выключить реактор и т.п.), исполняет через
--       driver.actions[action](proxy, args).
--
--  Запуск:  agent
--  Выход:   Q / Esc / Ctrl+Alt+C
-- ============================================================
local component = require("component")
local computer  = require("computer")
local event     = require("event")
local proto     = require("lgm.protocol")

-- Sanity check: если /lib/lgm/protocol.lua устарел (без encodeSnap),
-- падаем сразу с понятным сообщением, а не циклом «nil value» из главной петли.
do
  local need = { "encodeSnap", "encodeCmd", "decode", "PORT" }
  local missing = {}
  for _, k in ipairs(need) do
    if proto[k] == nil then missing[#missing+1] = k end
  end
  if #missing > 0 then
    local have = {}
    for k in pairs(proto) do have[#have+1] = k end
    io.stderr:write(
      "agent: stale lgm.protocol — missing: " .. table.concat(missing, ", ") .. "\n" ..
      "       found fields: " .. table.concat(have, ", ") .. "\n" ..
      "       run: install.lua agent reactor flux  (and restart this script)\n"
    )
    os.exit(1)
  end
end


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
modem.open(proto.PORT)
if modem.setStrength then modem.setStrength(400) end
local NODE_ID = modem.address

print(("agent: node=%s, port=%d"):format(NODE_ID:sub(1, 8), proto.PORT))
for id, d in pairs(drivers) do
  print(("  driver: %-10s poll=%ds actions=%s"):format(
    id, d.pollInterval,
    d.actions and table.concat((function()
      local k = {}; for n in pairs(d.actions) do k[#k+1] = n end; return k
    end)(), ",") or "—"))
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
    -- Ключ в батче: по умолчанию адрес; драйвер может переопределить.
    local key = addr
    if ok and driver.batchKey then
      local kok, k = pcall(driver.batchKey, addr, snap)
      if kok and k ~= nil then key = tostring(k) end
    end
    if not batch[key] then
      if ok then
        snap._addr = addr  -- сохраним реальный адрес для команд
        batch[key] = snap
      else
        batch[key] = { _error = tostring(snap), _addr = addr }
      end
      count = count + 1
    end
  end
  if count > 0 then
    modem.broadcast(proto.PORT, proto.encodeSnap(driver.id, NODE_ID, batch))
    print(("  → [%s] %d entr%s"):format(driver.id, count, count == 1 and "y" or "ies"))
  end
end

-- ── Command handling ─────────────────────────────────────
local function handleCommand(pkt)
  local driver = drivers[pkt.driverId]
  if not driver then
    print(("  ← cmd: unknown driver '%s'"):format(tostring(pkt.driverId)))
    return
  end
  local action = driver.actions and driver.actions[pkt.action]
  if not action then
    print(("  ← cmd: driver '%s' has no action '%s'"):format(pkt.driverId, tostring(pkt.action)))
    return
  end

  local targets = {}
  if pkt.target == "*" then
    for _, addr in ipairs(listAddresses(driver)) do targets[#targets+1] = addr end
  elseif type(pkt.target) == "string" then
    targets[1] = pkt.target
  end

  local ok_count, err_count = 0, 0
  for _, addr in ipairs(targets) do
    local proxy = component.proxy(addr)
    local ok, err = pcall(action, proxy, pkt.args or {})
    if ok then ok_count = ok_count + 1
    else
      err_count = err_count + 1
      print(("  ! cmd %s.%s on %s: %s"):format(pkt.driverId, pkt.action, addr:sub(1,8), tostring(err)))
    end
  end
  print(("  ← cmd %s.%s target=%s ok=%d err=%d"):format(
    pkt.driverId, pkt.action, tostring(pkt.target):sub(1,8), ok_count, err_count))

  -- Принудительный poll сразу — чтобы дашборд увидел новое состояние
  driver._lastPoll = 0
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
  if name == "modem_message" then
    local pkt = proto.decode(table.unpack(ev, 6))
    if pkt and pkt.type == "cmd" then
      handleCommand(pkt)
    end
  end
end

modem.close(proto.PORT)
print("agent: stopped.")
