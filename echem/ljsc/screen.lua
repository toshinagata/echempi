-- ---------------------------------------------
--   screen.lua       2017/06/18
--   Copyright (c) 2017 Toshi Nagata
--   released under the MIT open source license.
-- ---------------------------------------------

local ffi = require "ffi"
local bit = require "bit"

local vg = require "vg"
local bcm = require "bcm"
local egl = require "egl"

local png = require "png"
local util = require "util"

ffi.cdef[[

struct fb_fix_screeninfo {
    char id[16];
    unsigned long smem_start;
    unsigned int smem_len;
    unsigned int type;
    unsigned int type_aux;
    unsigned int visual;
    unsigned short xpanstep;
    unsigned short ypanstep;
    unsigned short ywrapstep;
    unsigned int line_length;
    unsigned long mmio_start;
    unsigned int mmio_len;
    unsigned int accel;
    unsigned short reserved[3];
};

struct fb_bitfield {
    unsigned int offset;
    unsigned int length;
    unsigned int msb_right;
};

struct fb_var_screeninfo {
    unsigned int xres;
    unsigned int yres;
    unsigned int xres_virtual;
    unsigned int yres_virtual;
    unsigned int xoffset;
    unsigned int yoffset;
    unsigned int bits_per_pixel;
    unsigned int grayscale;
    struct fb_bitfield red;
    struct fb_bitfield green;
    struct fb_bitfield blue;
    struct fb_bitfield transp;
    unsigned int nonstd;
    unsigned int activate;
    unsigned int height;
    unsigned int width;
    unsigned int accel_flags;
    unsigned int pixclock;
    unsigned int left_margin;
    unsigned int right_margin;
    unsigned int upper_margin;
    unsigned int lower_margin;
    unsigned int hsync_len;
    unsigned int vsync_len;
    unsigned int sync;
    unsigned int vmode;
    unsigned int rotate;
    unsigned int reserved[5];
};

typedef uint32_t size_t;
typedef int32_t off_t;

int ioctl(int, unsigned long, ...);
int open(const char* filename, int flags);
int close(int fd);
void *mmap(void *addr, size_t length, int prot, int flags, int fd, off_t offset);
int munmap(void *addr, size_t length);
void *memmove(void *dst, const void *src, size_t len);

struct LPattern {
  uint16_t width, height;
  int32_t ofs;
  VGImage image;
};

]]

local screen = {
  NUMBER_OF_PATTERNS = 256,
  NUMBER_OF_PATHS = 4096
}

--  A hidden global variable that retains the screen object.
--  Declaring 'screen' as a global variable would give the same result, 
--  but we want to avoid overwriting 'screen' accidentally.
--  '_Screen' is less likely to be overwritten by mistake.
_Screen = screen

local pname = ...
local pdir = string.gsub(package.searchpath(pname, package.path), pname .. "%.lua$", "")

function screen.init_egl()

  --  Initialize bcm_host
  bcm.bcm_host_init()

  --  Get an EGL display connection
  _Screen.display = egl.getDisplay(ffi.cast("EGLDisplay", egl.DEFAULT_DISPLAY))

  --  Initialize the EGL display connection
  local result = egl.initialize(_Screen.display, nil, nil)

  --  Get an appropriate EGL frame buffer configuration
  local attribute_list = ffi.new('int[13]', {egl.RED_SIZE, 8,
    egl.GREEN_SIZE, 8, egl.BLUE_SIZE, 8, egl.ALPHA_SIZE, 8,
    egl.SURFACE_TYPE, egl.WINDOW_BIT,
    egl.RENDERABLE_TYPE, egl.OPENVG_BIT,
    egl.NONE})
  _Screen.numConfigs = ffi.new('int[1]')
  _Screen.config = ffi.new('void *[1]')
  result = egl.chooseConfig(_Screen.display, attribute_list, _Screen.config, 1, _Screen.numConfigs)

  --  Bind OpenVG API
  result = egl.bindAPI(egl.OPENVG_API)

  --  Create an EGL rendering context
  _Screen.context = egl.createContext(_Screen.display, _Screen.config[0], nil, nil)

  --  Create an EGL window surface
  local ww = ffi.new("uint32_t[1]")
  local hh = ffi.new("uint32_t[1]")
  result = bcm.graphics_get_display_size(0, ww, hh)
  local VC_DISPMANX_ALPHA_T = ffi.typeof("VC_DISPMANX_ALPHA_T")
  local EGL_DISPMANX_WINDOW_T = ffi.typeof("EGL_DISPMANX_WINDOW_T")
  local dst_rect = bcm.VC_RECT_T(0, 0, ww[0], hh[0])
  local src_rect = bcm.VC_RECT_T(0, 0, bit.lshift(ww[0], 16), bit.lshift(hh[0], 16))
  local dispman_display = bcm.vc_dispmanx_display_open(0)
  local dispman_update = bcm.vc_dispmanx_update_start(0)
  local dispman_element = bcm.vc_dispmanx_element_add(dispman_update,
    dispman_display, 0, dst_rect, 0, src_rect, 0, nil, nil, 0)
  bcm.vc_dispmanx_update_submit_sync(dispman_update)
  _Screen.dispman_display = dispman_display
  _Screen.dispman_element = dispman_element
  _Screen.nativewindow = EGL_DISPMANX_WINDOW_T(dispman_element, ww[0], hh[0])
  _Screen.dispman_width = ww[0]
  _Screen.dispman_height = hh[0]
  _Screen.surface = egl.createWindowSurface(_Screen.display, _Screen.config[0], _Screen.nativewindow, nil)
  _Screen.fb_width = ww[0]
  _Screen.fb_height = hh[0]
  
  --  Make the physical display current
  result = egl.makeCurrent(_Screen.display, _Screen.surface, _Screen.surface, _Screen.context)
  
  return true

