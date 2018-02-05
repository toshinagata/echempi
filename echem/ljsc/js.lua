-- ---------------------------------------------
--   js.lua       2017/08/09
--   Copyright (c) 2017 Toshi Nagata
--   released under the MIT open source license.
-- ---------------------------------------------

local ffi = require "ffi"
local bit = require "bit"
local util = require "util"
local ctl = require "ctl"

local js = {}

ffi.cdef[[
  struct js_event {
    unsigned int time;  /* event timestamp in milliseconds */
    short value;
    char type;
    char number;
  };
  static const int F_SETFL = 4;
]]

local JS_EVENT_BUTTON = 0x01
local JS_EVENT_AXIS   = 0x02
local JS_EVENT_INIT   = 0x80
local JSIOCGVERSION   = ctl.IOR(0x6a, 0x01, 4) -- 0x80046a01, 0x6a = 'j'
local JSIOCGAXES      = ctl.IOR(0x6a, 0x11, 1) -- 0x80016a11
local JSIOCGBUTTONS   = ctl.IOR(0x6a, 0x12, 1) -- 0x80016a12
local JSIOCGNAME      = function (len) return ctl.IOR(0x6a, 0x13, len) end -- 0x80006a13 + len*0x10000

local devices = {}
local initialized = false

function js.getDeviceInfo(fd)
  local dev = {}
  local version = ffi.new("int[1]")
  local axes = ffi.new("unsigned char[1]")
  local buttons = ffi.new("unsigned char[1]")
  local name = ffi.new("char[128]")
  ffi.C.ioctl(fd, JSIOCGNAME(128), name)
  dev.name = ffi.string(name)
  local lname = string.lower(dev.name)
  if string.find(lname, "keyboard") or string.find(lname, "mouse") or string.find(lname, "touchscreen") then
    return nil  --  This is (probably) not a joystick
  end
  ffi.C.ioctl(fd, JSIOCGVERSION, version)
  ffi.C.ioctl(fd, JSIOCGAXES, axes)
  ffi.C.ioctl(fd, JSIOCGBUTTONS, buttons)
  dev.version = version[0]
  dev.num_axes = axes[0]
  dev.num_buttons = buttons[0]
  dev.event_buf = ffi.new("struct js_event[1]")
  dev.buf_size = ffi.sizeof(dev.event_buf)
  dev.axes = {}
  dev.buttons = {}
  for j = 1, axes[0] do
    table.insert(dev.axes, { type = 0, number = 0, value = 0, time = 0 })
  end
  for j = 1, buttons[0] do
    table.insert(dev.buttons, { type = 0, number = 0, value = 0, time = 0 })
  end
  return dev
end
  
function js.open(devno)
  if devno < 0 or devno >= 8 then return -1 end
  local fd = ffi.C.open(string.format("/dev/input/js%d", devno), ctl.O_RDONLY + ctl.O_NONBLOCK)
  if fd >= 0 then
    dev = js.getDeviceInfo(fd)
    if dev then
      dev.num = devno
      dev.fd = fd
      dev.last_time = 0
      devices[#devices + 1] = dev
      return #devices
    else
      ffi.C.close(fd)
    end
  end
  return -1
end

function js.init()
  for i = 0, 7 do
    js.open(i)
  end
  return #devices
end
  
function js.devinfo(devno)
  if (devno < 0) or (devno >= #devices) then
    return nil
  else
    return devices[devno + 1]
  end
end

--  Read joystick event
--  Returns nil if no input
--  Returns a device record if any input was detected
--    dev.axes[n].value = value for the n-th axis (1: x, 2: y)
--    dev.axes[n].time = timestamp of the last event on this axis
--    dev.buttons[n].value = value for the n-th button
--    dev.axes[n].time = timestamp of the last event on this button
function js.read_event(devno)
  if (devno < 0) or (devno >= #devices) then
    return nil  --  Invalid device
  end
  local dev = devices[devno + 1]
  local res, count
  count = 0
  while true do
    res = ffi.C.read(dev.fd, dev.event_buf, dev.buf_size)
    if res == dev.buf_size then
      local type = bit.band(dev.event_buf[0].type, bit.bnot(JS_EVENT_INIT))
      if type == JS_EVENT_AXIS then
        local axis = dev.axes[dev.event_buf[0].number + 1]
        axis.value = dev.event_buf[0].value
        axis.time = dev.event_buf[0].time
      elseif type == JS_EVENT_BUTTON then
        local button = dev.buttons[dev.event_buf[0].number + 1]
        if dev.event_buf[0].value ~= 0 then
          button.value = 1
        else
          button.value = 0
        end
        button.time = dev.event_buf[0].time
      end
      count = count + 1
    else
      if count == 0 then return nil else return dev end
    end
  end
end

return js
