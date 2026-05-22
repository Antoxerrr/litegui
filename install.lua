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

local shell = require("shell")
local fs    = require("filesystem")

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

local function download(src, dst)
  ensureDir(dst)
  -- cache-buster, чтобы Fastly CDN не подсовывал stale-копию
  local url = BASE .. src .. "?v=" .. tostring(os.time())
  -- удаляем существующий, wget -f всё равно перезапишет, но так чище
  if fs.exists(dst) then fs.remove(dst) end
  local ok = shell.execute(string.format('wget -fq "%s" "%s"', url, dst))
  if ok then
    print("  + " .. dst)
  else
    print("  ! FAILED " .. dst)
  end
  return ok
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