end

function screen.create_offscreen_image(width, height)
  local attribute_list = ffi.new('int[13]', {egl.RED_SIZE, 8,
    egl.GREEN_SIZE, 8, egl.BLUE_SIZE, 8, egl.ALPHA_SIZE, 8,
    egl.SURFACE_TYPE, egl.WINDOW_BIT,
    egl.RENDERABLE_TYPE, egl.OPENVG_BIT,
    egl.NONE})
  
  --  The offscreen image is bound to the physical screen
  local result = egl.makeCurrent(_Screen.display, _Screen.surface, _Screen.surface, _Screen.context)

  local colors = ffi.new('VGfloat[4]', {0.0, 0.0, 0.0, 0.0})
  vg.setfv(vg.CLEAR_COLOR, 4, colors)
  
  if (_Screen.off_image ~= nil) then
    egl.destroySurface(_Screen.display, _Screen.off_surface)
    egl.destroyContext(_Screen.display, _Screen.off_context)
    vg.destroyImage(_Screen.off_image)
  end
  
  _Screen.off_image = vg.createImage(vg.sRGBA_8888, width, height, vg.IMAGE_QUALITY_FASTER)
  vg.clearImage(_Screen.off_image, 0, 0, width, height)
  egl.chooseConfig(_Screen.display, attribute_list, _Screen.config, 1, _Screen.numConfigs)
  _Screen.off_context = egl.createContext(_Screen.display, _Screen.config[0], _Screen.context, nil)
  _Screen.off_surface = egl.createPbufferFromClientBuffer(_Screen.display, egl.OPENVG_IMAGE, ffi.cast("EGLClientBuffer", _Screen.off_image), _Screen.config[0], nil)
  
  --  If the framebuffer is mapped to the memory and the image size is not equal to the
  -- framebuffer, we need another offscreen image to scale before transferring to fb
  if _Screen.tmp_image ~= nil then
    egl.destroySurface(_Screen.display, _Screen.tmp_surface)
    egl.destroyContext(_Screen.display, _Screen.tmp_context)
    vg.destroyImage(_Screen.tmp_image)
    _Screen.tmp_context = nil
    _Screen.tmp_surface = nil
    _Screen.tmp_image = nil
  end
  if _Screen.fbp ~= nil and (_Screen.fb_width ~= width or _Screen.fb_height ~= height) then
    _Screen.tmp_image = vg.createImage(vg.sRGBA_8888, _Screen.fb_width, _Screen.fb_height, vg.IMAGE_QUALITY_FASTER)
    vg.clearImage(_Screen.tmp_image, 0, 0, _Screen.fb_width, _Screen.fb_height)
    egl.chooseConfig(_Screen.display, attribute_list, _Screen.config, 1, _Screen.numConfigs)
    _Screen.tmp_context = egl.createContext(_Screen.display, _Screen.config[0], _Screen.context, nil)
    _Screen.tmp_surface = egl.createPbufferFromClientBuffer(_Screen.display, egl.OPENVG_IMAGE, ffi.cast("EGLClientBuffer", _Screen.tmp_image), _Screen.config[0], nil)
  end

  result = egl.makeCurrent(_Screen.display, _Screen.off_surface, _Screen.off_surface, _Screen.off_context)
  vg.setfv(vg.CLEAR_COLOR, 4, colors)
  return result
end

function screen.init_framebuffer(devno, map)
  local FBIOGET_VSCREENINFO = 0x4600
  local FBIOPUT_VSCREENINFO = 0x4601
  local FBIOGET_FSCREENINFO = 0x4602
  local O_RDONLY = 0
  local O_RDWR = 2
  if _Screen.fbp ~= nil then
    ffi.C.munmap(_Screen.fbp, _Screen.fsinfo.smem_len)
    _Screen.fbp = nil
  end
  if _Screen.fbfd ~= nil then
    ffi.C.close(_Screen.fbfd)
    _Screen.fbfd = nil
  end
  _Screen.fbfd = ffi.C.open(string.format("/dev/fb%d", devno), O_RDWR)
  if _Screen.fbfd < 0 then
    return false
  end
  local fsinfo = ffi.new("struct fb_fix_screeninfo[1]")
  local vsinfo = ffi.new("struct fb_var_screeninfo[1]")
  ffi.C.ioctl(_Screen.fbfd, FBIOGET_FSCREENINFO, fsinfo)
  ffi.C.ioctl(_Screen.fbfd, FBIOGET_VSCREENINFO, vsinfo)
  _Screen.fsinfo = fsinfo[0]
  _Screen.vsinfo = vsinfo[0]
  if map then
    --  Map the framebuffer to memory
    local PROT_READ = 1
    local PROT_WRITE = 2
    local PROT_EXEC = 4
    local MAP_SHARED = 1
    local fbp = ffi.C.mmap(nil, _Screen.fsinfo.smem_len, bit.bor(PROT_READ, PROT_WRITE), MAP_SHARED, _Screen.fbfd, 0)
    if (tonumber(ffi.cast("unsigned int", fbp)) == 0xffffffff) then
      _Screen.fbp = nil
      return false
    else
      _Screen.fbp = ffi.cast("uint8_t *", fbp)
    end
  else
    --  We do not use the framebuffer but only its info
    _Screen.fbp = nil
    ffi.C.close(_Screen.fbfd)
    _Screen.fbfd = nil
  end
  _Screen.fb_width = _Screen.vsinfo.xres
  _Screen.fb_height = _Screen.vsinfo.yres
  return true
