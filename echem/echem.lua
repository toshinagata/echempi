-- ---------------------------------------------
--   echem.lua          2018/01/18
--   Copyright (c) 2018 Toshi Nagata,
--   released under the MIT open source license.
-- ---------------------------------------------

require "ljsc/init"

local util = require("util")
local sc = require("screen")
local term = require("termios")
local ffi = require("ffi")
local ts = require("ts")

--  Compile echemsub.c in the same directory as echem.lua
dname = string.gsub(arg[0], "echem%.lua$", "")
if dname == "" then dname = "./" end
os.execute("cd " .. dname .. "; if [ ! -f echemsub.so ] || [ echemsub.so -ot echemsub.c ]; then echo 'Building echemsub.so...'; gcc -O2 -fPIC -shared -o echemsub.so echemsub.c -lwiringPi; echo 'Done.'; fi")
--  And load it
echemsub = ffi.load(dname .. "echemsub.so")
ffi.cdef[[
  struct conv_record { double stamp; int outdata; int indata; };
  int conv_init(int ch1, int speed1, int ch2, int speed2, int gpio);
  int conv_quit(void);
  int conv_reset(void);
  int conv_queue(struct conv_record *data);
  int conv_start(void);
  int conv_read(struct conv_record *data);
  int conv_stop(void);
  int conv_direct_write(int val);
  int conv_direct_read(void);
  int conv_last_output(void);
  int conv_last_input(void);
]]

sc.init(1)
sc.cls()
ts.init()

tech = "StandBy"

--  Calibration data
--  { Iw_zero_point, Vd_zero_point, Vw_scale, Iw_scale, Vd_scale }
--  Note: Vd_*** is no longer used
--  "zero_point" is the DAC readout corresponding to 0.0
--  "scale" is the multiplier*1000 for DAC/ADC value

function write_settings()
  local f, s
  s = string.format("calib = { %f, %f, %f, %f, %f }\n", calib[1], calib[2], calib[3], calib[4], calib[5])
  --  { potential, interval, time, rest_potential }
  s = s .. string.format("electrolysis_settings = { %f, %f, %f, %f }\n", electrolysis_settings[1], electrolysis_settings[2], electrolysis_settings[3], electrolysis_settings[4])
  --  { initial, high, low, polarity (0:pos, 1:neg), speed, scans, wait }
  s = s .. string.format("cv_settings = { %f, %f, %f, %d, %f, %d, %f }\n", cv_settings[1], cv_settings[2], cv_settings[3], cv_settings[4], cv_settings[5], cv_settings[6], cv_settings[7])
  s = s .. string.format("echem_graph = { %d, %d, %f, %f, 0, %d, %d }\n", echem_graph[1], echem_graph[2], echem_graph[3], echem_graph[4], echem_graph[6], echem_graph[7])
  s = s .. string.format("volw_zero = %d\n", volw_zero)
  f = io.open("echem_settings.lua", "w")
  f:write(s)
  f:close()
end

--  Settings
pcall(dofile, "echem_settings.lua")
if calib == nil or #calib < 5 then
  calib = { 1725.24, 1726.78, 1.998046, -6.143303, -6.109678 }
end
if electrolysis_settings == nil or #electrolysis_settings < 4 then
  electrolysis_settings = { 0.0, 1.0, 3600.0, 2.0 }
end
if cv_settings == nil or #cv_settings < 7 then
  cv_settings = { 0.0, 1.0, -1.0, 0, 1000.0, 2, 2.0 }
end
if volw_zero == nil then
  volw_zero = 2194    -- (1.29/2.7+1.29)/3.3*4095
end

vol = 0.0
cur = 0.0
vol_raw = volw_zero
cur_raw = volw_zero

-- {running, tech, start_time, last_index, interval, ...}
-- tech = 1 (const pot): [...] = end_time
-- tech = 2 (CV): [...] = start_pot, high_pot, low_pot, interval_e
echem_setup = {0}

echem_send_idx = 0
echem_receive_idx = 0

-- date & time
datetime = {}

-- graph magnification
i_mag = { 0.01, 0.02, 0.05, 0.1, 0.2, 0.5, 1.0, 2.0, 5.0 }
i_mag_labels = { 10, 20, 50, 100, 200, 500, 1, 2, 5 }
i_mag_formats = { "%.0fuA", "%.0fuA", "%.0fuA", "%.0fuA", "%.0fuA", "%.0fuA", "%.1fmA", "%.1fmA", "%.1fmA" }
v_mag = i_mag
v_mag_labels = { 10, 20, 50, 100, 200, 500, 1, 2 }
v_mag_formats = { "%.0fmV", "%.0fmV", "%.0fmV", "%.0fmV", "%.0fmV", "%.0fmV", "%.1fV", "%.1fV" }
t_mag = { 1.0, 5.0, 10.0, 20.0, 30.0, 60.0, 300.0, 600.0, 1200.0, 1800.0, 3600.0, 7200.0, 14400.0, 21600.0, 28800.0 }
t_mag_labels = { 1, 5, 10, 20, 30, 1, 5, 10, 20, 30, 1, 2, 4, 6, 8 }
t_mag_formats = { "%.0fs", "%.0fs", "%.0fs", "%.0fs", "%.0fs", "%.0fm", "%.0fm", "%.0fm", "%.0fm", "%.0fm", "%.0fh", "%.0fh", "%.0fh", "%.0fh", "%.0fh" }

-- graph: {ox, oy, dx, dy, redraw_flag, v_mag_idx, i_mag_idx, t_mag_idx}
if echem_graph == nil or #echem_graph < 8 then
  echem_graph = {0, 72, 1.0, 1.0, 0, 7, 8, 3}
end

-- echem start time
echem_start_time = nil
echem_stop_time = nil
echem_wait = nil

-- echm function generator
echem_func = nil
echem_conv_data = ffi.new("struct conv_record")
echem_dbuf = nil  --  Allocated as struct conv_record[] when starting echem

--  colors for item (normal and highlighted)
item_fcolor = sc.rgb(1, 1, 1)
item_bcolor = sc.rgb(0.4, 0.4, 0)
item_fcolor_hi = sc.rgb(1, 1, 0)
item_bcolor_hi = sc.rgb(0, 0, 1)
item_bcolor_sel = sc.rgb(0.5, 0.5, 0.2)
item_fcolor_push = sc.rgb(0.9, 0.9, 1)
item_bcolor_push = sc.rgb(0.6, 0.6, 0.2)
item_frcolor = sc.rgb(0.7, 0.7, 0.7)
item_bcolor_numpad = sc.rgb(0.6, 0.6, 0.3)

item_modal_min = nil
item_modal_max = nil

action_numpad = nil

--  patterns
r = sc.rgb(1, 0, 0)
w = sc.rgb(1, 1, 1)
y = sc.rgb(1, 1, 0)
red_dot = {
0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,
0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,
0,0,0,0,0,0,0,r,r,0,0,0,0,0,0,0,
0,0,0,0,0,r,r,r,r,r,r,0,0,0,0,0,
0,0,0,0,r,r,r,r,r,r,r,r,0,0,0,0,
0,0,0,r,r,r,r,r,r,r,r,r,r,0,0,0,
0,0,0,r,r,r,r,r,r,r,r,r,r,0,0,0,
0,0,r,r,r,r,r,r,r,r,r,r,r,r,0,0,
0,0,r,r,r,r,r,r,r,r,r,r,r,r,0,0,
0,0,0,r,r,r,r,r,r,r,r,r,r,0,0,0,
0,0,0,r,r,r,r,r,r,r,r,r,r,0,0,0,
0,0,0,0,r,r,r,r,r,r,r,r,0,0,0,0,
0,0,0,0,0,r,r,r,r,r,r,0,0,0,0,0,
0,0,0,0,0,0,0,r,r,0,0,0,0,0,0,0,
0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,
0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0 }

white_cross = {
0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,
0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,
0,0,w,0,0,0,0,0,0,0,0,0,0,w,0,0,
0,0,0,w,0,0,0,0,0,0,0,0,w,0,0,0,
0,0,0,0,w,0,0,0,0,0,0,w,0,0,0,0,
0,0,0,0,0,w,0,0,0,0,w,0,0,0,0,0,
0,0,0,0,0,0,w,0,0,w,0,0,0,0,0,0,
0,0,0,0,0,0,0,w,w,0,0,0,0,0,0,0,
0,0,0,0,0,0,0,w,w,0,0,0,0,0,0,0,
0,0,0,0,0,0,w,0,0,w,0,0,0,0,0,0,
0,0,0,0,0,w,0,0,0,0,w,0,0,0,0,0,
0,0,0,0,w,0,0,0,0,0,0,w,0,0,0,0,
0,0,0,w,0,0,0,0,0,0,0,0,w,0,0,0,
0,0,w,0,0,0,0,0,0,0,0,0,0,w,0,0,
0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,
0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0 }

