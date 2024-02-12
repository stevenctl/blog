#!/bin/bash

for f in $(find . -type f -name "*.mp4"); do
  OUT=$(dirname $f)/$(basename -- "$f")
  OUT="${OUT%.*}.webm"
  ffmpeg -i $f -c:v libvpx-vp9 -crf 30 -b:v 0 -b:a 128k -c:a libopus $OUT
done

