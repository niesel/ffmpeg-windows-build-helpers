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
#
#Build directory
basedir="$(pwd)"
buildir="${basedir}/build"
#Target directory for bz2-files (if unset, no .tar.bz will be made)
bz2dir="${basedir}/bz2"
#Build static and shared versions
ffbuildstatic=false
ffbuildshared=false

# Text color variables #########################################################

WARN='\e[1;31m'   # red - Bold
PASS='\e[1;32m'   # green
INFO='\e[1;33m'   # yellow
QUES='\e[1;36m'   # cyan
RST='\e[0m'       # Text reset

# Functions ####################################################################

yes_no_sel () {
unset user_input
local question="$1"
shift
while [[ "$user_input" != [YyNn] ]]; do
  echo -e "$question \c"
  read user_input
  if [[ "$user_input" != [YyNn] ]]; then
    echo -e "\n${WARN}Your selection was not vaild, please try again.\n${RST}"
  fi
done
# downcase it
user_input=$(echo $user_input | tr '[A-Z]' '[a-z]')
}

make_dir () {
    if [[ ! -d "$*" ]]; then
        mkdir -p "$*" 
        if [[ ! -d "$*" ]]; then
            echo -e "\n${WARN}Could not create $*.\nExiting! ${RST}"; exit 1
        else
            echo -e "\n${PASS}Successfully created $* ${RST}"
        fi
    else
        if [[ ! -w "${buildir}" ]]; then
            echo -e "\n${WARN}No write permissions in $*.\nExiting! ${RST}"; exit 1
        else
            echo -e "\n${PASS} Directory $* already exists and is writeable. ${RST}"
        fi
    fi
}

intro() {
    echo -e "\n######################### Welcome ###########################"
    echo -e "Welcome to the ffmpeg cross-compile builder-helper script."
    echo -e "Downloads and builds will be processed within the folder"
    echo -e "    $buildir"
    echo -e "If this is not ok, then exit now, and cd to the directory where"
    echo -e "you would like them installed, then run this script again."

  yes_no_sel "${QUES}Is ${buildir} ok? ${RST}[y/n]?"
  if [[ "${user_input}" = "n" ]]; then
    exit 1
  fi
  
  make_dir "$buildir"  
  cd "$buildir"
  
  echo -e "\nWould you like to include non-free (non GPL compatible) libraries, like certain high quality aac encoders?"
  echo -e "The resultant binary will not be distributable, but might be useful for in-house use."
  yes_no_sel "${QUES}Include non-free?${RST} [y/n]?"
  non_free="$user_input"
  
  yes_no_sel "\n${QUES}Would you like to make a static build?${RST} [y/n]?"
  if [[ "$user_input" = "y" ]]; then 
    ffbuildstatic=true
    echo "${ffbuildstatic}"
  fi  
  type -p lib.exe >/dev/null 2>&1 && libexeok=true || libexeok=false
  if $libexeok; then 
    yes_no_sel "\n${QUES}Would you like to make a shared build?${RST} [y/n]?"
    if [[ "$user_input" = "y" ]]; then 
        ffbuildshared=true
        echo -e "${ffbuildshared}"
    fi
  else
    echo -e "\n${WARN}Wine with installed lib.exe required for shared ffmpeg build, but it could not be found.\nCan not build shared libs!${RST}"
  fi    
  if ! $ffbuildstatic && ! $ffbuildshared; then
    echo -e "\n${WARN}Neither static nor shared build selected!\nExiting${RST}"; exit 1
  fi
}

install_cross_compiler() {
  if [[ -f "mingw-w64-i686/compiler.done" || -f "mingw-w64-x86_64/compiler.done" ]]; then
   echo -e "\n${PASS}MinGW-w64 compiler of some type already installed, not re-installing it...${RST}"
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
  echo -e "${PASS}Ok, done building MinGW-w64 cross-compiler...${RST}"
}

setup_env() {
    # disable pkg-config from reverting back to and finding system installed packages [yikes]
    export PKG_CONFIG_LIBDIR= 
}

do_svn_checkout() {
  repo_url="$1"
  to_dir="$2"
  if [ ! -d $to_dir ]; then
    echo -e "\n${INFO}svn checking out to $to_dir ${RST}"
    svn checkout $repo_url $to_dir.tmp || exit 1
    mv $to_dir.tmp $to_dir
  else
    cd ${archdir}/${to_dir}
    echo -e "\n${INFO}Updating $to_dir ${RST}"
    svn up
    cd ${archdir}
  fi
}