end

--  This function must be occasionally called; otherwise the screen will not be updated
function screen.flush()
  vg.flush()
  if _Screen.fbp == nil then
    --  Make current the physical screen and draw the offscreen image
    local result
    result = egl.makeCurrent(_Screen.display, _Screen.surface, _Screen.surface, _Screen.context)
    vg.seti(vg.IMAGE_MODE, vg.DRAW_IMAGE_NORMAL)
    vg.drawImage(_Screen.off_image)
    egl.swapBuffers(_Screen.display, _Screen.surface)
    result = egl.makeCurrent(_Screen.display, _Screen.off_surface, _Screen.off_surface, _Screen.off_context)
  else
    --  Copy offscreen image to the frame buffer
    local w = _Screen.fb_width
    local h = _Screen.fb_height
    local fbp = _Screen.fbp + (h - 1) * w * 2
    if _Screen.tmp_image then
      --  We need to draw the image to the temporary image (for scaling)
      result = egl.makeCurrent(_Screen.display, _Screen.tmp_surface, _Screen.tmp_surface, _Screen.tmp_context)
      vg.seti(vg.IMAGE_MODE, vg.DRAW_IMAGE_NORMAL)
      vg.drawImage(_Screen.off_image)
      vg.flush()
      vg.getImageSubData(_Screen.tmp_image, fbp, -w * 2, vg.sRGB_565, 0, 0, w, h)
      result = egl.makeCurrent(_Screen.display, _Screen.off_surface, _Screen.off_surface, _Screen.off_context)
    else
      vg.getImageSubData(_Screen.off_image, fbp, -w * 2, vg.sRGB_565, 0, 0, w, h)
    end
  end
  --  Destroy the invalidated paths
  if _Screen.paths ~= nil then
    for i = 0, _Screen.NUMBER_OF_PATHS do
      if _Screen.pathflags[i] ~= 0 then
        vg.destroyPath(_Screen.paths[i])
        _Screen.paths[i] = vg.INVALID_HANDLE
        _Screen.pathflags[i] = 0
      end
    end
  end
end

--  devno = 0: HDMI screen; OpenVG calls will directly go to the screen 
--  devno ~= 0: framebuffer; OpenVG calls go to the offscreen image, 
--    which is transferred to screen on flush_screen() call
function screen.init(devno, width, height)
  _Screen.init_egl()
  if not _Screen.init_framebuffer(devno, devno ~= 0) then
    return false
  end
  width = width or _Screen.fb_width
  height = height or _Screen.fb_height
  _Screen.create_offscreen_image(width, height)
  _Screen.width = width
  _Screen.height = height
  if width ~= _Screen.fb_width or height ~= _Screen.fb_height then
    if _Screen.tmp_image ~= nil then
      egl.makeCurrent(_Screen.display, _Screen.tmp_surface, _Screen.tmp_surface, _Screen.tmp_context)
    else
      egl.makeCurrent(_Screen.display, _Screen.surface, _Screen.surface, _Screen.context)
    end
    vg.seti(vg.MATRIX_MODE, vg.MATRIX_PATH_USER_TO_SURFACE)
    vg.loadIdentity()
    vg.scale(_Screen.fb_width / width, _Screen.fb_height / height)
    vg.seti(vg.MATRIX_MODE, vg.MATRIX_IMAGE_USER_TO_SURFACE)
    vg.loadIdentity()
    vg.scale(_Screen.fb_width / width, _Screen.fb_height / height)
    egl.makeCurrent(_Screen.display, _Screen.off_surface, _Screen.off_surface, _Screen.off_context)
  end
  
  --  Patterns
  if _Screen.patbuffer_size == nil then
    _Screen.patbuffer_size = 32 * 32 * _Screen.NUMBER_OF_PATTERNS
  end
  _Screen.patbuffer_used = 0
  _Screen.patbuffer = ffi.new("uint32_t[?]", _Screen.patbuffer_size)
  _Screen.patterns = ffi.new("struct LPattern[?]", _Screen.NUMBER_OF_PATTERNS)
  
  --  Colors and draw flags
  local cols = ffi.new("VGfloat[4]", 1, 1, 1, 1)
  _Screen.stroke_color = vg.createPaint()
  vg.setParameteri(_Screen.stroke_color, vg.PAINT_TYPE, vg.PAINT_TYPE_COLOR)
  vg.setParameterfv(_Screen.stroke_color, vg.PAINT_COLOR, 4, cols)
  vg.setPaint(_Screen.stroke_color, vg.STROKE_PATH)
  _Screen.fill_color = vg.createPaint()
  vg.setParameteri(_Screen.stroke_color, vg.PAINT_TYPE, vg.PAINT_TYPE_COLOR)
  vg.setParameterfv(_Screen.stroke_color, vg.PAINT_COLOR, 4, cols)
  _Screen.draw_flag = vg.STROKE_PATH
  
  -- Load the ASCII font data
  _Screen.fontdata = ffi.new("uint8_t[2048]")
  local f = io.open(pdir .. "font8x16.dat", "r")
  if f == nil then
    error("Cannot read font8x16.dat.")
  end
  local s = f:read(1520)
  local i
  for i = 1, 1520 do
    _Screen.fontdata[i + 527] = s:byte(i)
  end
  _Screen.pattemp = ffi.new("uint32_t[128]")
  _Screen.pattempsize = 128
  _Screen.fonttemp = ffi.new("uint32_t[128]")
  _Screen.text_color = _Screen.rgb(1, 1, 1)
  _Screen.text_bgcolor = _Screen.rgb(0, 0, 0)
  _Screen.clear_color = _Screen.rgb(0, 0, 0)
  cols[0] = 0
  cols[1] = 0
  cols[2] = 0
  cols[3] = 1
  vg.setfv(vg.CLEAR_COLOR, 4, cols)
  vg.clear(0, 0, width, height)
  _Screen.tempcols = cols
  return true
