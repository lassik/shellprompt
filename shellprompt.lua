-- Globals

local buffer    = ""
local last_ansi = nil
local tracing   = false

local has_ansi_escapes = false
local has_utf8_encoding = false
local has_vt100_graphics = false
local has_xterm_title = false

local is_bash = false
local is_tcsh = false
local is_zsh  = false

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

function string_rtrim(s)
  local i, n = s:reverse():find("%s*")
  if i == 1 then return s:sub(1, s:len()-n) end
  return s
end

function string_count_matches(s, pattern)
  local a, b, n = nil, 0, -1
  while b do
    n = n + 1
    a, b = string.find(s, pattern, b+1)
  end
  return n
end

function string_findlast_plain(s, pattern)
  local a, b = nil, nil
  while true do
    local i, j = string.find(s, pattern, (b or 0)+1, true)
    if not i then break end
    a, b = i, j
  end
  return a, b
end

function string_suffix_or_whole(part, whole)
  local _, last = string_findlast_plain(whole, part)
  return string.sub(whole, (last or 0)+1, string.len(whole))
end

function string_has_prefix(whole, part)
  return (string.find(whole, part, 1, true) == 1)
end

function get_lower_env(envar)
  return (os.getenv(envar) or ""):gsub("^%s+", ""):gsub("%s+$", ""):lower()
end

function get_boolean_env(envar, default)
  local s = get_lower_env(envar)
  if (s == "true") or (s == "on") or (s == "yes") or (s == "y") then
    return true
  elseif (s == "false") or (s == "off") or (s == "no") or (s == "n") then
    return false
  else
    return default
  end
end

function get_first_line_of_output(...)
  local output = shellprompt_os_get_output(...)
  local i = output:find("[\n\r%z]")
  if i then return output:sub(1, i-1) end
  return output
end

-- Terminal capabilities

function detect_terminal_capabilities()

  local lang     = get_lower_env("LANG")
  local lc_ctype = get_lower_env("LC_CTYPE")
  local term     = get_lower_env("TERM")

  -- TERM "dumb" is used by Emacs M-x shell-command and also M-x
  -- shell.  TERM "emacs" is sometimes used by Emacs M-x shell.  To
  -- complicate things further, recent versions of GNU Emacs M-x shell
  -- can actually read ANSI colors, but they still advertise
  -- themselves as TERM "dumb". So I don't know how to tell the Emacs
  -- versions that support colors from the ones that don't.
  has_ansi_escapes = ((term ~= "dumb") and (term ~= "emacs"))

  has_utf8_encoding = (lc_ctype:find("utf%-8") or lang:find("utf%-8"))

  -- Linux console and GNU Screen lack the VT100 graphics character
  -- set (or at least its line-drawing subset) on UTF-8 locales.
  has_vt100_graphics = ((term ~= "dumb") and (term ~= "emacs") and
                          (term ~= "linux") and (term ~= "screen"))

  has_xterm_title = not not term:match("^xterm")

  -- Autodetection is tricky, so allow user overrides.
  has_ansi_escapes =
    get_boolean_env("SHELLPROMPT_ANSI_ESCAPES", has_ansi_escapes)
  has_vt100_graphics =
    get_boolean_env("SHELLPROMPT_VT100_GRAPHICS", has_vt100_graphics)
  has_utf8_encoding = 
    get_boolean_env("SHELLPROMPT_UTF8_ENCODING", has_utf8_encoding)
  has_xterm_title =
    get_boolean_env("SHELLPROMPT_XTERM_TITLE", has_xterm_title)

end

-- Program file handling

function try_insert_conf_dir(tabl, envar, suffix)
  local dir = (os.getenv(envar) or "")
  if not dir:match("^/") then return end
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

-- Output

function putraw(s)
  s = tostring(s or "")
  buffer = buffer..s
end

function put(s)
  s = tostring(s or "")
  if is_zsh then
    s = s:gsub("%%", "%%%%")
  end
  putraw(s)
