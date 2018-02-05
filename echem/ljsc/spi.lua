-- ---------------------------------------------
--  spi.lua      2017/08/07
--   Copyright (c) 2017 Toshi Nagata,
--   released under the MIT open source license.
-- ---------------------------------------------

local ffi = require("ffi")
local bit = require("bit")

ffi.cdef[[
  struct spi_info {
    int fd;
    int speed;
    int mode;
    int bpw;
  };
  int ioctl(int, unsigned long, ...);
  int open(const char* filename, int flags);
  int close(int fd);
]]

local spi = {
  IOC_RD_MODE = 0x80016b01,
  IOC_WR_MODE = 0x40016b01,
  IOC_RD_BITS_PER_WORD = 0x80016b03,
  IOC_WR_BITS_PER_WORD = 0x40016b03,
  IOC_RD_MAX_SPEED_HZ = 0x80046b04,
  IOC_WR_MAX_SPEED_HZ = 0x40046b04,
}

function spi.checkchannel(ch)
  if ch >= 0 and ch <= 2 then return ch end
  if ch >= 10 and ch <= 12 then return ch - 7 end
  return nil
end

function spi.setup(ch, speed, mode, bpw)
  ch = spi.checkchannel(ch)
  if ch == nil then error("Bad SPI device number " .. ch .. " (must be 0/1/2 or 10/11/12)") end
  mode = mode or 0
  bpw = bpw or 8
  if spi.infos == nil then
    spi.infos = ffi.new("struct spi_info[6]")
    for i = 0, 5 do
      spi.infos[i].fd = -1
    end
  end
  local n
  if spi.infos[ch] >= 0 then
    n = spi.infos[ch]
  else
    local O_RDWR = 2
    local spidev = string.format("/dev/spidev%d.%d", math.floor(ch / 3), ch % 3)
    n = ffi.C.open(spidev, O_RDWR)
    if n < 0 then error("Cannot open SPI device " .. spidev) end
  end
  ival = ffi.new("int[1]")
  ival = mode
  if ffi.C.ioctl(n, spi.IOC_WR_MODE, ival) < 0 then
    ffi.C.close(n)
    error("Cannot set SPI write mode")
  end
  ival = bpw
  if ffi.C.ioctl(n, spi.IOC_WR_BITS_PER_WORD, ival) < 0 then
    ffi.C.close(n)
    error("Cannot set SPI write bits-per-word")
  end
  ival = speed
  if ffi.C.ioctl(n, spi.IOC_WR_MAX_SPEED_HZ, ival) < 0 then
    ffi.C.close(n)
    error("Cannot set SPI write speed")
  end
  ival = mode
  if ffi.C.ioctl(n, spi.IOC_RD_MODE, ival) < 0 then
    ffi.C.close(n)
    error("Cannot set SPI read mode")
  end
  ival = bpw
  if ffi.C.ioctl(n, spi.IOC_RD_BITS_PER_WORD, ival) < 0 then
    ffi.C.close(n)
    error("Cannot set SPI read bits-per-word")
  end
  ival = speed
  if ffi.C.ioctl(n, spi.IOC_RD_MAX_SPEED_HZ, ival) < 0 then
    ffi.C.close(n)
    error("Cannot set SPI read speed")
  end
  spi.infos[n].speed = speed
  spi.infos[n].mode = mode
  spi.infos[n].bpw = bpw
end

    
    /*  Internal routine for SPI read/write; flag = 1: read, 2: write, 3: both  */
    static int
    l_spi_readwrite_sub(lua_State *L, int flag)
    {
    int ch, channel, i;
    unsigned int length, len;
    unsigned char *p;
    struct spi_ioc_transfer tr;
    channel = luaL_checkinteger(L, 1);
    luaL_checktype(L, 2, LUA_TTABLE);
    length = luaL_checkinteger(L, 3);
    ch = l_spi_checkchannel(channel);
    if (length < 32) {
        p = alloca(length * 2);
    } else {
        p = malloc(length * 2);
    }
    if (p == NULL)
        luaL_error(L, "Cannot allocate SPI buffer");
    len = lua_rawlen(L, 2);
    if (flag & 2) {
        for (i = 1; i <= length; i++) {
            char c;
            if (i > len)
                c = 0;
            else {
                lua_rawgeti(L, 2, i);
                c = luaL_checkinteger(L, -1);
                lua_pop(L, 1);
            }
            p[i - 1] = c;
        }
    } else {
        memset(p, 0, length);
    }
    memset(&tr, 0, sizeof(tr));
    tr.tx_buf = (unsigned long)p;
    tr.rx_buf = (unsigned long)(p + length);
    tr.len = length;
    tr.delay_usecs = 0;
    tr.speed_hz = s_spi_speed[ch];
    tr.bits_per_word = s_spi_bpw[ch];
    tr.cs_change = 0;
    if (ioctl(s_spi_fd[ch], SPI_IOC_MESSAGE(1), &tr) < 0) {
        lua_pushinteger(L, 1);
        return 1;
    }
    if (flag & 1) {
        for (i = 1; i <= length; i++) {
            lua_pushinteger(L, (unsigned char)p[i + length - 1]);
            lua_rawseti(L, 2, i);
        }
    }
    if (length >= 32)
        free(p);
    lua_pushinteger(L, 0);
    return 1;
    }
    
    /*  spi.read(channel, table, length)  */
    static int
    l_spi_read(lua_State *L)
    {
    return l_spi_readwrite_sub(L, 1);
    }
    
    /*  spi.write(channel, table, length)  */
    static int
    l_spi_write(lua_State *L)
    {
    return l_spi_readwrite_sub(L, 2);
    }
    
    /*  spi.readwrite(channel, table, length)  */
    static int
    l_spi_readwrite(lua_State *L)
    {
    return l_spi_readwrite_sub(L, 3);
    }
    
    /*  spi.close(channel)  */
    static int
    l_spi_close(lua_State *L)
    {
    int ch, channel;
    channel = luaL_checkinteger(L, 1);
    ch = l_spi_checkchannel(channel);
    if (s_spi_fd[ch] < 0)
        return luaL_error(L, "SPI channel %d is not opened", channel);
    close(s_spi_fd[ch]);
    s_spi_fd[ch] = -1;
    return 0;
    }
    

return spi
