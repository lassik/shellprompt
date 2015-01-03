function contents_or_blank(filename)
  local contents = ""
  local stream = io.open(filename, "rb")
  if stream then
    contents = stream:read("*a")
    stream:close()
  end
  return contents
end

function shellprompt_os_getpowerinfo()
  local charging = nil
  local curcharge = nil
  local maxcharge = nil
  for i, bat in ipairs({"BAT1"}) do
    local info = contents_or_blank("/proc/acpi/battery/"..bat.."/info")
    local state = contents_or_blank("/proc/acpi/battery/"..bat.."/state")
    charging = state:match("charging state:%s*(%a+)")
    curcharge = state:match("remaining capacity:%s*(%d+)")
    maxcharge = info:match("last full capacity:%s*(%d+)")
  end
  curcharge = curcharge or 100
  maxcharge = maxcharge or 100
  local percent = math.max(0, math.min(100, curcharge*100/maxcharge))
  return {charging=charging, percent=percent}
end