end

function begin_zero_length_escape(sequence)
  if is_bash then
    putraw("\\[\\e"..sequence)
  elseif is_zsh or is_tcsh then
    putraw("%{"..string.char(0x1b)..sequence)
  else
    putraw(string.char(0x1b)..sequence)
  end
end

function end_zero_length_escape()
  if is_bash then
    putraw("\\]")
  elseif is_zsh or is_tcsh then
    putraw("%}")
  end
end

function put_terminal_escape(sequence)
  begin_zero_length_escape(sequence)
  end_zero_length_escape()
end

function ansi_attribute_putter(ansi)
  return function()
    if has_ansi_escapes and (last_ansi ~= ansi) then
      put_terminal_escape("["..ansi.."m")
      last_ansi = ansi
    end
  end
end

-- Word skipping (consume word without evaluating it)

function skip_text_arg(worditer)
  local text = worditer()
  assert(text)
end

function skipper_until(sentinel)
  return function(worditer)
    for word in worditer do
      if word_definition(word) == sentinel then
        break
      else
        skip_forth_word(word, worditer)
      end
    end
  end
end

-- Queries

local queries = {}
local query_skippers = {}  -- NB: Indexed by name, not function object

function queries.text(readarg)
  local text = readarg()
  assert(text)
  return text
end

query_skippers.text = skip_text_arg

function queries.reptext(readarg)
  local text = readarg()
  assert(text)
  return string.rep(text, pop_number())
end

query_skippers.reptext = skip_text_arg

function queries.absdir()
  return shellprompt_os_get_cur_directory()
end

function queries.dir()
  local absdir = shellprompt_os_get_cur_directory()
  local home = (os.getenv("HOME") or "")
  if string_has_prefix(absdir, home) then
    return "~"..string.sub(absdir, string.len(home)+1)
  end
  return absdir
end

function queries.host()
  return string_suffix_or_whole('.', shellprompt_os_get_full_hostname())
end

function queries.time12()
  return os.date("%I:%M %p")
end

function queries.time24()
  return os.date("%H:%M")
end

function queries.weekday()
  return os.date("%a")
end

function queries.fullweekday()
  return os.date("%A")
end

function queries.user()
  return shellprompt_os_get_username()
end

function queries.sign()
  if shellprompt_os_is_superuser() then
    return "#"
  elseif is_tcsh then
    return "%"
  else
    return "$"
  end
end

function queries.sp()
  return " "
end

function queries.shell()
  if is_bash then
    return "bash"
  elseif is_zsh then
    return "zsh"
  elseif is_tcsh then
    return "tcsh"
  else
    -- TODO
    return ""
  end
end

function queries.termcols()
  local cols = shellprompt_os_termcolsrows()
  return (cols or 0)  -- TODO: Is zero really a good fallback?
end

function queries.battery()
  local info = shellprompt_os_getpowerinfo()
  return info.percent
end

function queries.virtualenv()
  return string_suffix_or_whole("/", (os.getenv("VIRTUAL_ENV") or ""))
end

function queries.gitbranch()
  return string_suffix_or_whole(
    "/",
    get_first_line_of_output("git", "symbolic-ref", "HEAD"))
end

function queries.gitstashcount()
  local xs = shellprompt_os_get_output("git", "stash", "list", "--format=format:x")
  local count = xs:gsub("%s+", ""):len()
  if count > 0 then return count end
  return ""
end

function queries.hgbranch()
  return get_first_line_of_output("hg", "branch")
end

-- Forth

local dictionary = {}
local skippers = {}
local stack = {}

function truth_value(x)
  return not ((x == nil) or (x == false) or
                (x == 0) or (x == "0") or (x == ""))
end

function push_value(x)
  table.insert(stack, x)
  return x
end

