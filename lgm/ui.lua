-- ============================================================
--  lgm.ui — построение UI дашборда из state.
--
--  Главная функция: ui.build(state, bus) → корневой элемент litegui.
--    state — таблица из lgm.state (state.reactors, state.flux, ...)
--    bus   — объект с :sendCmd(nodeId, driverId, target, action, args)
--            (используется для onClick кнопок: вкл/выкл реакторы)
--
--  Дашборд перестраивается каждый кадр через GUI.render(ui.build(...)).
-- ============================================================
local GUI = require("litegui")
local el  = GUI.el

local M = {}

-- ── Палитра ──────────────────────────────────────────────
local C = {
  bg       = 0x0F0F1A,
  panel    = 0x1A1A2E,
  panel2   = 0x252540,
  panel3   = 0x1F1F38,
  border   = 0x3D3D5C,
  shadow   = 0x05050A,
  accent   = 0xA78BFA,
  blue     = 0x60A5FA,
  green    = 0x4ADE80,
  yellow   = 0xFBBF24,
  orange   = 0xFB923C,
  red      = 0xF87171,
  pink     = 0xF472B6,
  cyan     = 0x22D3EE,
  white    = 0xF8FAFC,
  dim      = 0x64748B,
  dimmer   = 0x3A4256,
  gaugeBg  = 0x2A2A44,
}
M.colors = C

-- ── Format helpers ───────────────────────────────────────
local function fmtRF(n)
  n = n or 0
  if n >= 1e9 then return string.format("%.2fG", n / 1e9) end
  if n >= 1e6 then return string.format("%.2fM", n / 1e6) end
  if n >= 1e3 then return string.format("%.1fk", n / 1e3) end
  return tostring(math.floor(n))
end

local function fmtMb(n)
  n = n or 0
  if n >= 1e6 then return string.format("%.1fM", n / 1e6) end
  if n >= 1e3 then return string.format("%.1fk", n / 1e3) end
  return tostring(math.floor(n))
end

local function tempColor(t, tMax)
  if not t or not tMax or tMax <= 0 then return C.dim end
  local p = t / tMax
  if p >= 0.85 then return C.red end
  if p >= 0.6  then return C.orange end
  if p >= 0.3  then return C.yellow end
  return C.green
end

local function safe(v, default) if v == nil then return default end; return v end

-- ── Карточка одного реактора ─────────────────────────────
-- размер задаётся снаружи (grid layout). Заполняем абсолютным позиционированием.
local function buildReactorCard(reactor, index, bus, isStale)
  local r = reactor
  local active = safe(r.active, false)
  local statusBg = active and C.green or C.dimmer
  local statusFg = active and 0x000000 or C.dim
  local statusText = active and "ON" or "OFF"

  local tMax = math.max(r.tempMax or 0, 1)
  local tempPct = math.min((r.temp or 0) / tMax, 1)
  local tC = tempColor(r.temp, tMax)

  local cMax = math.max(r.coolantMax or 0, 1)
  local coolantPct = math.min((r.coolant or 0) / cMax, 1)
  local hasCoolant = r.liquid == true

  local toggleLabel = active and "TURN OFF" or "TURN ON"
  local toggleAction = active and "off" or "on"
  local toggleColor = active and C.red or C.green

  local titleFg = isStale and C.dim or C.accent
  local titleText = string.format("R%d", index)

  local panel = el.panel {
    bg = isStale and C.panel3 or C.panel,
    border = isStale and C.dimmer or C.border,
    title = titleText,
    titleFg = titleFg,
    shadow = true, shadowColor = C.shadow,
    children = {
      -- Статус-бэдж в правом верхнем углу
      el.badge { x=43, y=1, label=statusText, bg=statusBg, fg=statusFg },

      -- Адрес + тип охлаждения
      el.text { x=2, y=2, text=(r._addr or "?"):sub(1, 8), fg=C.dim },
      el.text { x=12, y=2,
                text = (hasCoolant and "liquid" or "air") .. " · L" .. tostring(r.level or 0),
                fg = C.dim },

      -- TEMP
      el.text { x=2, y=4, text="TEMP", fg=C.dim },
      el.text { x=7, y=4,
                text = (r.temp or 0) .. "/" .. (r.tempMax or 0) .. " °C",
                fg = tC },
      el.progress { x=2, y=5, w=46, value=tempPct, fgFill=tC, bg=C.panel2 },

      -- GEN
      el.text { x=2, y=6, text="GEN", fg=C.dim },
      el.text { x=6, y=6,
                text = fmtRF(r.gen) .. " RF/t",
                fg = active and C.green or C.dim },

      -- COOLANT (если liquid — показываем уровень, иначе только потребление)
      el.text { x=2, y=7, text="COOL", fg=C.dim },
      el.text { x=7, y=7,
                text = hasCoolant
                       and (fmtMb(r.coolant) .. "/" .. fmtMb(r.coolantMax) .. " mb")
                       or ("-" .. (r.coolantConsume or 0) .. " mb/s"),
                fg = C.cyan },
      el.progress { x=2, y=8, w=46, value=coolantPct, fgFill=C.cyan, bg=C.panel2 },

      -- Кнопка вкл/выкл
      el.button {
        x=2, y=9, w=46, h=2,
        bg = C.panel2, border = toggleColor, borderStyle = "rounded",
        label = toggleLabel, fg = toggleColor,
        shadow = true, shadowColor = C.shadow,
        onClick = function()
          if bus and r._node and r._addr then
            bus:sendCmd(r._node, "reactor", r._addr, toggleAction, {})
          end
        end,
      },
    }
  }

  return panel