do_git_checkout() {
  repo_url="$1"
  to_dir="$2"
  if [ ! -d $to_dir ]; then
    echo -e "\n${INFO}Downloading (via git clone) $to_dir ${RST}"
    # prevent partial checkouts by renaming it only after success
    git clone $repo_url $to_dir.tmp || exit 1
    mv $to_dir.tmp $to_dir
    echo -e "${PASS}done downloading $to_dir ${RST}"
  else
    cd ${archdir}/${to_dir}
    echo -e "\n${INFO}Updating to latest $to_dir version...${RST}"
    git checkout master
    git reset --hard
    git pull
    cd ${archdir}
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
  # sanitize, disallow too long of length
  local touch_name=$(echo -- $configure_options | /usr/bin/env md5sum) 
  # add prefix so we can delete it easily, remove spaces
  touch_name=$(echo already_configured_$touch_name | sed "s/ //g") 
  if [ $english_name = "ffmpeg_git" -o ! -f "$touch_name" ]; then 
    # always reconfigure ffmpeg-git
    if [ $english_name = "ffmpeg_git" ]; then
        # make distclean before configure (only ffmpeg_git)
        make -s distclean > /dev/null 2>&1 
    fi
    echo -e "${INFO}configuring $english_name as $ PATH=$PATH $configure_name $configure_options${RST}"
    make -s clean /dev/null 2>&1
    if [ -f bootstrap.sh ]; then
      ./bootstrap.sh
    elif [ -f autogen.sh ]; then
      ./autogen.sh
    fi
    # any old configuration options, since they'll be out of date after the next configure
    rm -f already_configured*
    rm -f already_ran_make
    "$configure_name" $configure_options || exit 1
    touch -- "$touch_name"
  else
    echo -e "\n${PASS}already configured $cur_dir2 ${RST}" 
  fi
}

do_make_install() {
  extra_make_options="$1"
  local cur_dir2=$(pwd)
  if [ ! -f already_ran_make ]; then
    echo -e "\n${INFO}making $cur_dir2 as $ PATH=$PATH make $extra_make_options ${RST}"
    make -s clean /dev/null 2>&1
    make $extra_make_options || exit 1
    make install $extra_make_options || exit 1
    touch already_ran_make
  else
    echo -e "${PASS}already did make $(basename "$cur_dir2") ${RST}"
  fi
}

build_x264() {
  do_git_checkout "http://repo.or.cz/r/x264.git" "x264"
  cd ${archdir}/x264
  do_configure "--host=$host_target --enable-static --cross-prefix=$cross_prefix --prefix=$mingw_w64_x86_64_prefix --enable-win32thread"
  # rm -f already_ran_make # just in case the git checkout did something, re-make
  do_make_install
  cd ${archdir}
}

build_librtmp() {
  # download_and_unpack_file http://rtmpdump.mplayerhq.hu/download/rtmpdump-2.3.tgz rtmpdump-2.3
  # cd rtmpdump-2.3/librtmp

  do_git_checkout "http://repo.or.cz/r/rtmpdump.git" rtmpdump_git
  cd ${archdir}/rtmpdump_git/librtmp
  # TODO use gnuts?
  make install OPT='-O2 -g' "CROSS_COMPILE=$cross_prefix" SHARED=no "prefix=$mingw_w64_x86_64_prefix" || exit 1
  cd ${archdir}
}

build_libopenjpeg() {
  # TRUNK didn't seem to build right...
  #do_svn_checkout http://openjpeg.googlecode.com/svn/trunk/ openjpeg
  #cd openjpeg
  #generic_configure
  #do_make_install
  #cd ..
  download_and_unpack_file http://openjpeg.googlecode.com/files/openjpeg_v1_4_sources_r697.tgz openjpeg_v1_4_sources_r697
  cd ${archdir}/openjpeg_v1_4_sources_r697
  generic_configure
  # install pkg_config to the right dir...
  sed -i "s/\/usr\/lib/\$\(libdir\)/" Makefile 
  do_make_install
  cd ${archdir} 
}