white_plus = {
0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,
0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,
0,0,0,0,0,0,0,0,w,0,0,0,0,0,0,0,
0,0,0,0,0,0,0,0,w,0,0,0,0,0,0,0,
0,0,0,0,0,0,0,0,w,0,0,0,0,0,0,0,
0,0,0,0,0,0,0,0,w,0,0,0,0,0,0,0,
0,0,0,0,0,0,0,0,w,0,0,0,0,0,0,0,
0,0,0,w,w,w,w,w,w,w,w,w,w,w,0,0,
0,0,0,0,0,0,0,0,w,0,0,0,0,0,0,0,
0,0,0,0,0,0,0,0,w,0,0,0,0,0,0,0,
0,0,0,0,0,0,0,0,w,0,0,0,0,0,0,0,
0,0,0,0,0,0,0,0,w,0,0,0,0,0,0,0,
0,0,0,0,0,0,0,0,w,0,0,0,0,0,0,0,
0,0,0,0,0,0,0,0,w,0,0,0,0,0,0,0,
0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,
0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0 }

white_minus = {
0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,
0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,
0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,
0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,
0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,
0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,
0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,
0,0,0,w,w,w,w,w,w,w,w,w,w,w,0,0,
0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,
0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,
0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,
0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,
0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,
0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,
0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,
0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0 }

yellow_folder = {
0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,
0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,
0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,
0,0,0,0,y,y,y,0,0,0,0,0,0,0,0,0,
0,0,0,y,y,y,y,y,0,0,0,0,0,0,0,0,
0,0,y,y,y,y,y,y,y,y,y,y,y,y,0,0,
0,0,y,y,y,y,y,y,y,y,y,y,y,y,0,0,
0,0,y,y,y,y,y,y,y,y,y,y,y,y,0,0,
0,0,y,y,y,y,y,y,y,y,y,y,y,y,0,0,
0,0,y,y,y,y,y,y,y,y,y,y,y,y,0,0,
0,0,y,y,y,y,y,y,y,y,y,y,y,y,0,0,
0,0,y,y,y,y,y,y,y,y,y,y,y,y,0,0,
0,0,y,y,y,y,y,y,y,y,y,y,y,y,0,0,
0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,
0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,
0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0 }

sc.patdef(1, 16, 16, red_dot)
sc.patdef(2, 16, 16, white_cross)
sc.patdef(3, 16, 16, white_plus)
sc.patdef(4, 16, 16, white_minus)
sc.patdef(5, 16, 16, yellow_folder)

items = {}
table.insert(items, {1, 1, 8, 224, 104, 16, "Vw [      V]", sc.rgb(1, 1, 1), sc.rgb(0, 0, 0)})
  ITEM_VW = #items
table.insert(items, {1, 1, 112, 224, 136, 16, "Iw [       mA]", sc.rgb(1, 1, 1), sc.rgb(0, 0, 0)})
  ITEM_IW = #items
table.insert(items, {1, 1, 8, 0, 168, 16, "----/--/-- --:--:--", sc.rgb(1, 1, 1), sc.rgb(0, 0, 0)})
  ITEM_DATETIME = #items
table.insert(items, {1, 1, 220, 0, 116, 16, "     -.- s", sc.rgb(1, 1, 1), sc.rgb(0, 0, 0)})
  ITEM_ECHEMTIME = #items
table.insert(items, {1, 1, 8, 168, 80, 32, "ConstPot", item_fcolor, item_bcolor_sel, item_frcolor})
  ITEM_CONPOT = #items
table.insert(items, {1, 1, 8, 124, 80, 32, "CV", item_fcolor, item_bcolor, item_frcolor})
  ITEM_CV = #items
table.insert(items, {1, 1, 8, 80, 80, 32, "Calib.", item_fcolor, item_bcolor, item_frcolor})
  ITEM_CALIB = #items
table.insert(items, {1, 1, 8, 36, 80, 32, "Shutdown", item_fcolor, item_bcolor, item_frcolor})
  ITEM_SHUTDOWN = #items
table.insert(items, {1, 0, 89, 24, 223, 192, "", 0, item_bcolor_sel, item_frcolor})
  ITEM_TAB = #items

table.insert(items, {0, 0, 90, 192, 222, 24, "Const. Pot. Electrolysis", item_fcolor, item_bcolor_sel, 0})
  ITEM_CONPOT_MSG = #items
  ITEM_CONPOT_FIRST = #items
table.insert(items, {0, 0, 106, 163, 48, 24, "Vw", item_fcolor, item_bcolor_sel, 0})
  ITEM_CONPOT_VWLABEL = #items
table.insert(items, {0, 1, 160, 160, 96, 30, "-0.000 V", item_fcolor, item_bcolor, item_frcolor})
  ITEM_CONPOT_VW = #items
table.insert(items, {0, 1, 260, 160, 36, 30, "Set", item_fcolor_push, item_bcolor_push, item_frcolor})
  ITEM_CONPOT_VWSET = #items
table.insert(items, {0, 0, 106, 130, 48, 24, "Interval", item_color, item_bcolor_sel, 0})
  ITEM_CONPOT_INTLABEL = #items
table.insert(items, {0, 1, 160, 127, 96, 30, "1.0 s", item_fcolor, item_bcolor, item_frcolor})
  ITEM_CONPOT_INT = #items
table.insert(items, {0, 0, 106, 97, 48, 24, "Time", item_color, item_bcolor_sel, 0})
  ITEM_CONPOT_TIMELABEL = #items
table.insert(items, {0, 1, 160, 94, 96, 30, "3600 s", item_fcolor, item_bcolor, item_frcolor})
  ITEM_CONPOT_TIME = #items
table.insert(items, {0, 0, 106, 64, 48, 24, "Rest Vw", item_color, item_bcolor_sel, 0})
  ITEM_CONPOT_RESTLABEL = #items
table.insert(items, {0, 1, 160, 61, 96, 30, "-0.000 V", item_fcolor, item_bcolor, item_frcolor})
  ITEM_CONPOT_REST = #items
table.insert(items, {0, 1, 260, 61, 36, 30, "Set", item_fcolor_push, item_bcolor_push, item_frcolor})
  ITEM_CONPOT_RESTSET = #items
table.insert(items, {0, 1, 166, 28, 70, 30, "Start", item_fcolor, item_bcolor, item_frcolor})
  ITEM_CONPOT_START = #items
  ITEM_CONPOT_LAST = #items

table.insert(items, {0, 1, 106, 166, 191, 32, "Zero Adjust", item_fcolor, item_bcolor, item_frcolor})
  ITEM_CALIB_ZEROADJ = #items
  ITEM_CALIB_FIRST = #items
table.insert(items, {0, 1, 106, 124, 191, 32, "Scale Tuning", item_fcolor, item_bcolor, item_frcolor})
  ITEM_CALIB_SCALE = #items
table.insert(items, {0, 1, 106, 82, 191, 32, "Date & Time", item_fcolor, item_bcolor, item_frcolor})
  ITEM_CALIB_DATETIME = #items
table.insert(items, {0, 1, 106, 40, 191, 32, "Software Update", item_fcolor, item_bcolor, item_frcolor})
  ITEM_CALIB_UPDATE = #items
  ITEM_CALIB_LAST = #items

table.insert(items, {0, 1, 90, 162, 222, 24, "Please adjust zero position", item_fcolor, item_bcolor_sel, 0})
  ITEM_ZEROADJ_MSG = #items
  ITEM_ZEROADJ_FIRST = #items
table.insert(items, {0, 1, 106, 98, 191, 32, "Done", item_fcolor, item_bcolor, item_frcolor})
  ITEM_ZEROADJ_OK = #items
  ITEM_ZEROADJ_LAST = #items

table.insert(items, {0, 0, 90, 190, 222, 24, "Set range dial to 'x10',", item_fcolor, item_bcolor_sel, 0})
  ITEM_SCALE_MSG = #items
  ITEM_SCALE_FIRST = #items
table.insert(items, {0, 0, 90, 162, 222, 24, "and enter actual Vw.", item_fcolor, item_bcolor_sel, 0})
  ITEM_SCALE_MSG1 = #items
table.insert(items, {0, 0, 106, 120, 32, 24, "Vw", item_fcolor, item_bcolor_sel, 0})
  ITEM_SCALE_VWLABEL = #items
table.insert(items, {0, 1, 154, 116, 96, 32, "-0.000 V", item_fcolor, item_bcolor, item_frcolor})
  ITEM_SCALE_VW = #items
table.insert(items, {0, 1, 115, 36, 60, 32, "Cancel", item_fcolor, item_bcolor, item_frcolor})
  ITEM_SCALE_CANCEL = #items
