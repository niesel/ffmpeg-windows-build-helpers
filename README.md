ffmpeg-windows-build-helpers
============================

This script is a fork of the brilliant script https://github.com/rdp/ffmpeg-windows-build-helpers by rdp(Roger Pack). 

It lets you compile a Windows version of ffmpeg/ffplay/ffprobe (including some dependency libraries) with mingw64 on a Linux Machine.

Working for 32bit and 64bit versions of ffmpeg, as static or shared build.

It should work on most Linux distributions with automake and autotools installed, but it is tested on an Ubuntu 12.04 VM. 

To run the script:

- First download it (git clone the repo, run it, or do the following in a bash script)

```bash
wget https://raw.github.com/niesel/ffmpeg-windows-build-helpers/master/cross_compile_ffmpeg.sh -O cross_compile_ffmpeg.sh
chmod u+x cross_compile_ffmpeg.sh
./cross_compile_ffmpeg.sh
```
And follow the prompts.
It works with 32 or 64 bit Linux.

If you want to make shared builds of ffmpeg including the MSVC import libraries, it's easier to use a 32bit OS,
because you don't have to deal with wine prefixes. 
Just install wine "sudo apt-get install wine" and follow the instructions below.

For the shared libraries "lib.exe" under wine is needed.
Install it according to the explanation in the arrozcru wiki
http://ffmpeg.arrozcru.org/wiki/index.php?title=Cross-compiling :

* Install MSVC++ under wine (select only '''Developer Tools->Visual C++ Compilers'''):                                                                    + 
```bash
wget http://www.kegel.com/wine/winetricks
chmod +x winetricks
./winetricks psdkwin7
```

* Copy mspdb80.dll to the same directory as lib.exe:
```bash
cp $HOME/.wine/drive_c/Program\ Files/Microsoft\ Visual\ Studio\ 9.0/Common7/IDE/mspdb80.dll \
       $HOME/.wine/drive_c/Program\ Files/Microsoft\ Visual\ Studio\ 9.0/VC/bin/
```

* Create a lib.exe helper in /usr/local/bin:
```bash
sudo tee /usr/local/bin/lib.exe << EOF
#!/bin/sh
$HOME/.wine/drive_c/Program\ Files/Microsoft\ Visual\ Studio\ 9.0/VC/bin/lib.exe \$*
EOF
sudo chmod +x /usr/local/bin/lib.exe
```

Now when you build FFmpeg with --enable-shared, you should have Visual Studio import libraries.

Enjoy!

