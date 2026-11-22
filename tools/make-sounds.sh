#!/bin/zsh
# Generates the nature soundscapes with ffmpeg into the given folder.
# Each is two minutes long and loops cleanly, because it is shaped noise.
set -euo pipefail

out="${1:-build/sounds}"
mkdir -p "$out"
duration=120

render() {
  local name=$1 graph=$2
  if [[ -f "$out/$name.m4a" ]]; then
    echo "skip   $name.m4a"
    return
  fi
  ffmpeg -loglevel error -y -filter_complex "$graph" -t $duration -c:a aac -b:a 128k "$out/$name.m4a"
  echo "made   $name.m4a"
}

render rain "\
anoisesrc=c=pink:r=44100:a=0.6:s=11,highpass=f=500,lowpass=f=7500[hiss];\
anoisesrc=c=brown:r=44100:a=0.5:s=12,lowpass=f=350[rumble];\
[hiss][rumble]amix=inputs=2:weights=1 0.6:normalize=0,volume='0.85+0.15*sin(2*PI*t/17)':eval=frame,volume=1.4"

render waves "\
anoisesrc=c=brown:r=44100:a=0.7:s=21,lowpass=f=900[body];\
anoisesrc=c=pink:r=44100:a=0.35:s=22,highpass=f=1200,lowpass=f=6000[foam];\
[body]volume='0.2+0.8*pow(0.5+0.5*sin(2*PI*t/9),3)':eval=frame[swell];\
[foam]volume='0.1+0.9*pow(0.5+0.5*sin(2*PI*t/9-0.6),6)':eval=frame[spray];\
[swell][spray]amix=inputs=2:normalize=0,volume=1.6"

render stream "\
anoisesrc=c=white:r=44100:a=0.4:s=31,bandpass=f=1800:w=2600,lowpass=f=9000[splash];\
anoisesrc=c=brown:r=44100:a=0.5:s=32,lowpass=f=600[flow];\
[splash][flow]amix=inputs=2:weights=0.8 1:normalize=0,volume='0.9+0.1*sin(2*PI*t/5)*sin(2*PI*t/13)':eval=frame,volume=1.3"

render wind "\
anoisesrc=c=brown:r=44100:a=0.8:s=41,lowpass=f=700[low];\
anoisesrc=c=pink:r=44100:a=0.3:s=42,bandpass=f=900:w=500[whistle];\
[low][whistle]amix=inputs=2:weights=1 0.5:normalize=0,\
volume='0.35+0.65*pow(0.5+0.25*sin(2*PI*t/13)+0.25*sin(2*PI*t/7.3+1.0),2)':eval=frame,volume=1.5"

render fire "\
anoisesrc=c=brown:r=44100:a=0.6:s=51,lowpass=f=280[roar];\
aevalsrc='if(lt(random(0),0.0011),(random(1)-0.5)*1.6,0)':s=44100,highpass=f=900,lowpass=f=5000[crackle];\
anoisesrc=c=pink:r=44100:a=0.08:s=52,highpass=f=2000[hiss];\
[roar][crackle][hiss]amix=inputs=3:weights=1 1 0.5:normalize=0,volume=1.6"
