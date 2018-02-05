-- ---------------------------------------------
--   mixer.lua       2017/08/09
--   Copyright (c) 2017 Toshi Nagata
--   released under the MIT open source license.
-- ---------------------------------------------

local ffi = require "ffi"
local bit = require "bit"
local util = require "util"
local ctl = require "ctl"

local sdl = require "sdl"

libSDLmixer = ffi.load("libSDL_mixer-1.2.so.0")

ffi.cdef[[
  typedef struct Mix_Music Mix_Music;
  typedef struct Mix_Chunk Mix_Chunk;
  typedef uint32_t Mix_MusicType;
  typedef uint32_t Mix_Fading;
  
  int Mix_Init(int flags);
  void Mix_Quit(void);

  int Mix_OpenAudio(int frequency, uint16_t format, int channels, int chunksize);
  int Mix_AllocateChannels(int numchans);
  int Mix_QuerySpec(int *frequency,uint16_t *format,int *channels);

  Mix_Chunk * Mix_LoadWAV_RW(SDL_RWops *src, int freesrc);
  Mix_Music * Mix_LoadMUS(const char *file);
  Mix_Music * Mix_LoadMUS_RW(SDL_RWops *rw);
  Mix_Music * Mix_LoadMUSType_RW(SDL_RWops *rw, Mix_MusicType type, int freesrc);
  Mix_Chunk * Mix_QuickLoad_WAV(uint8_t *mem);
  Mix_Chunk * Mix_QuickLoad_RAW(uint8_t *mem, uint32_t len);
  void Mix_FreeChunk(Mix_Chunk *chunk);
  void Mix_FreeMusic(Mix_Music *music);
  
  int Mix_GetNumChunkDecoders(void);
  const char * Mix_GetChunkDecoder(int index);
  int Mix_GetNumMusicDecoders(void);
  const char * Mix_GetMusicDecoder(int index);
  Mix_MusicType Mix_GetMusicType(const Mix_Music *music);
  void Mix_SetPostMix(void (*mix_func)
                             (void *udata, uint8_t *stream, int len), void *arg);
  void Mix_HookMusic(void (*mix_func)
                          (void *udata, uint8_t *stream, int len), void *arg);
  void Mix_HookMusicFinished(void (*music_finished)(void));
  void * Mix_GetMusicHookData(void);
  void Mix_ChannelFinished(void (*channel_finished)(int channel));
  
  typedef void (*Mix_EffectFunc_t)(int chan, void *stream, int len, void *udata);
  typedef void (*Mix_EffectDone_t)(int chan, void *udata);
  
  int Mix_RegisterEffect(int chan, Mix_EffectFunc_t f, Mix_EffectDone_t d, void *arg);
  int Mix_UnregisterEffect(int channel, Mix_EffectFunc_t f);
  int Mix_UnregisterAllEffects(int channel);

  int Mix_SetPanning(int channel, uint8_t left, uint8_t right);
  int Mix_SetPosition(int channel, int16_t angle, uint8_t distance);
  int Mix_SetDistance(int channel, uint8_t distance);
  int Mix_SetReverseStereo(int channel, int flip);
 
  int Mix_ReserveChannels(int num);
  int Mix_GroupChannel(int which, int tag);
  int Mix_GroupChannels(int from, int to, int tag);
  int Mix_GroupAvailable(int tag);
  int Mix_GroupCount(int tag);
  int Mix_GroupOldest(int tag);
  int Mix_GroupNewer(int tag);
 
  int Mix_PlayChannelTimed(int channel, Mix_Chunk *chunk, int loops, int ticks);
  int Mix_PlayMusic(Mix_Music *music, int loops);
  int Mix_FadeInMusic(Mix_Music *music, int loops, int ms);
  int Mix_FadeInMusicPos(Mix_Music *music, int loops, int ms, double position);

  int Mix_FadeInChannelTimed(int channel, Mix_Chunk *chunk, int loops, int ms, int ticks);
   
  int Mix_Volume(int channel, int volume);
  int Mix_VolumeChunk(Mix_Chunk *chunk, int volume);
  int Mix_VolumeMusic(int volume);
   
  int Mix_HaltChannel(int channel);
  int Mix_HaltGroup(int tag);
  int Mix_HaltMusic(void);
   
  int Mix_ExpireChannel(int channel, int ticks);
   
  int Mix_FadeOutChannel(int which, int ms);
  int Mix_FadeOutGroup(int tag, int ms);
  int Mix_FadeOutMusic(int ms);
 
  Mix_Fading Mix_FadingMusic(void);
  Mix_Fading Mix_FadingChannel(int which);
 
  void Mix_Pause(int channel);
  void Mix_Resume(int channel);
  int Mix_Paused(int channel);
 
  void Mix_PauseMusic(void);
  void Mix_ResumeMusic(void);
  void Mix_RewindMusic(void);
  int Mix_PausedMusic(void);

  int Mix_SetMusicPosition(double position);
  int Mix_Playing(int channel);
  int Mix_PlayingMusic(void);

  int Mix_SetMusicCMD(const char *command);
  int Mix_SetSynchroValue(int value);
  int Mix_GetSynchroValue(void);
  
  int Mix_SetSoundFonts(const char *paths);
  const char* Mix_GetSoundFonts(void);
  int Mix_EachSoundFont(int (*function)(const char*, void*), void *data);
  
  Mix_Chunk * Mix_GetChunk(int channel);

  void Mix_CloseAudio(void);

]]

