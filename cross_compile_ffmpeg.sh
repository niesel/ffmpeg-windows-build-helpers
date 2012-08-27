#!/usr/bin/env bash
################################################################################
# ffmpeg windows cross compile helper/downloader script
################################################################################
# Copyright (C) 2012 Roger Pack
# Copyright (C) 2012 Michael Anisimoff
#
# This program is free software: you can redistribute it and/or modify it under
# the terms of the GNU General Public License as published by the Free Software
# Foundation, either version 3 of the License, or (at your option) any later
# version.
#
# This program is distributed in the hope that it will be useful, but WITHOUT
# ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
# FOR A PARTICULAR PURPOSE.  See the GNU General Public License for more
# details.
#
# You should have received a copy of the GNU General Public License along with
# this program.  If not, see <http://www.gnu.org/licenses/>.
#
# The GNU General Public License can be found in the LICENSE file.
################################################################################

# Directory where finally the ffmpeg builds should be put at. (if unset, cur_dir will be used) 
ffbasedir=
#Build directory
cur_dir="$(pwd)/build"
#Target directory for bz2-files (if unset, no .tar.bz will be made)
ffbz2target="${cur_dir}/bz2"

################################################################################
# Text color variables
WARN='\e[1;31m'   # red - Bold
PASS='\e[1;32m'   # green
INFO='\e[1;33m'   # yellow
QUES='\e[1;36m'   # cyan
RST='\e[0m'       # Text reset

if [[ "${ffbasedir}" = "" || "${ffbasedir}" = "${cur_dir}" ]]; then
    ffbasedir="${cur_dir}"
elif [[ -d "${ffbasedir}" ]]; then
    if [[ -w "${ffbasedir}" ]]; then
        echo -e "${PASS}\nTarget directory is ${ffbasedir}.${RST}"
     else
        echo -e "${WARN}\n Target directory ${ffbasedir} is not writeable.\n Exiting.${RST}}"; exit 1
    fi 

else
    mkdir -p ${ffbasedir}
    if [[ ! -w "${ffbasedir}" ]]; then
        echo -e "${WARN}\n Target directory ${ffbasedir} not existing and could not be created.\n Exiting.${RST}}"; exit 1
    fi
fi


yes_no_sel () {
unset user_input
local question="$1"
shift
while [[ "$user_input" != [YyNn] ]]; do
  echo -e "$question\c"
  read user_input
  if [[ "$user_input" != [YyNn] ]]; then
    echo -e "\n${WARN}Your selection was not vaild, please try again.\n${RST}"
  fi
done
# downcase it
user_input=$(echo $user_input | tr '[A-Z]' '[a-z]')
}



intro() {
    echo -e "\n######################### Welcome ###########################"
    echo -e "Welcome to the ffmpeg cross-compile builder-helper script."
    echo -e "Downloads and builds will be processed within the folder"
    echo -e "    $cur_dir"
    echo -e "If this is not ok, then exit now, and cd to the directory where"
    echo -e "you would like them installed, then run this script again."

  yes_no_sel "${QUES}Is $cur_dir ok? ${RST}[y/n]?"
  if [[ "${user_input}" = "n" ]]; then
    exit 1
  fi
  if [[ ! -d "${cur_dir}" ]]; then
    mkdir -p "$cur_dir"
	if [[ ! -d "${cur_dir}" ]]; then
		echo -e "${WARN}Could not create subdir ./builds.\nExiting${RST}"; exit 1
	fi
  else
    if [[ ! -w "${cur_dir}" ]]; then
        echo -e "${WARN}No write permissions in ./builds.\nExiting${RST}"; exit 1
    fi
  fi
  cd "$cur_dir"
  echo -e "\nWould you like to include non-free (non GPL compatible) libraries, like certain high quality aac encoders?"
  echo -e "The resultant binary will not be distributable, but might be useful for in-house use."
  yes_no_sel "${QUES}Include non-free?${RST} [y/n]?"
  non_free="$user_input" # save it away
}

