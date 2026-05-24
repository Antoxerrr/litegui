-- ============================================================
--  lgm.ui — построение UI дашборда из state.
--
--  Главная функция: ui.build(state, bus) → корневой элемент litegui.
--    state — таблица из lgm.state (state.reactors, state.flux, ...)
--    bus   — объект с :sendCmd(nodeId, driverId, target, action, args)
--
--  Layout (160×50):
--    header h=3
--    grid реакторов 3×2 h=21 (карточки 52×10)
--    нижний ряд h=24: сводка | управление | flux
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
  cyan     = 0x22D3EE,
  white    = 0xF8FAFC,
  dim      = 0x64748B,
  dimmer   = 0x3A4256,
}
M.colors = C

-- ── Format helpers ───────────────────────────────────────
local function fmtRF(n)
  n = n or 0
  if n >= 1e9 then return string.format("%.2fG", n / 1e9) end
  if n >= 1e6 then return string.format("%.2fM", n / 1e6) end
  if n >= 1e3 then return string.format("%.1fk", n / 1e3) end
  return string.format("%.1f", n)
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

-- ── Карточка одного реактора (52×10) ─────────────────────
local function buildReactorCard(reactor, index, bus, isStale)
  local r = reactor
  local active = safe(r.active, false)
  local statusBg = active and C.green or C.dimmer
  local statusFg = active and 0x000000 or C.white
  local statusText = active and "ВКЛ" or "ВЫКЛ"

  local tMax = math.max(r.tempMax or 0, 1)
  local tempPct = math.min((r.temp or 0) / tMax, 1)
  local tC = tempColor(r.temp, tMax)

  local cMax = math.max(r.coolantMax or 0, 1)
  local coolantPct = math.min((r.coolant or 0) / cMax, 1)
  local hasCoolant = r.liquid == true

  local toggleLabel  = active and "ОТКЛЮЧИТЬ" or "ВКЛЮЧИТЬ"
  local toggleAction = active and "off" or "on"
  local toggleBg     = active and C.red or C.green
  local toggleFg     = active and C.white or 0x000000

  local title = "Реактор " .. tostring(index)
  local typeStr = (hasCoolant and "Fluid" or "Air") .. " · L" .. tostring(r.level or 0)
  local addr = (r._addr or "?"):sub(1, 8)

  return el.panel {
    bg = isStale and C.panel3 or C.panel,
    border = isStale and C.dimmer or C.border,
    title = title,
    titleFg = isStale and C.dim or C.accent,
    shadow = true, shadowColor = C.shadow,
    children = {
      -- Статус-бэдж в правом верхнем углу (накладывается на верхнюю рамку)
      el.badge { x = 52 - 6, y = 1, label = statusText, bg = statusBg, fg = statusFg },

      -- Адрес + тип
      el.text { x = 2, y = 2, text = addr .. " · " .. typeStr, fg = C.dim },

      -- Нагрев + value
      el.text { x = 2, y = 3, text = "Нагрев", fg = C.dim },
      el.text { x = 10, y = 3,
                text = (r.temp or 0) .. "/" .. (r.tempMax or 0) .. " °C",
                fg = tC },
      el.progress { x = 2, y = 4, w = 48, value = tempPct, fgFill = tC, bg = C.panel2 },

      -- Генерация
      el.text { x = 2, y = 5, text = "Ген", fg = C.dim },
      el.text { x = 10, y = 5,
                text = fmtRF(r.gen) .. " mRF/t",
                fg = active and C.green or C.dim },

      -- Охлаждение / расход
      el.text { x = 2, y = 6, text = "Охлад", fg = C.dim },
      el.text { x = 10, y = 6,
                text = hasCoolant
                       and (fmtMb(r.coolant) .. "/" .. fmtMb(r.coolantMax) .. " mb")
                       or  ((r.coolantConsume or 0) .. " mb/s"),
                fg = C.cyan },

      -- Кнопка вкл/выкл — залитая
      el.button {
        x = 2, y = 8, w = 48, h = 2,
        bg = toggleBg, fg = toggleFg,
        label = toggleLabel,
        shadow = true, shadowColor = C.shadow,
        onClick = function()
          if bus and r._node and r._addr then
            bus:sendCmd(r._node, "reactor", r._addr, toggleAction, {})
          end
        end,
      },
    }
  }
end

-- ── Пустой слот ──────────────────────────────────────────
local function buildEmptySlot(index)
  return el.panel {
    bg = C.panel3, border = C.dimmer,
    title = "Реактор " .. tostring(index),
    titleFg = C.dim,
    shadow = true, shadowColor = C.shadow,
    children = {
      el.text { x = 2, y = 5, text = "не подключён", fg = C.dimmer },
    }
  }
end