table.insert(items, {0, 1, 225, 36, 60, 32, "OK", item_fcolor, item_bcolor, item_frcolor})
  ITEM_SCALE_OK = #items
  ITEM_SCALE_LAST = #items

table.insert(items, {0, 1, 106, 162, 191, 32, "Power Off", item_fcolor, item_bcolor, item_frcolor})
  ITEM_SHUTDOWN_POWEROFF = #items
  ITEM_SHUTDOWN_FIRST = #items
table.insert(items, {0, 1, 106, 98, 191, 32, "Reboot", item_fcolor, item_bcolor, item_frcolor})
  ITEM_SHUTDOWN_REBOOT = #items
  ITEM_SHUTDOWN_LAST = #items

table.insert(items, {0, 0, 12, 24, 300, 192, "", 0, item_bcolor_sel, item_frcolor})
  ITEM_CV_TAB = #items
  ITEM_CV_FIRST = #items
table.insert(items, {0, 0, 14, 190, 296, 24, "Cyclic Voltammetry", item_fcolor, item_bcolor_sel, 0})
  ITEM_CV_MSG = #items
table.insert(items, {0, 0, 16, 163, 54, 24, "Initial", item_fcolor, item_bcolor_sel, 0})
  ITEM_CV_INITIALLABEL = #items
table.insert(items, {0, 1, 74, 160, 78, 30, " 0.000 V", item_fcolor, item_bcolor, item_frcolor})
  ITEM_CV_INITIAL = #items
table.insert(items, {0, 0, 16, 130, 54, 24, "High", item_color, item_bcolor_sel, 0})
  ITEM_CV_HIGHLABEL = #items
table.insert(items, {0, 1, 74, 127, 78, 30, " 1.000 V", item_fcolor, item_bcolor, item_frcolor})
  ITEM_CV_HIGH = #items
table.insert(items, {0, 0, 16, 97, 54, 24, "Low", item_color, item_bcolor_sel, 0})
  ITEM_CV_LOWLABEL = #items
table.insert(items, {0, 1, 74, 94, 78, 30, "-1.000 V", item_fcolor, item_bcolor, item_frcolor})
  ITEM_CV_LOW = #items
table.insert(items, {0, 0, 168, 163, 54, 24, "Polarity", item_fcolor, item_bcolor_sel, 0})
  ITEM_CV_POLARITYLABEL = #items
table.insert(items, {0, 1, 226, 160, 37, 30, "Pos", item_fcolor_push, item_bcolor_push, item_frcolor})
  ITEM_CV_POL_POS = #items
table.insert(items, {0, 1, 267, 160, 37, 30, "Neg", item_fcolor, item_bcolor, item_frcolor})
  ITEM_CV_POL_NEG = #items
table.insert(items, {0, 0, 168, 130, 54, 24, "Speed", item_color, item_bcolor_sel, 0})
  ITEM_CV_SPEEDLABEL = #items
table.insert(items, {0, 1, 226, 127, 78, 30, "1000mV/s", item_fcolor, item_bcolor, item_frcolor})
  ITEM_CV_SPEED = #items
table.insert(items, {0, 0, 168, 97, 54, 24, "Scans", item_color, item_bcolor_sel, 0})
  ITEM_CV_SCANSLABEL = #items
table.insert(items, {0, 1, 226, 94, 78, 30, "2", item_fcolor, item_bcolor, item_frcolor})
  ITEM_CV_SCANS = #items
table.insert(items, {0, 0, 168, 64, 54, 24, "Wait", item_color, item_bcolor_sel, 0})
  ITEM_CV_WAITLABEL = #items
table.insert(items, {0, 1, 226, 61, 78, 30, "2.0 s", item_fcolor, item_bcolor, item_frcolor})
  ITEM_CV_WAIT = #items
table.insert(items, {0, 1, 27, 28, 100, 30, "Set Initial", item_fcolor, item_bcolor, item_frcolor})
  ITEM_CV_SETINITIAL = #items
table.insert(items, {0, 1, 152, 28, 60, 30, "Start", item_fcolor, item_bcolor, item_frcolor})
  ITEM_CV_START = #items
table.insert(items, {0, 1, 237, 28, 60, 30, "Close", item_fcolor, item_bcolor, item_frcolor})
  ITEM_CV_CLOSE = #items
  ITEM_CV_LAST = #items

table.insert(items, {0, 0, 12, 24, 300, 192, "", 0, item_bcolor_sel, item_frcolor})
  ITEM_DATETIME_TAB = #items
  ITEM_DATETIME_FIRST = #items
table.insert(items, {0, 0, 14, 190, 296, 24, "Date & Time", item_fcolor, item_bcolor_sel, 0})
  ITEM_DATETIME_MSG = #items
table.insert(items, {0, 0, 16, 160, 54, 24, "Date", item_fcolor, item_bcolor_sel, 0})
  ITEM_DATETIME_DATELABEL = #items
table.insert(items, {0, 0, 16, 120, 54, 24, "Time", item_color, item_bcolor_sel, 0})
  ITEM_DATETIME_TIMELABEL = #items
table.insert(items, {0, 1, 74, 156, 78, 32, "2017", item_fcolor, item_bcolor, item_frcolor})
  ITEM_DATETIME_YEAR = #items
table.insert(items, {0, 1, 168, 156, 54, 32, "1", item_fcolor, item_bcolor, item_frcolor})
  ITEM_DATETIME_MONTH = #items
table.insert(items, {0, 1, 238, 156, 54, 32, "1", item_fcolor, item_bcolor, item_frcolor})
  ITEM_DATETIME_DAY = #items
table.insert(items, {0, 1, 74, 116, 54, 32, "22", item_fcolor, item_bcolor, item_frcolor})
  ITEM_DATETIME_HOUR = #items
table.insert(items, {0, 1, 144, 116, 54, 32, "00", item_color, item_bcolor, item_frcolor})
  ITEM_DATETIME_MIN = #items
table.insert(items, {0, 1, 214, 116, 54, 32, "00", item_fcolor, item_bcolor, item_frcolor})
  ITEM_DATETIME_SEC = #items
table.insert(items, {0, 1, 57, 36, 60, 32, "Set", item_fcolor, item_bcolor, item_frcolor})
  ITEM_DATETIME_SET = #items
table.insert(items, {0, 1, 207, 36, 60, 32, "Cancel", item_fcolor, item_bcolor, item_frcolor})
  ITEM_DATETIME_CANCEL = #items
  ITEM_DATETIME_LAST = #items

  ITEM_TABITEMS_FIRST = ITEM_CONPOT_FIRST
  ITEM_TABITEMS_LAST = ITEM_DATETIME_LAST

table.insert(items, {0, 0, 10, 38, 300, 142, "", 0, item_bcolor_numpad, item_frcolor})
  ITEM_NUMPAD = #items
table.insert(items, {0, 0, 25, 137, 115, 31, "", item_fcolor, item_bcolor_numpad, 0})
  ITEM_NUMPAD_MSG = #items
table.insert(items, {0, 0, 145, 137, 115, 31, "-0.000       ", item_fcolor, sc.rgb(0, 0, 0), item_frcolor})
  ITEM_NUMPAD_VALUE = #items
table.insert(items, {0, 1, 25, 88, 35, 35, "-", item_fcolor, item_bcolor, item_frcolor})
  ITEM_NUMPAD_MINUS = #items
table.insert(items, {0, 1, 25, 48, 35, 35, ".", item_fcolor, item_bcolor, item_frcolor})
  ITEM_NUMPAD_DOT = #items
table.insert(items, {0, 1, 265, 88, 35, 35, "Del", item_fcolor, item_bcolor, item_frcolor})
  ITEM_NUMPAD_DEL = #items
table.insert(items, {0, 1, 265, 48, 35, 35, "Ent", item_fcolor, item_bcolor, item_frcolor})
  ITEM_NUMPAD_ENT = #items
ITEM_NUMPAD_0 = #items + 1
for i = 0, 9 do
  table.insert(items, {0, 1, (i % 5) * 40 + 65, (1 - math.floor(i / 5)) * 40 + 48, 35, 35, tostring(i), item_fcolor, item_bcolor, item_frcolor})
end
table.insert(items, {0, 1, 265, 135, 35, 35, "Can", item_fcolor, item_bcolor, item_frcolor})
  ITEM_NUMPAD_CANCEL = #items

table.insert(items, {0, 0, 8, 24, 304, 192, "", 0, item_bcolor_numpad, item_frcolor})
  ITEM_GRAPH = #items
table.insert(items, {0, 1, 8, 144, 24, 24, {16, 16, 3}, 0, item_bcolor, item_frcolor})
  ITEM_GRAPH_PLUS = #items
