-- Globals

local MAIN_INCLUDE_FILE = "prompt"

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

local include_path = get_xdg_config_homes()
local included_set = {}  -- Items are filenames.
local includestack = {}  -- Items are filenames.

function get_program_dirname_for_writing()
  local homes = get_xdg_config_homes()
  if #homes == 0 then die("Home directory not found") end
  local home = homes[1]
  shellprompt_os_ensure_dir_exists(home)
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

function sourcefilename()
  return includestack[#includestack]
end

function is_included(filename)
  -- TODO: take realpaths of filenames (or use unix dev/ino for checking)
  return (included_set[filename] ~= nil)
end

function open_include_file(filename, canfail)
  -- TODO: Allow caller to give absolute filename
  -- TODO: Assumes all include_path entries end in dir separator.
  for _, dir in ipairs(include_path) do
    local fullpath = dir..filename
    local stream = io.open(fullpath, "r")
    if stream then return stream, fullpath end
  end
  if not stream and not canfail then
    error("cannot open include file "..tostring(filename))
  end
  return nil, nil
end

function read_include_file(filename, canfail)
  local contents = ""
  local stream, fullpath = open_include_file(filename, canfail)
  if stream then
    contents = stream:read("*a")
    stream:close()
  end
  return contents, fullpath
end

function include_file(filename, canfail)
  local contents, fullpath = read_include_file(filename, canfail)
  table.insert(included_set, fullpath)
  table.insert(includestack, fullpath)
  local program = load_program_from_string(contents)
  local worditer = consumer(program)
  for word in worditer do
    execute(compile(word, worditer))
  end
  table.remove(includestack)
end

function require_file(filename)
  if is_included(filename) then return end
  include_file(filename)
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
  sequence = sequence or ""
  if is_bash then
    putraw("\\[\\e"..sequence)
  elseif is_zsh or is_tcsh then
    putraw("%{"..string.char(0x1b)..sequence)
  else
    putraw(string.char(0x1b)..sequence)
  end
end

function end_zero_length_escape(sequence)
  sequence = sequence or ""
  if is_bash then
    putraw(sequence.."\\]")
  elseif is_zsh or is_tcsh then
    putraw(sequence.."%}")
  else
    putraw(sequence)
  end
end

function put_zero_length_escape(sequence)
  begin_zero_length_escape(sequence)
  end_zero_length_escape()
end

function ansi_attribute_putter(ansi)
  return function()
    if has_ansi_escapes and (last_ansi ~= ansi) then
      put_zero_length_escape("["..ansi.."m")
      last_ansi = ansi
    end
  end
end

-- Queries

local queries = {}

queries.text = {
  function(readarg)
    local text = readarg()
    assert(text)
    return function()
      return text
    end
  end
}

queries.reptext = {
  function(readarg)
    local text = readarg()
    assert(text)
    return function()
      return string.rep(text, pop_number())
    end
  end
}

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

function queries.space()
  return " "
end

function queries.spaces()
  return string.rep(" ", pop_number())
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

function queries.getenv()
  return (os.getenv(pop_string())) or ""
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
local variables = {}
local stack = {}
local defnstack = {} -- TODO: Really need to accommodate multiple entries?

function printvars()
  for key, val in pairs(variables) do
    print(key.." = "..tostring(val))
  end
end

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

function pop_string()
  return pop_value_of_type("string")
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

function word_has_definition(word, d)
  -- NOTE: word need not be defined.
  return dictionary[word] == d
end

function execute(xt)
  if xt == nil then return end
  assert(type(xt) == "function")
  -- TODO: If we stored the name/description of xt somewhere, we could
  -- implement a trace feature that printed here the name/description
  -- of the token that's about to be executed.
  if tracing then
    --io.stderr:write(string.format("Evaluating %s\n", tostring(word)))
  end
  xt()
end

function execlist(xts)
  for _, xt in ipairs(xts) do
    execute(xt)
  end
end

function compile_number(word)
  if not string.match(word, "^[+-]?%d+$") then return nil end
  local value = tonumber(word)
  return function()
    if tracing then
      io.stderr:write(string.format("Pushing %s\n", tostring(value)))
    end
    push_value(value)
  end
end

function compile(word, worditer)
  if not word then error("premature end of file") end
  local defn = compile_number(word)
  if defn then return defn end
  defn = dictionary[word]
  if type(defn) == "function" then -- executed
    return defn
  elseif type(defn) == "table" then -- compiled
    assert((#defn == 1) and (type(defn[1]) == "function"))
    return defn[1](worditer)
  elseif not defn then
    error("undefined word: "..tostring(word))
  else
    error("word cannot be used here: "..tostring(word))
  end
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

-- Forth words

for name, defn in pairs(queries) do
  local getter, putter = nil, nil
  if type(defn) == "table" then  -- compiled
    local compile = defn[1]
    getter = {
      function(worditer)
        local f = compile(worditer)
        return function()
          push_value((f()))
        end
      end
    }
    putter = {
      function(worditer)
        local f = compile(worditer)
        return function()
          put((f()) or "")
        end
      end
    }
  else
    assert(type(defn) == "function")  -- executed
    local f = defn
    getter = function ()
      push_value((f()))
    end
    putter = function ()
      put((f()) or "")
    end
  end
  dictionary["?"..name] = getter
  dictionary[name] = putter
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

function dictionary.sourcefilename()
  push_value(sourcefilename())
end

dictionary["included?"] = function()
  push_value(is_included(pop_string()))
end

function dictionary.included()
  include_file(pop_string())
end

function dictionary.required()
  require_file(pop_string())
end

dictionary["slurp-file"] = function()
  local filename = pop_string()
  local contents = ""
  local stream = io.open(filename, "r")
  if stream then
    contents = stream:read("*a")
    stream:close()
  end
  push_value(contents)
end

dictionary.constant = {
  function(worditer)
    local name = worditer()
    assert(name)
    local value = pop_value()
    redefine(name, function () push_value(value) end)
    return nil
  end
}

dictionary.variable = {
  function(worditer)
    local name = worditer()
    assert(name)
    local uniq = 0
    local key = name
    while variables[key] do
      uniq = uniq + 1
      key = name.."."..uniq
    end
    -- Wrap variable value in a table so it's never nil. Lua doesn't
    -- distinguish between nil-valued table keys and nonexistent keys.
    variables[key] = {nil}
    dictionary[name] = function() push_value(variables[key][1]) end
    dictionary[name.."!"] = function() variables[key][1] = pop_value() end
    return nil
  end
}

dictionary["then"] = "then"
dictionary["else"] = "else"

dictionary["if"] = {
  function(worditer)
    local thens, elses, inelse = {}, {}, false
    for word in worditer do
      if word_has_definition(word, "then") then
        break
      elseif word_has_definition(word, "else") then
        assert(not inelse)
        inelse = true
      elseif not inelse then
        table.insert(thens, compile(word, worditer))
      else
        table.insert(elses, compile(word, worditer))
      end
    end
    return function()
      if truth_value(pop_value()) then
        execlist(thens)
      else
        execlist(elses)
      end
    end
  end
}

dictionary[":"] = {
  function(worditer)
    local name = worditer()
    assert(name)
    local body = {}
    local defn = function() execlist(body) end
    table.insert(defnstack, defn)
    for word in worditer do
      if word_has_definition(word, ";") then
        break
      else
        table.insert(body, compile(word, worditer))
      end
    end
    table.remove(defnstack)
    dictionary[name] = defn
    return nil
  end
}

dictionary[";"] = ";"

dictionary.recurse = {
  function()
    local defn = defnstack[#defnstack]
    if not defn then error("recurse outside word definition") end
    return defn
  end
}

dictionary["'"] = {
  function(worditer)
    local name = worditer()
    assert(name)
    local f = dictionary[name]
    if not f then error("tick: undefined word: "..tostring(name)) end
    return function() push_value(f) end
  end
}

function dictionary.execute()
  local fn = pop_value_of_type("function")
  fn()
end

dictionary[".vs"] = printvars

dictionary["."] = function()
  print(pop_value())
end

function dictionary.type()
  put(tostring(pop_value() or ""))
end

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

dictionary["1+"] = function() push_value(pop_number() + 1) end
dictionary["1-"] = function() push_value(pop_number() - 1) end

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

function dictionary.length()
  push_value(string.len(pop_string()))
end

function dictionary.tolower()
  push_value(string.lower(pop_string()))
end

function dictionary.toupper()
  push_value(string.upper(pop_string()))
end

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
    put_zero_length_escape("(0")
    put(string.rep("q", length))
    put_zero_length_escape("(B")
  else
    put(string.rep("-", length))
  end
end

function dictionary.cr()
  if is_bash or is_tcsh then
    putraw("\\n")
  else
    putraw("\n")
  end
end

dictionary["endtitle"] = "endtitle"

-- TODO: It should be an error to use ANSI colors and other formatting
-- directives within the title. Or should it really?  If we permit
-- ANSI colors (and treat them as no-ops) then the same code can be
-- re-used within titles and outside of them.
dictionary.title = {
  function(worditer)
    local body = {}
    for word in worditer do
      if word_has_definition(word, "endtitle") then
        break
      else
        table.insert(body, compile(word, worditer))
      end
    end
    return function()
      if has_xterm_title then
        begin_zero_length_escape(']0;')
        execlist(body)
        end_zero_length_escape("\x07")
      end
    end
  end
}

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
  local stream, filename = open_include_file(MAIN_INCLUDE_FILE, true)
  if stream then
    stream:close()
  else
    filename = get_program_dirname_for_writing()..MAIN_INCLUDE_FILE
  end
  os.execute(editor.." "..filename)
end

actiondocs.show = "write out the program for the current prompt"

function actions.show(nextarg)
  assert(not nextarg())
  local contents, fullpath = read_include_file(MAIN_INCLUDE_FILE, true)
  if contents:len() > 0 then
    print(contents)
  end
end

actiondocs.set = "set the prompt to the given program"
actionargs.set = "<program...>"

function actions.set(nextarg)
  save_program(nextarg, get_program_dirname_for_writing()..MAIN_INCLUDE_FILE)
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
  local reset = compile("reset")
  execute(reset)
  include_file(MAIN_INCLUDE_FILE, true)
  execute(reset)
  if is_tcsh then
    -- TODO: This extra space at the end of the prompt is needed so
    -- the last color from the prompt doesn't bleed over into the
    -- user-editable command line.  The tcsh manual, section "Special
    -- shell variables", command "prompt", says for "%{string%}":
    -- "This cannot be the last sequence in prompt."  Using %L last
    -- doesn't work either (it has no effect). We could try to be
    -- smart and catch a trailing "space" command or other whitespace
    -- and put the ANSI reset before that, but there has to be a
    -- better way...
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