install_cross_compiler() {
  if [[ -f "mingw-w64-i686/compiler.done" || -f "mingw-w64-x86_64/compiler.done" ]]; then
   echo -e "\n${PASS}MinGW-w64 compiler of some type already installed, not re-installing it...${RST}\n"
   return
  fi
  echo -e "\nFirst we will download and compile a gcc cross-compiler (MinGW-w64)."
  echo -e "You will be prompted with a few questions as it installs. (it takes quite a while)"
  echo -e "${QUES}Enter to continue:${RST}\c"
  read -p ''

  wget http://zeranoe.com/scripts/mingw_w64_build/mingw-w64-build-3.0.6 -O mingw-w64-build-3.0.6
  chmod u+x mingw-w64-build-3.0.6
  ./mingw-w64-build-3.0.6 --disable-nls --disable-shared --default-configure --clean-build || exit 1
  if [ -d mingw-w64-x86_64 ]; then
    touch mingw-w64-x86_64/compiler.done
  fi
  if [ -d mingw-w64-i686 ]; then
    touch mingw-w64-i686/compiler.done
  fi
  echo -e "${PASS}Ok, done building MinGW-w64 cross-compiler...${RST}\n"
}

setup_env() {
  export PKG_CONFIG_LIBDIR= # disable pkg-config from reverting back to and finding system installed packages [yikes]
}

do_svn_checkout() {
  repo_url="$1"
  to_dir="$2"
  if [ ! -d $to_dir ]; then
    echo -e "${INFO}svn checking out to $to_dir ${RST}"
    svn checkout $repo_url $to_dir.tmp || exit 1
    mv $to_dir.tmp $to_dir
  else
    cd $to_dir
    echo -e "${INFO}Updating $to_dir ${RST}"
    svn up
    cd ..
  fi
}

do_git_checkout() {
  repo_url="$1"
  to_dir="$2"
  if [ ! -d $to_dir ]; then
    echo -e "${INFO}Downloading (via git clone) $to_dir ${RST}"
    # prevent partial checkouts by renaming it only after success
    git clone $repo_url $to_dir.tmp || exit 1
    mv $to_dir.tmp $to_dir
    echo -e "${INFO}done downloading $to_dir ${RST}"
  else
    cd $to_dir
    echo -e "${INFO}Updating to latest $to_dir version... ${RST}"
    git pull
    cd ..
  fi
}

do_configure() {
  configure_options="$1"
  configure_name="$2"
  if [[ "$configure_name" = "" ]]; then
    configure_name="./configure"
  fi
  local cur_dir2=$(pwd)
  local english_name=$(basename $cur_dir2)
  local touch_name=$(echo -- $configure_options | /usr/bin/env md5sum) # sanitize, disallow too long of length
  touch_name=$(echo already_configured_$touch_name | sed "s/ //g") # add prefix so we can delete it easily, remove spaces
  if [ $english_name = "ffmpeg_git" -o ! -f "$touch_name" ]; then # always reconfigure ffmpeg-git
    if [ $english_name = "ffmpeg_git" ]; then
        make -s distclean  # make distclean before configure (only ffmpeg_git)
    fi
    echo -e "\n${INFO}configuring $english_name as $ PATH=$PATH $configure_name $configure_options${RST}\n"
    make -s clean # just in case
    #make uninstall # does weird things when used with ffmpeg
    if [ -f bootstrap.sh ]; then
      ./bootstrap.sh
    fi
    rm -f already_configured* # any old configuration options, since they'll be out of date after the next configure
    rm -f already_ran_make
    "$configure_name" $configure_options || exit 1
    touch -- "$touch_name"
    make -s clean # just in case
  else
    echo -e "\n${INFO}already configured $cur_dir2 ${RST}\n" 
  fi
}