table.insert(items, {0, 1, 8, 96, 24, 24, {16, 16, 4}, 0, item_bcolor, item_frcolor})
  ITEM_GRAPH_MINUS = #items
table.insert(items, {0, 0, 248, 192, 24, 24, {16, 16, 5}, 0, item_bcolor, item_frcolor})
  ITEM_GRAPH_SAVE = #items
table.insert(items, {0, 1, 288, 192, 24, 24, {16, 16, 1}, 0, item_bcolor, item_frcolor})
  ITEM_GRAPH_STOP = #items

table.insert(items, {0, 0, 30, 38, 260, 142, "", 0, item_bcolor_numpad, item_frcolor})
  ITEM_DIALOG = #items
table.insert(items, {0, 0, 35, 137, 250, 31, "", item_fcolor, item_bcolor_numpad, 0})
  ITEM_DIALOG_MSG = #items
table.insert(items, {0, 0, 35, 105, 250, 31, "", item_fcolor, item_bcolor_numpad, 0})
  ITEM_DIALOG_MSG2 = #items
table.insert(items, {0, 1, 125, 48, 60, 32, "OK", item_fcolor, item_bcolor, item_frcolor})
  ITEM_DIALOG_OK = #items
table.insert(items, {0, 1, 57, 48, 60, 32, "OK", item_fcolor, item_bcolor, item_frcolor})
  ITEM_DIALOG_OK2 = #items
table.insert(items, {0, 1, 207, 48, 60, 32, "Cancel", item_fcolor, item_bcolor, item_frcolor})
  ITEM_DIALOG_CANCEL = #items
  ITEM_DIALOG_END = #items

selected_tab = ITEM_CONPOT
numpad_value = ""

function voltage_to_raw(vol)
  if vol == nil then return -1 end
  local vn = vol * 1000.0 / calib[3] + volw_zero
  if vn < 0 then
    vn = 0
  elseif vn > 4095 then
    vn = 4095
  else
    vn = math.floor(vn + 0.5)
  end
  return vn
end

function voltage_from_raw(vn)
  return (vn - volw_zero) * calib[3] / 1000.0
end

function current_from_raw(vn)
  return (vn - calib[1]) * calib[4] / 1000.0
end

function output_voltage(v)
  echemsub.conv_direct_write(voltage_to_raw(v))
end

function read_voltage(av)
  do return end
  local a, v2, v3, v2sum, v3sum, n, nn
  a = {}
  v2sum = 0
  v3sum = 0
  nn = av or 1
  for n = 1, nn do
    a[1] = 0x06
    a[2] = 0x00
    a[3] = 0
    spi.readwrite(12, a, 3)
    v3 = bit.band(a[2], 0x0f) * 256 + bit.band(a[3], 0xff)
    v3sum = v3sum + v3
  end
  curw_raw = (v3sum / (nn + 0.0))
  curw = (curw_raw - calib[1]) * calib[4] / 1000.0
  vold = 0.0
  vold_raw = 0.0
  volw = (volw_raw - volw_zero) * calib[3] / 1000.0
  return curw_raw, vold_raw
end

function sense_tp()
  local x, y, pres, i, box, imin, imax
  x, y, pres = ts.read()
  if x then
    y = sc.height - y
    imin = item_modal_min or 1
    imax = item_modal_max or #items
    for i = imax, imin, -1 do
      local it = items[i]
      if it[1] > 0 and it[2] > 0 then
        if x >= it[3] and y >= it[4] and x < it[3] + it[5] and y < it[4] + it[6] then
          return i, pres
        end
      end
    end
    return -1, pres
  else
    return nil
  end
end

function show_menu_item(tbl, j, selected)
  local ix, iy, b
  sc.tcolor(rgb(0, 1, 1))
  sc.color(rgb(1, 1, 1))
  if selected then
    sc.fillcolor(rgb(0, 0, 0.8))
  else
    sc.fillcolor(rgb(0.3, 0.3, 0.1))
  end
  ix = (j - 1) % 2
  iy = (j - 1) / 2
  sc.gputs(8 * (4 + 17 * ix), 200 - 16 * (3 + 2 * jy), tbl[j])
  b = {28 + 136 * ix, 174 - 32 * iy, 96, 24}
  sc.box(b[1], b[2], b[3], b[4])
  return b
end

function show_dialog(msg, msg2, cancelable)
  local i, item_modal_min_save, item_modal_max_save, msg_save, msg2_save, items_save, res
  msg_save = items[ITEM_DIALOG_MSG][7]
  msg2_save = items[ITEM_DIALOG_MSG2][7]
  items[ITEM_DIALOG_MSG][7] = msg
  if not msg2 then msg2 = "" end
  items[ITEM_DIALOG_MSG2][7] = msg2
  items_save = {}
  for i = ITEM_DIALOG, ITEM_DIALOG_END do
    items_save[i] = items[i][1]
    items[i][1] = 1
  end
  if cancelable then
    items[ITEM_DIALOG_OK][1] = 0
  else
    items[ITEM_DIALOG_OK2][1] = 0
    items[ITEM_DIALOG_CANCEL][1] = 0
  end
  item_modal_min_save = item_modal_min
  item_modal_max_save = item_modal_max
  item_modal_min = ITEM_DIALOG + 1
  item_modal_max = ITEM_DIALOG_END
  show_all_items(true)
  while true do
    res = event_loop()
    if res then break end
  end
  item_modal_min = item_modal_min_save
  item_modal_max = item_modal_max_save
  for i = ITEM_DIALOG, ITEM_DIALOG_END do
    items[i][1] = items_save[i]
  end
  items[ITEM_DIALOG_MSG][7] = msg_save
  items[ITEM_DIALOG_MSG2][7] = msg2_save
  show_all_items(true)
  return res
end

function show_numpad(msg, val)
  local i, item_modal_min_save, item_modal_max_save, res
  msg = msg or ""
  items[ITEM_NUMPAD_MSG][7] = string.sub("             " .. msg, -13)
  items[ITEM_NUMPAD_VALUE][7] = string.sub(val .. "_" .. "              ", 1, 13)
  numpad_value = val
  for i = ITEM_NUMPAD, ITEM_NUMPAD_CANCEL do
    items[i][1] = 1
  end
  item_modal_min_save = item_modal_min
  item_modal_max_save = item_modal_max
  item_modal_min = ITEM_NUMPAD + 1
  item_modal_max = ITEM_NUMPAD_CANCEL
  show_all_items(true)
  while true do
    res = event_loop()
    if res then break end
  end
  item_modal_min = item_modal_min_save
  item_modal_max = item_modal_max_save
  for i = ITEM_NUMPAD, ITEM_NUMPAD_CANCEL do
    items[i][1] = 0
  end
  show_all_items(true)
  if res == "ENT" then
    if numpad_value == "" then
      return nil
    end
    return numpad_value + 0.0
  else
    return nil
  end
end

function hide_numpad()
  local i
  for i = ITEM_NUMPAD, ITEM_NUMPAD_CANCEL do
    items[i][1] = 0
  end
  item_modal_min = nil
  item_modal_max = nil
  show_all_items(true)
end

function show_graph()
  local i
  for i = ITEM_GRAPH, ITEM_GRAPH_STOP do
    items[i][1] = 1
  end
  item_modal_min = ITEM_GRAPH + 1
  item_modal_max = ITEM_GRAPH_STOP
  show_all_items(true)
  draw_graph(true)
end

function hide_graph()
  local i
  for i = ITEM_GRAPH, ITEM_GRAPH_STOP do
    items[i][1] = 0
  end
  item_modal_min = nil
  item_modal_max = nil
  show_all_items(true)
end

value_pressed = 0
tb1 = { { 0, 208, 56, 32 }, { 88, 208, 56, 32 }, { 224, 0, 80, 32 } }

function update_values()
  cur_raw = echemsub.conv_direct_read()
  vol_raw = echemsub.conv_last_output()
  cur = current_from_raw(cur_raw)
  vol = voltage_from_raw(vol_raw)
  set_item_value(ITEM_VW, string.format("Vw [%6.3fV]", vol))
  set_item_value(ITEM_IW, string.format("Iw [%7.3fmA]", cur))
  set_item_value(ITEM_DATETIME, os.date("%Y/%m/%d %H:%M:%S"))
  if echem_setup[1] == 1 then
    set_item_value(ITEM_ECHEMTIME, string.format("%8.1f s", util.now() - echem_start_time - echem_wait))
  elseif echem_setup[1] == 2 then
    set_item_value(ITEM_ECHEMTIME, string.format("%8.1f s", echem_stop_time - echem_start_time - echem_wait))
  else
    set_item_value(ITEM_ECHEMTIME, "     -.- s")
  end
  show_all_items()
end

