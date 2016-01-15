-- Globals

math.randomseed(shellprompt_os_milliseconds())

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

function shallow_copy(orig)
  -- Based on http://lua-users.org/wiki/CopyTable
  local copy
  if type(orig) == 'table' then
    copy = {}
    setmetatable(copy, getmetatable(orig))
    for key, value in pairs(orig) do
      copy[key] = value
    end
  else
    copy = orig
  end
  return copy
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

function string:split(delim, is_plain)
  -- Credit to Joan Ordinas, http://lua-users.org/wiki/SplitJoin
  assert(delim ~= '')
  local ans = {}
  if self:len() > 0 then
    local start = 1
    local first, last = self:find(delim, start, is_plain)
    while first do
      table.insert(ans, self:sub(start, first-1))
      start = last+1
      first, last = self:find(delim, start, is_plain)
    end
    table.insert(ans, self:sub(start))
  end
  return ans
end

function string_has_prefix(whole, part)
  return (string.find(whole, part, 1, true) == 1)
end

function string_prefix_or_whole(part, whole)
  local first, _ = string.find(whole, part, 1, true)
  return string.sub(whole, 1, (first or 1+string.len(whole))-1)
end

function string_suffix_or_whole(part, whole)
  local _, last = string_findlast_plain(whole, part)
  return string.sub(whole, (last or 0)+1, string.len(whole))
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

function skip_whitespace_and_comments(s, i)
  local a, b
  while i <= string.len(s) do
    a, b = string.find(s, "%s+", i)
    if a == i then
      i = b + 1
    else
      a, b = string.find(s, "\\", i, true)
      if a == i then
        a, b = string.find(s, "[\n\r]+", i)
        b = b or string.len(s)
        i = b + 1
      else
        break
      end
    end
  end
  return i
end

function parse_bare_word(s, i)
  local a, b
  local tok = nil
  a, b = string.find(s, "[^\"\\%s]+", i)
  if a == i then
    tok = string.sub(s, a, b)
    i = b + 1
  end
  return i, tok
end

function parse_quoted_string(s, i)
  local a, b
  local tok = nil
  if string.find(s, '"', i, true) == i then
    tok = ""
    i = i + 1
    while not (string.find(s, '"', i, true) == i) do
      a, b = string.find(s, "[^\t\n\r\"\\]+", i)
      if a == i then
        tok = tok..string.sub(s, a, b)
        i = b + 1
      else
        a, b = string.find(s, "\\[^\t\n\r]", i)
        if a == i then
          tok = tok..string.sub(s, b, b)
          i = b + 1
        else
          die("Missing closing quote or newline/tab in string")
        end
      end
    end
    i = i + 1
  end
  return i, tok
end

function load_program_from_string(s)
  local tok
  local tokens = {}
  local i = 1
  while i <= string.len(s) do
    i = skip_whitespace_and_comments(s, i)
    i, tok = parse_quoted_string(s, i)
    if tok then
      table.insert(tokens, {tok})
    else
      i, tok = parse_bare_word(s, i)
      if tok and string.match(tok, "^[+-]?%d+$") then
        table.insert(tokens, {tonumber(tok)})
      elseif tok then
        table.insert(tokens, tok)
      else
        break
      end
    end
  end
  return tokens
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

function get_string_token(tokiter, for_whom)
  local token = tokiter()
  if type(token) ~= "table" or #token ~= 1 or type(token[1]) ~= "string" then
    error(for_whom..": string expected")
  end
  return token[1]
end

-- Queries

local queries = {}

queries.text = {
  function(tokiter)
    local text = get_string_token(tokiter, "text")
    return function()
      return text
    end
  end
}

