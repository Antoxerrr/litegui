-- ============================================================
--  litegui.lua — LiteGUI for OpenComputers
--  Декларативная GUI-библиотека с half-block пиксельной графикой.
--
--  Главный приём: символ "▀" с разными fg/bg = 2 "пикселя" на ячейку.
--  Это даёт эффективное разрешение 80×50 на тиере 2 и позволяет
--  рисовать настоящие круги, дуги, линии и градиенты, а не их
--  символьные карикатуры.
-- ============================================================
--
--  БЫСТРЫЙ СТАРТ
--    local GUI = require("litegui")
--    local el  = GUI.el
--    local s = el.panel { x=1, y=1, w=80, h=25, bg=0x1A1A2E, border=0x7C6FCD,
--                         title="hello", shadow=true }
--    s:add(el.text { x=2, y=3, text="привет", fg=0xFFFFFF })
--    GUI.run(s)
--
--  КОМПОНЕНТЫ
--    rect       — заливка + опц. рамка (border, borderStyle)
--    panel      — rect с заголовком, тенью, скруглением
--    text       — строка
--    button     — кликабельная кнопка
--    progress   — горизонтальный bar (sub-cell precision)
--    gradient   — линейный градиент (direction = "h"|"v")
--    line       — линия в char-координатах
--    circle     — круг в pixel-координатах (fill=true для заливки)
--    arc        — дуга (a0, a1 в радианах, thickness)
--    gauge      — круговой индикатор (value 0..1)
--    sparkline  — мини-график из массива values
--    barchart   — столбчатая диаграмма
--    slider     — визуальный слайдер (value 0..1)
--    badge      — маленький цветной лейбл
--    pixelGrid  — массив пикселей cells[r][c] = color
--
--  Координаты детей — относительно родителя. :add() возвращает родителя.
-- ============================================================

local component = component or require("component")
local event     = event     or require("event")
local unicode   = unicode   or require("unicode")
local gpu       = component.gpu

-- ============================================================
--  UTILS / COLOR MATH
-- ============================================================

local function clamp(v, lo, hi)
  if v < lo then return lo end
  if v > hi then return hi end
  return v
end

local function unpackColor(c)
  local r = math.floor(c / 65536) % 256
  local g = math.floor(c / 256) % 256
  local b = c % 256
  return r, g, b
end

local function packColor(r, g, b)
  return math.floor(r) * 65536 + math.floor(g) * 256 + math.floor(b)
end

local function lerp(a, b, t) return a + (b - a) * t end

local function lerpColor(c1, c2, t)
  local r1, g1, b1 = unpackColor(c1)
  local r2, g2, b2 = unpackColor(c2)
  return packColor(lerp(r1, r2, t), lerp(g1, g2, t), lerp(b1, b2, t))
end

local function darken(c, factor)
  local r, g, b = unpackColor(c)
  return packColor(r * factor, g * factor, b * factor)
end

