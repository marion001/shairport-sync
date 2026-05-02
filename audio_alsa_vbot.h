#ifndef AUDIO_ALSA_VBOT_H
#define AUDIO_ALSA_VBOT_H

// VBot global variables for ALSA control
extern volatile int vbot_open_alsa;           // 1 = exclusive mode, 0 = shared mode
extern volatile int vbot_shairport_silent_mode; // 1 = silent mode (mute), 0 = normal
extern float vbot_volume_factor;              // 1.0 = full volume, 0.0 = silent

// VBot wrapper functions for ALSA device control
int vbot_alsa_open(int do_auto_setup);
int vbot_alsa_close(void);

#endif /* AUDIO_ALSA_VBOT_H */