function show_item(i)
  local it
  if i < 1 then
    return
  end
  it = items[i]
  if it[1] > 0 then
    local fcolor, bcolor, frame
    fcolor = it[8] or sc.rgb(1, 1, 1)
    bcolor = it[9] or sc.rgb(0, 0, 0)
    frame = it[10]
    sc.color(frame)
    sc.fillcolor(bcolor)
    sc.rbox(it[3], it[4], it[5], it[6], 4)
    if it[7] then
      local x, y, wid
      if type(it[7]) == "string" then
        --  Draw string
        wid = #it[7] * 8  --  May be wrong
        y = it[4] + (it[6] - 16) / 2
        x = it[3] + (it[5] - wid) / 2
        sc.tcolor(fcolor, bcolor)
        sc.gputs(x, y, it[7])
      elseif type(it[7]) == "table" then
        local mask
        if it[2] > 0 then
          mask = sc.rgb(1, 1, 1)
        else
          mask = sc.rgb(0.5, 0.5, 0.5)
        end
        y = it[4] + (it[6] - it[7][2]) / 2
        x = it[3] + (it[5] - it[7][1]) / 2
        sc.patdraw(it[7][3], x, y, mask)
      end
    end
  end
end

function set_item_value(i, val)
  local it
  it = items[i]
  if it then
    it[7] = val
    it[11] = true
  end
end

function show_all_items(force)
  local i
  if force then
    sc.cls()
  end
  for i = 1, #items do
    if force or items[i][11] then
      show_item(i)
      items[i][11] = nil
    end
  end
  sc.flush()
end

need_draw_axis = nil

function set_need_draw_axis()
  for idx = ITEM_GRAPH, ITEM_GRAPH_STOP do
    items[idx][11] = 1
  end
  need_draw_axis = true
  echem_graph[9] = 0
end

function select_tab(idx)
  local i, imin, imax
  for i = ITEM_TABITEMS_FIRST, ITEM_TABITEMS_LAST do
    items[i][1] = 0
  end
  if idx == ITEM_CONPOT then
    imin = ITEM_CONPOT_FIRST
    imax = ITEM_CONPOT_LAST
  elseif idx == ITEM_CV then
    imin = ITEM_CV_FIRST
    imax = ITEM_CV_LAST
  elseif idx == ITEM_CALIB then
    imin = ITEM_CALIB_FIRST
    imax = ITEM_CALIB_LAST
  elseif idx == -1 then
    -- Zero adjust subscreen
    imin = ITEM_ZEROADJ_FIRST
    imax = ITEM_ZEROADJ_LAST
  elseif idx == -2 then
    -- Scale Tuning subscreen
    imin = ITEM_SCALE_FIRST
    imax = ITEM_SCALE_LAST
  elseif idx == -3 then
    -- Date & Time subscreen
    imin = ITEM_DATETIME_FIRST
    imax = ITEM_DATETIME_LAST
  elseif idx == ITEM_SHUTDOWN then
    imin = ITEM_SHUTDOWN_FIRST
    imax = ITEM_SHUTDOWN_LAST
  else
    imin = nil
    imax = nil
  end
  if imin and imax then
    for i = imin, imax do
      items[i][1] = 1
    end
  end
  items[ITEM_CONPOT][9] = item_bcolor
  items[ITEM_CALIB][9] = item_bcolor
  items[ITEM_CV][9] = item_bcolor
  items[ITEM_SHUTDOWN][9] = item_bcolor
  if idx and idx >= 1 then
    items[idx][9] = item_bcolor_sel
  end
  show_all_items(true)
  selected_tab = idx
end

function do_action_numpad(idx)
  local ch
  ch = nil
  if idx >= ITEM_NUMPAD_0 and idx <= ITEM_NUMPAD_0 + 9 then
    ch = tostring(idx - ITEM_NUMPAD_0)
  elseif idx == ITEM_NUMPAD_MINUS then
    if numpad_value == "" then
      ch = "-"
    end
  elseif idx == ITEM_NUMPAD_DOT then
    if string.find(numpad_value, "^-?%d+$") then
      ch = "."
    end
  elseif idx == ITEM_NUMPAD_DEL then
    numpad_value = string.sub(numpad_value, 1, -2)
    ch = false  --  Dummy value
  elseif idx == ITEM_NUMPAD_ENT then
    hide_numpad()
    return "ENT"
  elseif idx == ITEM_NUMPAD_CANCEL then
    hide_numpad()
    return "CAN"
  end
  if ch ~= nil then
    if ch and #numpad_value < 13 then
      numpad_value = numpad_value .. ch
    end
    items[ITEM_NUMPAD_VALUE][7] = string.sub(numpad_value .. "             ", 1, 13)
    show_item(ITEM_NUMPAD_VALUE)
  end
  return nil
end

function set_pushbuttons(idx, idx_table)
  local i, j
  for i = 1, #idx_table do
    j = idx_table[i]
    if j == idx then
      items[j][8] = item_fcolor_push
      items[j][9] = item_bcolor_push
    else
      items[j][8] = item_fcolor
      items[j][9] = item_bcolor
    end
    items[j][11] = 1
  end
end

function echem_queue()
  if echemsub.conv_queue(echem_conv_data) < 0 then return -1 end
  echem_send_idx = echem_send_idx + 1
  return 0
end

function echem_receive()
  if echemsub.conv_read(echem_conv_data) < 0 then return -1 end
  echem_receive_idx = echem_receive_idx + 1
  return 0
end

function start_echem()
  local pot, stamp
  echem_send_idx = 0
  echem_receive_idx = 0

  --  Set initial potential and reset ring buffer
  pot = echem_func(-1)
  echemsub.conv_direct_write(voltage_to_raw(pot))
  echemsub.conv_reset()

  --  Allocate data receive buffer
  echem_dbuf = ffi.new("struct conv_record[?]", echem_setup[6] + 1)
  
  --  Queue events (as many as possible)
  while echem_send_idx < echem_setup[6] do
    pot, stamp = echem_func(echem_send_idx)
    echem_conv_data.stamp = stamp + echem_wait
    echem_conv_data.outdata = voltage_to_raw(pot)
    if echem_queue() < 0 then break end
  end
  
  --  Start scanning
  echem_start_time = util.now()
  echem_setup[1] = 1  --  Start echem
  echemsub.conv_start()
end

function handle_echem()
  local count = 0
  --  Receive events (as many as possible)
  while true do
    if echem_receive() < 0 then break end
    echem_dbuf[echem_receive_idx - 1] = echem_conv_data
    count = count + 1
  end
  if count > 0 then echem_graph[5] = 1 end
  if echem_receive_idx >= echem_setup[6] then
    stop_echem()
    return
  end
  --  Queue events (as many as possible)
  while true do
    if echem_send_idx >= echem_setup[6] then break end
    local pot, stamp = echem_func(echem_send_idx)
    echem_conv_data.stamp = stamp + echem_wait
    echem_conv_data.outdata = voltage_to_raw(pot)
    if echem_queue() < 0 then break end
  end
end

function stop_echem()
  echemsub.conv_stop()
  echem_stop_time = util.now()
  echem_setup[1] = 2
  local pot = echem_func(-2)
  if pot then
    echemsub.conv_direct_write(voltage_to_raw(pot))
  end
  items[ITEM_GRAPH_STOP][8] = item_fcolor
  items[ITEM_GRAPH_STOP][7] = {16, 16, 2}
  items[ITEM_GRAPH_SAVE][2] = 1
  show_item(ITEM_GRAPH_STOP)
  show_item(ITEM_GRAPH_SAVE)
end

function mount_usbmem()
  local f, res
  f, res = os.execute("ls /dev/sda1 >/dev/null 2>&1")
  if f ~= 0 then
    return "USB memory is not found."
  end
  f, res = os.execute("(mount | grep '/media/usbmem' >/dev/null 2>&1) || (mkdir -p /media/usbmem && sudo mount /dev/sda1 /media/usbmem -o uid=pi,gid=pi >/dev/null 2>&1)")
  if f ~= 0 then
    return "Cannot mount USB memory."
  end
  return nil
end

function unmount_usbmem()
  local f, res
  f, res = os.execute("sudo umount /media/usbmem")
  if f == nil then
    return "Cannot unmount USB memory."
  end
  return nil
end

function update_software()
  local i, f, res, mes, names
  mes = mount_usbmem()
  if mes ~= nil then goto error1 end
  names = { "echem.lua", "echemsub.c", "ljsc" }
  for i = 1, 3 do
    f, res = os.execute("ls /media/usbmem/echem/" .. names[i] .. " >/dev/null")
    if f ~= 0 then
      mes = "echem/" .. names[i] .. " is not found."
      goto error2
    end
  end
  for i = 1, 3 do
    f, res = os.execute("rm -rf " .. names[i] .. ".orig && mv -f " .. names[i] .. " " .. names[i] .. ".orig")
    if f ~= 0 then
      mes = "Cannot make backup of " .. names[i] .. "."
      goto error2
    end
    f, res = os.execute("cp -a /media/usbmem/echem/" .. names[i] .. " .")
    if f ~= 0 then
      mes = "Cannot copy " .. names[i]
      os.execute("mv -f " .. names[i] .. ".orig " .. names[i])
      goto error2
    end
  end
  unmount_usbmem()
  do_action(ITEM_SHUTDOWN_REBOOT)  -- no return
