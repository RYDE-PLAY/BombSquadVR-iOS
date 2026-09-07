// Released under the MIT License. See LICENSE for details.
//
// The current Apple platform source keeps the historical Tremor include and
// read-call shape for streaming audio. BombSquadVR-iOS uses the standard
// libvorbis
// decoder, so provide only the small source-compatible adapter needed there.

#ifndef BOMBSQUADVR_IVORBISFILE_H_
#define BOMBSQUADVR_IVORBISFILE_H_

#include <vorbis/vorbisfile.h>

inline long ov_read(OggVorbis_File* file, char* buffer, int length,
                    int* bitstream) {
  return ::ov_read(file, buffer, length, 0, 2, 1, bitstream);
}

#endif  // BOMBSQUADVR_IVORBISFILE_H_