-- Bresenham (целочисленный список точек)
local function linePoints(x0, y0, x1, y1)
  x0, y0, x1, y1 = math.floor(x0), math.floor(y0), math.floor(x1), math.floor(y1)
  local pts = {}
  local dx = math.abs(x1 - x0)
  local dy = math.abs(y1 - y0)
  local sx = x0 < x1 and 1 or -1
  local sy = y0 < y1 and 1 or -1
  local err = dx - dy
  while true do
    pts[#pts+1] = {x0, y0}
    if x0 == x1 and y0 == y1 then break end
    local e2 = 2 * err
    if e2 > -dy then err = err - dy; x0 = x0 + sx end
    if e2 <  dx then err = err + dx; y0 = y0 + sy end
  end
  return pts
end

-- ============================================================
--  BUFFER  (с half-block пиксельным слоем)
-- ============================================================
--  Ячейка хранит {ch, fg, bg}. Пиксельные операции работают через
--  символ "▀": fg = верхний пиксель, bg = нижний.
--  pixel (px, py)  →  cellX = px, cellY = ceil(py/2), top = (py%2==1)

local Buffer = {}
Buffer.__index = Buffer

function Buffer.new()
  local w, h = gpu.getResolution()
  local self = setmetatable({
    w = w, h = h,
    pw = w, ph = h * 2,
    cur  = {},
    next = {},
  }, Buffer)
  for y = 1, h do
    self.cur[y]  = {}
    self.next[y] = {}
    for x = 1, w do
      self.cur[y][x]  = {fg=0xFFFFFF, bg=0x000000, ch=" "}
      self.next[y][x] = {fg=0xFFFFFF, bg=0x000000, ch=" "}
    end
  end
  return self
end

function Buffer:set(x, y, ch, fg, bg)
  x, y = math.floor(x), math.floor(y)
  if x < 1 or y < 1 or x > self.w or y > self.h then return end
  local cell = self.next[y][x]
  if ch then cell.ch = ch end
  if fg then cell.fg = fg end
  if bg then cell.bg = bg end
end

function Buffer:fill(x, y, w, h, ch, fg, bg)
  for dy = 0, h-1 do
    for dx = 0, w-1 do
      self:set(x+dx, y+dy, ch, fg, bg)
    end
  end
end

-- Из ячейки достаём (top, bottom) — цвета двух «пикселей»
local function decodeCell(cell)
  if cell.ch == "▀" then return cell.fg, cell.bg
  elseif cell.ch == "▄" then return cell.bg, cell.fg
  elseif cell.ch == " " or cell.ch == "█" then return cell.bg, cell.bg
  else return cell.bg, cell.bg end
end

function Buffer:setPixel(px, py, color)
  px, py = math.floor(px), math.floor(py)
  if px < 1 or py < 1 or px > self.pw or py > self.ph then return end
  local cellY = math.ceil(py / 2)
  local isTop = (py % 2 == 1)
  local cell = self.next[cellY][px]
  local top, bot = decodeCell(cell)
  if isTop then top = color else bot = color end
  if top == bot then
    cell.ch, cell.fg, cell.bg = " ", 0xFFFFFF, top
  else
    cell.ch, cell.fg, cell.bg = "▀", top, bot
  end
end

function Buffer:clear(bg)
  bg = bg or 0x000000
  self:fill(1, 1, self.w, self.h, " ", 0xFFFFFF, bg)
end

-- На GPU выливаем только изменившиеся ячейки
function Buffer:flush()
  local curFg, curBg
  for y = 1, self.h do
    for x = 1, self.w do
      local n = self.next[y][x]
      local c = self.cur[y][x]
      if n.ch ~= c.ch or n.fg ~= c.fg or n.bg ~= c.bg then
        if n.fg ~= curFg then gpu.setForeground(n.fg); curFg = n.fg end
        if n.bg ~= curBg then gpu.setBackground(n.bg); curBg = n.bg end
        gpu.set(x, y, n.ch)
        c.ch, c.fg, c.bg = n.ch, n.fg, n.bg
      end
    end
  end
end

-- ============================================================
--  PRIMITIVES
-- ============================================================

local P = {}

function P.rect(buf, x, y, w, h, bg)
  buf:fill(x, y, w, h, " ", bg, bg)
end

local BORDERS = {
  single  = {h="─", v="│", tl="┌", tr="┐", bl="└", br="┘"},
  double  = {h="═", v="║", tl="╔", tr="╗", bl="╚", br="╝"},
  thick   = {h="━", v="┃", tl="┏", tr="┓", bl="┗", br="┛"},
  rounded = {h="─", v="│", tl="╭", tr="╮", bl="╰", br="╯"},
}

function P.border(buf, x, y, w, h, color, bg, style)
  local s = BORDERS[style or "single"] or BORDERS.single
  for dx = 1, w-2 do
    buf:set(x+dx, y,     s.h, color, bg)
    buf:set(x+dx, y+h-1, s.h, color, bg)
  end
  for dy = 1, h-2 do
    buf:set(x,     y+dy, s.v, color, bg)
    buf:set(x+w-1, y+dy, s.v, color, bg)
  end
  buf:set(x,       y,       s.tl, color, bg)
  buf:set(x+w-1,   y,       s.tr, color, bg)
  buf:set(x,       y+h-1,   s.bl, color, bg)
  buf:set(x+w-1,   y+h-1,   s.br, color, bg)
end

-- Тень под прямоугольником: тёмные ячейки со смещением (1,1)
function P.shadow(buf, x, y, w, h, color)
  color = color or 0x000000
  for dy = 1, h - 1 do
    buf:set(x + w, y + dy, " ", 0xFFFFFF, color)
  end
  for dx = 1, w do
    buf:set(x + dx, y + h, " ", 0xFFFFFF, color)
  end
end

function P.text(buf, x, y, str, fg, bg)
  local col = x
  for i = 1, unicode.len(str) do
    buf:set(col, y, unicode.sub(str, i, i), fg, bg)
    col = col + 1
  end
end

-- Горизонтальный градиент: интерполяция по колонкам
function P.gradientH(buf, x, y, w, h, c1, c2)
  for dx = 0, w-1 do
    local t = (w > 1) and (dx / (w - 1)) or 0
    local color = lerpColor(c1, c2, t)
    for dy = 0, h-1 do
      buf:set(x+dx, y+dy, " ", 0xFFFFFF, color)
    end
  end
end

-- Вертикальный градиент: интерполяция по пиксельным строкам (через ▀)
function P.gradientV(buf, x, y, w, h, c1, c2)
  local rows = h * 2
  for r = 0, rows - 1 do
    local t = (rows > 1) and (r / (rows - 1)) or 0
    local color = lerpColor(c1, c2, t)
    for dx = 0, w-1 do
      buf:setPixel(x + dx, (y - 1) * 2 + 1 + r, color)
    end
  end
end

function P.line(buf, x0, y0, x1, y1, color, bg, ch)
  ch = ch or "█"
  for _, p in ipairs(linePoints(x0, y0, x1, y1)) do
    buf:set(p[1], p[2], ch, color, bg)
  end
end

function P.pixelLine(buf, x0, y0, x1, y1, color)
  for _, p in ipairs(linePoints(x0, y0, x1, y1)) do
    buf:setPixel(p[1], p[2], color)
  end
end

-- Заливной круг в пиксельных координатах
function P.pixelCircleFill(buf, cx, cy, r, color)
  local r2 = r * r
  for dy = -r, r do
    for dx = -r, r do
      if dx*dx + dy*dy <= r2 then
        buf:setPixel(cx + dx, cy + dy, color)
      end
    end
  end
end

-- Контур круга, толщина в пикселях
function P.pixelCircle(buf, cx, cy, r, color, thickness)
  thickness = thickness or 1
  local rOuter2 = r * r
  local rInner  = math.max(0, r - thickness)
  local rInner2 = rInner * rInner
  for dy = -r, r do
    for dx = -r, r do
      local d2 = dx*dx + dy*dy
      if d2 <= rOuter2 and d2 >= rInner2 then
        buf:setPixel(cx + dx, cy + dy, color)
      end
    end
  end
end

-- Дуга. Параметрический проход от a0 к a1 (рад). Положит. угол — против часовой.
function P.pixelArc(buf, cx, cy, r, a0, a1, color, thickness)
  thickness = thickness or 1
  local sweep = a1 - a0
  local steps = math.max(4, math.floor(math.abs(sweep) * r * 1.5))
  for i = 0, steps do
    local t = i / steps
    local a = a0 + sweep * t
    for dr = 0, thickness - 1 do
      local rr = r - dr
      local px = math.floor(cx + rr * math.cos(a) + 0.5)
      local py = math.floor(cy - rr * math.sin(a) + 0.5)
      buf:setPixel(px, py, color)
    end
  end
end

-- Sub-cell горизонтальный прогресс (8 шагов на ячейку)
local FINE = {"▏", "▎", "▍", "▌", "▋", "▊", "▉", "█"}

function P.progressFine(buf, x, y, w, value, fgFill, bg)
  value = clamp(value, 0, 1)
  bg = bg or 0x000000
  fgFill = fgFill or 0x00FF00
  local total = w * 8
  local filled = value * total
  local fullCells = math.floor(filled / 8)
  local partial = math.floor(filled - fullCells * 8)
  for dx = 0, w-1 do
    if dx < fullCells then
      buf:set(x+dx, y, "█", fgFill, bg)
    elseif dx == fullCells and partial > 0 then
      buf:set(x+dx, y, FINE[partial], fgFill, bg)
    else
      buf:set(x+dx, y, " ", fgFill, bg)
    end
  end
end

-- Sparkline через вертикальные блоки 1/8..8/8
local VBARS = {"▁", "▂", "▃", "▄", "▅", "▆", "▇", "█"}

function P.sparkline(buf, x, y, w, values, color, bg)
  bg = bg or 0x000000
  if #values == 0 then return end
  local maxV, minV = -math.huge, math.huge
  for _, v in ipairs(values) do
    if v > maxV then maxV = v end
    if v < minV then minV = v end
  end
  if maxV == minV then maxV = minV + 1 end
  for dx = 0, w-1 do
    local idx = math.floor(dx * #values / w) + 1
    local v = values[idx] or minV
    local t = (v - minV) / (maxV - minV)
    local b = clamp(math.ceil(t * 8), 1, 8)
    buf:set(x+dx, y, VBARS[b], color, bg)
  end
end

-- Bar chart через half-block пиксели (плавная высота столбцов)
function P.barChart(buf, x, y, w, h, values, color, bg)
  bg = bg or 0x000000
  P.rect(buf, x, y, w, h, bg)
  if #values == 0 then return end
  local maxV = 0
  for _, v in ipairs(values) do
    if v > maxV then maxV = v end
  end
  if maxV == 0 then return end
  local pixelH = h * 2
  local n = #values
  local barW = math.max(1, math.floor(w / n))
  local gap = (barW > 1) and 1 or 0
  if barW > 1 then barW = barW - gap end
  for i, v in ipairs(values) do
    local barPxH = math.floor(v / maxV * pixelH)
    local bx = x + (i - 1) * (barW + gap)
    if bx + barW - 1 > x + w - 1 then break end
    -- pixel y координаты: дно столбика = y*2 + pixelH - 1 (если y начинается с 1 →
    -- пикс. строки [(y-1)*2+1 .. (y-1)*2+pixelH])
    local pyBottom = (y - 1) * 2 + pixelH
    for px = 0, barW - 1 do
      for ph = 0, barPxH - 1 do
        buf:setPixel(bx + px, pyBottom - ph, color)
      end
    end
  end
end

-- ============================================================
--  ELEMENT TREE
-- ============================================================

local Element = {}
Element.__index = Element

function Element.new(props)
  local self = setmetatable({}, Element)
  for k, v in pairs(props) do self[k] = v end
  self.x = props.x or 1
  self.y = props.y or 1
  self._children = {}
  if props.children then
    for _, c in ipairs(props.children) do self:add(c) end
  end
  return self
end

function Element:add(child)
  self._children[#self._children + 1] = child
  return self
end

function Element:move(x, y) self.x, self.y = x, y; return self end

-- ============================================================
--  RENDERER
-- ============================================================

local Renderer = {}

function Renderer.draw(buf, el, absX, absY)
  absX = (absX or 0) + el.x - 1
  absY = (absY or 0) + el.y - 1
  local t = el.type
  local x, y = absX, absY

  if t == "rect" then
    P.rect(buf, x, y, el.w or 10, el.h or 1, el.bg or 0x000000)
    if el.border then
      P.border(buf, x, y, el.w, el.h, el.border, el.bg, el.borderStyle)
    end

  elseif t == "panel" then
    local w, h = el.w, el.h
    if el.shadow then
      P.shadow(buf, x, y, w, h, el.shadowColor or 0x000000)
    end
    P.rect(buf, x, y, w, h, el.bg or 0x000000)
    if el.border then
      P.border(buf, x, y, w, h, el.border, el.bg, el.borderStyle or "rounded")
    end
    if el.title then
      local title = " " .. el.title .. " "
      P.text(buf, x + 2, y, title, el.titleFg or el.border or 0xFFFFFF, el.bg or 0x000000)
    end

  elseif t == "text" then
    P.text(buf, x, y, el.text or "", el.fg or 0xFFFFFF, el.bg)

  elseif t == "line" then
    P.line(buf, x, y,
      x + (el.x1 or 0) - el.x, y + (el.y1 or 0) - el.y,
      el.color or el.fg, el.bg, el.ch)

  elseif t == "circle" then
    -- центр задаётся в char-координатах; переводим в pixel
    local px = x
    local py = (y - 1) * 2 + 1
    if el.fill then
      P.pixelCircleFill(buf, px, py, el.r or 4, el.color or 0xFFFFFF)
    else
      P.pixelCircle(buf, px, py, el.r or 4, el.color or 0xFFFFFF, el.thickness or 1)
    end

  elseif t == "arc" then
    P.pixelArc(buf, x, (y - 1) * 2 + 1, el.r or 5,
      el.a0 or 0, el.a1 or math.pi,
      el.color or 0xFFFFFF, el.thickness or 1)

  elseif t == "gauge" then
    -- Полукруговой индикатор (270° sweep, низ открыт). x,y — левый-верхний угол bbox.
    local r = el.r or 6
    local cx = x + r
    local cyPx = (y - 1) * 2 + r + 1
    local startA = math.rad(225)
    local sweep  = math.rad(270)
    -- фон-дуга
    P.pixelArc(buf, cx, cyPx, r, startA - sweep, startA,
      el.bgColor or 0x222233, el.thickness or 2)
    -- value-дуга (от startA против часовой стрелки уменьшаем угол — идём по верху)
    local v = clamp(el.value or 0, 0, 1)
    local valEnd = startA - sweep * v
    P.pixelArc(buf, cx, cyPx, r, valEnd, startA,
      el.color or 0x4ADE80, el.thickness or 2)
    -- центральный лейбл
    if el.label then
      local lx = cx - math.floor(unicode.len(el.label) / 2)
      local ly = math.ceil(cyPx / 2)
      P.text(buf, lx, ly, el.label, el.fg or 0xFFFFFF, el.bg)
    end
    if el.caption then
      local lx = cx - math.floor(unicode.len(el.caption) / 2)
      P.text(buf, lx, math.ceil(cyPx / 2) + 1, el.caption, el.captionFg or 0x888899, el.bg)
    end

  elseif t == "button" then
    if el.shadow then
      P.shadow(buf, x, y, el.w, el.h, el.shadowColor or 0x000000)
    end
    P.rect(buf, x, y, el.w, el.h, el.bg or 0x333333)
    if el.border then
      P.border(buf, x, y, el.w, el.h, el.border, el.bg, el.borderStyle or "rounded")
    end
    local lbl = el.label or ""
    local lx = x + math.floor((el.w - unicode.len(lbl)) / 2)
    local ly = y + math.floor((el.h - 1) / 2)
    P.text(buf, lx, ly, lbl, el.fg or 0xFFFFFF, el.bg)

  elseif t == "progress" then
    P.progressFine(buf, x, y, el.w or 20, el.value or 0,
      el.fgFill or 0x00FF00, el.bg or 0x000000)

  elseif t == "gradient" then
    if (el.direction or "h") == "v" then
      P.gradientV(buf, x, y, el.w, el.h, el.from or 0x000000, el.to or 0xFFFFFF)
    else
      P.gradientH(buf, x, y, el.w, el.h, el.from or 0x000000, el.to or 0xFFFFFF)
    end

  elseif t == "sparkline" then
    P.sparkline(buf, x, y, el.w, el.values or {}, el.color or 0x00FF00, el.bg)

  elseif t == "barchart" then
    P.barChart(buf, x, y, el.w, el.h, el.values or {}, el.color or 0x00FF00, el.bg)

  elseif t == "slider" then
    local w = el.w or 20
    local val = clamp(el.value or 0, 0, 1)
    for dx = 0, w-1 do
      buf:set(x + dx, y, "─", el.trackColor or 0x444466, el.bg)
    end
    local tx = x + math.floor(val * (w - 1))
    buf:set(tx, y, "●", el.color or 0x7C6FCD, el.bg)

  elseif t == "badge" then
    local label = " " .. (el.label or "") .. " "
    P.text(buf, x, y, label, el.fg or 0xFFFFFF, el.bg or 0x7C6FCD)

  elseif t == "pixelGrid" then
    local cells = el.cells or {}
    local rows = #cells
    for r = 1, rows do
      local row = cells[r]
      for c = 1, #row do
        if row[c] then
          buf:setPixel(x + c - 1, (y - 1) * 2 + r, row[c])
        end
      end
    end
  end

  for _, child in ipairs(el._children) do
    Renderer.draw(buf, child, absX, absY)
  end
end

-- ============================================================
--  EVENT LOOP
-- ============================================================

local EventLoop = {}

function EventLoop.collectButtons(el, absX, absY, result)
  absX = (absX or 0) + el.x - 1
  absY = (absY or 0) + el.y - 1
  result = result or {}
  if el.type == "button" and el.onClick then
    result[#result+1] = {x=absX, y=absY, w=el.w, h=el.h, onClick=el.onClick}
  end
  for _, c in ipairs(el._children) do
    EventLoop.collectButtons(c, absX, absY, result)
  end
  return result
end

function EventLoop.hitTest(buttons, tx, ty)
  for _, b in ipairs(buttons) do
    if tx >= b.x and tx < b.x + b.w and ty >= b.y and ty < b.y + b.h then
      return b
    end
  end
end

-- ============================================================
--  PUBLIC API
-- ============================================================

local GUI = {}

GUI.el = setmetatable({}, {
  __index = function(_, typeName)
    return function(props)
      props = props or {}
      props.type = typeName
      return Element.new(props)
    end
  end
})

GUI.lerpColor = lerpColor
GUI.darken    = darken
GUI.clamp     = clamp

-- Возвращает экран к нормальному состоянию и печатает ошибку со стек-трейсом
local function dumpError(err)
  local w, h = gpu.getResolution()
  gpu.setBackground(0x000000)
  gpu.setForeground(0xFFFFFF)
  gpu.fill(1, 1, w, h, " ")
  gpu.setForeground(0xFF5555)
  gpu.set(1, 1, "LiteGUI error:")
  gpu.setForeground(0xFFFFFF)
  -- разбиваем по строкам и печатаем
  local y = 3
  for line in tostring(err):gmatch("[^\n]+") do
    if y > h then break end
    -- обрезаем длинные строки
    if #line > w then line = line:sub(1, w) end
    gpu.set(1, y, line)
    y = y + 1
  end
end

function GUI.render(root)
  local buf = Buffer.new()
  local ok, err = xpcall(function()
    buf:clear(root.bg or 0x000000)
    Renderer.draw(buf, root, 0, 0)
    buf:flush()
  end, debug.traceback)
  if not ok then dumpError(err); error(err, 0) end
  return buf
end

function GUI.run(root, onFrame)
  local buf = Buffer.new()
  local running = true
  local hadError = false

  local function redrawUnsafe()
    if onFrame then onFrame(root) end
    buf:clear(root.bg or 0x000000)
    Renderer.draw(buf, root, 0, 0)
    buf:flush()
  end

  local function redraw()
    local ok, err = xpcall(redrawUnsafe, debug.traceback)
    if not ok then
      dumpError(err)
      running = false
      hadError = true
    end
  end

  redraw()

  while running do
    local ev = {event.pull(0.1)}
    local name = ev[1]
    if name == "touch" then
      local tx, ty = ev[3], ev[4]
      local buttons = EventLoop.collectButtons(root, 0, 0)
      local hit = EventLoop.hitTest(buttons, tx, ty)
      if hit then
        local ok, err = xpcall(hit.onClick, debug.traceback)
        if not ok then
          dumpError(err); running = false; hadError = true
        else
          redraw()
        end
      end
    elseif name == "key_down" then
      local char = ev[3]
      if char == 113 or char == 27 then running = false end
    elseif name == nil then
      redraw()
    end
  end

  -- При ошибке оставляем трейс на экране; иначе чистим
  if not hadError then
    gpu.setBackground(0x000000)
    gpu.setForeground(0xFFFFFF)
    gpu.fill(1, 1, buf.w, buf.h, " ")
  end
end

return GUI