end

function screen.create_path()
  local i
  if _Screen.paths == nil then
    _Screen.paths = ffi.new("VGPath[?]", _Screen.NUMBER_OF_PATHS)
    _Screen.pathflags = ffi.new("unsigned char[?]", _Screen.NUMBER_OF_PATHS)
    for i = 0, _Screen.NUMBER_OF_PATHS - 1 do
      _Screen.paths[i] = vg.INVALID_HANDLE
      _Screen.pathflags[i] = 0;
    end
  end
  for i = 0, _Screen.NUMBER_OF_PATHS - 1 do
    if _Screen.paths[i] == vg.INVALID_HANDLE then
      local path = vg.createPath(vg.PATH_FORMAT_STANDARD, vg.PATH_DATATYPE_F, 1, 0, 0, 0, bit.bor(vg.PATH_CAPABILITY_APPEND_TO, vg.PATH_CAPABILITY_PATH_BOUNDS))
      if path == vg.INVALID_HANDLE then
        return -1
      end
      _Screen.paths[i] = path
      return i
    end
  end
  return -1
end

function screen.invalidate_path(idx)
  if _Screen.paths == nil or idx < 0 or idx >= _Screen.NUMBER_OF_PATHS or _Screen.paths[idx] == vg.INVALID_HANDLE then
    return -1
  end
  _Screen.pathflags[idx] = 1
  return idx
end

function screen.destroy_path(idx)
  if _Screen.paths == nil or idx < 0 or idx >= _Screen.NUMBER_OF_PATHS or _Screen.paths[idx] == vg.INVALID_HANDLE then
    return -1
  end
  vg.destroyPath(_Screen.paths[idx])
  _Screen.paths[idx] = vg.INVALID_HANDLE
  _Screen.pathflags[idx] = 0
  return idx
end

function screen.rgba(r, g, b, a)
  r = bit.lshift(bit.band(math.floor(r * 255), 255), 24)
  g = bit.lshift(bit.band(math.floor(g * 255), 255), 16)
  b = bit.lshift(bit.band(math.floor(b * 255), 255), 8)
  a = bit.band(math.floor(a * 255), 255)
  return r + g + b + a
end

function screen.rgb(r, g, b)
  return _Screen.rgba(r, g, b, 1.0)
end

pset_pattern = ffi.new("uint32_t[1]")  --  Used in pset(x, y)

function screen.color(rgba)
  if rgba == nil then
    _Screen.draw_flag = bit.band(_Screen.draw_flag, bit.bnot(vg.STROKE_PATH))
  else
    _Screen.draw_flag = bit.bor(_Screen.draw_flag, vg.STROKE_PATH)
    local cols = ffi.new("VGfloat[4]")
    cols[0] = bit.band(bit.rshift(rgba, 24), 255) / 255.0
    cols[1] = bit.band(bit.rshift(rgba, 16), 255) / 255.0
    cols[2] = bit.band(bit.rshift(rgba, 8), 255) / 255.0
    cols[3] = bit.band(rgba, 255) / 255.0
    vg.setParameterfv(_Screen.stroke_color, vg.PAINT_COLOR, 4, cols)
    vg.setPaint(_Screen.stroke_color, vg.STROKE_PATH)
    pset_pattern[0] = rgba
  end
end

