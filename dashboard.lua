-- ============================================================
--  dashboard.lua — главный экран litegui-monitor
--
--  Что делает:
--    1. Слушает modem на proto.PORT.
--    2. При получении snapshot-пакета — обновляет state.
--    3. Каждый кадр (или после события) — перестраивает UI
--       через ui.build(state, bus) и рендерит через GUI.render.
--    4. Кнопки в UI шлют команды через bus → modem.send → agent.
--
--  Запуск:  dashboard
--  Выход:   Q / Esc / Ctrl+Alt+C
-- ============================================================
local component = require("component")
local computer  = require("computer")
local event     = require("event")
local GUI       = require("litegui")
local proto     = require("lgm.protocol")
local state     = require("lgm.state")
local ui        = require("lgm.ui")

-- ── Resolution ───────────────────────────────────────────
local gpu = component.gpu
local W, H = 160, 50
gpu.setResolution(W, H)

-- ── Modem ────────────────────────────────────────────────
if not component.isAvailable("modem") then
  error("dashboard: no modem component (insert a Network Card)")
end
local modem = component.modem
modem.open(proto.PORT)
if modem.setStrength then modem.setStrength(400) end

-- ── Command bus ──────────────────────────────────────────
local bus = {}
function bus:sendCmd(nodeId, driverId, target, action, args)
  modem.send(nodeId, proto.PORT, proto.encodeCmd(driverId, target, action, args))
end

-- ── Render helpers ───────────────────────────────────────
local function redraw()
  local root = ui.build(state, bus)
  GUI.render(root)
  return root
end

-- ── Initial draw (state ещё пустое — будут empty slots) ──
local currentRoot = redraw()

-- ── Main loop ────────────────────────────────────────────
local running = true
local dirty   = false
local IDLE_REDRAW = 1.0  -- если ничего не пришло — перерисовка раз в секунду
                          -- (для обновления offline-индикаторов и т.п.)
local lastDraw = computer.uptime()

while running do
  local ev = { event.pull(0.1) }
  local name = ev[1]

  if name == "interrupted" then
    running = false
  elseif name == "key_down" then
    if ev[3] == 113 or ev[3] == 27 then running = false end
  elseif name == "modem_message" then
    -- ev = { "modem_message", localAddr, fromAddr, port, distance, ...payload }
    local pkt = proto.decode(table.unpack(ev, 6))
    if pkt and pkt.type == "snap" then
      state.onSnapshot(pkt)
      dirty = true
    end
  elseif name == "touch" then
    local tx, ty = ev[3], ev[4]
    local buttons = GUI.collectButtons(currentRoot)
    local hit = GUI.hitTest(buttons, tx, ty)
    if hit then
      local ok, err = pcall(hit.onClick)
      if not ok then
        io.stderr:write("button error: " .. tostring(err) .. "\n")
      end
      dirty = true
    end
  end

  local now = computer.uptime()
  if dirty or (now - lastDraw) >= IDLE_REDRAW then
    currentRoot = redraw()
    dirty = false
    lastDraw = now
  end
end

-- Чистый выход
modem.close(proto.PORT)
gpu.setBackground(0x000000)
gpu.setForeground(0xFFFFFF)
gpu.fill(1, 1, W, H, " ")
print("dashboard: stopped.")
