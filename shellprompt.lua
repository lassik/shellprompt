local PROGNAME  = "shellprompt"
local last_ansi = nil
local is_bash = false
local is_csh  = false
local is_zsh  = false
local buffer  = ""

-- Utilities

function die(msg)
  io.stderr:write(PROGNAME..": "..msg.."\n")
  os.exit(1)
end

function consumer(ary)
  local i = 1
  return function()
    local val = nil
    if i <= #ary then
      val = ary[i]
      i = i + 1
    end
    return val
  end
end

function isblank(s)
  return s == nil or s == ''
end

function rfind(s, ch)
  local i = s:reverse():find(ch, 1, true)
  if not i then return nil else return #s - i + 1 end
end

function map(tabl, fn)
  ans = {}
  for _, item in ipairs(tabl) do
    table.insert(ans, fn(item))
  end
  return ans
end

function try_insert_conf_dir(tabl, envar, suffix)
  local dir = os.getenv(envar)
  if not (dir and dir:match("^/")) then return end
  dir = dir.."/"..(suffix or "").."/"..PROGNAME
  dir = dir:gsub("/+", "/"):gsub("/$", "").."/"
  table.insert(tabl, dir)
end

function get_xdg_config_homes()
  local homes = {}
  try_insert_conf_dir(homes, "XDG_CONFIG_HOME")
  try_insert_conf_dir(homes, "HOME", ".config")
  return homes
end

function get_program_dirname_for_writing()
  local homes = get_xdg_config_homes()
  -- for i, home in ipairs(homes) do print(i, home) end
  if #homes == 0 then die("Home directory not found") end
  local home = homes[1]
  shellprompt_os.ensure_dir_exists(home)
  return home
end

function save_program(argiter, filename)
  local stream = assert(io.open(filename, "w"))
  local written = false
  for arg in argiter do
    if written then stream:write(" ") end
    if string.len(arg) == 0 or string.find(arg, "[\"\\\\' ]") then
      stream:write('"'..string.gsub(arg, "([\"\\\\])", "\\%1")..'"')
    else
      stream:write(arg)
    end
    written = true
  end
  if written then stream:write("\n") end
  stream:close()
end

-- Buffer

function put(s)
  if isblank(s) then return end
  buffer = buffer..s
end

function putsuffix(ch, whole)
  if isblank(whole) then return end
  local suffix = rfind(whole, ch)
  if suffix then
    suffix = suffix + 1
  else
    suffix = 1
  end
  put(whole:sub(suffix, #whole))
end

-- Command implementations

function put_ansi(ansi)
  return function()
    if last_ansi == ansi then return end
    last_ansi = ansi
    if is_zsh then
      put("%{\\e[")
      put(ansi)
      put("m%}")
    elseif is_bash then
      put("\\\\[\\\\e[")
      put(ansi)
      put("m\\\\]")
    else
      put(string.char(0x1b).."[")
      put(ansi)
      put("m")
    end
  end
end

function put_dir()
  put(shellprompt_os.get_cur_directory())
end

function put_host()
  putsuffix('.', shellprompt_os.get_full_hostname())
end

function put_time24()
  put(os.date("%H:%M"))
end

function put_user()
  put(shellprompt_os.get_username())
end

function put_sign()
  if shellprompt_os.is_superuser() then
    put("#")
  elseif is_csh then
    put("%")
  else
    put("$")
  end
end

function put_sp()
  put(" ")
end

function put_nl()
  put("\n")
end

function put_virtualenv()
  putsuffix("/", os.getenv("VIRTUAL_ENV"))
end

function put_gitbranch()
  putsuffix("/", shellprompt_os.get_output("git", "symbolic-ref", "HEAD"))
end

function put_hgbranch()
  put(shellprompt_os.get_output("hg", "branch"))
end

-- Command table

local commands = {

  reset      = put_ansi("0"),

  black      = put_ansi("30"),
  blue       = put_ansi("34"),
  cyan       = put_ansi("36"),
  green      = put_ansi("32"),
  magenta    = put_ansi("35"),
  red        = put_ansi("31"),
  white      = put_ansi("37"),
  yellow     = put_ansi("33"),

  sign       = put_sign,
  sp         = put_sp,
  nl         = put_nl,

  dir        = put_dir,
  host       = put_host,
  time24     = put_time24,
  user       = put_user,

  gitbranch  = put_gitbranch,
  hgbranch   = put_hgbranch,
  virtualenv = put_virtualenv,

}

-- Actions

function set_action(nextarg)
  save_program(nextarg, get_program_dirname_for_writing().."prompt")
end

local actions = {
  set = set_action,
}

-- Main

function main()
  local nextarg = consumer(arg)
  local actionname = nextarg()
  local action = actions[actionname]
  if not actionname then
    die("usage")
  elseif not action then
    die("unknown action: "..actionname)
  end
  action(nextarg)
end

main()