queries.reptext = {
  function(tokiter)
    local text = get_string_token(tokiter, "reptext")
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
  return string_prefix_or_whole('.', shellprompt_os_get_full_hostname())
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

local loopstack = {}
local loopindex = nil

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
  local value = pop_value()
  assert(type(value) == goaltype, goaltype.." expected")
  return value
end

function pop_value_with_metatable(desc, mt)
  local value = pop_value()
  assert(((type(value) == "table") and (getmetatable(value) == mt)),
         desc.." expected")
  return value
end

local list_mt = {}
local dict_mt= {}
local set_mt = {}

function is_integer(obj)
  return type(obj) == "number" and obj % 1 == 0
end

function is_string(obj)
  return type(obj) == "string"
end

function is_list(obj)
  return type(obj) == "table" and getmetatable(obj) == list_mt
end

function is_dict(obj)
  return type(obj) == "table" and getmetatable(obj) == dict_mt
end

function is_set(obj)
  return type(obj) == "table" and getmetatable(obj) == set_mt
end

function make_list(tabl)
  tabl = tabl or {}
  setmetatable(tabl, list_mt)
  return tabl
end

function make_dict()
  local obj = {}
  setmetatable(obj, dict_mt)
  return obj
end

function make_set()
  local obj = {}
  setmetatable(obj, set_mt)
  return obj
end

function pop_xt()
  return pop_value_of_type("function")
end

function pop_list()
  return pop_value_with_metatable("list", list_mt)
end

function pop_dict()
  return pop_value_with_metatable("dictionary", dict_mt)
end

function pop_set()
  return pop_value_with_metatable("set", set_mt)
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

function literal_pusher(value)
  return function()
    if tracing then
      io.stderr:write(string.format("Pushing %s\n", tostring(value)))
    end
    push_value(value)
  end
end

function compile(token, tokiter)
  if not token then
    error("premature end of file")
  elseif type(token) == "table" then -- literal
    assert(#token == 1)
    return literal_pusher(token[1])
  else
    assert(type(token) == "string") -- word
    local defn = dictionary[token]
    if type(defn) == "function" then -- executed
      return defn
    elseif type(defn) == "table" then -- compiled
      assert(#defn == 1)
      assert(type(defn[1]) == "function")
      return defn[1](tokiter)
    elseif not defn then
      error("undefined word: "..tostring(token))
    else
      assert(type(defn) == "string")
      error("word cannot be used here: "..tostring(token))
    end
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
    getter = function()
      push_value((f()))
    end
    putter = function()
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
    redefine(name, function() push_value(value) end)
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

dictionary["do"] = {
  function(worditer)
    local body = {}
    for word in worditer do
      if word_has_definition(word, "loop") then
        break
      else
        table.insert(body, compile(word, worditer))
      end
    end
    return function()
      table.insert(loopstack, loopindex)
      loopindex = pop_number()
      local limit = pop_number()
      while loopindex < limit do
        execlist(body)
        loopindex = loopindex + 1
      end
      loopindex = table.remove(loopstack)
    end
  end
}

dictionary["loop"] = "loop"

function dictionary.i()
  push_value(loopindex)
end

function compile_colon_xt(worditer)
  local body = {}
  local xt = function() execlist(body) end
  table.insert(defnstack, xt)
  for word in worditer do
    if word_has_definition(word, ";") then
      break
    else
      table.insert(body, compile(word, worditer))
    end
  end
  table.remove(defnstack)
  return xt
end

dictionary[":noname"] = {
  function(worditer)
    local xt = compile_colon_xt(worditer)
    return function() push_value(xt) end
  end
}

dictionary[":"] = {
  function(worditer)
    local name = worditer()
    assert(name)
    dictionary[name] = compile_colon_xt(worditer)
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

dictionary["{"] = {
  function(worditer)
    local body = {}
    for word in worditer do
      if word_has_definition(word, "}") then
        break
      else
        table.insert(body, compile(word, worditer))
      end
    end
    return function()
      local depth = #stack
      execlist(body)
      local items = {}
      for i = depth+1,#stack do
        table.insert(items, stack[i])
      end
      push_value(make_list(items))
    end
  end
}

dictionary["}"] = "}"

function dictionary.union()
  local a, b, c = pop_set(), pop_set(), make_set()
  for k in pairs(a) do c[k] = true end
  for k in pairs(b) do c[k] = true end
  push_value(c)
end

function dictionary.intersect()
  local a, b, c = pop_set(), pop_set(), make_set()
  for k in pairs(a) do
    c[k] = b[k]
  end
  push_value(c)
end

function dictionary.random()
  local spec = pop_value()
  if is_integer(spec) then
    push_value(math.random(0, spec-1))
  elseif is_string(spec) then
    assert(spec:len() > 0)
    local idx = math.random(spec:len())
    push_value(spec:sub(idx, idx))
  elseif is_list(spec) or is_dict(spec) or is_set(spec) then
    assert(#spec > 0)
    push_value(spec[math.random(#spec)])
  else
    error("random: integer or collection expected")
  end
end

function dictionary.each()
  local xt = pop_xt()
  local coll = pop_list()
  for _, item in ipairs(coll) do
    push_value(item)
    xt()
  end
end

function dictionary.map()
  local xt = pop_xt()
  local coll = pop_list()
  local results = {}
  for _, item in ipairs(coll) do
    push_value(item)
    xt()
    table.insert(results, pop_value())
  end
  push_value(make_list(results))
end

function dictionary.length()
  local coll = pop_value()
  if is_string(coll) then
    push_value(string.len(coll))
  elseif is_list(coll) or is_dict(coll) or is_set(coll) then
    push_value(#coll)
  else
    error("length: collection expected")
  end
end

function dictionary.last()
  local coll = pop_value()
  if is_string(coll) then
    assert(coll:len() > 0)
    push_value(coll:sub(coll:len(), coll:len()))
  elseif is_list(coll) then
    assert(#coll > 0)
    push_value(coll[#coll])
  else
    error("last: list or string expected")
  end
end

function dictionary.sort()
  local xt = pop_xt()
  local coll = pop_value()
  if not (is_list(coll) or is_set(coll)) then
    error("sort: list or set expected")
  end
  coll = make_list(shallow_copy(coll))
  function compare(a, b)
    push_value(a)
    push_value(b)
    xt()
    return truth_value(pop_value())
  end
  table.sort(coll, compare)
  push_value(coll)
end

function dictionary.join()
  local delimiter = pop_string()
  push_value(table.concat(pop_list(), delimiter))
end

function dictionary.split()
  local delimiter = pop_string()
  push_value(make_list(pop_string():split(delimiter, true)))
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
