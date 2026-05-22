-- ============================================================
--  lgm.protocol — wire format для litegui-monitor
--
--  Один порт, один magic-маркер. Каждый пакет:
--    magic    : "lgm"
--    version  : 1
--    kind     : имя драйвера ("reactor", "flux", ...)
--    nodeId   : адрес modem'а отправителя (уникален в OC-сети)
--    uptime   : computer.uptime() отправителя на момент отправки
--    payload  : сериализованная таблица { [componentAddress] = snapshot, ... }
--
--  Использование:
--    local proto = require("lgm.protocol")
--    modem.broadcast(proto.PORT, proto.encode("reactor", nodeId, payload))
--    -- on receiver:
--    local pkt = proto.decode(table.unpack(eventArgs, 6))
-- ============================================================
local serialization = require("serialization")
local computer      = require("computer")

local M = {
  PORT    = 1000,
  MAGIC   = "lgm",
  VERSION = 1,
}

function M.encode(kind, nodeId, payload)
  return M.MAGIC, M.VERSION, kind, nodeId, computer.uptime(), serialization.serialize(payload)
end

-- Принимает variadic от modem_message (с 6-го элемента),
-- возвращает таблицу-пакет или nil если это не наш протокол.
function M.decode(magic, version, kind, nodeId, uptime, serializedPayload)
  if magic ~= M.MAGIC then return nil end
  if version ~= M.VERSION then return nil end
  if type(serializedPayload) ~= "string" then return nil end
  local ok, payload = pcall(serialization.unserialize, serializedPayload)
  if not ok or type(payload) ~= "table" then return nil end
  return {
    kind    = kind,
    nodeId  = nodeId,
    uptime  = uptime,
    payload = payload,
  }
end

return M
