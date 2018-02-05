-- ---------------------------------------------
--   ctl.lua       2017/08/09
--   Copyright (c) 2017 Toshi Nagata
--   released under the MIT open source license.
-- ---------------------------------------------


local ffi = require "ffi"
local bit = require "bit"
local util = require "util"

--  Constants for ioctl/fcntl calls
local ctl = {
  --  from arm-linux-gnueabihf/bits/fcntl-linux.h
  O_ACCMODE = 3,
  O_RDONLY = 0,
  O_WRONLY = 1,
  O_RDWR = 2,
  O_CREAT = 0x40,
  O_EXCL = 0x80,
  O_NOCTTY = 0x100,
  O_TRUNC = 0x200,
  O_APPEND = 0x400,
  O_NONBLOCK = 0x800,
  O_SYNC = 0x101000,
  O_ASYNC = 0x002000,
  O_LARGEFILE = 0x004000,
  O_DIRECTORY = 0x008000,
  O_NOFOLLOW = 0x010000,
  O_CLOEXEC = 0x080000,
  O_DIRECT = 0x004000,
  O_NOATIME = 0x040000,
  O_PATH = 0x200000,
  O_DSYNC = 0x001000,
  O_TMPFILE = 0x410000,
  --  from asm-generic/ioctl.h
  IOC_NRSHIFT = 0,
  IOC_TYPESHIFT = 8,
  IOC_SIZESHIFT = 16,
  IOC_DIRSHIFT = 30,
  IOC_NRMASK = 0xff,
  IOC_TYPEMASK = 0xff,
  IOC_SIZEMASK = 0x3fff,
  IOC_DIRMASK = 3
}

function ctl.IOC(dir, type, nr, size)
    return bit.bor(bit.lshift(dir, ctl.IOC_DIRSHIFT), bit.lshift(type, ctl.IOC_TYPESHIFT), bit.lshift(nr, ctl.IOC_NRSHIFT), bit.lshift(size, ctl.IOC_SIZESHIFT))
end

function ctl.IO(type, nr)
  return ctl.IOC(0, type, nr, 0)
end
function ctl.IOR(type, nr, size)
  return ctl.IOC(2, type, nr, size)
end

function ctl.IOW(type, nr, size)
  return ctl.IOC(1, type, nr, size)
end

function ctl.IORW(type, nr, size)
  return ctl.IOC(3, type, nr, size)
end

ffi.cdef[[
int ioctl(int d, unsigned long request, ...);
int fcntl(int fd, int cmd, ...);
int open(const char* filename, int flags);
int read(int fd, void *buf, unsigned int nbytes);
int close(int fd);
]]

return ctl