do_make_install() {
  extra_make_options="$1"
  local cur_dir2=$(pwd)
  if [ ! -f already_ran_make ]; then
    echo -e "\n${INFO}making $cur_dir2 as $ PATH=$PATH make $extra_make_options ${RST}\n"
    make $extra_make_options || exit 1
    make install $extra_make_options || exit 1
    touch already_ran_make
  else
    echo -e "\n${INFO}already did make $(basename "$cur_dir2") ${RST}\n"
  fi
}

build_x264() {
  do_git_checkout "http://repo.or.cz/r/x264.git" "x264"
  cd x264
  do_configure "--host=$host_target --enable-static --cross-prefix=$cross_prefix --prefix=$mingw_w64_x86_64_prefix --enable-win32thread"
  # TODO more march=native here?
  # rm -f already_ran_make # just in case the git checkout did something, re-make
  do_make_install
  cd ..
}

build_librtmp() {
  #  download_and_unpack_file http://rtmpdump.mplayerhq.hu/download/rtmpdump-2.3.tgz rtmpdump-2.3
  #  cd rtmpdump-2.3/librtmp

  do_git_checkout "http://repo.or.cz/r/rtmpdump.git" rtmpdump_git
  cd rtmpdump_git/librtmp
  make install OPT='-O2 -g' "CROSS_COMPILE=$cross_prefix" SHARED=no "prefix=$mingw_w64_x86_64_prefix" || exit 1 # TODO use gnutls ?
  cd ../..
}

build_libopenjpeg() {
  # TRUNK didn't seem to build right...
  #do_svn_checkout http://openjpeg.googlecode.com/svn/trunk/ openjpeg
  #cd openjpeg
  #generic_configure
  #do_make_install
  #cd ..
  download_and_unpack_file http://openjpeg.googlecode.com/files/openjpeg_v1_4_sources_r697.tgz openjpeg_v1_4_sources_r697
  cd openjpeg_v1_4_sources_r697
  generic_configure
  sed -i "s/\/usr\/lib/\$\(libdir\)/" Makefile # install pkg_config to the right dir...
  do_make_install
  cd .. 
}

build_libvpx() {
  download_and_unpack_file http://webm.googlecode.com/files/libvpx-v1.1.0.tar.bz2 libvpx-v1.1.0
  cd libvpx-v1.1.0
  export CROSS="$cross_prefix"
  if [[ "$bits_target" = "32" ]]; then
    do_configure "--target=generic-gnu --prefix=$mingw_w64_x86_64_prefix --enable-static --disable-shared"
  else
    do_configure "--target=generic-gnu --prefix=$mingw_w64_x86_64_prefix --enable-static --disable-shared"
  fi
  do_make_install "extralibs='-lpthread'" # weird
  cd ..
}

download_and_unpack_file() {
  url="$1"
  output_name=$(basename $url)
  output_dir="$2"
  if [ ! -f "$output_dir/unpacked.successfully" ]; then
    wget "$url" -O "$output_name" || exit 1
    tar -xf "$output_name" || exit 1
    touch "$output_dir/unpacked.successfully"
    rm "$output_name"
  fi
}

generic_configure() {
  local extra_configure_options="$1"
  do_configure "--host=$host_target --prefix=$mingw_w64_x86_64_prefix --disable-shared --enable-static $extra_configure_options"
}

# needs 2 parameters currently
generic_download_and_install() {
  local url="$1"
  local english_name="$2" 
  local extra_configure_options="$3"
  download_and_unpack_file $url $english_name
  cd $english_name || exit "needs 2 parameters"
  generic_configure $extra_configure_options
  do_make_install
  cd ..
}