function screen.tcolor(rgba1, rgba2)
  _Screen.text_color = rgba1
  _Screen.text_bgcolor = rgba2
end

function screen.fillcolor(rgba)
  if rgba == nil then
    _Screen.draw_flag = bit.band(_Screen.draw_flag, bit.bnot(vg.FILL_PATH))
  else
    _Screen.draw_flag = bit.bor(_Screen.draw_flag, vg.FILL_PATH)
    local cols = ffi.new("VGfloat[4]")
    cols[0] = bit.band(bit.rshift(rgba, 24), 255) / 255.0
    cols[1] = bit.band(bit.rshift(rgba, 16), 255) / 255.0
    cols[2] = bit.band(bit.rshift(rgba, 8), 255) / 255.0
    cols[3] = bit.band(rgba, 255) / 255.0
    vg.setParameterfv(_Screen.fill_color, vg.PAINT_COLOR, 4, cols)
    vg.setPaint(_Screen.fill_color, vg.FILL_PATH)
  end
end

function screen.draw_path(idx)
  if _Screen.paths == nil or idx < 0 or idx >= _Screen.NUMBER_OF_PATHS or _Screen.paths[idx] == vg.INVALID_HANDLE then
    return -1
  end
  vg.drawPath(_Screen.paths[idx], bit.band(_Screen.draw_flag, bit.bor(vg.STROKE_PATH, vg.FILL_PATH)))
  -- _Screen.set_redraw(0, 0, 1, 1)
  return idx
end

function screen.p_moveto(idx, x, y)
  if _Screen.paths == nil or idx < 0 or idx >= _Screen.NUMBER_OF_PATHS or _Screen.paths[idx] == vg.INVALID_HANDLE then
    return -1
  end
  local segment = ffi.new("VGubyte[1]")
  local pdata = ffi.new("VGfloat[2]")
  pdata[0] = x
  pdata[1] = y
  segment[0] = vg.MOVE_TO_ABS
  vg.appendPathData(_Screen.paths[idx], 1, segment, pdata)
  return idx
end

function screen.p_lineto(idx, x, y)
  if _Screen.paths == nil or idx < 0 or idx >= _Screen.NUMBER_OF_PATHS or _Screen.paths[idx] == vg.INVALID_HANDLE then
    return -1
  end
  local segment = ffi.new("VGubyte[1]")
  local pdata = ffi.new("VGfloat[2]")
  pdata[0] = x
  pdata[1] = y
  segment[0] = vg.LINE_TO_ABS
  vg.appendPathData(_Screen.paths[idx], 1, segment, pdata)
  return idx
end

function screen.p_line(idx, x1, y1, x2, y2)
  local v = _Screen.p_moveto(idx, x1, y1)
  if v >= 0 then
    v = _Screen.p_lineto(idx, x2, y2)
  end
  return v
end

function screen.line(x1, y1, x2, y2)
  local idx = _Screen.create_path()
  if idx < 0 then return false end
  if _Screen.p_line(idx, x1, y1, x2, y2) >= 0 then _Screen.draw_path(idx) end
  _Screen.invalidate_path(idx)
  return true
end

function screen.pset(x , y)
  if x >= 0 and y >= 0 and x < _Screen.width and y < _Screen.width then
    _Screen.put_pattern(pset_pattern, x, y, 1, 1)
  end
end

local DEG2RAD = 3.1415926536 / 180.0

function screen.p_arc(idx, cx, cy, st, et, ra, rb, rot)
  if _Screen.paths == nil or idx < 0 or idx >= _Screen.NUMBER_OF_PATHS or _Screen.paths[idx] == vg.INVALID_HANDLE then
    return -1
  end
  local segments = ffi.new("VGubyte[3]")
  local pdata = ffi.new("VGfloat[7]")
  local dx, dy, cosr, sinr
  rot = rot or 0
  pdata[4] = rot
  st = st * DEG2RAD
  et = et * DEG2RAD
  rot = rot * DEG2RAD
  dx = ra * math.cos(st)
  dy = rb * math.sin(st)
  cosr = math.cos(rot)
  sinr = math.sin(rot)
  pdata[0] = cx + dx * cosr - dy * sinr
  pdata[1] = cy + dx * sinr + dy * cosr
  pdata[2] = ra
  pdata[3] = rb
  dx = ra * math.cos(et)
  dy = rb * math.sin(et)
  pdata[5] = cx + dx * cosr - dy * sinr
  pdata[6] = cy + dx * sinr + dy * cosr
  segments[0] = vg.MOVE_TO_ABS
  et = (et - st) / (2 * 3.1415926536)
  if et - math.floor(et) > 0.5 then
    segments[1] = vg.LCCWARC_TO_ABS
  else
    segments[1] = vg.SCCWARC_TO_ABS
  end
  segments[2] = vg.CLOSE_PATH
  vg.appendPathData(_Screen.paths[idx], 3, segments, pdata)
  return idx
end

function screen.arc(cx, cy, st, et, ra, rb, rot)
  local idx = _Screen.create_path()
  if idx < 0 then return false end
  if _Screen.p_arc(idx, cx, cy, st, et, ra, rb, rot) >= 0 then _Screen.draw_path(idx) end
  _Screen.invalidate_path(idx)
  return true