::error2::
  unmount_usbmem()
::error1::
  show_dialog(mes, "")
end

function do_action(idx)
  local val
  if idx == ITEM_CONPOT then
    set_item_value(ITEM_CONPOT_VW, string.format("%6.3f V", electrolysis_settings[1]))
    set_item_value(ITEM_CONPOT_INT, string.format("%.1f s", electrolysis_settings[2]))
    set_item_value(ITEM_CONPOT_TIME, string.format("%.0f s", electrolysis_settings[3]))
    set_item_value(ITEM_CONPOT_REST, string.format("%6.3f V", electrolysis_settings[4]))
    select_tab(idx)
  elseif idx == ITEM_CV then
    set_item_value(ITEM_CV_INITIAL, string.format("%6.3f V", cv_settings[1]))
    set_item_value(ITEM_CV_HIGH, string.format("%6.3f V", cv_settings[2]))
    set_item_value(ITEM_CV_LOW, string.format("%6.3f V", cv_settings[3]))
    if cv_settings[4] == 0 then
      set_pushbuttons(ITEM_CV_POL_POS, {ITEM_CV_POL_POS, ITEM_CV_POL_NEG})
    else
      set_pushbuttons(ITEM_CV_POL_NEG, {ITEM_CV_POL_POS, ITEM_CV_POL_NEG})
    end
    set_item_value(ITEM_CV_SPEED, string.format("%.0fmV/s", cv_settings[5]))
    set_item_value(ITEM_CV_SCANS, string.format("%d", cv_settings[6]))
    set_item_value(ITEM_CV_WAIT, string.format("%.1f s", cv_settings[7]))
    output_voltage(cv_settings[1])
    select_tab(idx)
  elseif idx == ITEM_CALIB then
    select_tab(idx)
  elseif idx == ITEM_SHUTDOWN then
    select_tab(idx)
  elseif idx == ITEM_CONPOT_VW then
    val = show_numpad("Vw value:", "")
    if val then
      electrolysis_settings[1] = val
      set_item_value(ITEM_CONPOT_VW, string.format("%6.3f V", val))
      write_settings()
    end
  elseif idx == ITEM_CONPOT_INT then
    val = show_numpad("Interval:", "")
    if val then
      electrolysis_settings[2] = val
      set_item_value(ITEM_CONPOT_INT, string.format("%.1f s", val))
      write_settings()
    end
  elseif idx == ITEM_CONPOT_TIME then
    val = show_numpad("Time:", "")
    if val then
      electrolysis_settings[3] = val
      set_item_value(ITEM_CONPOT_TIME, string.format("%.0f s", val))
      write_settings()
    end
  elseif idx == ITEM_CONPOT_REST then
    val = show_numpad("Rest Vw:", "")
    if val then
      electrolysis_settings[4] = val
      set_item_value(ITEM_CONPOT_REST, string.format("%6.3f V", val))
      write_settings()
    end
  elseif idx == ITEM_CONPOT_VWSET then
    output_voltage(electrolysis_settings[1])
    items[idx][8] = item_fcolor_push
    items[idx][9] = item_bcolor_push
    show_item(idx)
  elseif idx == ITEM_CONPOT_RESTSET then
    output_voltage(electrolysis_settings[4])
    items[idx][8] = item_fcolor_push
    items[idx][9] = item_bcolor_push
    show_item(idx)
  elseif idx == ITEM_CONPOT_START then
    output_voltage(electrolysis_settings[1])
    if echem_setup[5] == nil or echem_setup[5] <= 0 then
      echem_setup[5] = 1
    end
    echem_graph[1] = 0
    if electrolysis_settings[1] >= 0.0 then
      echem_graph[2] = 24
    else
      echem_graph[2] = 120
    end
    echem_graph[9] = 0
    echem_graph[7] = 7
    echem_setup[5] = electrolysis_settings[2]  --  Sampling interval (in seconds)
    if echem_setup[5] < 0.05 then
      echem_setup[5] = 0.05  -- minimum 50 ms
    end
    echem_setup[6] = math.floor(electrolysis_settings[3] / echem_setup[5]) + 1 -- Total steps
    -- Function generator
    echem_func = function (n)
      if n == -1 then return electrolysis_settings[1] end  -- initial potential
      if n == -2 then return electrolysis_settings[4] end  -- stop potential
      return nil, echem_setup[5] * n  -- potential, timestamp
    end
    echem_graph[3] = 24.0 / t_mag[echem_graph[8]] * (echem_setup[5] / 1000.0)
    echem_graph[4] = 24.0 / 1000.0 / i_mag[echem_graph[7]]
    echem_setup[4] = 0  --  Number of valid data
    echem_setup[3] = util.now()
    echem_setup[2] = 1  --  Constant potential electrolysis
    echem_wait = 0.0
    items[ITEM_GRAPH_SAVE][2] = 0
    start_echem()
    show_graph()
  elseif idx == ITEM_CV_INITIAL then
    val = show_numpad("Initial V:", "")
    if val then
      cv_settings[1] = val
      set_item_value(ITEM_CV_INITIAL, string.format("%6.3f V", val))
      write_settings()
    end
  elseif idx == ITEM_CV_HIGH then
    val = show_numpad("High V:", "")
    if val then
      cv_settings[2] = val
      set_item_value(ITEM_CV_HIGH, string.format("%6.3f V", val))
      write_settings()
    end
  elseif idx == ITEM_CV_LOW then
    val = show_numpad("Low V:", "")
    if val then
      cv_settings[3] = val
      set_item_value(ITEM_CV_LOW, string.format("%6.3f V", val))
      write_settings()
    end
  elseif idx == ITEM_CV_POL_POS then
    cv_settings[4] = 0
    set_pushbuttons(ITEM_CV_POL_POS, {ITEM_CV_POL_POS, ITEM_CV_POL_NEG})
  elseif idx == ITEM_CV_POL_NEG then
    cv_settings[4] = 1
    set_pushbuttons(ITEM_CV_POL_NEG, {ITEM_CV_POL_POS, ITEM_CV_POL_NEG})
  elseif idx == ITEM_CV_SPEED then
    val = show_numpad("Speed:", "")
    if val then
      cv_settings[5] = val
      set_item_value(ITEM_CV_SPEED, string.format("%.0fmV/s", val))
      write_settings()
    end
  elseif idx == ITEM_CV_SCANS then
    val = show_numpad("Scans:", "")
    if val then
      cv_settings[6] = math.floor(val + 0.5)
      set_item_value(ITEM_CV_SCANS, string.format("%d", cv_settings[6]))
      write_settings()
    end
  elseif idx == ITEM_CV_WAIT then
    val = show_numpad("Wait:", "")
    if val then
      cv_settings[7] = val
      set_item_value(ITEM_CV_WAIT, string.format("%.1f s", cv_settings[7]))
      write_settings()
    end
  elseif idx == ITEM_CV_SETINITIAL then
    output_voltage(cv_settings[1])
  elseif idx == ITEM_CV_START then
    if cv_settings[2] <= cv_settings[3] then
      show_dialog("The potentials should be", "High > Low")
      return nil
    elseif cv_settings[1] > cv_settings[2] or cv_settings[1] < cv_settings[3] then
      show_dialog("The potentials should be", "High >= Initial >= Low")
      return nil
    end
    output_voltage(cv_settings[1])
    --  Vertical scale and origin: scale is the same as the previous experiment
    echem_graph[2] = 24*3  --  origin
    --  Horizontal scale and origin
    local vmax = cv_settings[2]
    local vmin = cv_settings[3]
    if vmax < 0.0 then vmax = 0.0 end  --  The V=0 line should be in the screen
    if vmin > 0.0 then vmin = 0.0 end  --  (same as above)
    --  Look for the best scale
    local nzero, dx, vmag_idx, xplus
    vmag_idx = 0
    for i = 1, 9 do
      dx = v_mag[i]
      nzero = -math.floor(vmin / dx)  --  The position of the V=0 line
      xplus = vmax / dx
      if nzero <= 11 and nzero + xplus <= 11.5 then
        vmag_idx = i
        break
      end
    end
    if vmag_idx == 0 then
      vmag_idx = 9
      nzero = 6
    else
      local dx0 = nzero + vmin / dx
      local dx1 = 11.5 - nzero - xplus
      local dn = math.floor(dx1 - dx0)
      nzero = nzero + math.ceil(dn / 2)
    end
    echem_graph[6] = vmag_idx
    echem_graph[1] = 24 * nzero
    echem_graph[9] = 0
    local vi_raw = voltage_to_raw(cv_settings[1])  --  Initial potential in raw
    local vh_raw = voltage_to_raw(cv_settings[2])  --  High potential in raw
    local vl_raw = voltage_to_raw(cv_settings[3])  --  Low potential in raw
    local nsamples = vh_raw - vl_raw      --  Number of samples per one-way scan
    local tscan = 1000 * (cv_settings[2] - cv_settings[3]) / cv_settings[5] -- Time per one-way scan
    local dt = tscan / nsamples  --  Sampling interval (assuming +-1 step in raw value)
    if dt < 0.002 then
      local n = math.ceil(0.002 / dt)     --  Raw value step
      dt = dt * n
      nsamples = math.ceil(nsamples / n)
      vh_raw = vl_raw + nsamples * n      --  Update Vhigh so that the number of steps is integer
    end
    local vh = voltage_from_raw(vh_raw)
    local vl = voltage_from_raw(vl_raw)
    local vi = voltage_from_raw(vi_raw)
    local dv = (vh - vl) / nsamples  --  Potential step (in V)
    echem_setup[8] = nsamples
    echem_setup[9] = dv
    echem_setup[5] = dt
    if cv_settings[4] == 0 then
      --  Initially positive scan
      echem_setup[7] = math.floor((vh + vi - 2 * vl) / dv + 0.5)
    else
      --  Initially negative scan
      echem_setup[7] = math.floor((vh - vi) / dv + 0.5)
    end
    echem_setup[6] = math.floor(nsamples * cv_settings[6] * 2 + 1) -- Number of steps
    -- Function generator
    echem_func = function (n)
      if n == -1 then return cv_settings[1] end   -- initial potential
      if n == -2 then return nil end                     -- stop potential
      local nn = n
      if nn >= echem_setup[6] then nn = echem_setup[6] - 1 end
      local pot = math.abs((nn + 1 + echem_setup[7]) % (2 * echem_setup[8]) - echem_setup[8]) * echem_setup[9] + cv_settings[3]
      return pot, echem_setup[5] * n  -- potential, stamp
    end
    echem_wait = cv_settings[7]
    echem_graph[3] = 24.0 / 1000.0 / v_mag[echem_graph[6]]
    echem_graph[4] = 24.0 / 1000.0 / i_mag[echem_graph[7]]
    echem_setup[4] = 0  --  Number of valid data
    echem_setup[3] = util.now()
    echem_setup[2] = 2  --  Cyclic voltammetry
    echem_setup[1] = 1  --  Start echem
    items[ITEM_GRAPH_SAVE][2] = 0
    echem_start_time = util.now()
    start_echem()
    show_graph()
  elseif idx == ITEM_CV_CLOSE then
    select_tab(nil)
  elseif idx == ITEM_CALIB_ZEROADJ then
    select_tab(-1)
    output_voltage(0.0)
  elseif idx == ITEM_CALIB_SCALE then
    echemsub.conv_direct_write(4095)
    update_values()
    select_tab(-2)
    calib_save = {}
    calib_save[1], calib_save[2], calib_save[3] = calib[3], calib[4], calib[5]
  elseif idx == ITEM_CALIB_DATETIME then
    local i, t
    t = os.date("*t")
    datetime[1] = string.format("%04d", t.year)
    datetime[2] = string.format("%02d", t.month)
    datetime[3] = string.format("%02d", t.day)
    datetime[4] = string.format("%02d", t.hour)
    datetime[5] = string.format("%02d", t.min)
    datetime[6] = string.format("%02d", t.sec)
    for i = 0, 5 do
      set_item_value(ITEM_DATETIME_YEAR + i, datetime[i + 1])
    end
    select_tab(-3)
  elseif idx == ITEM_CALIB_UPDATE then
    local res = show_dialog("Please insert USB memory", "containing the new software.", 1)
    if res == "OK" then
      update_software()
    end
  elseif idx == ITEM_ZEROADJ_OK then
    select_tab(ITEM_CALIB)
    update_values()
    calib[1] = cur_raw
  elseif idx == ITEM_SCALE_VW then
    val = show_numpad("Vw value:", "")
    if val then
      calib[3] = val / ((4095 - volw_zero) / 1000.0)
      calib[4] = 1000.0 * val / (cur_raw - calib[1])
      calib[5] = 0.0
      set_item_value(ITEM_SCALE_VW, string.format("%6.3f V", val))
    end
  elseif idx == ITEM_SCALE_CANCEL then
    calib[3], calib[4], calib[5] = calib_save[1], calib_save[2], calib_save[3]
    select_tab(ITEM_CALIB)
    output_voltage(0.0)
  elseif idx == ITEM_SCALE_OK then
    write_settings()
    select_tab(ITEM_CALIB)
    output_voltage(0.0)
  elseif idx >= ITEM_DATETIME_YEAR and idx <= ITEM_DATETIME_SEC then
    local i, lbl
    i = idx - ITEM_DATETIME_YEAR + 1
    lbl = {"Year:", "Month:", "Day:", "Hour:", "Min:", "Sec:"}
    lbl = lbl[i]
    val = show_numpad(lbl, datetime[i])
    if val then
      val = math.floor(val)
      if i == 1 then
        if val >= 2017 and val <= 2079 then
          datetime[i] = string.format("%04d", val)
        else
          val = nil
        end
      else
        if (i == 2 and (val < 1 or val > 12)) then
          val = nil
        elseif i == 3 then
          local m, dmax
          m = datetime[2] + 0
          if m == 2 then
            dmax = 28
            if datetime[1] % 4 == 0 and (datetime[1] % 100 ~= 0 or datetime[1] % 400 == 0) then dmax = 29 end
          elseif m == 1 or m == 3 or m == 5 or m == 7 or m == 8 or m == 10 or m == 12 then
            dmax = 31
          else
            dmax = 30
          end
          if val < 1 or val > dmax then
            val = nil
          end
        elseif (i == 4 and (val < 0 or val >= 24)) then
          val = nil
        elseif val < 0 or val >= 60 then
          val = nil
        end
        datetime[i] = string.format("%02d", val)
      end
      if val then
        set_item_value(idx, datetime[i])
      end
    end
  elseif idx == ITEM_DATETIME_SET or idx == ITEM_DATETIME_CANCEL then
    if idx == ITEM_DATETIME_SET then
      local t
      t = datetime[1] .. "/" .. datetime[2] .. "/" .. datetime[3] .. " "
      t = t .. datetime[4] .. ":" .. datetime[5] .. ":" .. datetime[6]
      os.execute("sudo date -s \"" .. t .. "\"")
      os.execute("sudo hwclock -w")
    end
    select_tab(ITEM_CALIB)
  elseif idx == ITEM_SHUTDOWN_POWEROFF or idx == ITEM_SHUTDOWN_REBOOT then
    local msg, cmd
    if idx == ITEM_SHUTDOWN_POWEROFF then
      msg = "Shutting down..."
      cmd = "sudo poweroff"
    else
      msg = "Rebooting..."
      cmd = "sudo reboot"
    end
    sc.cls()
    sc.tcolor(sc.rgb(1, 1, 1), sc.rgb(0, 0, 0))
    sc.gputs(80, 84, msg)
    sc.flush()
    os.execute(cmd)
    -- No return
  elseif idx >= ITEM_NUMPAD and idx <= ITEM_NUMPAD_CANCEL then
    return do_action_numpad(idx)
  elseif idx == ITEM_GRAPH_PLUS then
    if echem_graph[7] > 1 then
      echem_graph[7] = echem_graph[7] - 1
      echem_graph[4] = 24.0 / 1000.0 / i_mag[echem_graph[7]]
      set_need_draw_axis()
      show_all_items()
      if echem_graph[5] == 0 then
        draw_graph(true)
      end
    end
  elseif idx == ITEM_GRAPH_MINUS then
    if echem_graph[7] < #i_mag then
      echem_graph[7] = echem_graph[7] + 1
      echem_graph[4] = 24.0 / 1000.0 / i_mag[echem_graph[7]]
      set_need_draw_axis()
      show_all_items()
      if echem_graph[5] == 0 then
        draw_graph(true)
      end
    end
  elseif idx == ITEM_GRAPH_STOP then
    if echem_setup[1] == 1 then
      stop_echem()
      if echem_setup[2] == 1 then
        output_voltage(electrolysis_settings[4])
      end
    else
      hide_graph()
      items[idx][8] = sc.rgb(1, 0, 0)
      items[idx][7] = {16, 16, 1}
      echem_setup[1] = 0
    end
  elseif idx == ITEM_GRAPH_SAVE then
    save_echem_data()
    set_need_draw_axis()
    show_all_items()
    draw_graph(true)
  elseif idx == ITEM_DIALOG_OK or idx == ITEM_DIALOG_OK2 then
    return "OK"
  elseif idx == ITEM_DIALOG_CANCEL then
    return "Cancel"
  else
    sc.gputs(0, 168, string.format("%d pressed", idx))
  end
  return nil