build_libgsm() {
  download_and_unpack_file http://www.quut.com/gsm/gsm-1.0.13.tar.gz gsm-1.0-pl13
  cd gsm-1.0-pl13
  make CC=${cross_prefix}gcc AR=${cross_prefix}ar RANLIB=${cross_prefix}ranlib INSTALL_ROOT=${mingw_w64_x86_64_prefix}i # fails, but we expect that LODO fix [?]
  cp lib/libgsm.a $mingw_w64_x86_64_prefix/lib || exit 1
  mkdir -p $mingw_w64_x86_64_prefix/include/gsm
  cp inc/gsm.h $mingw_w64_x86_64_prefix/include/gsm || exit 1
  cd ..
}

build_libogg() {
  generic_download_and_install http://downloads.xiph.org/releases/ogg/libogg-1.3.0.tar.gz libogg-1.3.0
}

build_libvorbis() {
  generic_download_and_install http://downloads.xiph.org/releases/vorbis/libvorbis-1.2.3.tar.gz libvorbis-1.2.3
}

build_libspeex() {
  generic_download_and_install http://downloads.xiph.org/releases/speex/speex-1.2rc1.tar.gz speex-1.2rc1
}  

build_libtheora() {
  generic_download_and_install http://downloads.xiph.org/releases/theora/libtheora-1.1.1.tar.bz2 libtheora-1.1.1
}

build_gmp() {
  download_and_unpack_file ftp://ftp.gnu.org/gnu/gmp/gmp-5.0.5.tar.bz2 gmp-5.0.5
  cd gmp-5.0.5
  generic_configure "ABI=$bits_target"
  do_make_install
  cd .. 
}

build_gnutls() {
  generic_download_and_install ftp://ftp.gnu.org/gnu/gnutls/gnutls-3.0.22.tar.xz gnutls-3.0.22
  sed -i 's/-lgnutls *$/-lgnutls -lnettle -lhogweed -lgmp -lcrypt32/' "$PKG_CONFIG_PATH/gnutls.pc"
}

build_libnettle() {
  generic_download_and_install http://www.lysator.liu.se/~nisse/archive/nettle-2.5.tar.gz nettle-2.5
}

build_zlib() {
  download_and_unpack_file http://zlib.net/zlib-1.2.7.tar.gz zlib-1.2.7
  cd zlib-1.2.7
    do_configure "--static --prefix=$mingw_w64_x86_64_prefix"
    do_make_install "CC=$(echo $cross_prefix)gcc AR=$(echo $cross_prefix)ar RANLIB=$(echo $cross_prefix)ranlib"
  cd ..
}

build_libxvid() {
  download_and_unpack_file http://downloads.xvid.org/downloads/xvidcore-1.3.2.tar.gz xvidcore
  cd xvidcore/build/generic
  if [ "$bits_target" = "64" ]; then
    local config_opts="--build=x86_64-unknown-linux-gnu --disable-assembly" # kludgey work arounds for 64 bit
  fi
  do_configure "--host=$host_target --prefix=$mingw_w64_x86_64_prefix $config_opts" # no static option...
  sed -i "s/-mno-cygwin//" platform.inc # remove old compiler flag that now apparently breaks us
  do_make_install
  cd ../../..
  # force a static build after the fact
  if [[ -f "$mingw_w64_x86_64_prefix/lib/xvidcore.dll" ]]; then
    rm $mingw_w64_x86_64_prefix/lib/xvidcore.dll || exit 1
    mv $mingw_w64_x86_64_prefix/lib/xvidcore.a $mingw_w64_x86_64_prefix/lib/libxvidcore.a || exit 1
  fi
}

build_openssl() {
  download_and_unpack_file http://www.openssl.org/source/openssl-1.0.1c.tar.gz openssl-1.0.1c
  cd openssl-1.0.1c
  export cross="$cross_prefix"
  export CC="${cross}gcc"
  export AR="${cross}ar"
  export RANLIB="${cross}ranlib"
  if [ "$bits_target" = "32" ]; then
    do_configure "--prefix=$mingw_w64_x86_64_prefix no-shared mingw" ./Configure
  else
    do_configure "--prefix=$mingw_w64_x86_64_prefix no-shared mingw64" ./Configure
  fi
  do_make_install
  unset cross
  unset CC
  unset AR
  unset RANLIB
  cd ..
}