end

function screen.p_cubic(idx, x1, y1, x2, y2, x3, y3)
  if _Screen.paths == nil or idx < 0 or idx >= 1024 or _Screen.paths[idx] == vg.INVALID_HANDLE then
    return -1
  end
  local segment = ffi.new("VGubyte[1]")
  local pdata = ffi.new("VGfloat[6]")
  pdata[0] = x1
  pdata[1] = y1
  pdata[2] = x2
  pdata[3] = y2
  pdata[4] = x3
  pdata[5] = y3
  segment[0] = vg.CUBIC_TO_ABS;
  vg.appendPathData(_Screen.paths[idx], 1, segment, pdata)
  return idx
end

function screen.p_close(idx)
  if _Screen.paths == nil or idx < 0 or idx >= _Screen.NUMBER_OF_PATHS or _Screen.paths[idx] == vg.INVALID_HANDLE then
    return -1
  end
  local segment = ffi.new("VGubyte[1]")
  segment[0] = vg.CLOSE_PATH;
  vg.appendPathData(_Screen.paths[idx], 1, segment, nil)
  return idx
end

function screen.p_box(idx, x, y, width, height)
  if _Screen.paths == nil or idx < 0 or idx >= _Screen.NUMBER_OF_PATHS or _Screen.paths[idx] == vg.INVALID_HANDLE then
    return -1
  end
  if vg.uRect(_Screen.paths[idx], x, y, width, height) == 0 then
    return idx
  end
  return -2
end

function screen.box(x, y, width, height)
  local idx = _Screen.create_path()
  if idx < 0 then return false end
  if _Screen.p_box(idx, x, y, width, height) >= 0 then _Screen.draw_path(idx) end
  _Screen.invalidate_path(idx)
  return true
end

function screen.p_rbox(idx, x, y, width, height, rx, ry)
  if _Screen.paths == nil or idx < 0 or idx >= _Screen.NUMBER_OF_PATHS or _Screen.paths[idx] == vg.INVALID_HANDLE then
    return -1
  end
  ry = ry or rx
  if vg.uRoundRect(_Screen.paths[idx], x, y, width, height, rx * 2, ry * 2) == 0 then
    return idx
  end
  return -2
end

function screen.rbox(x, y, width, height, rx, ry)
  local idx = _Screen.create_path()
  if idx < 0 then return false end
  if _Screen.p_rbox(idx, x, y, width, height, rx, ry) >= 0 then _Screen.draw_path(idx) end
  _Screen.invalidate_path(idx)
  return true
end

function screen.p_circle(idx, x, y, rx, ry)
  if _Screen.paths == nil or idx < 0 or idx >= _Screen.NUMBER_OF_PATHS or _Screen.paths[idx] == vg.INVALID_HANDLE then
    return -1
  end
  ry = ry or rx
  if vg.uEllipse(_Screen.paths[idx], x, y, rx * 2, ry * 2) == 0 then
    return idx
  end
  return -2
end

function screen.circle(x, y, rx, ry)
  local idx = _Screen.create_path()
  if idx < 0 then return false end
  if _Screen.p_circle(idx, x, y, rx, ry) >= 0 then _Screen.draw_path(idx) end
  _Screen.invalidate_path(idx)
  return true
end

function screen.p_fan(idx, cx, cy, st, et, ra, rb, rot)
  if _Screen.paths == nil or idx < 0 or idx >= _Screen.NUMBER_OF_PATHS or _Screen.paths[idx] == vg.INVALID_HANDLE then
    return -1
  end
  rb = rb or ra
  rot = rot or 0.0
  local v = _Screen.p_moveto(idx, cx, cy)
  if v >= 0 then
    v = _Screen.p_arc(idx, cx, cy, st, et, ra, rb, rot)
    if v >= 0 then
      v = _Screen.p_close(idx)
      if v >= 0 then
        return idx
      end
    end
  end
  return -2
end

function screen.fan(cx, cy, st, et, ra, rb, rot)
  local idx = _Screen.create_path()
  if idx < 0 then return false end
  if _Screen.p_fan(idx, cx, cy, st, et, ra, rb, rot) >= 0 then _Screen.draw_path(idx) end
  _Screen.invalidate_path(idx)
  return true
end

function screen.put_pattern(p, x, y, width, height)
  vg.writePixels(p + width * (height - 1), -width * 4, vg.sRGBA_8888, x, y, width, height)
--  _Screen.set_redraw(x, y, width, height)
end

function screen.get_pattern(p, x, y, width, height)
  vg.readPixels(p + width * (height - 1), -width * 4, vg.sRGBA_8888, x, y, width, height)
end

