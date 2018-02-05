-- ---------------------------------------------
-- vg.lua        2017/06/18
--   Copyright (c) 2017 Toshi Nagata
--   released under the MIT open source license.
-- ---------------------------------------------

local ffi = require("ffi")
local util = require("util")

if libgles2 == nil then
  require "egl"    -- load brcmEGL and brcmGLESv2
end

ffi.cdef[[
typedef float            VGfloat;
typedef int8_t           VGbyte;
typedef uint8_t          VGubyte;
typedef int16_t          VGshort;
typedef int32_t          VGint;
typedef uint32_t         VGuint;
typedef uint32_t         VGbitfield;
typedef VGuint           VGHandle;
typedef VGHandle         VGPath;
typedef VGHandle         VGImage;
typedef VGHandle         VGMaskLayer;
typedef VGHandle         VGFont;
typedef VGHandle         VGPaint;
typedef VGuint           VGboolean;
typedef unsigned int     VGErrorCode;
typedef unsigned int     VGParamType;
typedef unsigned int     VGRenderingQuality;
typedef unsigned int     VGPixelLayout;
typedef unsigned int     VGMatrixMode;
typedef unsigned int     VGMaskOperation;
typedef unsigned int     VGPathDatatype;
typedef unsigned int     VGPathAbsRel;
typedef unsigned int     VGPathSegment;
typedef unsigned int     VGPathCommand;
typedef unsigned int     VGPathCapabilities;
typedef unsigned int     VGPathParamType;
typedef unsigned int     VGCapStyle;
typedef unsigned int     VGJoinStyle;
typedef unsigned int     VGFillRule;
typedef unsigned int     VGPaintMode;
typedef unsigned int     VGPaintParamType;
typedef unsigned int     VGPaintType;
typedef unsigned int     VGColorRampSpreadMode;
typedef unsigned int     VGTilingMode;
typedef unsigned int     VGImageFormat;
typedef unsigned int     VGImageQuality;
typedef unsigned int     VGImageParamType;
typedef unsigned int     VGImageMode;
typedef unsigned int     VGImageChannel;
typedef unsigned int     VGBlendMode;
typedef unsigned int     VGFontParamType;
typedef unsigned int     VGHardwareQueryType;
typedef unsigned int     VGHardwareQueryResult;
typedef unsigned int     VGStringID;
typedef unsigned int     VGUErrorCode;

VGErrorCode vgGetError(void);

void vgFlush(void);
void vgFinish(void);

void vgSetf (VGParamType type, VGfloat value);
void vgSeti (VGParamType type, VGint value);
void vgSetfv(VGParamType type, VGint count, const VGfloat * values);
void vgSetiv(VGParamType type, VGint count, const VGint * values);

VGfloat vgGetf(VGParamType type);
VGint vgGeti(VGParamType type);
VGint vgGetVectorSize(VGParamType type);
void vgGetfv(VGParamType type, VGint count, VGfloat * values);
void vgGetiv(VGParamType type, VGint count, VGint * values);

void vgSetParameterf(VGHandle object, VGint paramType, VGfloat value);
void vgSetParameteri(VGHandle object, VGint paramType, VGint value);
void vgSetParameterfv(VGHandle object, VGint paramType, VGint count, const VGfloat * values);
void vgSetParameteriv(VGHandle object, VGint paramType, VGint count, const VGint * values);

VGfloat vgGetParameterf(VGHandle object, VGint paramType);
VGint vgGetParameteri(VGHandle object, VGint paramType);
VGint vgGetParameterVectorSize(VGHandle object, VGint paramType);
void vgGetParameterfv(VGHandle object, VGint paramType, VGint count, VGfloat * values);
void vgGetParameteriv(VGHandle object, VGint paramType, VGint count, VGint * values);

void vgLoadIdentity(void);
void vgLoadMatrix(const VGfloat * m);
void vgGetMatrix(VGfloat * m);
void vgMultMatrix(const VGfloat * m);
void vgTranslate(VGfloat tx, VGfloat ty);
void vgScale(VGfloat sx, VGfloat sy);
void vgShear(VGfloat shx, VGfloat shy);
void vgRotate(VGfloat angle);

void vgMask(VGHandle mask, VGMaskOperation operation, VGint x, VGint y, VGint width, VGint height);
void vgRenderToMask(VGPath path, VGbitfield paintModes, VGMaskOperation operation);
VGMaskLayer vgCreateMaskLayer(VGint width, VGint height);
void vgDestroyMaskLayer(VGMaskLayer maskLayer);
void vgFillMaskLayer(VGMaskLayer maskLayer, VGint x, VGint y, VGint width, VGint height, VGfloat value);
void vgCopyMask(VGMaskLayer maskLayer, VGint dx, VGint dy, VGint sx, VGint sy, VGint width, VGint height);
void vgClear(VGint x, VGint y, VGint width, VGint height);

VGPath vgCreatePath(VGint pathFormat, VGPathDatatype datatype, VGfloat scale, VGfloat bias, VGint segmentCapacityHint, VGint coordCapacityHint, VGbitfield capabilities);

void vgClearPath(VGPath path, VGbitfield capabilities);
void vgDestroyPath(VGPath path);
void vgRemovePathCapabilities(VGPath path, VGbitfield capabilities);
VGbitfield vgGetPathCapabilities(VGPath path);
void vgAppendPath(VGPath dstPath, VGPath srcPath);
void vgAppendPathData(VGPath dstPath, VGint numSegments, const VGubyte * pathSegments, const void * pathData);
void vgModifyPathCoords(VGPath dstPath, VGint startIndex, VGint numSegments, const void * pathData);
void vgTransformPath(VGPath dstPath, VGPath srcPath);
VGboolean vgInterpolatePath(VGPath dstPath, VGPath startPath, VGPath endPath, VGfloat amount);
VGfloat vgPathLength(VGPath path, VGint startSegment, VGint numSegments);
void vgPointAlongPath(VGPath path, VGint startSegment, VGint numSegments, VGfloat distance, VGfloat * x, VGfloat * y, VGfloat * tangentX, VGfloat * tangentY);
void vgPathBounds(VGPath path, VGfloat * minX, VGfloat * minY, VGfloat * width, VGfloat * height);
void vgPathTransformedBounds(VGPath path, VGfloat * minX, VGfloat * minY, VGfloat * width, VGfloat * height);
void vgDrawPath(VGPath path, VGbitfield paintModes);

VGPaint vgCreatePaint(void);
void vgDestroyPaint(VGPaint paint);
void vgSetPaint(VGPaint paint, VGbitfield paintModes);
VGPaint vgGetPaint(VGPaintMode paintMode);
void vgSetColor(VGPaint paint, VGuint rgba);
VGuint vgGetColor(VGPaint paint);
void vgPaintPattern(VGPaint paint, VGImage pattern);
VGImage vgCreateImage(VGImageFormat format, VGint width, VGint height, VGbitfield allowedQuality);
void vgDestroyImage(VGImage image);
void vgClearImage(VGImage image, VGint x, VGint y, VGint width, VGint height);
void vgImageSubData(VGImage image, const void * data, VGint dataStride, VGImageFormat dataFormat, VGint x, VGint y, VGint width, VGint height);
void vgGetImageSubData(VGImage image, void * data, VGint dataStride, VGImageFormat dataFormat, VGint x, VGint y, VGint width, VGint height);
VGImage vgChildImage(VGImage parent, VGint x, VGint y, VGint width, VGint height);
VGImage vgGetParent(VGImage image);
void vgCopyImage(VGImage dst, VGint dx, VGint dy, VGImage src, VGint sx, VGint sy, VGint width, VGint height, VGboolean dither);
void vgDrawImage(VGImage image);
void vgSetPixels(VGint dx, VGint dy, VGImage src, VGint sx, VGint sy, VGint width, VGint height);
void vgWritePixels(const void * data, VGint dataStride, VGImageFormat dataFormat, VGint dx, VGint dy, VGint width, VGint height);
void vgGetPixels(VGImage dst, VGint dx, VGint dy, VGint sx, VGint sy, VGint width, VGint height);
void vgReadPixels(void * data, VGint dataStride, VGImageFormat dataFormat, VGint sx, VGint sy, VGint width, VGint height);
void vgCopyPixels(VGint dx, VGint dy, VGint sx, VGint sy, VGint width, VGint height);

VGFont vgCreateFont(VGint glyphCapacityHint);
void vgDestroyFont(VGFont font);
void vgSetGlyphToPath(VGFont font, VGuint glyphIndex, VGPath path, VGboolean isHinted, VGfloat glyphOrigin [2], VGfloat escapement[2]);
void vgSetGlyphToImage(VGFont font, VGuint glyphIndex, VGImage image, VGfloat glyphOrigin [2], VGfloat escapement[2]);
void vgClearGlyph(VGFont font,VGuint glyphIndex);
void vgDrawGlyph(VGFont font, VGuint glyphIndex, VGbitfield paintModes, VGboolean allowAutoHinting);
void vgDrawGlyphs(VGFont font, VGint glyphCount, const VGuint *glyphIndices, const VGfloat *adjustments_x, const VGfloat *adjustments_y, VGbitfield paintModes, VGboolean allowAutoHinting);
void vgColorMatrix(VGImage dst, VGImage src, const VGfloat * matrix);
void vgConvolve(VGImage dst, VGImage src, VGint kernelWidth, VGint kernelHeight, VGint shiftX, VGint shiftY, const VGshort * kernel, VGfloat scale, VGfloat bias, VGTilingMode tilingMode);
void vgSeparableConvolve(VGImage dst, VGImage src, VGint kernelWidth, VGint kernelHeight, VGint shiftX, VGint shiftY, const VGshort * kernelX, const VGshort * kernelY, VGfloat scale, VGfloat bias, VGTilingMode tilingMode);
void vgGaussianBlur(VGImage dst, VGImage src, VGfloat stdDeviationX, VGfloat stdDeviationY, VGTilingMode tilingMode);
void vgLookup(VGImage dst, VGImage src, const VGubyte * redLUT, const VGubyte * greenLUT, const VGubyte * blueLUT, const VGubyte * alphaLUT, VGboolean outputLinear, VGboolean outputPremultiplied);
void vgLookupSingle(VGImage dst, VGImage src, const VGuint * lookupTable, VGImageChannel sourceChannel, VGboolean outputLinear, VGboolean outputPremultiplied);
VGHardwareQueryResult vgHardwareQuery(VGHardwareQueryType key, VGint setting);
const VGubyte * vgGetString(VGStringID name);

VGUErrorCode vguRect(VGPath path, VGfloat x, VGfloat y, VGfloat width, VGfloat height);
VGUErrorCode vguRoundRect(VGPath path, VGfloat x, VGfloat y, VGfloat width, VGfloat height, VGfloat argWidth, VGfloat arcHeight);
VGUErrorCode vguEllipse(VGPath path, VGfloat cx, VGfloat cy, VGfloat width, VGfloat height);

]]

