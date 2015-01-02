local last_ansi = nil
local is_bash = false
local is_tcsh = false
local is_zsh  = false
local is_dumb = false
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

function string_rtrim(s)
  local i, n = s:reverse():find("%s*")
  if i == 1 then return s:sub(1, s:len()-n) end
  return s
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
  shellprompt_os_ensure_dir_exists(home)
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

function load_program_text()
  local contents = ""
  local stream = open_program_for_reading()
  if stream then
    contents = stream:read("*a")
    stream:close()
  end
  return contents
end

function load_program()
  return load_program_from_string(load_program_text())
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

function begin_zero_length_escape(sequence)
  if is_bash then
    put("\\[\\e"..sequence)
  elseif is_zsh or is_tcsh then
    put("%{"..string.char(0x1b)..sequence)
  else
    put(string.char(0x1b)..sequence)
  end
end

function end_zero_length_escape()
  if is_bash then
    put("\\]")
  elseif is_zsh or is_tcsh then
    put("%}")
  end
end

function put_terminal_escape(sequence)
  begin_zero_length_escape(sequence)
  end_zero_length_escape()
end

function ansi_attribute_putter(ansi)
  return function()
    if is_dumb or (last_ansi == ansi) then return end
    put_terminal_escape("["..ansi.."m")
    last_ansi = ansi
  end
end

-- Forth

local dictionary = {}
local stack = {}