build_fdk_aac() {
  generic_download_and_install http://sourceforge.net/projects/opencore-amr/files/fdk-aac/fdk-aac-0.1.0.tar.gz/download fdk-aac-0.1.0
}

build_freetype() {
  generic_download_and_install http://download.savannah.gnu.org/releases/freetype/freetype-2.4.10.tar.gz freetype-2.4.10
} 

build_vo_aacenc() {
  generic_download_and_install http://sourceforge.net/projects/opencore-amr/files/vo-aacenc/vo-aacenc-0.1.2.tar.gz/download vo-aacenc-0.1.2
}

build_sdl() {
  # apparently ffmpeg expects prefix-sdl-config not sdl-config that they give us, so rename...
  export CFLAGS="-DDECLSPEC=" #-DDECLSPEC is needed for shared build
  generic_download_and_install http://www.libsdl.org/release/SDL-1.2.15.tar.gz SDL-1.2.15
  unset CFLAGS
  mkdir temp
  cd temp # so paths will work out right
  local prefix=$(basename $cross_prefix)
  local bin_dir=$(dirname $cross_prefix)
  sed -i "s/-mwindows//" "$mingw_w64_x86_64_prefix/bin/sdl-config" # allow ffmpeg to output anything
  sed -i "s/-mwindows//" "$PKG_CONFIG_PATH/sdl.pc"
  cp "$mingw_w64_x86_64_prefix/bin/sdl-config" "$bin_dir/${prefix}sdl-config" # this is the only one in the PATH so use it for now
  cd ..
  rmdir temp
}

build_faac() {
  generic_download_and_install http://downloads.sourceforge.net/faac/faac-1.28.tar.gz faac-1.28 "--with-mp4v2=no"
}

build_lame() {
  generic_download_and_install http://sourceforge.net/projects/lame/files/lame/3.99/lame-3.99.5.tar.gz/download lame-3.99.5
}