build_libvpx() {
  download_and_unpack_file http://webm.googlecode.com/files/libvpx-v1.1.0.tar.bz2 libvpx-v1.1.0
  cd ${archdir}/libvpx-v1.1.0
  export CROSS="$cross_prefix"
  if [[ "$bits_target" = "32" ]]; then
    do_configure "--target=generic-gnu --prefix=$mingw_w64_x86_64_prefix --enable-static --disable-shared"
  else
    do_configure "--target=generic-gnu --prefix=$mingw_w64_x86_64_prefix --enable-static --disable-shared"
  fi
  do_make_install "extralibs='-lpthread'"
  cd ${archdir}
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
  cd ${archdir}/$english_name || exit "needs 2 parameters"
  generic_configure $extra_configure_options
  do_make_install
  cd ${archdir}
}

build_libgsm() {
  download_and_unpack_file http://www.quut.com/gsm/gsm-1.0.13.tar.gz gsm-1.0-pl13
  cd ${archdir}/gsm-1.0-pl13
  #not needed, but who wants toast gets toast ;-)
  sed -i -e '/HAS_FCHMOD/,+14d' src/toast.c
  sed -i -e '/HAS_FCHOWN/,+6d' src/toast.c
  make CC=${cross_prefix}gcc AR=${cross_prefix}ar RANLIB=${cross_prefix}ranlib INSTALL_ROOT=${mingw_w64_x86_64_prefix}
  cp lib/libgsm.a $mingw_w64_x86_64_prefix/lib || exit 1
  mkdir -p $mingw_w64_x86_64_prefix/include/gsm
  cp inc/gsm.h $mingw_w64_x86_64_prefix/include/gsm || exit 1
  cd ${archdir}
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
  cd ${archdir}/gmp-5.0.5
  generic_configure "ABI=$bits_target"
  do_make_install
  cd ${archdir}
}

build_gnutls() {
  generic_download_and_install ftp://ftp.gnu.org/gnu/gnutls/gnutls-3.0.22.tar.xz gnutls-3.0.22
  sed -i 's/-lgnutls *$/-lgnutls -lnettle -lhogweed -lgmp -lcrypt32/' "$PKG_CONFIG_PATH/gnutls.pc"
  cd ${archdir}
}

build_libnettle() {
  generic_download_and_install http://www.lysator.liu.se/~nisse/archive/nettle-2.5.tar.gz nettle-2.5
}

build_zlib() {
  download_and_unpack_file http://zlib.net/zlib-1.2.7.tar.gz zlib-1.2.7
  cd ${archdir}/zlib-1.2.7
    do_configure "--static --prefix=$mingw_w64_x86_64_prefix"
    do_make_install "CC=$(echo $cross_prefix)gcc AR=$(echo $cross_prefix)ar RANLIB=$(echo $cross_prefix)ranlib"
  cd ${archdir}
}

build_libxvid() {
  download_and_unpack_file http://downloads.xvid.org/downloads/xvidcore-1.3.2.tar.gz xvidcore
  cd ${archdir}/xvidcore/build/generic
  if [ "$bits_target" = "64" ]; then
    # kludgey work arounds for 64 bit
    local config_opts="--build=x86_64-unknown-linux-gnu --disable-assembly" 
  fi
  # no static option...
  do_configure "--host=$host_target --prefix=$mingw_w64_x86_64_prefix $config_opts" 
  # remove old compiler flag that now apparently breaks us
  sed -i "s/-mno-cygwin//" platform.inc 
  do_make_install
  cd ${archdir}
  # force a static build after the fact
  if [[ -f "$mingw_w64_x86_64_prefix/lib/xvidcore.dll" ]]; then
    rm $mingw_w64_x86_64_prefix/lib/xvidcore.dll || exit 1
    mv $mingw_w64_x86_64_prefix/lib/xvidcore.a $mingw_w64_x86_64_prefix/lib/libxvidcore.a || exit 1
  fi
}

build_openssl() {
  download_and_unpack_file http://www.openssl.org/source/openssl-1.0.1c.tar.gz openssl-1.0.1c
  cd ${archdir}/openssl-1.0.1c
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
  cd ${archdir}
}