local vg = {
  
  NO_ERROR                                 = 0,
  BAD_HANDLE_ERROR                         = 0x1000,
  ILLEGAL_ARGUMENT_ERROR                   = 0x1001,
  OUT_OF_MEMORY_ERROR                      = 0x1002,
  PATH_CAPABILITY_ERROR                    = 0x1003,
  UNSUPPORTED_IMAGE_FORMAT_ERROR           = 0x1004,
  UNSUPPORTED_PATH_FORMAT_ERROR            = 0x1005,
  IMAGE_IN_USE_ERROR                       = 0x1006,
  NO_CONTEXT_ERROR                         = 0x1007,
  
  INVALID_HANDLE                           = 0,
  
  MATRIX_MODE                              = 0x1100,
  FILL_RULE                                = 0x1101,
  IMAGE_QUALITY                            = 0x1102,
  RENDERING_QUALITY                        = 0x1103,
  BLEND_MODE                               = 0x1104,
  IMAGE_MODE                               = 0x1105,

  SCISSOR_RECTS                            = 0x1106,
  
  COLOR_TRANSFORM                          = 0x1170,
  COLOR_TRANSFORM_VALUES                   = 0x1171,

  STROKE_LINE_WIDTH                        = 0x1110,
  STROKE_CAP_STYLE                         = 0x1111,
  STROKE_JOIN_STYLE                        = 0x1112,
  STROKE_MITER_LIMIT                       = 0x1113,
  STROKE_DASH_PATTERN                      = 0x1114,
  STROKE_DASH_PHASE                        = 0x1115,
  STROKE_DASH_PHASE_RESET                  = 0x1116,
  
  TILE_FILL_COLOR                          = 0x1120,
  
  CLEAR_COLOR                              = 0x1121,
  
  GLYPH_ORIGIN                             = 0x1122,
  
  MASKING                                  = 0x1130,
  SCISSORING                               = 0x1131,
  
  PIXEL_LAYOUT                             = 0x1140,
  SCREEN_LAYOUT                            = 0x1141,
  
  FILTER_FORMAT_LINEAR                     = 0x1150,
  FILTER_FORMAT_PREMULTIPLIED              = 0x1151,
  
  FILTER_CHANNEL_MASK                      = 0x1152,
  
  MAX_SCISSOR_RECTS                        = 0x1160,
  MAX_DASH_COUNT                           = 0x1161,
  MAX_KERNEL_SIZE                          = 0x1162,
  MAX_SEPARABLE_KERNEL_SIZE                = 0x1163,
  MAX_COLOR_RAMP_STOPS                     = 0x1164,
  MAX_IMAGE_WIDTH                          = 0x1165,
  MAX_IMAGE_HEIGHT                         = 0x1166,
  MAX_IMAGE_PIXELS                         = 0x1167,
  MAX_IMAGE_BYTES                          = 0x1168,
  MAX_FLOAT                                = 0x1169,
  MAX_GAUSSIAN_STD_DEVIATION               = 0x116A,
  
  RENDERING_QUALITY_NONANTIALIASED         = 0x1200,
  RENDERING_QUALITY_FASTER                 = 0x1201,
  RENDERING_QUALITY_BETTER                 = 0x1202,
  
  PIXEL_LAYOUT_UNKNOWN                     = 0x1300,
  PIXEL_LAYOUT_RGB_VERTICAL                = 0x1301,
  PIXEL_LAYOUT_BGR_VERTICAL                = 0x1302,
  PIXEL_LAYOUT_RGB_HORIZONTAL              = 0x1303,
  PIXEL_LAYOUT_BGR_HORIZONTAL              = 0x1304,
  
  MATRIX_PATH_USER_TO_SURFACE              = 0x1400,
  MATRIX_IMAGE_USER_TO_SURFACE             = 0x1401,
  MATRIX_FILL_PAINT_TO_USER                = 0x1402,
  MATRIX_STROKE_PAINT_TO_USER              = 0x1403,
  MATRIX_GLYPH_USER_TO_SURFACE             = 0x1404,
  
  CLEAR_MASK                               = 0x1500,
  FILL_MASK                                = 0x1501,
  SET_MASK                                 = 0x1502,
  UNION_MASK                               = 0x1503,
  INTERSECT_MASK                           = 0x1504,
  SUBTRACT_MASK                            = 0x1505,
  
  PATH_FORMAT_STANDARD                     =  0,
  
  PATH_DATATYPE_S_8                        =  0,
  PATH_DATATYPE_S_16                       =  1,
  PATH_DATATYPE_S_32                       =  2,
  PATH_DATATYPE_F                          =  3,
  
  ABSOLUTE                                 = 0,
  RELATIVE                                 = 1,
  
  CLOSE_PATH                               = 0,
  MOVE_TO                                  = 2,
  LINE_TO                                  = 4,
  HLINE_TO                                 = 6,
  VLINE_TO                                 = 8,
  QUAD_TO                                  = 10,
  CUBIC_TO                                 = 12,
  SQUAD_TO                                 = 14,
  SCUBIC_TO                                = 16,
  SCCWARC_TO                               = 18,
  SCWARC_TO                                = 20,
  LCCWARC_TO                               = 22,
  LCWARC_TO                                = 24,
  
  SEGMENT_MASK                             = 0x1e,
  
  MOVE_TO_ABS                              = 2,
  MOVE_TO_REL                              = 3,
  LINE_TO_ABS                              = 4,
  LINE_TO_REL                              = 5,
  HLINE_TO_ABS                             = 6,
  HLINE_TO_REL                             = 7,
  VLINE_TO_ABS                             = 8,
  VLINE_TO_REL                             = 9,
  QUAD_TO_ABS                              = 10,
  QUAD_TO_REL                              = 11,
  CUBIC_TO_ABS                             = 12,
  CUBIC_TO_REL                             = 13,
  SQUAD_TO_ABS                             = 14,
  SQUAD_TO_REL                             = 15,
  SCUBIC_TO_ABS                            = 16,
  SCUBIC_TO_REL                            = 17,
  SCCWARC_TO_ABS                           = 18,
  SCCWARC_TO_REL                           = 19,
  SCWARC_TO_ABS                            = 20,
  SCWARC_TO_REL                            = 21,
  LCCWARC_TO_ABS                           = 22,
  LCCWARC_TO_REL                           = 23,
  LCWARC_TO_ABS                            = 24,
  LCWARC_TO_REL                            = 25,
  
  PATH_CAPABILITY_APPEND_FROM              = 1,
  PATH_CAPABILITY_APPEND_TO                = 2,
  PATH_CAPABILITY_MODIFY                   = 4,
  PATH_CAPABILITY_TRANSFORM_FROM           = 8,
  PATH_CAPABILITY_TRANSFORM_TO             = 16,
  PATH_CAPABILITY_INTERPOLATE_FROM         = 32,
  PATH_CAPABILITY_INTERPOLATE_TO           = 64,
  PATH_CAPABILITY_PATH_LENGTH              = 128,
  PATH_CAPABILITY_POINT_ALONG_PATH         = 256,
  PATH_CAPABILITY_TANGENT_ALONG_PATH       = 512,
  PATH_CAPABILITY_PATH_BOUNDS              = 1024,
  PATH_CAPABILITY_PATH_TRANSFORMED_BOUNDS  = 2048,
  PATH_CAPABILITY_ALL                      = 4095,
  
  PATH_FORMAT                              = 0x1600,
  PATH_DATATYPE                            = 0x1601,
  PATH_SCALE                               = 0x1602,
  PATH_BIAS                                = 0x1603,
  PATH_NUM_SEGMENTS                        = 0x1604,
  PATH_NUM_COORDS                          = 0x1605,
  
  CAP_BUTT                                 = 0x1700,
  CAP_ROUND                                = 0x1701,
  CAP_SQUARE                               = 0x1702,
  
  JOIN_MITER                               = 0x1800,
  JOIN_ROUND                               = 0x1801,
  JOIN_BEVEL                               = 0x1802,
  
  EVEN_ODD                                 = 0x1900,
  NON_ZERO                                 = 0x1901,

  STROKE_PATH                              = 1,
  FILL_PATH                                = 2,
  
  PAINT_TYPE                               = 0x1A00,
  PAINT_COLOR                              = 0x1A01,
  PAINT_COLOR_RAMP_SPREAD_MODE             = 0x1A02,
  PAINT_COLOR_RAMP_PREMULTIPLIED           = 0x1A07,
  PAINT_COLOR_RAMP_STOPS                   = 0x1A03,
  
  PAINT_LINEAR_GRADIENT                    = 0x1A04,
  
  PAINT_RADIAL_GRADIENT                    = 0x1A05,
  
  PAINT_PATTERN_TILING_MODE                = 0x1A06,
  
  PAINT_TYPE_COLOR                         = 0x1B00,
  PAINT_TYPE_LINEAR_GRADIENT               = 0x1B01,
  PAINT_TYPE_RADIAL_GRADIENT               = 0x1B02,
  PAINT_TYPE_PATTERN                       = 0x1B03,
  
  COLOR_RAMP_SPREAD_PAD                    = 0x1C00,
  COLOR_RAMP_SPREAD_REPEAT                 = 0x1C01,
  COLOR_RAMP_SPREAD_REFLECT                = 0x1C02,
  
  TILE_FILL                                = 0x1D00,
  TILE_PAD                                 = 0x1D01,
  TILE_REPEAT                              = 0x1D02,
  TILE_REFLECT                             = 0x1D03,
  
  sRGBX_8888                               =  0,
  sRGBA_8888                               =  1,
  sRGBA_8888_PRE                           =  2,
  sRGB_565                                 =  3,
  sRGBA_5551                               =  4,
  sRGBA_4444                               =  5,
  sL_8                                     =  6,
  lRGBX_8888                               =  7,
  lRGBA_8888                               =  8,
  lRGBA_8888_PRE                           =  9,
  lL_8                                     = 10,
  A_8                                      = 11,
  BW_1                                     = 12,
  A_1                                      = 13,
  A_4                                      = 14,
  
  sXRGB_8888                               =  0x40,
  sARGB_8888                               =  0x41,
  sARGB_8888_PRE                           =  0x42,
  sARGB_1555                               =  0x44,
  sARGB_4444                               =  0x45,
  lXRGB_8888                               =  0x47,
  lARGB_8888                               =  0x48,
  lARGB_8888_PRE                           =  0x49,
  
  sBGRX_8888                               =  0x80,
  sBGRA_8888                               =  0x81,
  sBGRA_8888_PRE                           =  0x82,
  sBGR_565                                 =  0x83,
  sBGRA_5551                               =  0x84,
  sBGRA_4444                               =  0x85,
  lBGRX_8888                               =  0x87,
  lBGRA_8888                               =  0x88,
  lBGRA_8888_PRE                           =  0x89,

  sXBGR_8888                               =  0xc0,
  sABGR_8888                               =  0xc1,
  sABGR_8888_PRE                           =  0xc2,
  sABGR_1555                               =  0xc4,
  sABGR_4444                               =  0xc5,
  lXBGR_8888                               =  0xc7,
  lABGR_8888                               =  0xc8,
  lABGR_8888_PRE                           =  0xc9,
  
  IMAGE_QUALITY_NONANTIALIASED             = 1,
  IMAGE_QUALITY_FASTER                     = 2,
  IMAGE_QUALITY_BETTER                     = 4,
  
  IMAGE_FORMAT                             = 0x1E00,
  IMAGE_WIDTH                              = 0x1E01,
  IMAGE_HEIGHT                             = 0x1E02,
  
  DRAW_IMAGE_NORMAL                        = 0x1F00,
  DRAW_IMAGE_MULTIPLY                      = 0x1F01,
  DRAW_IMAGE_STENCIL                       = 0x1F02,
  
  RED                                      = 8,
  GREEN                                    = 4,
  BLUE                                     = 2,
  ALPHA                                    = 1,
  
  BLEND_SRC                                = 0x2000,
  BLEND_SRC_OVER                           = 0x2001,
  BLEND_DST_OVER                           = 0x2002,
  BLEND_SRC_IN                             = 0x2003,
  BLEND_DST_IN                             = 0x2004,
  BLEND_MULTIPLY                           = 0x2005,
  BLEND_SCREEN                             = 0x2006,
  BLEND_DARKEN                             = 0x2007,
  BLEND_LIGHTEN                            = 0x2008,
  BLEND_ADDITIVE                           = 0x2009,
  
  FONT_NUM_GLYPHS                          = 0x2F00,
  
  IMAGE_FORMAT_QUERY                       = 0x2100,
  PATH_DATATYPE_QUERY                      = 0x2101,
  
  HARDWARE_ACCELERATED                     = 0x2200,
  HARDWARE_UNACCELERATED                   = 0x2201,
  
  VENDOR                                   = 0x2300,
  RENDERER                                 = 0x2301,
  VERSION                                  = 0x2302,
  EXTENSIONS                               = 0x2303,

  getError = libgles2.vgGetError,
  flush = libgles2.vgFlush,
  finish = libgles2.vgFinish,

  setf = libgles2.vgSetf,
  seti = libgles2.vgSeti,
  setfv = libgles2.vgSetfv,
  setiv = libgles2.vgSetiv,

  getf = libgles2.vgGetf,
  geti = libgles2.vgGeti,
  getVectorSize = libgles2.vgGetVectorSize,
  getfv = libgles2.vgGetfv,
  getiv = libgles2.vgGetiv,

  setParameterf = libgles2.vgSetParameterf,
  setParameteri = libgles2.vgSetParameteri,
  setParameterfv = libgles2.vgSetParameterfv,
  setParameteriv = libgles2.vgSetParameteriv,

  getParameterf = libgles2.vgGetParameterf,
  getParameteri = libgles2.vgGetParameteri,
  getParameterVectorSize = libgles2.vgGetParameterVectorSize,
  getParameterfv = libgles2.vgGetParameterfv,
  getParameteriv = libgles2.vgGetParameteriv,

  loadIdentity = libgles2.vgLoadIdentity,
  loadMatrix = libgles2.vgLoadMatrix,
  getMatrix = libgles2.vgGetMatrix,
  multMatrix = libgles2.vgMultMatrix,
  translate = libgles2.vgTranslate,
  scale = libgles2.vgScale,
  shear = libgles2.vgShear,
  rotate = libgles2.vgRotate,

  mask = libgles2.vgMask,
  renderToMask = libgles2.vgRenderToMask,
  createMaskLayer = libgles2.vgCreateMaskLayer,
  destroyMaskLayer = libgles2.vgDestroyMaskLayer,
  fillMaskLayer = libgles2.vgFillMaskLayer,
  copyMask = libgles2.vgCopyMask,
  clear = libgles2.vgClear,

  createPath = libgles2.vgCreatePath,

  clearPath = libgles2.vgClearPath,
  destroyPath = libgles2.vgDestroyPath,
  removePathCapabilities = libgles2.vgRemovePathCapabilities,
  getPathCapabilities = libgles2.vgGetPathCapabilities,
  appendPath = libgles2.vgAppendPath,
  appendPathData = libgles2.vgAppendPathData,
  modifyPathCoords = libgles2.vgModifyPathCoords,
  transformPath = libgles2.vgTransformPath,
  interpolatePath = libgles2.vgInterpolatePath,
  pathLength = libgles2.vgPathLength,
  pointAlongPath = libgles2.vgPointAlongPath,
  pathBounds = libgles2.vgPathBounds,
  pathTransformedBounds = libgles2.vgPathTransformedBounds,
  drawPath = libgles2.vgDrawPath,

  createPaint = libgles2.vgCreatePaint,
  destroyPaint = libgles2.vgDestroyPaint,
  setPaint = libgles2.vgSetPaint,
  getPaint = libgles2.vgGetPaint,
  setColor = libgles2.vgSetColor,
  getColor = libgles2.vgGetColor,
  paintPattern = libgles2.vgPaintPattern,
  createImage = libgles2.vgCreateImage,
  destroyImage = libgles2.vgDestroyImage,
  clearImage = libgles2.vgClearImage,
  imageSubData = libgles2.vgImageSubData,
  getImageSubData = libgles2.vgGetImageSubData,
  childImage = libgles2.vgChildImage,
  getParent = libgles2.vgGetParent,
  copyImage = libgles2.vgCopyImage,
  drawImage = libgles2.vgDrawImage,
  setPixels = libgles2.vgSetPixels,
  writePixels = libgles2.vgWritePixels,
  getPixels = libgles2.vgGetPixels,
  readPixels = libgles2.vgReadPixels,
  copyPixels = libgles2.vgCopyPixels,

  createFont = libgles2.vgCreateFont,
  destroyFont = libgles2.vgDestroyFont,
  setGlyphToPath = libgles2.vgSetGlyphToPath,
  setGlyphToImage = libgles2.vgSetGlyphToImage,
  clearGlyph = libgles2.vgClearGlyph,
  drawGlyph = libgles2.vgDrawGlyph,
  drawGlyphs = libgles2.vgDrawGlyphs,
  colorMatrix = libgles2.vgColorMatrix,
  convolve = libgles2.vgConvolve,
  separableConvolve = libgles2.vgSeparableConvolve,
  gaussianBlur = libgles2.vgGaussianBlur,
  lookup = libgles2.vgLookup,
  lookupSingle = libgles2.vgLookupSingle,
  hardwareQuery = libgles2.vgHardwareQuery,
  getString = libgles2.vgGetString,
  
  uRect = libgles2.vguRect,
  uRoundRect = libgles2.vguRoundRect,
  uEllipse = libgles2.vguEllipse
}

function vg.checkError(message)
  local err = vg.getError()
  if (err ~= 0) then
    util.printf("%s : VG Error %d\n", err)
  end
end

return vg