function pop_value()
  assert(#stack > 0, "Stack underflow")
  return table.remove(stack)
end

function pop_value_of_type(goaltype)
  local value = table.remove(stack)
  assert(type(value) == goaltype, goaltype.." expected")
  return value
end

function pop_number()
  return pop_value_of_type("number")
end

function value_bin_op(fn)
  return function()
    local b, a = pop_value(), pop_value()
    return push_value(fn(a, b))
  end
end

function number_bin_op(fn)
  return function()
    local b, a = pop_number(), pop_number()
    return push_value(fn(a, b))
  end
end

function word_definition_or_nil(word)
  return dictionary[word]
end

function word_definition(word)
  local d = word_definition_or_nil(word)
  assert(d, "undefined word: "..tostring(word))
  return d
end

function forth_equal(a, b)
  local na, nb = tonumber(a), tonumber(b)
  if na and nb then
    return na == nb
  else
    return a == b
  end
end

function redefine(name, new_definition)
  -- Yes, it's possible to shadow any built-in word.
  if tracing and dictionary[name] then
    io.stderr:write("Warning: redefining word "..name)
  end
  dictionary[name] = new_definition
end

function eval_forth_word(word, worditer)
  assert(word)
  local numtext = string.match(word, "^[+-]?%d+$")
  if numtext then
    if tracing then
      io.stderr:write(string.format("Pushing %s\n", tostring(word)))
    end
    table.insert(stack, tonumber(numtext))
    return
  end
  local d = word_definition(word)
  assert(type(d) == "function", "word cannot be used here: "..tostring(word))
  if tracing then
    io.stderr:write(string.format("Evaluating %s\n", tostring(word)))
  end
  d(worditer)
end

function skip_forth_word(word, worditer)
  local skipper = skippers[word_definition(word)]
  if skipper then
    skipper(worditer)
  end
end

-- Forth words

for name, fn_ in pairs(queries) do
  local fn = fn_
  local getter = function (readarg)
    table.insert(stack, (fn(readarg)))
  end
  local putter = function (readarg)
    put((fn(readarg)) or "")
  end
  dictionary["?"..name] = getter
  dictionary[name] = putter
  local skipper = query_skippers[name]
  if skipper then
    skippers[getter] = skipper
    skippers[putter] = skipper
  end
end

dictionary.reset   = ansi_attribute_putter("0")
dictionary.black   = ansi_attribute_putter("30")
dictionary.blue    = ansi_attribute_putter("34")
dictionary.cyan    = ansi_attribute_putter("36")
dictionary.green   = ansi_attribute_putter("32")
dictionary.magenta = ansi_attribute_putter("35")
dictionary.red     = ansi_attribute_putter("31")
dictionary.white   = ansi_attribute_putter("37")
dictionary.yellow  = ansi_attribute_putter("33")

dictionary[".s"] = function()
  io.stderr:write("[")
  for i, val in ipairs(stack) do
    local sep = (i > 1 and " ") or ""
    io.stderr:write(tostring(val)..sep)
  end
  io.stderr:write("]\n")
end

function dictionary.constant(worditer)
  local value = pop_value()
  redefine(worditer(),
           function () push_value(value) end)
end

dictionary["then"] = "then"
dictionary["else"] = "else"

dictionary["if"] = function(worditer)
  local flag = truth_value(pop_value())
  for word in worditer do
    local d = word_definition_or_nil(word)
    if d == "then" then
      break
    elseif d == "else" then
      flag = not flag
    elseif flag then
      eval_forth_word(word, worditer)
    else
      skip_forth_word(word, worditer)
    end
  end
end

skippers[dictionary["if"]] = skipper_until("then")

function dictionary.invert()
  push_value(not truth_value(pop_value()))
end

dictionary["and"] = value_bin_op(function(a,b) return truth_value(a) and truth_value(b) end)
dictionary["or"]  = value_bin_op(function(a,b) return truth_value(a) or  truth_value(b) end)

dictionary["="]  = value_bin_op(forth_equal)
dictionary["<>"] = value_bin_op(function(a,b) return not forth_equal(a,b) end)

dictionary["<"]  = number_bin_op(function(a,b) return a <  b end)
dictionary["<="] = number_bin_op(function(a,b) return a <= b end)
dictionary[">"]  = number_bin_op(function(a,b) return a >  b end)
dictionary[">="] = number_bin_op(function(a,b) return a >= b end)

dictionary["+"] = number_bin_op(function(a,b) return a + b end)
dictionary["-"] = number_bin_op(function(a,b) return a - b end)
dictionary["*"] = number_bin_op(function(a,b) return a * b end)

-- TODO: division by zero currently pushes the value NaN or -NaN
dictionary["/"] = number_bin_op(function(a,b) return a / b end)
dictionary["mod"] = number_bin_op(function(a,b) return a % b end)

dictionary["/mod"] = function()
  local b, a = pop_number(), pop_number()
  push_value(a % b)
  push_value(a / b)
end

dictionary["min"] = number_bin_op(math.min)
dictionary["max"] = number_bin_op(math.max)

function dictionary.drop()
  pop_value()
end

function dictionary.dup()
  local x = pop_value()
  push_value(x)
  push_value(x)
end

function dictionary.over()
  assert(#stack >= 2, "stack underflow")
  push_value(stack[#stack - 1])
end

function dictionary.swap()
  local b, a = pop_value(), pop_value()
  push_value(b)
  push_value(a)
end

function dictionary.line()
  local length = pop_number()
  if has_utf8_encoding then
    -- This seems to work in Linux console, xterm, gnome-terminal and
    -- PuTTY. PuTTY and old versions of xterm can't do VT100 line
    -- drawing characters, so prefer the Unicode ones where
    -- possible. They seem to be slightly more portable.
    put(string.rep("\xe2\x94\x80", length)) -- UTF-8 encoding of U+2500
  elseif has_vt100_graphics then
    put_terminal_escape("(0")
    put(string.rep("q", length))
    put_terminal_escape("(B")
  else
    put(string.rep("-", length))
  end
end

function dictionary.nl()
  if is_bash or is_tcsh then
    putraw("\\n")
  else
    putraw("\n")
  end
end

dictionary["endtitle"] = "endtitle"

function dictionary.title(worditer)
  -- TODO: It should be an error to use ANSI colors and other
  -- formatting directives within the title. Or should it really?  If
  -- we permit ANSI colors (and treat them as no-ops) then the same
  -- code can be re-used within titles and outside of them.
  if has_xterm_title then
    begin_zero_length_escape(']0;')
  end
  for word in worditer do
    if word_definition(word) == "endtitle" then
      break
    elseif has_xterm_title then
      eval_forth_word(word, worditer)
    else
      skip_forth_word(word, worditer)
    end
  end
  if has_xterm_title then
    putraw("\x07")
    end_zero_length_escape()
  end
end

skippers[dictionary.title] = skipper_until("endtitle")

-- Actions

local actions = {}
local actionargs = {}
local actiondocs = {}

actiondocs.activate = "activate the prompt in your shell"
actionargs.activate = "<shell>"

function actions.activate(nextarg)
  local which_shell = nextarg()
  if which_shell == "bash" then
    print([[PROMPT_COMMAND='PS1="$(shellprompt encode bash || echo "$ ")"']])
  elseif which_shell == "zsh" then
    print([[precmd () { PROMPT="$(shellprompt encode zsh || echo "$ ")" }]])
  elseif which_shell == "tcsh" then
    print([[alias precmd 'set prompt = "`shellprompt encode tcsh || echo %`"']])
  else
    die(string.format("unknown shell: %q", which_shell))
  end
end

actiondocs.edit = "edit the shell prompt in your text editor of choice"

function actions.edit(nextarg)
  local editor = (os.getenv("EDITOR") or "")
  if not editor:match("%w+") then
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
  detect_terminal_capabilities()
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
