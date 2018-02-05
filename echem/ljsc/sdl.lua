-- ---------------------------------------------
--   sdl.lua       2017/08/09
--   Copyright (c) 2017 Toshi Nagata
--   released under the MIT open source license.
-- ---------------------------------------------

local ffi = require "ffi"
local bit = require "bit"

libSDL = ffi.load("libSDL-1.2.so.0")

ffi.cdef[[
  int SDL_Init(uint32_t flags);
  int SDL_InitSubSystem(uint32_t flags);
  void SDL_QuitSubSystem(uint32_t flags);
  uint32_t SDL_WasInit(uint32_t flags);
  void SDL_Quit(void);
  void SDL_Delay(uint32_t ms);

  typedef struct SDL_RWops SDL_RWops;
  SDL_RWops *SDL_RWFromFile(const char *file, const char *mode);

]]

local sdl = {
  INIT_TIMER       = 0x00000001,
  INIT_AUDIO       = 0x00000010,
  INIT_VIDEO       = 0x00000020,
  INIT_CDROM       = 0x00000100,
  INIT_JOYSTICK    = 0x00000200,
  INIT_NOPARACHUTE = 0x00100000,
  INIT_EVENTTHREAD = 0x01000000,
  INIT_EVERYTHING  = 0x0000FFFF,
  
  init = libSDL.SDL_Init,
  delay = libSDL.SDL_Delay,
  quit = libSDL.SDL_Quit
}

return sdl