end

pos_neg = {"positive", "negative"}
function save_echem_data_sub(fp)
  local xdata, ydata, i
  --  { potential, interval, time, rest_potential }
  --  { initial, high, low, polarity (0:pos, 1:neg), speed, scans, wait }
  if echem_setup[2] == 1 then
    --  Constant potential electrolysis
    fp:write("#  Constant potential electrolysis\n")
    fp:write(string.format("# Potential %6.3f V\n", electrolysis_settings[1]))
    fp:write(string.format("# Interval  %.1f s\n", electrolysis_settings[2]))
    fp:write(string.format("# Time %.0f s\n", electrolysis_settings[3]))
    fp:write(string.format("# Resting potential %6.3f V\n", electrolysis_settings[4]))
  else
    --  Cyclic voltammetry
    fp:write("#  Cyclic voltammetry\n")
    fp:write(string.format("#  Initial %6.3f V\n", cv_settings[1]))
    fp:write(string.format("#  High    %6.3f V\n", cv_settings[2]))
    fp:write(string.format("#  Low     %6.3f V\n", cv_settings[3]))
    fp:write(string.format("#  Polarity %s\n", pos_neg[cv_settings[4] + 1]))
    fp:write(string.format("#  Speed   %.0f mV/s\n", cv_settings[5]))
    fp:write(string.format("#  Scans   %d\n", cv_settings[6]))
    fp:write(string.format("#  Wait    %.1f s\n", cv_settings[7]))
  end
  fp:write("# time potential current\n")
  for i = 1, echem_receive_idx do
    local t, v, c
    t = echem_dbuf[i - 1].stamp - echem_wait
    v = voltage_from_raw(echem_dbuf[i - 1].outdata)
    c = current_from_raw(echem_dbuf[i - 1].indata)
    fp:write(string.format("%f %f %f\n", t, v, c))
  end
