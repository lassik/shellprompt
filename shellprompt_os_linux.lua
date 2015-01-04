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
  local MAXBAT = 5  -- TODO: Pulled this one out of a hat
  for batnum=0,MAXBAT do
    local batdir = "/proc/acpi/battery/BAT"..tostring(batnum)
    local info = contents_or_blank(batdir.."/info")
    local state = contents_or_blank(batdir.."/state")
    if info ~= "" and state ~= "" then
      charging = state:match("charging state:%s*(%a+)")
      curcharge = state:match("remaining capacity:%s*(%d+)")
      maxcharge = info:match("last full capacity:%s*(%d+)")
      break
    end
  end
  -- For computers without a battery, fake 100% charge
  curcharge = curcharge or 100
  maxcharge = maxcharge or 100
  local percent = math.max(0, math.min(100, curcharge*100/maxcharge))
  return {charging=charging, percent=percent}
end