function screen.patdef(num, width, height, tbl)
  num = math.floor(num)
  width = math.floor(width)
  height = math.floor(height)
  assert(num >= 0 and num < _Screen.NUMBER_OF_PATTERNS, "Arg #1 (patnum) must be in 0.." .. (_Screen.NUMBER_OF_PATTERNS - 1))
  assert(width > 0, "Arg #2 (width) must be a positive number")
  assert(height > 0, "Arg #3 (height) must be a positive number")
  assert(type(tbl) == "table", "Arg #4 must be a table")
  local i
  local len = width * height
  local len2 = _Screen.patterns[num].width * _Screen.patterns[num].height
  local ofs = _Screen.patterns[num].ofs
  if len2 > 0 then
    vg.destroyImage(_Screen.patterns[num].image)
    _Screen.patterns[num].image = vg.INVALID_HANDLE
  end
  if _Screen.patbuffer_used + (len - len2) > _Screen.patbuffer_size then
    error(string.format("Out of pattern memory; pattern size (%dx%d) is too large", width, height))
  end
  if num < _Screen.NUMBER_OF_PATTERNS - 1 and len ~= len2 then
    local ofs2 = _Screen.patterns[num + 1].ofs
    ffi.C.memmove(_Screen.patbuffer + (ofs + len), _Screen.patbuffer + ofs2, (_Screen.patbuffer_used - ofs2) * 4)
    for i = num + 1, _Screen.NUMBER_OF_PATTERNS - 1 do
      _Screen.patterns[i].ofs = _Screen.patterns[i].ofs + (len - len2)
    end
  end
  _Screen.patterns[num].width = width
  _Screen.patterns[num].height = height
  _Screen.patbuffer_used = _Screen.patbuffer_used + (len - len2)
  for i = 1, len do
    _Screen.patbuffer[ofs + i - 1] = tbl[i]
  end
  _Screen.patterns[num].image = vg.createImage(vg.sRGBA_8888, width, height, vg.IMAGE_QUALITY_FASTER)
  vg.imageSubData(_Screen.patterns[num].image, _Screen.patbuffer + ofs + (height - 1) * width, -width * 4, vg.sRGBA_8888, 0, 0, width, height)
end

function screen.patpng(num, pngfile)
  local image, bytes, w, h, bpp, ncol = png.readPNG(pngfile, 1)
  if image == nil then return end
  local t = {}
  local i = 0
  while i < bytes do
    local r = image[i]
    local g = image[i + 1]
    local b = image[i + 2]
    local a = image[i + 3]
    r = math.floor(r * a / 255)
    g = math.floor(g * a / 255)
    b = math.floor(b * a / 255)
    local n = a + 256 * (b + 256 * (g + 256 * r))
    t[i / 4 + 1] = n
    i = i + 4
  end
  _Screen.patdef(num, w, h, t)
end

function screen.patget(num)
  num = math.floor(num)
  assert(num >= 0 and num < _Screen.NUMBER_OF_PATTERNS, "Arg #1 (patnum) must be in 1.." .. (_Screen.NUMBER_OF_PATTERNS - 1))
  if _Screen.patterns[num].width == 0 then
    return nil
  end
  local t = {}
  local w = _Screen.patterns[num].width
  local h = _Screen.patterns[num].height
  local ofs = _Screen.patterns[num].ofs
  for i = 1, w * h do
    t[i] = _Screen.patbuffer[ofs + i - 1]
  end
  return w, h, t
end

function screen.patundef(num)
  num = math.floor(num)
  assert(num >= 0 and num < _Screen.NUMBER_OF_PATTERNS, "Arg #1 (patnum) must be in 1.." .. (_Screen.NUMBER_OF_PATTERNS - 1))
  local i, len, ofs
  len = _Screen.patterns[num].width * _Screen.patterns[num].height
  ofs = _Screen.patterns[num].ofs
  if len == 0 then return end
  ffi.C.memmove(_Screen.patbuffer + ofs, _Screen.patbuffer + ofs + len, (_Screen.patbuffer_used - (ofs + len)) * 4)
  for i = num + 1, _Screen.NUMBER_OF_PATTERNS - 1 do
    if _Screen.patterns[i].ofs > 0 then
      _Screen.patterns[i].ofs = _Screen.patterns[i].ofs - len
    end
  end
  _Screen.patterns[num].ofs = 0
  _Screen.patterns[num].width = 0
  _Screen.patterns[num].height = 0
  vg.destroyImage(_Screen.patterns[num].image)
  _Screen.patterns[num].image = vg.INVALID_HANDLE
end

--  TODO: eraseflag should be obsolete
--  p + ofs should be a pointer to a VGImage
function screen.patwrite(image, x1, y1, mask)
  local save_paint
  vg.seti(vg.MATRIX_MODE, vg.MATRIX_IMAGE_USER_TO_SURFACE)
  vg.loadIdentity()
  vg.translate(math.floor(x1), math.floor(y1))
  if mask then
    save_paint = vg.getPaint(vg.FILL_PATH)
    if _Screen.mask_color == nil then
      _Screen.mask_color = vg.createPaint()
      vg.setParameteri(_Screen.mask_color, vg.PAINT_TYPE, vg.PAINT_TYPE_COLOR)
    end
    _Screen.tempcols[0] = bit.band(bit.rshift(mask, 24), 255) / 255.0
    _Screen.tempcols[1] = bit.band(bit.rshift(mask, 16), 255) / 255.0
    _Screen.tempcols[2] = bit.band(bit.rshift(mask, 8), 255) / 255.0
    _Screen.tempcols[3] = bit.band(mask, 255) / 255.0
    vg.setParameterfv(_Screen.mask_color, vg.PAINT_COLOR, 4, _Screen.tempcols)
    vg.setPaint(_Screen.mask_color, vg.FILL_PATH)
    vg.seti(vg.IMAGE_MODE, vg.DRAW_IMAGE_MULTIPLY)
  else
    vg.seti(vg.IMAGE_MODE, vg.DRAW_IMAGE_NORMAL)
  end