end

-- ── Сводка по реакторам (slot со статистикой) ────────────
local function buildReactorsSummary(reactors)
  local totalGen, hotMax, hotMaxLim = 0, 0, 1
  local onCount = 0
  for _, r in ipairs(reactors) do
    totalGen = totalGen + (r.gen or 0)
    if r.active then onCount = onCount + 1 end
    if (r.temp or 0) / math.max(r.tempMax or 1, 1) > hotMax / math.max(hotMaxLim, 1) then
      hotMax = r.temp or 0
      hotMaxLim = r.tempMax or 1
    end
  end

  return el.panel {
    bg=C.panel, border=C.border, title="reactors summary", titleFg=C.accent,
    shadow=true, shadowColor=C.shadow,
    children = {
      el.text { x=2, y=2, text="active", fg=C.dim },
      el.text { x=10, y=2,
                text = onCount .. " / " .. #reactors,
                fg = onCount > 0 and C.green or C.dim },

      el.text { x=2, y=4, text="total gen", fg=C.dim },
      el.text { x=13, y=4, text=fmtRF(totalGen) .. " RF/t", fg=C.green },

      el.text { x=2, y=6, text="hottest", fg=C.dim },
      el.text { x=11, y=6,
                text=hotMax .. "/" .. hotMaxLim,
                fg=tempColor(hotMax, hotMaxLim) },
      el.progress { x=2, y=7, w=28, value=hotMax/math.max(hotMaxLim,1),
                    fgFill=tempColor(hotMax, hotMaxLim), bg=C.panel2 },
    }
  }
end