function pop_number()
  assert(#stack > 0, "Stack underflow")
  local value = table.remove(stack)
  assert(type(value) == "number", "Number expected")
  return value
end

function eval_forth_word(word, worditer)
  -- io.stderr:write(string.format("Evaluating %q\n", word))
  assert(word)
  local numtext = string.match(word, "^[+-]?%d+$")
  if numtext then
    table.insert(stack, tonumber(numtext))
    return
  end
  local definition = dictionary[word]
  if definition then
    definition(worditer)
    return
  end
  die("undefined word: "..word)
end

-- Forth words

dictionary.reset   = ansi_attribute_putter("0")
dictionary.black   = ansi_attribute_putter("30")
dictionary.blue    = ansi_attribute_putter("34")
dictionary.cyan    = ansi_attribute_putter("36")
dictionary.green   = ansi_attribute_putter("32")
dictionary.magenta = ansi_attribute_putter("35")
dictionary.red     = ansi_attribute_putter("31")
dictionary.white   = ansi_attribute_putter("37")
dictionary.yellow  = ansi_attribute_putter("33")

function dictionary.min()
  table.insert(stack, math.min(pop_number(), pop_number()))
end

function dictionary.max()
  table.insert(stack, math.max(pop_number(), pop_number()))
end

function dictionary.text(readarg)
  local text = readarg()
  assert(text)
  put(text)
end

function dictionary.termcols()
  cols, rows = shellprompt_os_termcolsrows()
  table.insert(stack, cols or 0)  -- TODO: Is zero really a good fallback?
end

function dictionary.reptext(readarg)
  local text = readarg()
  assert(text)
  local count = table.remove(stack)
  assert(type(count) == "number",
         "reptext need to pop a numerical count from the stack")
  put(string.rep(text, count))
end

function dictionary.line()
  local length = pop_number()
  if is_dumb then
    put(string.rep("-", length))
  else
    put_terminal_escape("(0")
    put(string.rep("q", length))
    put_terminal_escape("(B")
  end
end

function dictionary.dir()
  put(shellprompt_os_get_cur_directory())
end

function dictionary.host()
  putsuffix('.', shellprompt_os_get_full_hostname())
end

function dictionary.time12()
  put(os.date("%I:%M %p"))
end

function dictionary.time24()
  put(os.date("%H:%M"))
end

function dictionary.weekday()
  put(os.date("%a"))
end

function dictionary.fullweekday()
  put(os.date("%A"))
end

function dictionary.user()
  put(shellprompt_os_get_username())
end

function dictionary.sign()
  if shellprompt_os_is_superuser() then
    put("#")
  elseif is_tcsh then
    put("%")
  else
    put("$")
  end
end

function dictionary.sp()
  put(" ")
end

function dictionary.nl()
  if is_bash or is_tcsh then
    put("\\n")
  else
    put("\n")
  end
end

function dictionary.shell()
  if is_bash then
    put("bash")
  elseif is_zsh then
    put("zsh")
  elseif is_tcsh then
    put("tcsh")
  else
    -- TODO
  end
end

function dictionary.battery()
  local info = shellprompt_os_getpowerinfo()
  put(info.percent.."%")
end

function dictionary.virtualenv()
  putsuffix("/", os.getenv("VIRTUAL_ENV"))
end

function dictionary.gitbranch()
  putsuffix("/", shellprompt_os_get_output("git", "symbolic-ref", "HEAD"))
end

function dictionary.hgbranch()
  put(shellprompt_os_get_output("hg", "branch"))
end

function dictionary.title(worditer)
  -- TODO: This is a hack. endtitle should be a real dictionary word,
  -- not a special-cased magic sentinel word.  It should be an error
  -- to use ANSI colors and other formatting directives within the
  -- title.
  local supported = (os.getenv("TERM") or ""):match("^xterm")
  if supported then
    begin_zero_length_escape(']0;')
    for word in worditer do
      if word == 'endtitle' then break end
      eval_forth_word(word, worditer)
    end
    put("\x07")
    end_zero_length_escape()
  else
    for word in worditer do
      -- TODO: This is so lame
      if word == 'endtitle' then break end
    end
  end
end

-- Actions

local actions = {}
local actionargs = {}
local actiondocs = {}

actiondocs.edit = "edit the shell prompt in your text editor of choice"

function actions.edit(nextarg)
  local editor = os.getenv("EDITOR")
  if not (editor and editor:match("%w+")) then
    editor = "vi"
  end
  local stream, filename = open_program_for_reading()
  if stream then
    stream:close()
  else
    filename = get_program_dirname_for_writing().."prompt"
  end
  os.execute(editor.." "..filename)
end

actiondocs.get = "write out the program for the current prompt"

function actions.get(nextarg)
  assert(not nextarg())
  local text = string_rtrim(load_program_text())
  if text:len() > 0 then
    print(text)
  end
end

actiondocs.set = "set the prompt to the given program"
actionargs.set = "<program...>"

function actions.set(nextarg)
  save_program(nextarg, get_program_dirname_for_writing().."prompt")
end

actiondocs.encode = "encode the prompt in a format understood by the shell"
actionargs.encode = "<shell>"

function actions.encode(nextarg)
  local which_shell = nextarg()
  if which_shell == "bash" then
    is_bash = true
  elseif which_shell == "zsh" then
    is_zsh = true
  elseif which_shell == "tcsh" then
    is_tcsh = true
  else
    die(string.format("unknown shell: %q", which_shell))
  end

  -- TERM "dumb" is used by Emacs M-x shell-command and also M-x
  -- shell.  TERM "emacs" is sometimes used by Emacs M-x shell.  To
  -- complicate things further, recent versions of GNU Emacs M-x shell
  -- can actually read ANSI colors, but they still advertise
  -- themselves as TERM "dumb". So I don't know how to tell the Emacs
  -- versions that support colors from the ones that don't.
  local term = os.getenv("TERM") or ""
  is_dumb = ((term == "") or (term == "dumb") or (term == "emacs"))

  local program = load_program()
  local worditer = consumer(program)
  eval_forth_word("reset")
  for word in worditer do
    eval_forth_word(word, worditer)
  end
  eval_forth_word("reset")
  if is_tcsh then
    -- TODO: This extra space at the end of the prompt is needed so
    -- the last color from the prompt doesn't bleed over into the
    -- user-editable command line.  The tcsh manual, section "Special
    -- shell variables", command "prompt", says for "%{string%}":
    -- "This cannot be the last sequence in prompt."  Using %L last
    -- doesn't work either (it has no effect). We could try to be
    -- smart and catch a trailing "sp" command or other whitespace and
    -- put the ANSI reset before that, but there has to be a better
    -- way...
    put(" ")
  end 
  io.write(buffer, "\n")
end

actiondocs.version = "write out version information"

function actions.version()
  local os_version = shellprompt_os_unamesys()
  local lua_version = _VERSION
  print(string.format("%s %s (%s, %s)",
                      PROGNAME, PROGVERSION,
                      os_version, lua_version))
end

actions["--version"] = actions.version
actiondocs["--version"] = actiondocs.version

-- Main

function usage(msg)
  if msg then
    io.stderr:write(""..msg.."\n")
  end
  local maxlen = 0
  local sorted = {}
  local items = {}
  local docs = {}
  for action in pairs(actions) do
    table.insert(sorted, action)
  end
  table.sort(sorted)
  for _, action in ipairs(sorted) do
    local item = action.." "..(actionargs[action] or "")
    maxlen = math.max(maxlen, item:len())
    table.insert(items, item)
    table.insert(docs, (actiondocs[action] or ""))
  end
  for i, item in ipairs(items) do
    local prefix = nil
    if i == 1 then
      prefix = "usage: "
    else
      prefix = "       "
    end
    io.stderr:write(prefix..PROGNAME.." "..item..
                      string.rep(" ", maxlen-item:len()+2)..docs[i].."\n")
  end
  os.exit(1)
end

function main()
  local nextarg = consumer(arg)
  local actionname = nextarg()
  local action = actions[actionname]
  if not actionname then
    usage()
  elseif not action then
    usage("unknown action: "..actionname)
  end
  action(nextarg)
end

main()
