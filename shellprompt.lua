-- http://www.understudy.net/custom.html


local last_ansi = nil
local is_bash = false
local is_csh  = false
local is_zsh  = false
local buffer  = ""


function isblank(s)
  return s == nil or s == ''
end

function put(s)
  if isblank(s) then return end
  buffer = buffer..s
end

function rfind(s, ch)
  local i = s:reverse():find(ch, 1, true)
  if not i then return nil else return #s - i + 1 end
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
  if is_zsh then
    put('%~')
  elseif is_bash then -- or is_ksh
    put('\w')
  else
    put(shellprompt_os.get_cur_directory())
    -- TODO
  end
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

function main()
  local nextarg = consumer(arg)
  for a in nextarg do
    if a == "text" then
      local v = nextarg()
      if not v then
        die2("text", "command requies an argument")
        exit()
      end
      put(v)
    else
      local v = commands[a]
      if not v then
        print("no such command: "..a)
        os.exit(1)
      end
      v()
    end
  end
  commands["reset"]()
  io.write(buffer, "\n")
end

main()