--    vg.seti(vg.BLEND_MODE, vg.BLEND_DST_OVER)
  vg.drawImage(image)
  vg.loadIdentity()
  if mask then
    vg.setPaint(save_paint, vg.FILL_PATH)
  end
  return true
end

function screen.patdraw(n, x, y, mask)
  n = math.floor(n)
--  x = math.floor(x)
--  y = math.floor(y)
--  if mask then
--    mask = math.floor(mask)
--  else
--    mask = 0xffffffff
--  end
  if n < 0 or n >= _Screen.NUMBER_OF_PATTERNS then
    error("Arg #1 (patnum) must be in 0.." .. (_Screen.NUMBER_OF_PATTERNS - 1))
  end
  if _Screen.patterns[n].width == 0 then
    error("Pattern " .. n .. " is undefined")
  end
  if false and mask then
    --  Workaround (VG_DRAW_IMAGE_MULTIPLY does not seem to work)
    local w = _Screen.patterns[n].width
    local h = _Screen.patterns[n].height
    local ofs = _Screen.patterns[n].ofs
    local pos = _Screen.patbuffer_used
    if _Screen.patbuffer_size - pos >= w * h then
      --  Create a masked image and draw it
      local image = vg.createImage(vg.sRGBA_8888, w, h, vg.IMAGE_QUALITY_FASTER)
      local mr, mg, mb, ma
      mask = math.floor(mask)
      ma = bit.band(mask, 255) / 255.0
      mr = bit.band(bit.rshift(mask, 24), 255) / 255.0 * ma
      mg = bit.band(bit.rshift(mask, 16), 255) / 255.0 * ma
      mb = bit.band(bit.rshift(mask, 8), 255) / 255.0 * ma
      for i = 0, w * h - 1 do
        local r, g, b, a, c
        c = _Screen.patbuffer[ofs + i]
        r = math.floor(bit.band(bit.rshift(c, 24), 255) * mr)
        g = math.floor(bit.band(bit.rshift(c, 16), 255) * mg)
        b = math.floor(bit.band(bit.rshift(c, 8), 255) * mb)
        a = c % 256
        c = bit.lshift(r, 24) + bit.lshift(g, 16) + bit.lshift(b, 8) + a
        _Screen.patbuffer[pos + i] = c
      end
      vg.imageSubData(image, _Screen.patbuffer + pos + (h - 1) * w, -w * 4, vg.sRGBA_8888, 0, 0, w, h)
      _Screen.patwrite(image, x, y)
      vg.destroyImage(image)
      return
    end
  end
  _Screen.patwrite(_Screen.patterns[n].image, x, y, mask)
end

function screen.gputs(x, y, s)
  local i, j, k, n
  if _Screen.fonttemp == nil then
    _Screen.fonttemp = ffi.new("uint32_t[256]")
  end
  if _Screen.fontimage8 == nil then
    _Screen.fontimage8 = vg.createImage(vg.sRGBA_8888, 8, 16, vg.IMAGE_QUALITY_FASTER)
  end

  for i = 1, s:len() do
    local c = s:byte(i)
    --  TODO: support zenkaku characters
    if c >= 0 and c < 128 then
      for j = 0, 15 do
        n = _Screen.fontdata[c * 16 + j]
        for k = 0, 7 do
          local col
          if bit.band(n, 1) ~= 0 then
            col = _Screen.text_color or _Screen.rgb(1, 1, 1)
          else
            col = _Screen.text_bgcolor or 0
          end
          _Screen.fonttemp[j * 8 + k] = col
          n = bit.rshift(n, 1)
        end
      end
      vg.imageSubData(_Screen.fontimage8, _Screen.fonttemp + 15 * 8, -32, vg.sRGBA_8888, 0, 0, 8, 16)
      _Screen.patwrite(_Screen.fontimage8, x, y)
    end
    x = x + 8
  end
end

function screen.clearbox(x, y, width, height, rgba)
  rgba = rgba or _Screen.clear_color
  _Screen.tempcols[0] = bit.band(bit.rshift(rgba, 24), 255) / 255.0
  _Screen.tempcols[1] = bit.band(bit.rshift(rgba, 16), 255) / 255.0
  _Screen.tempcols[2] = bit.band(bit.rshift(rgba, 8), 255) / 255.0
  _Screen.tempcols[3] = bit.band(rgba, 255) / 255.0
  vg.setfv(vg.CLEAR_COLOR, 4, _Screen.tempcols)
  vg.clear(x, y, width, height)
end

function screen.cls(rgba)
  _Screen.clearbox(0, 0, _Screen.width, _Screen.height, rgba)
end

return screen
