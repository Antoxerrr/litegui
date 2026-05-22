-- ============================================================
--  lgm.state — состояние мониторинга на главном компе
--
--  Хранит:
--    nodes[nodeId]    — { lastSeen }
--    reactors[addr]   — снапшоты реакторов
--    flux[netId]      — снапшоты flux-сетей (дедуп по netId)
--
--  Главный вызывает state.onSnapshot(pkt) при получении пакета.
--  UI читает state.reactors / state.flux при рендере.
-- ============================================================
local computer = require("computer")

local M = {
  nodes    = {},
  reactors = {},
  flux     = {},
}

-- Порог offline: если узел не отвечал N секунд — считаем мёртвым.
M.OFFLINE_TIMEOUT = 10

local function markNode(nodeId)
  local n = M.nodes[nodeId]
  if not n then
    n = {}
    M.nodes[nodeId] = n
  end
  n.lastSeen = computer.uptime()
end

-- Обработка snapshot-пакета.
function M.onSnapshot(pkt)
  markNode(pkt.nodeId)
  local now = computer.uptime()

  if pkt.kind == "reactor" then
    for _, snap in pairs(pkt.payload) do
      if snap._addr then
        snap._node       = pkt.nodeId
        snap._receivedAt = now
        M.reactors[snap._addr] = snap
      end
    end

  elseif pkt.kind == "flux" then
    for _, snap in pairs(pkt.payload) do
      local id = snap.netId
      if id ~= nil then
        snap._node       = pkt.nodeId
        snap._receivedAt = now
        M.flux[id] = snap
      end
    end
  end
end

function M.isNodeOnline(nodeId, now)
  local n = M.nodes[nodeId]
  if not n then return false end
  return (now - n.lastSeen) <= M.OFFLINE_TIMEOUT
end

function M.isStale(snap, now)
  if not snap or not snap._receivedAt then return true end
  return (now - snap._receivedAt) > M.OFFLINE_TIMEOUT
end

-- Все реакторы как массив (детерминированный порядок по адресу).
function M.reactorList()
  local out = {}
  for _, r in pairs(M.reactors) do out[#out+1] = r end
  table.sort(out, function(a, b) return (a._addr or "") < (b._addr or "") end)
  return out
end

-- Один (любой) flux-сети снапшот — нам пока хватает.
function M.fluxAny()
  return (next(M.flux))
    and select(2, next(M.flux))
    or nil
end

function M.fluxList()
  local out = {}
  for _, f in pairs(M.flux) do out[#out+1] = f end
  return out
end

return M