build_libnut() {
    if [[ -d "${archdir}/libnut" ]]; then
        cd ${archdir}/libnut
        nutrev_old=`git rev-parse --short HEAD`
        cd ${archdir}
    else
        nutrev_old="0"
    fi
    echo -e "${INFO} \nnutrev_old: $nutrev_old\n${RST}"
    do_git_checkout git://git.ffmpeg.org/nut libnut
    cd ${archdir}/libnut
    nutrev=`git rev-parse --short HEAD`
    echo -e "${INFO} \nnutrev: $nutrev\n${RST}"
    if [[ "${nutrev_old}" == "${nutrev}" ]]; then
        echo -e "\n${PASS}libnut does not need an update.${RST}"
    else
        cd ${archdir}/libnut/src/trunk
        make clean 
        make CC="${cross_prefix}gcc" AR="${cross_prefix}ar" RANLIB="${cross_prefix}ranlib" && echo -e "${PASS}libnut buildt.${RST}" || echo -e "${WARN}Making libnut failed!${RST}"
        make install prefix="${mingw_w64_x86_64_prefix}" && echo -e "${PASS}libnut installed.${RST}" || echo -e "${WARN}libnut install failed!.${RST}"
    fi
    cd ${archdir}
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
  #-DDECLSPEC is needed for shared build
  export CFLAGS="-DDECLSPEC=" 
  generic_download_and_install http://www.libsdl.org/release/SDL-1.2.15.tar.gz SDL-1.2.15
  unset CFLAGS
  mkdir temp
  # cd - so paths will work out right
  cd temp 
  local prefix=$(basename $cross_prefix)
  local bin_dir=$(dirname $cross_prefix)
  # allow ffmpeg to output anything
  sed -i "s/-mwindows//" "$mingw_w64_x86_64_prefix/bin/sdl-config" 
  sed -i "s/-mwindows//" "$PKG_CONFIG_PATH/sdl.pc"
  # this is the only one in the PATH so use it for now
  cp "$mingw_w64_x86_64_prefix/bin/sdl-config" "$bin_dir/${prefix}sdl-config" 
  cd ..
  rmdir temp
}

