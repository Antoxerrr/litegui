-- ============================================================
--  lgm.ui — построение UI дашборда из state.
--
--  Главная функция: ui.build(state, bus) → корневой элемент litegui.
--    state — таблица из lgm.state (state.reactors, state.flux, ...)
--    bus   — объект с :sendCmd(nodeId, driverId, target, action, args)
--
--  Layout (160×50):
--    h=1   статус-бар (Q — выход + индикатор связи)
--    h=11  ряд из 6 компактных вертикальных карточек реакторов (≈25×11)
--    h=14  нижний ряд: сводка+управление | flux
--  Снизу остаётся пустой фон — дашборду не нужны все 50 строк.
-- ============================================================
local GUI = require("litegui")
local el  = GUI.el

local M = {}

-- ── Палитра ─────────────────────────────────────────────
-- Тёмно-чёрные карточки на серо-синем фоне.
local C = {
  bg       = 0x3A3A48,   -- главный фон (серый)
  panel    = 0x0A0A12,   -- фон карточки (почти чёрный)
  panel2   = 0x1E1E2A,   -- фон прогресс-бара
  panel3   = 0x14141C,   -- фон пустого слота
  accent   = 0x8B5CF6,
  green    = 0x22C55E,
  yellow   = 0xEAB308,
  orange   = 0xF97316,
  red      = 0xEF4444,
  cyan     = 0x06B6D4,
  white    = 0xF8FAFC,
  dim      = 0x8088A0,
  dimmer   = 0x4A4F60,
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

-- ── Вертикальная карточка реактора (~25×11, компактная) ──
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

  local toggleLabel  = active and "Отключить" or "Включить"
  local toggleAction = active and "off" or "on"
  local toggleBg     = active and C.red or C.green
  local toggleFg     = active and C.white or 0x000000

  local title = "Реактор " .. tostring(index)
  local typeStr = (hasCoolant and "Fluid" or "Air") .. " · L" .. tostring(r.level or 0)
  local addr = (r._addr or "?"):sub(1, 8)

  -- badge ширина: " ВКЛ "=5, " ВЫКЛ "=6 — пинуем к правому краю карточки.
  local badgeLen = active and 5 or 6
  local badgeX = 25 - badgeLen

  local coolantText = hasCoolant
                      and (fmtMb(r.coolant) .. "/" .. fmtMb(r.coolantMax))
                      or  ((r.coolantConsume or 0) .. " mb/s")

  local children = {
    el.badge { x = badgeX, y = 1, label = statusText, bg = statusBg, fg = statusFg },

    el.text { x = 2, y = 2, text = addr .. " · " .. typeStr, fg = C.dim },

    -- Нагрев: метка + значение в одну строку, бар ниже.
    el.text { x = 2, y = 4, text = "НАГРЕВ", fg = C.dim },
    el.text { x = 10, y = 4,
              text = (r.temp or 0) .. "/" .. (r.tempMax or 0),
              fg = tC },
    el.progress { x = 2, y = 5, w = 21, value = tempPct, fgFill = tC, bg = C.panel2 },

    -- Ген и Охл — inline (label x=2, value x=8).
    el.text { x = 2, y = 7, text = "ГЕН", fg = C.dim },
    el.text { x = 8, y = 7,
              text = fmtRF(r.gen) .. " mRF/t",
              fg = active and C.green or C.dim },

    el.text { x = 2, y = 8, text = "ОХЛ", fg = C.dim },
    el.text { x = 8, y = 8, text = coolantText, fg = C.cyan },

    -- Кнопка h=3 chamfered rect: углы ▟▙▜▛ съедают по 1 квадранту в outer-углах,
    -- боковины полной высоты ⇒ ~75% «выпуклости».
    -- w=13 = "Отключить" (9) + 2/2 padding. x=7 центрирует в карточке w=25.
    el.button {
      x = 7, y = 9, w = 13, h = 3,
      bg = toggleBg, fg = toggleFg,
      label = toggleLabel,
      rounded = true, cornerBg = C.panel,
      onClick = function()
        if bus and r._node and r._addr then
          bus:sendCmd(r._node, "reactor", r._addr, toggleAction, {})
        end
      end,
    },
  }

  return el.panel {
    bg = isStale and C.panel3 or C.panel,
    title = title,
    titleFg = isStale and C.dim or C.accent,
    rounded = true, cornerBg = C.bg,
    children = children,
  }
end

-- ── Пустой слот ──────────────────────────────────────────
local function buildEmptySlot(index)
  return el.panel {
    bg = C.panel3,
    title = "Реактор " .. tostring(index),
    titleFg = C.dim,
    rounded = true, cornerBg = C.bg,
    children = {
      el.text { x = 2, y = 6, text = "не подключён", fg = C.dimmer },
    }
  }
end

-- ── Сводка + Управление (объединено) ─────────────────────
local function buildSummaryAndControl(reactors, bus)
  local totalGen = 0
  local onCount  = 0
  for _, r in ipairs(reactors) do
    totalGen = totalGen + (r.gen or 0)
    if r.active then onCount = onCount + 1 end
  end

  -- Уникальные ноды для bulk-команды.
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

  -- Панель w=60, кнопки w=46 (две колонки по 28+gap не влезут красиво — оставляем
  -- по одной в строке для крупных тач-зон).
  return el.panel {
    w = 60,
    bg = C.panel, title = "Сводка", titleFg = C.accent,
    rounded = true, cornerBg = C.bg,
    children = {
      el.text { x = 2, y = 2,  text = "Активны",   fg = C.dim },
      el.text { x = 13, y = 2,
                text = onCount .. " / " .. #reactors,
                fg = onCount > 0 and C.green or C.dim },

      el.text { x = 2, y = 3,  text = "Генерация", fg = C.dim },
      el.text { x = 13, y = 3, text = fmtRF(totalGen) .. " mRF/t", fg = C.green },

      -- Chamfered rect h=3: углы ▟▙▜▛ дают ~75% боковины.
      -- w=17 = "Отключить все" (13) + 2/2 padding.
      el.button {
        x = 22, y = 5, w = 17, h = 3,
        bg = C.green, fg = 0x000000,
        label = "Включить все",
        rounded = true, cornerBg = C.panel,
        onClick = bulk("on"),
      },
      el.button {
        x = 22, y = 9, w = 17, h = 3,
        bg = C.red, fg = C.white,
        label = "Отключить все",
        rounded = true, cornerBg = C.panel,
        onClick = bulk("off"),
      },
    }
  }
end

-- ── Flux network panel (компактная: 3 строки данных) ─────
local function buildFluxPanel(fluxList)
  local f = fluxList and fluxList[1]
  if not f then
    return el.panel {
      flex = 1,
      bg = C.panel,
      title = "Flux сеть", titleFg = C.accent,
      rounded = true, cornerBg = C.bg,
      children = {
        el.text { x = 2, y = 2, text = "нет flux сети", fg = C.dim },
      }
    }
  end

  local input   = f.energyInput  or 0
  local output  = f.energyOutput or 0
  local maxRate = math.max(input, output, 1)

  return el.panel {
    flex = 1,
    bg = C.panel,
    title = "Flux · " .. (f.netName or "?"),
    titleFg = C.accent,
    rounded = true, cornerBg = C.bg,
    children = {
      el.text { x = 2, y = 2,
                text = "id " .. tostring(f.netId) .. " · " .. (f.energyType or ""),
                fg = C.dim },

      el.text { x = 2, y = 4,  text = "Приход", fg = C.dim },
      el.text { x = 11, y = 4, text = fmtRF(input) .. " mRF/t", fg = C.green },
      el.progress { x = 2, y = 5, w = 90, value = input / maxRate,
                    fgFill = C.green, bg = C.panel2 },

      el.text { x = 2, y = 7,  text = "Расход", fg = C.dim },
      el.text { x = 11, y = 7, text = fmtRF(output) .. " mRF/t", fg = C.yellow },
      el.progress { x = 2, y = 8, w = 90, value = output / maxRate,
                    fgFill = C.yellow, bg = C.panel2 },
    }
  }
end

-- ── Корневой layout ──────────────────────────────────────
function M.build(state, bus)
  local computer = require("computer")
  local now = computer.uptime()
  local reactors = state.reactorList()
  local flux     = state.fluxList()

  -- 6 вертикальных карточек в один ряд.
  local cards = {}
  for i = 1, 6 do
    local r = reactors[i]
    if r then
      cards[i] = buildReactorCard(r, i, bus, state.isStale(r, now))
    else
      cards[i] = buildEmptySlot(i)
    end
  end

  -- Статус связи.
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
      -- Тонкая шапка: подсказка + индикатор связи (прижато к правому краю).
      el.rect {
        h = 1, bg = C.bg,
        children = {
          el.text  { x = 132, y = 1, text = "Q — выход", fg = C.dim },
          el.badge { x = 144, y = 1, label = headerStatus,
                     bg = headerStatusColor, fg = headerStatusFg },
        }
      },

      -- РЕАКТОРЫ: 6 компактных вертикальных карточек в один ряд.
      el.grid {
        h = 12, cols = 6, rows = 1, gap = 1,
        children = cards,
      },

      -- НИЖНИЙ РЯД: Сводка+Управление | Flux. Высота фиксирована,
      -- ниже него — пустой серый фон (дашборду не нужны все 50 строк).
      el.hbox {
        h = 14, gap = 1,
        children = {
          buildSummaryAndControl(reactors, bus),
          buildFluxPanel(flux),
        }
      },
    }
  }
end

return M