end

function save_echem_data()
  local f, res, fname, fp, msg1, msg2, i, s, xdata, ydata
  msg2 = ""
  msg1 = mount_usbmem()
  if msg1 ~= nil then
    goto error
  end
  fname = os.date("%Y%m%d-%H%M%S.txt")
  fp, msg2 = io.open("/media/usbmem/" .. fname, "w")
  if fp == nil then
    msg1 = "I/O error"
    goto unmount
  end
  save_echem_data_sub(fp)
  fp:close()
  msg1 = unmount_usbmem()
  if msg1 ~= nil then
    goto error
  end
  msg1 = "Saved to file:"
  msg2 = fname
  show_dialog("Saved to file:", fname)
  msg1 = nil
  goto exit
::unmount::
  unmount_usbmem()
::error::
  show_dialog(msg1, msg2)
  --  Silently save the data internally
  os.execute("mkdir -p echem_data")
  fname = os.date("%Y%m%d-%H%M%S.txt")
  fp, msg2 = io.open("echem_data/" .. fname, "w")
  if fp ~= nil then
    save_echem_data_sub(fp)
    fp:close()
  end
::exit::
  return msg1
end

function draw_graph(draw_axis)
  local i, x, y, s1, s2, s3
  local idx, idx_min, idx_max, idx_lim
  if need_draw_axis or draw_axis then
    sc.color(sc.rgb(0.5, 0.5, 0.5))
    sc.line(32.5, 48, 32.5, 192)
    for i = 1, 11 do
      x = 32.5 + 24 * i
      if x == echem_graph[1] + 32.5 then
        sc.color(sc.rgb(0, 0, 0))
      else
        sc.color(sc.rgb(0.5, 0.5, 0.5))
      end
      sc.line(x, 48, x, 192)
    end
    for i = 1, 7 do
      y = 24.5 + 24 * i
      if y == echem_graph[2] + 48.5 then
        sc.color(sc.rgb(0, 0, 0))
      else
        sc.color(sc.rgb(0.5, 0.5, 0.5))
      end
      sc.line(32, y, 312, y)
    end
    s1 = string.format(i_mag_formats[echem_graph[7]], i_mag_labels[echem_graph[7]])
    s2 = string.format(i_mag_formats[echem_graph[7]], math.floor(-echem_graph[2]/24 * i_mag_labels[echem_graph[7]] + 0.5))
    sc.tcolor(item_fcolor, item_bcolor_numpad)
    sc.gputs(12, 196, s1 .. "/div", 12, 196)
    if echem_setup[2] == 1 then
      s1 = string.format(t_mag_formats[echem_graph[8]], t_mag_labels[echem_graph[8]])
      s3 = string.format(t_mag_formats[echem_graph[8]], math.floor(-echem_graph[1]/24 * t_mag_labels[echem_graph[8]] + 0.5))
    else
      s1 = string.format(v_mag_formats[echem_graph[6]], v_mag_labels[echem_graph[6]])
      s3 = string.format(v_mag_formats[echem_graph[6]], math.floor(-echem_graph[1]/24 * v_mag_labels[echem_graph[6]] + 0.5))
    end
    sc.tcolor(item_fcolor, item_bcolor_numpad)
    sc.gputs(184, 28, s1 .. "/div")
    sc.gputs(12, 28, string.format("(%s,%s)", s3, s2))
    need_draw_axis = nil
  end
  local xdiv, ydiv
  local dlen = echem_receive_idx
  ydiv = i_mag[echem_graph[7]]
  if echem_setup[2] == 1 then
    -- Constant potential electrolysis
    -- x-axis is time
    xdiv = t_mag[echem_graph[8]]
    sc.color(sc.rgb(1, 1, 1))
    x = echem_graph[1]
    for idx = 1, dlen do
      x = math.floor(echem_graph[1] + (echem_dbuf[idx - 1].stamp - echem_wait) * 24 / xdiv)
      y = math.floor(echem_graph[2] + current_from_raw(echem_dbuf[idx - 1].indata) * 24 / ydiv)
      if x >= 0 and x < 280 and y >= 0 and y < 168 then
        sc.pset(x + 32, y + 48)
      end
    end
    if x >= 280 and echem_graph[8] < #t_mag then
      echem_graph[8] = echem_graph[8] + 1
      set_need_draw_axis()
      echem_graph[5] = 1
    else
      echem_graph[5] = 0
    end
  elseif echem_setup[2] == 2 then
    -- Cyclic voltammetry
    -- x-axis is voltage
    xdiv = v_mag[echem_graph[6]]
    sc.color(sc.rgb(1, 1, 1))
    for idx = 1, dlen do
      x = math.floor(echem_graph[1] + voltage_from_raw(echem_dbuf[idx - 1].outdata) * 24 / xdiv)
      y = math.floor(echem_graph[2] + current_from_raw(echem_dbuf[idx - 1].indata) * 24 / ydiv)
      if x >= 0 and x < 280 and y >= 0 and y < 168 then
        sc.pset(x + 32, y + 48)
      end
    end
    echem_graph[5] = 0
  end
  -- sc.flush()  --  This will be called in update_values() anyway
end

last_time = nil

function event_loop()
  local idx, pres
  idx, pres = sense_tp()
  if idx then
    if pres > 0 then
      --  Pen down
      if hi_item > 0 and hi_item ~= idx then
        items[hi_item][8] = item_fcolor
        items[hi_item][9] = item_bcolor
        show_item(hi_item)
        hi_item = -1
      end
      if idx > 0 and hi_item ~= idx then
        items[idx][8] = item_fcolor_hi
        items[idx][9] = item_bcolor_hi
        show_item(idx)
        hi_item = idx
      end
    else
      --  Pen up
      if hi_item > 0 then
        items[hi_item][8] = item_fcolor
        items[hi_item][9] = item_bcolor
        show_item(hi_item)
        idx = hi_item
        hi_item = -1
        local res = do_action(idx)
        sc.flush()
        if res then return res end
      end
    end
  end
  local t = util.now()
  if last_time == nil or t > last_time + 0.1 then
    if echem_setup[1] == 1 then
      handle_echem()
      if echem_graph[5] ~= 0 then
        draw_graph()
      end
    end
    update_values()
    last_time = t
  end
  return nil
end

--  main

echemsub.conv_init(10, 1000000, 12, 1000000, 22)
echemsub.conv_direct_write(voltage_to_raw(0.0))

hi_item = 0
show_all_items(true)

while true do
  event_loop()
end
