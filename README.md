ffmpeg-windows-build-helpers
============================

This script is a fork of the brilliant script https://github.com/rdp/ffmpeg-windows-build-helpers by rdp(Roger Pack). 

It lets you compile a Windows version of ffmpeg/ffplay/ffprobe (including some dependency libraries) with  mingw64 on a Linux Machine.
Working for 32bit and 64bit versions, as static or shared build.


To run:
In a Linux box (VM or native):

- First download it (git clone the repo, run it, or do the following in a bash script)

```bash
wget https://raw.github.com/niesel/ffmpeg-windows-build-helpers/master/cross_compile_ffmpeg.sh -O cross_compile_ffmpeg.sh
chmod u+x cross_compile_ffmpeg.sh
./cross_compile_ffmpeg.sh
```

And follow the prompts.

Enjoy!
