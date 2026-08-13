#!/bin/sh
set -eu

audio_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)

ffmpeg -hide_banner -loglevel error -y \
  -f lavfi -i "sine=frequency=440:sample_rate=16000:duration=10" \
  -ac 1 -ar 16000 -c:a pcm_s16le -map_metadata -1 \
  "$audio_dir/sine_440.wav"

ffmpeg -hide_banner -loglevel error -y \
  -f lavfi -i "anoisesrc=color=white:seed=424242:sample_rate=16000:duration=10:amplitude=0.25" \
  -ac 1 -ar 16000 -c:a pcm_s16le -map_metadata -1 \
  "$audio_dir/white_noise.wav"

ffmpeg -hide_banner -loglevel error -y \
  -f lavfi -i "aevalsrc=sin(2*PI*80*10/log(7900/80)*(exp(log(7900/80)*t/10)-1)):s=16000:d=10" \
  -ac 1 -ar 16000 -c:a pcm_s16le -map_metadata -1 \
  "$audio_dir/chirp.wav"

ffmpeg -hide_banner -loglevel error -y \
  -f lavfi -i "aevalsrc=if(lt(mod(t\\,0.5)\\,0.008)\\,0.8*exp(-500*mod(t\\,0.5))\\,0):s=16000:d=10" \
  -ac 1 -ar 16000 -c:a pcm_s16le -map_metadata -1 \
  "$audio_dir/clicks.wav"

ffmpeg -hide_banner -loglevel error -y \
  -f lavfi -i "aevalsrc=if(lt(mod(t\\,0.5)\\,0.008)\\,0.8*exp(-500*mod(t\\,0.5))\\,0):s=44100:d=10" \
  -ac 1 -ar 44100 -c:a pcm_s16le -map_metadata -1 \
  -fflags +bitexact -flags:a +bitexact \
  "$audio_dir/clicks_44100.wav"

printf '\147\063\365\254\021\236\304\177\000\377\052\201\116\331\007\143\270\356\115\232\061\200\374\023\252\126\340\071\315\104\167\005' \
  > "$audio_dir/undecodable.m4a"