build_ffmpeg() {
  if [[ "$1" = "shared" ]]; then 
    local ffshared="shared"
  else
    local ffshared="static"
  fi
  do_git_checkout https://github.com/FFmpeg/FFmpeg.git ffmpeg_git
  cd ffmpeg_git
  git checkout master; git reset --hard; git checkout master #reset git to master 
  local ffgit=`git rev-parse --short HEAD`
  local ffdate=`date +%Y%m%d`
  if [ "$bits_target" = "32" ]; then
    local arch=x86
    local ffarch=win32
  else
    local arch=x86_64
    local ffarch=win64
  fi
  local ffdir="ffmpeg-${ffdate}-${ffgit}-${ffarch}-${ffshared}"
  local ffpath="${ffbasedir}/${ffdir}"
  if [[ -d "${ffpath}" ]]; then
    rm -rf ${ffbasedir}/${ffdir}/*
  else
    mkdir -p "${ffpath}"
  fi

  config_options="--prefix=$ffpath --enable-memalign-hack --arch=$arch --enable-gpl --enable-libx264 --enable-avisynth --enable-libxvid --target-os=mingw32  --cross-prefix=$cross_prefix --pkg-config=pkg-config --enable-libmp3lame --enable-version3 --enable-libvo-aacenc --enable-libvpx --extra-libs=-lws2_32 --extra-libs=-lpthread --enable-zlib --extra-libs=-lwinmm --extra-libs=-lgdi32 --enable-librtmp --enable-libvorbis --enable-libtheora --enable-libspeex --enable-libopenjpeg --enable-gnutls --enable-libgsm --enable-libfreetype"
  
  if [[ "$non_free" = "y" ]]; then
    config_options="$config_options --enable-nonfree --enable-openssl --enable-libfdk-aac" # --enable-libfaac -- faac too poor quality and becomes the default -- add it in and uncomment the build_faac line to include it
  fi
  
  if [[ "$native_build" = "y" ]]; then
    config_options="$config_options --disable-runtime-cpudetect"
    # TODO --cpu=host
  else
    config_options="$config_options --enable-runtime-cpudetect"
  fi
  if [[ "$ffshared" = "shared" ]] ; then
    config_options="$config_options --disable-static --enable-shared"
  fi
  do_configure "$config_options"
  rm -f *.exe # just in case some library dependency was updated, force it to re-link
  echo -e "\n${INFO}ffmpeg: doing PATH=$PATH make${RST}\n"
  local ffcpucount=`grep -c ^processor /proc/cpuinfo`
  make -j${ffcpucount} || exit 1
  make install
  local cur_dir2=$(pwd)
  cd ${ffbasedir}
  cp -r ${cur_dir2}/doc ${ffpath}/ #cp docs to install dir
  if [[ ! ${ffbz2target} = ""]]; then
    tar -cjf ${ffdir}.tar.bz2 ${ffdir} # bzip 
    rm -rf ${ffdir}/* && rmdir ${ffdir}
  fi  
  cd ${cur_dir2}
  echo -e "${PASS}\n Done! You will find the bz2 packed binaries in ${ffbasedir} ${RST}\n"
  cd ..
}

intro # remember to always run the intro, since it adjust pwd
install_cross_compiler # always run this, too, since it adjust the PATH
setup_env

build_all() {
  build_zlib # rtmp depends on it [as well as ffmpeg's optional but handy --enable-zlib]
  build_gmp
  build_libnettle # needs gmp
  build_gnutls #  needs libnettle
  build_libgsm
  build_sdl # needed for ffplay to be created
  build_libogg
  build_libspeex # needs libogg
  build_libvorbis # needs libogg
  build_libtheora # needs libvorbis, libogg
  build_libxvid
  build_x264
  build_lame
  build_libvpx
  build_vo_aacenc
  build_freetype
  build_libopenjpeg
  if [[ "$non_free" = "y" ]]; then
    build_fdk_aac
    # build_faac # not included for now, see comment above, poor quality
  fi
  build_openssl
  build_librtmp # needs openssl today [TODO use gnutls]
  build_ffmpeg
  build_ffmpeg shared
}

original_path="$PATH"
if [ -d "mingw-w64-i686" ]; then # they installed a 32-bit compiler
  echo -e "\n${INFO}Building 32-bit ffmpeg...${RST}\n"
  host_target='i686-w64-mingw32'
  mingw_w64_x86_64_prefix="$cur_dir/mingw-w64-i686/$host_target"
  export PATH="$cur_dir/mingw-w64-i686/bin:$original_path"
  export PKG_CONFIG_PATH="$cur_dir/mingw-w64-i686/i686-w64-mingw32/lib/pkgconfig"
  bits_target=32
  cross_prefix="$cur_dir/mingw-w64-i686/bin/i686-w64-mingw32-"
  mkdir -p win32
  cd win32
  build_all
  cd ..
fi

if [ -d "mingw-w64-x86_64" ]; then # they installed a 64-bit compiler
  echo -e "\n${INFO}Building 64-bit ffmpeg...${RST}\n"
  host_target='x86_64-w64-mingw32'
  mingw_w64_x86_64_prefix="$cur_dir/mingw-w64-x86_64/$host_target"
  export PATH="$cur_dir/mingw-w64-x86_64/bin:$original_path"
  export PKG_CONFIG_PATH="$cur_dir/mingw-w64-x86_64/x86_64-w64-mingw32/lib/pkgconfig"
  mkdir -p x86_64
  bits_target=64
  cross_prefix="$cur_dir/mingw-w64-x86_64/bin/x86_64-w64-mingw32-"
  cd x86_64
  build_all
  cd ..
fi

cd ..
echo -e "${WARN}\n All complete. Ending ffmpeg cross compiler script.\n Bye.${RST}\n "
