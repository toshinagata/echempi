-- ---------------------------------------------
--   ts.lua       2017/08/09
--   Copyright (c) 2017 Toshi Nagata
--   released under the MIT open source license.
-- ---------------------------------------------

local ffi = require "ffi"
local bit = require "bit"
local util = require "util"
local ctl = require "ctl"

libts = ffi.load("libts-0.0.so.0")

ffi.cdef[[
struct tsdev;
struct tsdev *ts_open(const char *dev_name, int nonblock);
struct ts_sample {
  int x, y;
  unsigned int pressure;
  struct timeval tv;
};
int ts_read(struct tsdev *dev, struct ts_sample *samp, int nr);
int ts_config(struct tsdev *ts);
int ts_close(struct tsdev *ts);

]]

local ts = {}

function ts.init()
  local name = ffi.new("char[256]")
  local EVIOCGNAME = function (len) return ctl.IOR(0x45, 0x06, len) end  -- 0x45 = 'E'
  local devname
  for i = 0, 9 do
    local dname = string.format("/dev/input/event%d", i)
    local fd = ffi.C.open(dname, ctl.O_RDONLY)
    if fd >= 0 then
      if ffi.C.ioctl(fd, EVIOCGNAME(256), name) >= 0 then
        if string.match(ffi.string(name), "[Tt]ouchscreen") then
          ffi.C.close(fd)
          devname = dname
          break
        end
      end
      ffi.C.close(fd)
    end
  end
  if devname == nil then return false end
  local tsdev = libts.ts_open(devname, 1)
  if tsdev == nil then return false end
  if libts.ts_config(tsdev) ~= 0 then
    libts.ts_close(tsdev)
    return false
  end
  ts.dev = tsdev
  return true
end
  
function ts.read()
  if ts.dev == nil then
    if not ts.init() then error "Cannot setup touchscreen device" end
  end
  local samp = ffi.new("struct ts_sample[1]")
  if libts.ts_read(ts.dev, samp, 1) == 1 then
    return samp[0].x, samp[0].y, samp[0].pressure
  else
    return nil
  end
end

return ts