#build_opus() {
#    do_git_checkout git://git.xiph.org/celt.git celt
#    cd celt
#    do_configure "--host=$host_target --enable-static --disable-shared --prefix=$mingw_w64_x86_64_prefix"
#    do_make_install
#    cd ..
#}

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

  gitdir="ffmpeg_git"
  do_git_checkout git://source.ffmpeg.org/ffmpeg.git ${gitdir}
  cd ${gitdir}
    
  local ffgit=`git rev-parse --short HEAD` && echo -e "\n${PASS}Git Hash (short): ${ffgit}${RST}"
  local ffgitrev=`git rev-list HEAD | wc -l` && let ffgitrev-- && echo -e "${PASS}Git Rev.: ${ffgitrev}\n" 
  local ffdate=`date +%Y%m%d`
  
  if [ "$bits_target" = "32" ]; then
    local arch=x86
    local ffarch=win32
  else
    local arch=x86_64
    local ffarch=win64
  fi
  
  local ffinstalldir="ffmpeg-${ffdate}-${ffgitrev}-${ffgit}-${ffarch}-${ffshared}"
  local ffinstallpath="${buildir}/${ffinstalldir}"
  if [[ -d "${ffinstallpath}" ]]; then
    rm -rf ${buildir}/${ffinstalldir}/*
  else
    mkdir -p "${ffinstallpath}"
  fi

  config_options="--prefix=$ffinstallpath --enable-memalign-hack --arch=$arch --enable-gpl --enable-libx264 --enable-avisynth --enable-libxvid --target-os=mingw32 --cross-prefix=$cross_prefix --pkg-config=pkg-config"
  config_options="$config_options --enable-libmp3lame --enable-version3 --enable-libvo-aacenc --enable-libvpx --extra-libs=-lws2_32 --extra-libs=-lpthread --enable-zlib --extra-libs=-lwinmm --extra-libs=-lgdi32 --enable-libnut"
  config_options="$config_options --enable-librtmp --enable-libvorbis --enable-libtheora --enable-libspeex --enable-libopenjpeg --enable-gnutls --enable-libgsm --enable-libfreetype"
  config_options="$config_options --enable-runtime-cpudetect"
  
  if [[ "$non_free" = "y" ]]; then
    config_options="$config_options --enable-nonfree --enable-openssl --enable-libfdk-aac" 
    # faac too poor quality and becomes the default -- add it in and comment the build_faac line to exclude it
    config_options="$config_options --enable-libfaac"
  fi
  
  if [[ "$ffshared" = "shared" ]] ; then
    config_options="$config_options --disable-static --enable-shared"
  fi
  
  do_configure "$config_options"
  # just in case some library dependency was updated, force it to re-link
  rm -f *.exe 
  
  echo -e "\n${INFO}ffmpeg: doing PATH=$PATH make${RST}\n"
  local cpucount=`grep -c ^processor /proc/cpuinfo`
  make -j${cpucount} || exit 1
  make install
  
  local cur_dir2=$(pwd)
  
  cd ${buildir}
  #cp docs to install dir
  cp -r ${cur_dir2}/doc ${ffinstallpath}/ 
  if [[ ! "${bz2dir}" = "" && ! "${ffinstalldir}" = "" ]]; then
    echo -e "\n${INFO}Compressing to ${ffinstalldir}.tar.bz2 ${RST}\n"
    tar -cjf "${bz2dir}"/${ffinstalldir}.tar.bz2 ${ffinstalldir} && rm -rf ${ffinstalldir}/* && rmdir ${ffinstalldir}
  fi 
   
  cd ${cur_dir2}
  echo -e "${PASS}\n Done! You will find the bz2 packed binaries in ${bz2dir} ${RST}\n"
  cd ..
}

build_all() {
  # rtmp depends on it [as well as ffmpeg's optional but handy --enable-zlib]
  build_zlib 
  build_gmp
  # needs gmp
  build_libnettle 
  # needs libnettle
  build_gnutls 
  build_libgsm
  # needed for ffplay to be created
  build_sdl 
  build_libogg
  # needs libogg
  build_libspeex 
  # needs libogg
  build_libvorbis
  # needs libvorbis, libogg
  build_libtheora 
  build_libxvid
  build_x264
  build_lame
  build_libvpx
  build_vo_aacenc
  build_freetype
  build_libopenjpeg
  build_libnut
  if [[ "$non_free" = "y" ]]; then
    build_fdk_aac
    build_faac 
  fi
  build_openssl
  # needs openssl
  build_librtmp 
  if $ffbuildstatic; then
    build_ffmpeg
  fi
  if $ffbuildshared; then  
    build_ffmpeg shared
  fi
}
################################################################################

# Main #########################################################################

make_dir "${bz2dir}"

# Remember to always run the intro, since it adjust pwd
intro 

# Always run this, too, since it adjust the PATH
install_cross_compiler 

setup_env

original_path="$PATH"

# 32bit
if [ -d "mingw-w64-i686" ]; then 
  echo -e "\n${PASS}Building 32-bit ffmpeg...${RST}"
  host_target='i686-w64-mingw32'
  mingw_w64_x86_64_prefix="${buildir}/mingw-w64-i686/$host_target"
  export PATH="${buildir}/mingw-w64-i686/bin:$original_path"
  export PKG_CONFIG_PATH="${buildir}/mingw-w64-i686/i686-w64-mingw32/lib/pkgconfig"
  bits_target=32
  cross_prefix="${buildir}/mingw-w64-i686/bin/i686-w64-mingw32-"
  archdir="${buildir}/win32"
  mkdir -p ${archdir}
  cd ${archdir}
  build_all
  cd ${buildir}
fi

# 64bit 
if [ -d "mingw-w64-x86_64" ]; then 
  echo -e "\n${PASS}Building 64-bit ffmpeg...${RST}"
  host_target='x86_64-w64-mingw32'
  mingw_w64_x86_64_prefix="${buildir}/mingw-w64-x86_64/$host_target"
  export PATH="${buildir}/mingw-w64-x86_64/bin:$original_path"
  export PKG_CONFIG_PATH="${buildir}/mingw-w64-x86_64/x86_64-w64-mingw32/lib/pkgconfig"
  bits_target=64
  cross_prefix="${buildir}/mingw-w64-x86_64/bin/x86_64-w64-mingw32-"
  archdir="${buildir}/x86_64"
  mkdir -p ${archdir}
  cd ${archdir}
  build_all
  cd ${buildir}
fi

cd ..
echo -e "${WARN}\nAll complete. Ending ffmpeg cross compiler script.\n${PASS}Bye. ;-) ${RST}\n "