-- ── Сводка по реакторам ──────────────────────────────────
local function buildReactorsSummary(reactors)
  local totalGen, hot, hotLim = 0, 0, 1
  local onCount = 0
  for _, r in ipairs(reactors) do
    totalGen = totalGen + (r.gen or 0)
    if r.active then onCount = onCount + 1 end
    local t, tm = r.temp or 0, math.max(r.tempMax or 1, 1)
    if t / tm > hot / math.max(hotLim, 1) then hot, hotLim = t, tm end
  end

  return el.panel {
    w = 50,
    bg = C.panel, border = C.border, title = "Сводка", titleFg = C.accent,
    shadow = true, shadowColor = C.shadow,
    children = {
      el.text { x = 2, y = 2, text = "Активны",  fg = C.dim },
      el.text { x = 13, y = 2,
                text = onCount .. " / " .. #reactors,
                fg = onCount > 0 and C.green or C.dim },

      el.text { x = 2, y = 4, text = "Генерация", fg = C.dim },
      el.text { x = 13, y = 4, text = fmtRF(totalGen) .. " mRF/t", fg = C.green },

      el.text { x = 2, y = 6, text = "Макс нагрев", fg = C.dim },
      el.text { x = 14, y = 6, text = hot .. "/" .. hotLim,
                fg = tempColor(hot, hotLim) },
      el.progress { x = 2, y = 7, w = 46,
                    value = hot / math.max(hotLim, 1),
                    fgFill = tempColor(hot, hotLim), bg = C.panel2 },
    }
  }
end

-- ── Bulk-кнопки управления ───────────────────────────────
local function buildBulkControls(reactors, bus)
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
    w = 40,
    bg = C.panel, border = C.border, title = "Управление", titleFg = C.accent,
    shadow = true, shadowColor = C.shadow,
    children = {
      el.button {
        x = 2, y = 2, w = 36, h = 3,
        bg = C.green, fg = 0x000000,
        label = "ВКЛЮЧИТЬ ВСЕ",
        shadow = true, shadowColor = C.shadow,
        onClick = bulk("on"),
      },
      el.button {
        x = 2, y = 6, w = 36, h = 3,
        bg = C.red, fg = C.white,
        label = "ОТКЛЮЧИТЬ ВСЕ",
        shadow = true, shadowColor = C.shadow,
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
      flex = 1,
      bg = C.panel, border = C.border,
      title = "Flux сеть", titleFg = C.accent,
      shadow = true, shadowColor = C.shadow,
      children = {
        el.text { x = 2, y = 2, text = "нет flux сети", fg = C.dim },
      }
    }
  end

  local input  = f.energyInput  or 0
  local output = f.energyOutput or 0
  local balance = input - output
  local balanceColor = balance >= 0 and C.green or C.red
  local balanceText = (balance >= 0 and "+" or "") .. fmtRF(balance)

  local maxRate = math.max(input, output, 1)

  return el.panel {
    flex = 1,
    bg = C.panel, border = C.border,
    title = "Flux · " .. (f.netName or "?"),
    titleFg = C.accent,
    shadow = true, shadowColor = C.shadow,
    children = {
      el.text { x = 2, y = 2,
                text = "id " .. tostring(f.netId) .. " · " .. (f.energyType or ""),
                fg = C.dim },

      el.text { x = 2, y = 4, text = "Приход", fg = C.dim },
      el.text { x = 11, y = 4, text = fmtRF(input) .. " mRF/t", fg = C.green },
      el.progress { x = 2, y = 5, w = 64, value = input / maxRate,
                    fgFill = C.green, bg = C.panel2 },

      el.text { x = 2, y = 7, text = "Расход", fg = C.dim },
      el.text { x = 11, y = 7, text = fmtRF(output) .. " mRF/t", fg = C.yellow },
      el.progress { x = 2, y = 8, w = 64, value = output / maxRate,
                    fgFill = C.yellow, bg = C.panel2 },

      el.text { x = 2, y = 10, text = "Баланс", fg = C.dim },
      el.text { x = 11, y = 10, text = balanceText .. " mRF/t", fg = balanceColor },
    }
  }
end

-- ── Корневой layout ──────────────────────────────────────
function M.build(state, bus)
  local computer = require("computer")
  local now = computer.uptime()
  local reactors = state.reactorList()
  local flux     = state.fluxList()

  -- 6 карточек (3×2). Слоты без реакторов — пустые.
  local cards = {}
  for i = 1, 6 do
    local r = reactors[i]
    if r then
      cards[i] = buildReactorCard(r, i, bus, state.isStale(r, now))
    else
      cards[i] = buildEmptySlot(i)
    end
  end

  -- Статус связи
  local headerStatus = "НЕТ СВЯЗИ"
  local headerStatusColor = C.red
  local headerStatusFg = C.white
  for _, n in pairs(state.nodes) do
    if (now - (n.lastSeen or 0)) <= state.OFFLINE_TIMEOUT then
      headerStatus = "СВЯЗЬ"
      headerStatusColor = C.green
      headerStatusFg = 0x000000
      break
    end
  end

  return el.rect {
    x = 1, y = 1, w = 160, h = 50, bg = C.bg,
    layout = "vbox", gap = 1,
    children = {
      -- HEADER
      el.gradient {
        h = 3, direction = "v", from = 0x2E2E55, to = C.panel,
        children = {
          el.text  { x = 4,   y = 2, text = "▎ LiteGUI · Реакторы", fg = C.accent },
          el.badge { x = 144, y = 2, label = headerStatus,
                     bg = headerStatusColor, fg = headerStatusFg },
          el.text  { x = 130, y = 2, text = "Q — выход", fg = C.dim },
        }
      },

      -- РЕАКТОРЫ
      el.grid {
        h = 21, cols = 3, rows = 2, gap = 1,
        children = cards,
      },

      -- НИЖНИЙ РЯД
      el.hbox {
        flex = 1, gap = 1,
        children = {
          buildReactorsSummary(reactors),
          buildBulkControls(reactors, bus),
          buildFluxPanel(flux),
        }
      },
    }
  }
end

return M
