local PROGNAME  = "shellprompt"
local last_ansi = nil
local is_bash = true  -- TODO
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

function open_program_for_reading()
  for _, confdir in ipairs(get_xdg_config_homes()) do
    local filename = confdir.."prompt"
    local stream = io.open(filename, "r")
    if stream ~= nil then
      return stream, filename
    end
  end
  return nil, nil
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

function load_program_from_string(s)
  local args, i, j, k
  i = 1
  args = {}
  while true do
    j, k = string.find(s, "%s+", i)
    if i == j and k then
      i = k + 1
    end
    if i > string.len(s) then break end
    local arg = ""
    if string.find(s, '"', i) == i then
      -- Double-quoted arg, backslash escapes allowed
      i = i + 1
      while not (string.find(s, '"', i) == i) do
        j, k = string.find(s, "[^\\%\"]+", i)
        if i == j and k then
          arg = arg..string.sub(s, j, k)
          i = k + 1
        end
        j, k = string.find(s, "\\[\\%\"]", i)
        if i == j and k then
          arg = arg..string.sub(s, k, k)
          i = k + 1
        end
        if i > string.len(s) then
          die("Missing closing quote")
        end
      end
      i = i + 1
    else
      -- Bare arg without quoting, backslash escapes not allowed
      j, k = string.find(s, "[^\\%\"%s]+", i)
      if i == j and k then
        arg = string.sub(s, j, k)
        i = k + 1
      end
    end
    table.insert(args, arg)
  end
  return args
end

function load_program()
  local contents = ""
  local stream = open_program_for_reading()
  if stream then
    contents = stream:read("*a")
    stream:close()
  end
  return load_program_from_string(contents)
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

function put_text(readarg)
  local text = readarg()
  assert(text)
  put(text)
end

function put_ansi(ansi)
  return function()
    if last_ansi == ansi then return end
    last_ansi = ansi
    if is_zsh then
      put("%{\\e[")
      put(ansi)
      put("m%}")
    elseif is_bash then
      put("\\[\\e[")
      put(ansi)
      put("m\\]")
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

local dictionary = {

  text       = put_text,

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

function eval_forth_word(word, worditer)
  -- io.stderr:write(string.format("Evaluating %q\n", word))
  local definition = dictionary[word]
  if not definition then
    die("undefined word: "..word)
  end
  definition(worditer)
end

-- Actions

function set_action(nextarg)
  save_program(nextarg, get_program_dirname_for_writing().."prompt")
end

function encode_action(nextarg)
  local which_shell = nextarg()
  local program = load_program()
  local worditer = consumer(program)
  eval_forth_word("reset")
  for word in worditer do
    eval_forth_word(word, worditer)
  end
  eval_forth_word("reset")
  io.write(buffer, "\n")
end

local actions = {
  encode = encode_action,
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
