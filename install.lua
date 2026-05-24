-- ============================================================
--  install.lua — установщик litegui-monitor
--
--  Bootstrap (на любом компе с интернет-картой):
--    wget -f https://raw.githubusercontent.com/Antoxerrr/litegui/main/install.lua /home/install.lua
--
--  Использование:
--    install main                     -- главный комп (UI / listen)
--    install agent <driver>...        -- gateway-комп (агент + драйверы)
--    install <driver>...              -- shorthand для agent
--
--  Примеры:
--    install main
--    install agent reactor flux
--    install reactor                  -- = install agent reactor
--
--  Известные драйверы: reactor, flux
-- ============================================================

local shell    = require("shell")
local fs       = require("filesystem")
local internet = require("internet")

local REPO   = "Antoxerrr/litegui"
local BRANCH = "main"
local BASE   = "https://raw.githubusercontent.com/" .. REPO .. "/" .. BRANCH .. "/"

-- Манифест: для каждого профиля и драйвера — список {source, target}.
-- Source — путь в репе. Target — путь на OC-машине.
local MANIFEST = {
  profiles = {
    main = {
      { "litegui.lua",       "/lib/litegui.lua"      },
      { "lgm/protocol.lua",  "/lib/lgm/protocol.lua" },
      { "lgm/state.lua",     "/lib/lgm/state.lua"    },
      { "lgm/ui.lua",        "/lib/lgm/ui.lua"       },
      { "dashboard.lua",     "/home/dashboard.lua"   },
      { "listen.lua",        "/home/listen.lua"      },  -- остаётся для дебага
    },
    agent = {
      { "lgm/protocol.lua",  "/lib/lgm/protocol.lua" },
      { "agent.lua",         "/home/agent.lua"       },
    },
  },
  drivers = {
    reactor = { { "lgm/drivers/reactor.lua", "/lib/lgm/drivers/reactor.lua" } },
    flux    = { { "lgm/drivers/flux.lua",    "/lib/lgm/drivers/flux.lua"    } },
  },
}

-- ── helpers ──────────────────────────────────────────────
local function knownDriverNames()
  local out = {}
  for name in pairs(MANIFEST.drivers) do out[#out+1] = name end
  table.sort(out)
  return out
end

-- Принимает "reactor" или "reactors" — возвращает каноничное имя или nil.
local function resolveDriver(name)
  if MANIFEST.drivers[name] then return name end
  if #name > 1 and name:sub(-1) == "s" then
    local s = name:sub(1, -2)
    if MANIFEST.drivers[s] then return s end
  end
  return nil
end

local function usage(msg)
  if msg then io.stderr:write("error: " .. msg .. "\n\n") end
  print("Usage:")
  print("  install main")
  print("  install agent <driver>...")
  print("  install <driver>...           (shorthand for `agent`)")
  print("")
  print("Drivers: " .. table.concat(knownDriverNames(), ", "))
end

local function ensureDir(path)
  local dir = fs.path(path)
  if dir and dir ~= "" and not fs.exists(dir) then
    fs.makeDirectory(dir)
  end
end

-- Если файл уже лежит где-то ещё в package.path (например /usr/lib/...
-- или /home/lib/... — остатки старой ручной установки), require найдёт
-- ЕГО раньше, чем нашу /lib-версию. Чистим все альтернативы до wget.
local PATH_ALTERNATES = { "/usr/lib/", "/home/lib/", "/home/" }

local function cleanupAlternates(dst)
  if dst:sub(1, 5) ~= "/lib/" then return end
  local rest = dst:sub(6)  -- "lgm/protocol.lua"
  for _, root in ipairs(PATH_ALTERNATES) do
    local alt = root .. rest
    if alt ~= dst and fs.exists(alt) then
      fs.remove(alt)
      print("  - removed stale " .. alt)
    end
  end
end

-- Качаем напрямую через internet.request с no-cache заголовками.
-- wget в OpenOS на практике тянет stale-версию даже с query cache-buster,
-- т.к. где-то на пути сидит кеш, игнорирующий query. Свой fetch его обходит.
local function fetch(url)
  local ok, reqOrErr = pcall(internet.request, url, nil, {
    ["Cache-Control"] = "no-cache",
    ["Pragma"]        = "no-cache",
  })
  if not ok then return nil, tostring(reqOrErr) end
  local buf = {}
  local okPull, errPull = pcall(function()
    for chunk in reqOrErr do buf[#buf + 1] = chunk end
  end)
  if not okPull then return nil, tostring(errPull) end
  return table.concat(buf)
end

local function download(src, dst)
  ensureDir(dst)
  cleanupAlternates(dst)
  -- cache-buster всё равно ставим — не повредит, помогает на некоторых прокси
  local url = BASE .. src .. "?v=" .. tostring(os.time())
  local body, err = fetch(url)
  if not body or #body == 0 then
    print("  ! FAILED " .. dst .. " (" .. tostring(err or "empty body") .. ")")
    return false
  end
  if fs.exists(dst) then fs.remove(dst) end
  local f, ferr = io.open(dst, "w")
  if not f then
    print("  ! FAILED " .. dst .. " (open: " .. tostring(ferr) .. ")")
    return false
  end
  f:write(body); f:close()
  -- небольшой sanity-вывод: размер + первая строка, чтобы видеть что приехало
  local head = body:match("[^\r\n]*") or ""
  if #head > 60 then head = head:sub(1, 60) .. "…" end
  print(("  + %s  [%d B]  %s"):format(dst, #body, head))
  return true
end

-- ── parse args ───────────────────────────────────────────
local args = {...}

if #args == 0 then usage(); return end

local profile
local drivers = {}

local first = args[1]
if first == "main" or first == "agent" then
  profile = first
  for i = 2, #args do
    local d = resolveDriver(args[i])
    if not d then usage("unknown driver: " .. args[i]); return end
    drivers[#drivers+1] = d
  end
else
  -- shorthand: всё считается драйверами, профиль = agent
  profile = "agent"
  for i = 1, #args do
    local d = resolveDriver(args[i])
    if not d then usage("unknown profile or driver: " .. args[i]); return end
    drivers[#drivers+1] = d
  end
end

if profile == "agent" and #drivers == 0 then
  usage("agent install requires at least one driver"); return
end
if profile == "main" and #drivers > 0 then
  print("note: drivers ignored for `main` profile (main doesn't run drivers)")
  drivers = {}
end

-- ── execute ──────────────────────────────────────────────
print(("install: profile=%s drivers=[%s]"):format(
  profile, table.concat(drivers, ", ")))
print(("source : %s"):format(BASE))
print()

local failed = 0
local function step(items)
  for _, it in ipairs(items) do
    if not download(it[1], it[2]) then failed = failed + 1 end
  end
end

step(MANIFEST.profiles[profile])
for _, d in ipairs(drivers) do step(MANIFEST.drivers[d]) end

print()
if failed == 0 then
  print("✓ done.")
else
  print("✗ done with " .. failed .. " failure(s).")
end