-- ── Bulk-кнопки управления ───────────────────────────────
local function buildBulkControls(reactors, bus)
  -- Определяем nodeId(ы) gateway'ев — bulk-команда уйдёт каждому уникальному
  local nodes = {}
  for _, r in ipairs(reactors) do
    if r._node then nodes[r._node] = true end
  end
  local nodeList = {}
  for n in pairs(nodes) do nodeList[#nodeList+1] = n end

  local function bulk(action)
    return function()
      if not bus then return end
      for _, n in ipairs(nodeList) do
        bus:sendCmd(n, "reactor", "*", action, {})
      end
    end
  end

  return el.panel {
    bg=C.panel, border=C.border, title="bulk control", titleFg=C.accent,
    shadow=true, shadowColor=C.shadow,
    children = {
      el.button {
        x=2, y=2, w=30, h=2,
        bg=C.panel2, border=C.green, borderStyle="rounded",
        label="ALL REACTORS ON", fg=C.green,
        shadow=true, shadowColor=C.shadow,
        onClick = bulk("on"),
      },
      el.button {
        x=2, y=5, w=30, h=2,
        bg=C.panel2, border=C.red, borderStyle="rounded",
        label="ALL REACTORS OFF", fg=C.red,
        shadow=true, shadowColor=C.shadow,
        onClick = bulk("off"),
      },
    }
  }
end

-- ── Flux network panel ───────────────────────────────────
local function buildFluxPanel(fluxList)
  local f = fluxList and fluxList[1]
  if not f then
    return el.panel {
      flex=1,
      bg=C.panel, border=C.border, title="flux network", titleFg=C.accent,
      shadow=true, shadowColor=C.shadow,
      children = {
        el.text { x=2, y=2, text="no flux network detected", fg=C.dim },
      }
    }
  end

  local input  = f.energyInput  or 0
  local output = f.energyOutput or 0
  local balance = input - output
  local balanceColor = balance >= 0 and C.green or C.red
  local balanceText = (balance >= 0 and "+" or "") .. fmtRF(balance)

  local maxRate = math.max(input, output, 1)
  local inPct  = input  / maxRate
  local outPct = output / maxRate

  return el.panel {
    flex=1,
    bg=C.panel, border=C.border,
    title="flux · " .. (f.netName or "?"),
    titleFg=C.accent,
    shadow=true, shadowColor=C.shadow,
    children = {
      el.text { x=2, y=2, text="net id "..tostring(f.netId).." · "..(f.energyType or ""), fg=C.dim },

      el.text { x=2, y=4, text="INPUT", fg=C.dim },
      el.text { x=8, y=4, text=fmtRF(input).." RF/t", fg=C.green },
      el.progress { x=2, y=5, w=58, value=inPct, fgFill=C.green, bg=C.panel2 },

      el.text { x=2, y=7, text="OUTPUT", fg=C.dim },
      el.text { x=9, y=7, text=fmtRF(output).." RF/t", fg=C.yellow },
      el.progress { x=2, y=8, w=58, value=outPct, fgFill=C.yellow, bg=C.panel2 },

      el.text { x=2, y=10, text="BALANCE", fg=C.dim },
      el.text { x=10, y=10, text=balanceText.." RF/t", fg=balanceColor },
    }
  }
end

-- ── Корневой layout ──────────────────────────────────────
function M.build(state, bus)
  local computer = require("computer")
  local now = computer.uptime()
  local reactors = state.reactorList()
  local flux     = state.fluxList()

  -- Сетка карточек реакторов (до 6, 3×2). Если меньше — пустые слоты.
  local cards = {}
  for i = 1, 6 do
    local r = reactors[i]
    if r then
      local stale = state.isStale(r, now)
      cards[i] = buildReactorCard(r, i, bus, stale)
    else
      cards[i] = el.panel {
        bg=C.panel3, border=C.dimmer, title=("R"..i),
        titleFg=C.dim, shadow=true, shadowColor=C.shadow,
        children = { el.text { x=2, y=2, text="empty slot", fg=C.dimmer } }
      }
    end
  end

  local headerStatus = "OFFLINE"
  local headerStatusColor = C.red
  do
    local anyOnline = false
    for _, n in pairs(state.nodes) do
      if (now - (n.lastSeen or 0)) <= state.OFFLINE_TIMEOUT then
        anyOnline = true; break
      end
    end
    if anyOnline then headerStatus = "ONLINE"; headerStatusColor = C.green end
  end

  return el.rect {
    x=1, y=1, w=160, h=50, bg=C.bg,
    layout="vbox", gap=1,
    children = {
      -- HEADER
      el.gradient {
        h=3, direction="v", from=0x2E2E55, to=C.panel,
        children = {
          el.text { x=4, y=2, text="▎ LiteGUI Monitor", fg=C.accent },
          el.text { x=24, y=2, text="· reactor control panel", fg=C.dim },
          el.badge { x=128, y=2, label=headerStatus, bg=headerStatusColor,
                     fg = headerStatus == "ONLINE" and 0x000000 or 0xFFFFFF },
          el.text { x=140, y=2, text="press Q to exit", fg=C.dim },
        }
      },
      -- REACTORS GRID
      el.grid {
        h=24, cols=3, rows=2, gap=1,
        children = cards,
      },
      -- BOTTOM ROW: summary | bulk controls | flux
      el.hbox {
        flex=1, gap=1,
        children = {
          el.vbox {
            w=34, gap=1,
            children = {
              buildReactorsSummary(reactors),
              buildBulkControls(reactors, bus),
            }
          },
          buildFluxPanel(flux),
        }
      },
    }
  }
end

return M
