-- ============================================================
--  inspect.lua — универсальный ресёрчер компонентов OpenComputers
--
--  Использование:
--    inspect                      → список всех компонентов (type + address)
--    inspect <substr>             → для компонентов, чей type содержит <substr>:
--                                   список методов + попытка вызова безопасных
--                                   геттеров (get*/is*/has*) БЕЗ аргументов.
--    inspect <substr> --all       → вызвать ВСЕ методы без аргументов
--                                   (опаснее: activate/deactivate и т.п.)
--
--  Вывод дублируется в /home/inspect.log (перезаписывается).
-- ============================================================

local component = require("component")
local shell     = require("shell")
local fs        = require("filesystem")
local serialization = require("serialization")

local args, opts = shell.parse(...)
local filter = args[1]              -- подстрока для типа, например "reactor"
local callAll = opts.all == true    -- вызвать все методы, не только safe-геттеры

local LOG_PATH = "/home/inspect.log"
local logFile = io.open(LOG_PATH, "w")

local function out(...)
  local parts = {}
  for i = 1, select("#", ...) do parts[i] = tostring(select(i, ...)) end
  local line = table.concat(parts, "\t")
  print(line)
  if logFile then logFile:write(line .. "\n") end
end

local function header(s)
  out("")
  out("=== " .. s .. " ===")
end

-- ── Сбор всех компонентов ────────────────────────────────
local all = {}
for address, ctype in component.list() do
  all[#all + 1] = { address = address, type = ctype }
end
table.sort(all, function(a, b)
  if a.type == b.type then return a.address < b.address end
  return a.type < b.type
end)

-- ── Шаг 1: всегда печатаем общий список ──────────────────
header("ALL COMPONENTS (" .. #all .. ")")
for _, c in ipairs(all) do
  out(c.type, c.address)
end

-- Если фильтра нет — выходим
if not filter then
  out("")
  out("hint: запусти `inspect <substr>` для подробностей по конкретному типу")
  if logFile then logFile:close() end
  return
end

-- ── Шаг 2: фильтруем и инспектируем ──────────────────────
local matched = {}
for _, c in ipairs(all) do
  if c.type:find(filter, 1, true) then
    matched[#matched + 1] = c
  end
end

header("MATCHED: '" .. filter .. "' → " .. #matched .. " component(s)")
if #matched == 0 then
  out("ничего не найдено")
  if logFile then logFile:close() end
  return
end

local function isSafeGetter(name)
  return name:match("^get") or name:match("^is") or name:match("^has")
end

local function fmtValue(v)
  local t = type(v)
  if t == "table" then
    local ok, s = pcall(serialization.serialize, v)
    if ok then return s end
    return "<table>"
  elseif t == "string" then
    return string.format("%q", v)
  else
    return tostring(v)
  end
end

for _, c in ipairs(matched) do
  header("[" .. c.type .. "] " .. c.address)

  local ok, proxy = pcall(component.proxy, c.address)
  if not ok or not proxy then
    out("!! не удалось получить proxy:", proxy)
  else
    -- Список методов
    local methods = {}
    for name in pairs(proxy) do
      if type(proxy[name]) == "function" then
        methods[#methods + 1] = name
      end
    end
    table.sort(methods)

    out("methods (" .. #methods .. "):")
    for _, name in ipairs(methods) do
      out("  ." .. name)
    end

    -- Попытка вызвать
    out("")
    out("invocations:")
    for _, name in ipairs(methods) do
      if callAll or isSafeGetter(name) then
        local cok, cres, cres2 = pcall(proxy[name])
        if cok then
          local extra = cres2 ~= nil and (", " .. fmtValue(cres2)) or ""
          out(string.format("  .%s() = %s%s", name, fmtValue(cres), extra))
        else
          out(string.format("  .%s() ! err: %s", name, tostring(cres)))
        end
      else
        out(string.format("  .%s() ~ skipped (not a safe getter; use --all)", name))
      end
    end
  end
end

out("")
out("done. log → " .. LOG_PATH)
if logFile then logFile:close() end
