-- ============================================================
--  lgm.protocol — wire format litegui-monitor
--
--  Два типа пакетов:
--
--  SNAPSHOT (gateway → main, broadcast):
--    magic, version, "s", kind, nodeId, uptime, serializedPayload
--      kind      — id драйвера ("reactor", "flux", ...)
--      nodeId    — modem.address отправителя
--      payload   — { [batchKey] = snapshot }
--
--  COMMAND (main → gateway, direct modem.send):
--    magic, version, "c", driverId, target, action, serializedArgs
--      target    — адрес компонента или "*" (все)
--      action    — имя действия (driver.actions[action])
--      args      — таблица доп. параметров (или пустая)
--
--  decode(...) возвращает таблицу с полем `type` ("snap"|"cmd") или nil.
-- ============================================================
local serialization = require("serialization")
local computer      = require("computer")

local M = {
  PORT    = 1000,
  MAGIC   = "lgm",
  VERSION = 1,
}

function M.encodeSnap(kind, nodeId, payload)
  return M.MAGIC, M.VERSION, "s", kind, nodeId, computer.uptime(), serialization.serialize(payload)
end

function M.encodeCmd(driverId, target, action, args)
  return M.MAGIC, M.VERSION, "c", driverId, target, action, serialization.serialize(args or {})
end

function M.decode(magic, version, kind, ...)
  if magic ~= M.MAGIC then return nil end
  if version ~= M.VERSION then return nil end

  if kind == "s" then
    local driver, nodeId, uptime, serPayload = ...
    if type(serPayload) ~= "string" then return nil end
    local ok, payload = pcall(serialization.unserialize, serPayload)
    if not ok or type(payload) ~= "table" then return nil end
    return {
      type    = "snap",
      kind    = driver,
      nodeId  = nodeId,
      uptime  = uptime,
      payload = payload,
    }
  elseif kind == "c" then
    local driverId, target, action, serArgs = ...
    if type(serArgs) ~= "string" then return nil end
    local ok, args = pcall(serialization.unserialize, serArgs)
    if not ok then return nil end
    return {
      type     = "cmd",
      driverId = driverId,
      target   = target,
      action   = action,
      args     = args or {},
    }
  end
  return nil
end

return M
