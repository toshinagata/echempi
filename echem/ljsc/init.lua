-- ---------------------------------------------
-- ljsc.lua        2017/06/18
--   Copyright (c) 2017 Toshi Nagata
--   released under the MIT open source license.
-- ---------------------------------------------

--  Where am I?
local pname = ...
local dname = string.gsub(pname, "init", "")
package.path = dname .. "?.lua;" .. package.path
