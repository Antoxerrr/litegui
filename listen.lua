-- ============================================================
--  listen.lua — debug-листенер для litegui-monitor
--
--  Запускается на главном компьютере. Слушает modem на нужном
--  порту, валидирует пакеты, печатает приходящие snapshot'ы.
--  Это не дашборд — это проверка что трубопровод работает.
--
--  Запуск:  lua listen.lua
--  Выход:   Ctrl+Alt+C
-- ============================================================
local component = require("component")
local event     = require("event")
local proto     = require("lgm.protocol")

if not component.isAvailable("modem") then
  error("listen: no modem component (insert a Network Card)")
end
local modem = component.modem
modem.open(proto.PORT)
if modem.setStrength then modem.setStrength(400) end

print(("listen: port=%d, self=%s"):format(proto.PORT, modem.address:sub(1, 8)))
print("waiting for broadcasts. Ctrl+Alt+C to stop.")
print(("─"):rep(60))

local function countKeys(t)
  local n = 0
  for _ in pairs(t) do n = n + 1 end
  return n
end

local function printSnapshot(addr, snap)
  if snap._error then
    print(("    %s  ! %s"):format(addr:sub(1, 8), snap._error))
    return
  end
  local parts = {}
  for k, v in pairs(snap) do
    parts[#parts+1] = k .. "=" .. tostring(v)
  end
  print(("    %s  %s"):format(addr:sub(1, 8), table.concat(parts, "  ")))
end

while true do
  local ev = { event.pull(1) }
  local name = ev[1]
  if name == "interrupted" then break end
  if name == "modem_message" then
    -- ev = { "modem_message", localAddr, fromAddr, port, distance, ...payload }
    local pkt = proto.decode(table.unpack(ev, 6))
    if pkt then
      print(("[%s] kind=%s node=%s dist=%s items=%d"):format(
        os.date("%H:%M:%S"),
        pkt.kind,
        pkt.nodeId:sub(1, 8),
        tostring(ev[5] or "?"),
        countKeys(pkt.payload)
      ))
      for addr, snap in pairs(pkt.payload) do
        printSnapshot(addr, snap)
      end
    end
  end
end

modem.close(proto.PORT)
print("listen: stopped.")
