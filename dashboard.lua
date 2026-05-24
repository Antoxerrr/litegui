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
--  Запуск:  dashboard.lua
--  Выход:   Q / Esc / Ctrl+Alt+C
--
--  Любая ошибка (на старте или в цикле) восстановит экран
--  и выведет traceback + запишет копию в /home/dashboard.err.
-- ============================================================

-- ── Safety: error reporter ───────────────────────────────
-- Восстанавливает читаемый экран и печатает traceback наружу.
local function reportError(err)
  local ok_gpu, component = pcall(require, "component")
  if ok_gpu and component.isAvailable("gpu") then
    local gpu = component.gpu
    pcall(gpu.setResolution, 80, 25)
    pcall(gpu.setBackground, 0x000000)
    pcall(gpu.setForeground, 0xFFFFFF)
    local w, h = gpu.getResolution()
    pcall(gpu.fill, 1, 1, w, h, " ")
  end
  io.write("\n=== dashboard error ===\n")
  io.write(tostring(err) .. "\n")
  io.write("=======================\n")
  local f = io.open("/home/dashboard.err", "w")
  if f then
    f:write(os.date() .. "\n")
    f:write(tostring(err) .. "\n")
    f:close()
    io.write("(copy written to /home/dashboard.err)\n")
  end
end

local function main()
  io.write("dashboard: starting...\n")

  local component = require("component")
  local computer  = require("computer")
  local event     = require("event")
  io.write("dashboard: requiring litegui...\n")
  local GUI       = require("litegui")
  io.write("dashboard: requiring lgm modules...\n")
  local proto     = require("lgm.protocol")
  local state     = require("lgm.state")
  local ui        = require("lgm.ui")

  -- ── Resolution ─────────────────────────────────────────
  if not component.isAvailable("gpu") then
    error("dashboard: no gpu component")
  end
  local gpu = component.gpu
  local maxW, maxH = gpu.maxResolution()
  io.write(("dashboard: gpu maxResolution = %dx%d\n"):format(maxW, maxH))
  local W = math.min(160, maxW)
  local H = math.min(50,  maxH)
  io.write(("dashboard: setting resolution %dx%d\n"):format(W, H))
  gpu.setResolution(W, H)

  -- ── Modem ──────────────────────────────────────────────
  if not component.isAvailable("modem") then
    error("dashboard: no modem component (insert a Network Card)")
  end
  local modem = component.modem
  modem.open(proto.PORT)
  if modem.setStrength then modem.setStrength(400) end
  io.write(("dashboard: modem ok, listening on port %d\n"):format(proto.PORT))

  -- ── Command bus ────────────────────────────────────────
  local bus = {}
  function bus:sendCmd(nodeId, driverId, target, action, args)
    modem.send(nodeId, proto.PORT, proto.encodeCmd(driverId, target, action, args))
  end

  -- ── Render helpers ─────────────────────────────────────
  local function redraw()
    local root = ui.build(state, bus)
    GUI.render(root)
    return root
  end

  io.write("dashboard: first render...\n")
  local currentRoot = redraw()
  io.write("dashboard: entering main loop. press Q/Esc to exit.\n")

  -- ── Main loop ──────────────────────────────────────────
  local running = true
  local dirty   = false
  local IDLE_REDRAW = 1.0
  local lastDraw = computer.uptime()

  while running do
    local ev = { event.pull(0.1) }
    local name = ev[1]

    if name == "interrupted" then
      running = false
    elseif name == "key_down" then
      if ev[3] == 113 or ev[3] == 27 then running = false end
    elseif name == "modem_message" then
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
end

local ok, err = xpcall(main, debug.traceback)
if not ok then reportError(err) end