local mix = {

  AUDIO_U8 = 0x0008,
  AUDIO_S8 = 0x8008,
  AUDIO_U16LSB = 0x0010,
  AUDIO_S16LSB = 0x8010,
  AUDIO_U16MSB = 0x1010,
  AUDIO_S16MSB = 0x9010,
  AUDIO_U16 = 0x0010,
  AUDIO_S16 = 0x8010,
  
  MUS_NONE = 0,
  MUS_CMD = 1,
  MUS_WAV = 2,
  MUS_MOD = 3,
  MUS_MID = 4,
  MUS_OGG = 5,
  MUS_MP3 = 6,
  MUS_MP3_MAD = 7,
  MUS_FLAC = 8,
  MUS_MODPLUG = 9,

  MIX_NO_FADING = 0,
  MIX_FADING_OUT = 1,
  MIX_FADING_IN = 2,

  openAudio = libSDLmixer.Mix_OpenAudio,
  allocateChannels = libSDLmixer.Mix_AllocateChannels,
  querySpec = libSDLmixer.Mix_QuerySpec,
  
  loadWAV_RW = libSDLmixer.Mix_LoadWAV_RW,
  loadMUS = libSDLmixer.Mix_LoadMUS,
  loadMUS_RW = libSDLmixer.Mix_LoadMUS_RW,
  loadMUSType_RW = libSDLmixer.Mix_LoadMUSType_RW,
  quickLoad_WAV = libSDLmixer.Mix_QuickLoad_WAV,
  quickLoad_RAW = libSDLmixer.Mix_QuickLoad_RAW,
  freeChunk = libSDLmixer.Mix_FreeChunk,
  freeMusic = libSDLmixer.Mix_FreeMusic,
  
  getNumChunkDecoders = libSDLmixer.Mix_GetNumChunkDecoders,
  getChunkDecoder = libSDLmixer.Mix_GetChunkDecoder,
  getNumMusicDecoders = libSDLmixer.Mix_GetNumMusicDecoders,
  getMusicDecoder = libSDLmixer.Mix_GetMusicDecoder,
  getMusicType = libSDLmixer.Mix_GetMusicType,
  setPostMix = libSDLmixer.Mix_SetPostMix,
  hookMusic = libSDLmixer.Mix_HookMusic,
  hookMusicFinished = libSDLmixer.Mix_HookMusicFinished,
  
  registerEffect = libSDLmixer.Mix_RegisterEffect,
  unregisterEffect = libSDLmixer.Mix_UnregisterEffect,
  unregisterAllEffects = libSDLmixer.Mix_UnregisterAllEffects,
  
  setPanning = libSDLmixer.Mix_SetPanning,
  setPosition = libSDLmixer.Mix_SetPosition,
  setDistance = libSDLmixer.Mix_SetDistance,
  setReverseStereo = libSDLmixer.Mix_SetReverseStereo,
  
  reserveChannels = libSDLmixer.Mix_ReserveChannels,
  groupChannel = libSDLmixer.Mix_GroupChannel,
  groupChannels = libSDLmixer.Mix_GroupChannels,
  groupAvailable = libSDLmixer.Mix_GroupAvailable,
  groupCount = libSDLmixer.Mix_GroupCount,
  groupOldest = libSDLmixer.Mix_GroupOldest,
  groupNewer = libSDLmixer.Mix_GroupNewer,
  
  playChannelTimed = libSDLmixer.Mix_PlayChannelTimed,
  playMusic = libSDLmixer.Mix_PlayMusic,
  fadeInMusic = libSDLmixer.Mix_FadeInMusic,
  fadeInMusicPos = libSDLmixer.Mix_FadeInMusicPos,
  fadeInChannelTimed = libSDLmixer.Mix_FadeInChannelTimed,
  
  volume = libSDLmixer.Mix_Volume,
  volumeChunk = libSDLmixer.Mix_VolumeChunk,
  volumeMusic = libSDLmixer.Mix_VolumeMusic,
  
  haltChannel = libSDLmixer.Mix_HaltChannel,
  haltGroup = libSDLmixer.Mix_HaltGroup,
  haltMusic = libSDLmixer.Mix_HaltMusic,
  
  expireChannel = libSDLmixer.Mix_ExpireChannel,
  
  fadeOutChannel = libSDLmixer.Mix_FadeOutChannel,
  fadeOutGroup = libSDLmixer.Mix_FadeOutGroup,
  fadeOutMusic = libSDLmixer.Mix_FadeOutMusic,
  
  fadingMusic = libSDLmixer.Mix_FadingMusic,
  fadingChannel = libSDLmixer.Mix_FadingChannel,

  pause = libSDLmixer.Mix_Pause,
  resume = libSDLmixer.Mix_Resume,
  paused = libSDLmixer.Mix_Paused,
  
  pauseMusic = libSDLmixer.Mix_PauseMusic,
  resumeMusic = libSDLmixer.Mix_ResumeMusic,
  rewindMusic = libSDLmixer.Mix_RewindMusic,
  pausedMusic = libSDLmixer.Mix_PausedMusic,
  
  setMusicPosition = libSDLmixer.Mix_SetMusicPosition,
  playing = libSDLmixer.Mix_Playing,
  playingMusic = libSDLmixer.Mix_PlayingMusic,
  
  setMusicCMD = libSDLmixer.Mix_SetMusicCMD,
  setSynchroValue = libSDLmixer.Mix_SetSynchroValue,
  getSynchroValue = libSDLmixer.Mix_GetSynchroValue,
  
  setSoundFonts = libSDLmixer.Mix_SetSoundFonts,
  getSoundFonts = libSDLmixer.Mix_GetSoundFonts,
  eachSoundFont = libSDLmixer.Mix_EachSoundFont,
  
  getChunk = libSDLmixer.Mix_GetChunk,

  closeAudio = libSDLmixer.Mix_CloseAudio,

  loadWAV = function(file)
    return libSDLmixer.Mix_LoadWAV_RW(libSDL.SDL_RWFromFile(file, "rb"), 1)
  end,
  playChannel = function(channel, chunk, loops)
    return libSDLmixer.Mix_PlayChannelTimed(channel, chunk, loops, -1)
  end,
  fadeInChannel = function(channel, chunk, loops, ms)
    return libSDLmixer.Mix_FadeInChannelTimed(channel, chunk, loops, ms, -1)
  end,

}

function mix.waitWhilePlaying(channel)
  while mix.playing(channel) > 0 do
    util.sleep(0.01)
  end
end

return mix
