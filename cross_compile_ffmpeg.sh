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
# Base directory
basedir="$(pwd)"
# Build directory
buildir="${basedir}/build"
# Target directory for bz2-files (if unset, no .tar.bz will be made)
bz2dir="${basedir}/bz2"

# Build static (default: true)
ffbuildstatic=false
# Build shared (default: false)
ffbuildshared=true
# make 32bit build (default: true)
ff32=true
# make 64bit build (default: true)
ff64=true
# do vanilla ffmpeg build (no external libaries) (default: true)
ffvanilla=false
# bild non free libs (default: false)
ffnonfree=true
# build ffmpeg (default: true)
ffmpeg=true
# build ffmbc (default: false)
ffmbc=true
# use gnutls instead of openssl for librtmp (default: true)
ffgnutls=true

# Ask me questions and show the intro or run with options configured above! (default: true)
askmequestions=false

################################################################################

type -p lib.exe >/dev/null 2>&1 && libexeok=true || libexeok=false
if $libexeok
then
    libexepath=`type -p lib.exe | head -n1 -q`
fi

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
    while [[ "$user_input" != [YyNn] ]]
    do
        echo -e "$question \c"
        read user_input
        if [[ "$user_input" != [YyNn] ]]
        then
            echo -e "\n${WARN}Your selection was not vaild, please try again.\n${RST}"
        fi
    done
    # downcase it
    user_input=$(echo $user_input | tr '[A-Z]' '[a-z]')
}

make_dir () {
    if [[ ! -d "$*" ]]
    then
        mkdir -p "$*" 
        if [[ ! -d "$*" ]]
        then
            echo -e "\n${WARN}Could not create $*.\nExiting! ${RST}"; exit 1
        else
            echo -e "\n${PASS}Successfully created $* ${RST}"
        fi
    else
        if [[ ! -w "${buildir}" ]]
        then
            echo -e "\n${WARN}No write permissions in $*.\nExiting! ${RST}"; exit 1
        else
            echo -e "\n${PASS} Directory $* already exists and is writeable. ${RST}"
        fi
    fi
}

intro() {
    echo -e "\n${PASS}============================== Welcome ==============================${RST}"
    echo -e "Welcome to the ffmpeg cross-compile builder-helper script."
    echo -e "Downloads and builds will be processed within the folder"
    echo -e "    $buildir"
    echo -e "If this is not ok, then exit now, and cd to the directory where"
    echo -e "you would like them installed, then run this script again."

    yes_no_sel "${QUES}Is ${buildir} ok? ${RST}[y/n]?"
    if [[ "${user_input}" = "n" ]]
    then
        exit 1
    fi
    
    yes_no_sel "\n${QUES}Build and include external libs? (libx264,librtmp,libxvid, etc) ${RST} [y/n]?"
    if [[ "$user_input" = "y" ]]
    then 
        ffvanilla=false
        echo "true"
        echo -e "\nWould you like to include non-free (non GPL compatible) libraries, like certain high quality aac encoders?"
        echo -e "The resultant binary will not be distributable, but might be useful for in-house use."
        yes_no_sel "${QUES}Include non-free?${RST} [y/n]?"
        [[ "$user_input" = "y" ]] && ffnonfree=true || ffnonfree=false
        echo $ffnonfree
    else
        ffvanilla=true
        echo "false"
    fi
    
    # disabled for now
    #yes_no_sel "\n${QUES}Would you like to also build ffmbc?${RST} [y/n]?"
    #if [[ "$user_input" = "y" ]]
    #then 
    #    ffmbc=true
    #fi
    
    yes_no_sel "\n${QUES}Would you like to make a 32-bit build?${RST} [y/n]?"
    [[ "$user_input" = "y" ]] && ff32=true || ff32=false
    echo $ff32

    yes_no_sel "\n${QUES}Would you like to make a 64-bit build?${RST} [y/n]?"
    [[ "$user_input" = "y" ]] && ff64=true || ff64=false
    echo $ff64
    
    if ! $ff32 && ! $ff64
    then
        echo -e "\n${WARN}Neither 32-bit nor 64-bit build selected!\nExiting${RST}"
        exit 1
    fi
    
    if $libexeok
    then
        yes_no_sel "\n${QUES}Would you like to make a static build?${RST} [y/n]?"
        [[ "$user_input" = "y" ]] && ffbuildstatic=true || ffbuildstatic=false
        echo $ffbuildstatic
        
        yes_no_sel "\n${QUES}Would you like to make a shared build?${RST} [y/n]?"
        [[ "$user_input" = "y" ]] && ffbuildshared=true || ffbuildshared=false
        echo $ffbuildshared
        if ! $ffbuildstatic && ! $ffbuildshared 
        then
            echo -e "\n${WARN}Neither static nor shared build selected!\nExiting${RST}"
            exit 1
        fi
    else
        echo -e "\n${WARN}Wine with installed lib.exe required for shared ffmpeg builds, but it could not be found.\nCan not build shared libs!${RST}"
        echo -e "\n${INFO}Only static builds will be done!${RST}"
        ffbuildstatic=true
    fi
}

install_cross_compiler() {
    if [[ -f "mingw-w64-i686/compiler.done" || -f "mingw-w64-x86_64/compiler.done" ]]
    then
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
    if [ -d mingw-w64-x86_64 ]
    then
        touch mingw-w64-x86_64/compiler.done
    fi
    if [ -d mingw-w64-i686 ]
    then
        touch mingw-w64-i686/compiler.done
    fi
    echo -e "${PASS}OK, done building MinGW-w64 cross-compiler...${RST}\n"
}

setup_env() {
    # disable pkg-config from reverting back to and finding system installed packages [yikes]
    export PKG_CONFIG_LIBDIR= 
}

do_svn_checkout() {
    repo_url="$1"
    to_dir="$2"
    if [ ! -d $to_dir ]
    then
        echo -e "${INFO}svn checking out to $to_dir ${RST}\n"
        svn checkout $repo_url $to_dir.tmp || exit 1
        mv $to_dir.tmp $to_dir
    else
        cd ${archdir}/${to_dir}
        echo -e "${INFO}Updating $to_dir ${RST}\n"
        svn up
        cd ${archdir}
    fi
}

do_git_checkout() {
    repo_url="$1"
    to_dir="$2"
    if [ ! -d $to_dir ]
    then
        echo -e "${INFO}Downloading (via git clone) $to_dir ${RST}"
        # prevent partial checkouts by renaming it only after success
        git clone $repo_url $to_dir.tmp || exit 1
        mv $to_dir.tmp $to_dir
        echo -e "${PASS}Done downloading $to_dir ${RST}\n"
    else
        cd ${archdir}/${to_dir}
        echo -e "${INFO}Updating local git repository to latest $to_dir version.${RST}"
        local old_git_version=`git rev-parse HEAD`
        git pull
        local new_git_version=`git rev-parse HEAD`
        if [[ "$old_git_version" != "$new_git_version" ]]
        then
            echo -e "${PASS}${to_dir} updated..${RST}"
            # force reconfigure always...
            rm already* # force reconfigure always...
        else
            echo -e "${PASS}${to_dir} does not need an update.${RST}\n"
        fi 
        cd ${archdir}
    fi
}

do_configure() {
    configure_options="$1"
    configure_name="$2"
    [[ "$configure_name" = "" ]] && configure_name="./configure"
    local localdir=$(pwd)
    local english_name=$(basename $localdir)
    # sanitize, disallow too long of length
    local touch_name=$(echo -- $configure_options | /usr/bin/env md5sum) 
    # add prefix so we can delete it easily, remove spaces
    touch_name=$(echo already_configured_$touch_name | sed "s/ //g") 
    if [ $english_name = "ffmpeg_git" -o $english_name = "FFmbc-0.7-rc7" -o ! -f "$touch_name" ]
    then 
        # any old configuration options, since they'll be out of date after the next configure
        rm -f already*
        # always distclean before configuring
        make -s distclean
        [ -f autogen.sh ] && ./autogen.sh || [ -f bootstrap.sh ] && ./bootstrap.sh
        echo -e "${INFO}Configuring $english_name\nPATH=$PATH $configure_name $configure_options${RST}"
        "$configure_name" $configure_options || exit 1
        touch -- "$touch_name"
    else
        echo -e "${PASS}Already configured $localdir ${RST}" 
    fi
}

generic_configure() {
    local extra_configure_options="$*"
    do_configure "--host=$host_target --prefix=$mingwprefix --disable-shared --enable-static $extra_configure_options"
    # --build=x86_64-unknown-linux-gnu --target=$host_target
}

do_make() {
    extra_make_options="$*"
    local localdir=$(pwd)
    if [ ! -f already_ran_make ]
    then
        echo -e "${INFO}Making ${localdir} as:\nPATH=$PATH make ${extra_make_options} ${RST}"
        make -s clean
        make $extra_make_options || exit 1
        touch already_ran_make
        echo -e "${PASS}Successfully did make and install $(basename "$localdir") ${RST}\n"
    else
        echo -e "${PASS}Already did make  $(basename "$localdir") ${RST}\n"
    fi
}


do_make_install() {
    extra_make_options="$*"
    local localdir=$(pwd)
    if [ ! -f already_ran_make ]
    then
        echo -e "${INFO}Making ${localdir} as:\n PATH=$PATH make ${extra_make_options} ${RST}"
        make -s clean
        make $extra_make_options || exit 1
        touch already_ran_make
        make install || exit 1
        touch already_ran_make_install
        echo -e "${PASS}Successfully did make and install $(basename "$localdir") ${RST}\n"
    else
        echo -e "${PASS}Already did make and install $(basename "$localdir") ${RST}\n"
    fi
}

download_and_unpack_file() {
    url="$1"
    output_name=$(basename $url)
    output_dir="$2"
    if [ ! -f "$output_dir/unpacked.successfully" ]
    then
        if [ ! -f "$output_name" ]
        then
            wget "$url" -O "$output_name" || exit 1
        fi
        tar -xf "$output_name" || unzip $output_name || exit 1
        touch "$output_dir/unpacked.successfully"
        # rm "$output_name"
    fi
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

build_x264() {
    do_git_checkout "http://repo.or.cz/r/x264.git" "x264"
    cd ${archdir}/x264
    do_configure "--host=$host_target --enable-static --cross-prefix=$cross_prefix --prefix=$mingwprefix --enable-win32thread"
    # rm -f already_ran_make # just in case the git checkout did something, re-make
    do_make_install
    cd ${archdir}
}

build_librtmp() {
    do_git_checkout "http://repo.or.cz/r/rtmpdump.git" rtmpdump_git
    cd ${archdir}/rtmpdump_git/librtmp
        if $ffgnutls && [ ! -f "already_gnutls" ]
        then
            [ -f "already_openssl" ] && rm "already_openssl"
            make install CRYPTO=GNUTLS OPT='-O2 -g' "CROSS_COMPILE=$cross_prefix" SHARED=no "prefix=$mingwprefix" || exit 1
            touch already_gnutls
        elif ! $ffgnutls && [ ! -f "already_openssl" ]
        then
            [ -f "already_gnutls" ] && rm "already_gnutls"
            make install OPT='-O2 -g' "CROSS_COMPILE=$cross_prefix" SHARED=no "prefix=$mingwprefix" || exit 1
            touch already_openssl
        fi
        touch already_ran_make_install
        echo -e "${PASS}Successfully did make and install librtmp ${RST}\n"
    cd ${archdir}
}

build_utvideo() {
    # shared ffmpeg will not build with utvideo
    local localdir="utvideo-11.1.0"
    download_and_unpack_file https://github.com/downloads/rdp/FFmpeg/utvideo-11.1.0-src.zip ${localdir}
    cd ${localdir}
    if [ ! -f "already_ran_make_install" ]
    then
        local file2patch="utv_core/Codec.h"
        if grep -Fxq "#include <windows.h>" $file2patch
        then
            echo -e "${INFO}Already patched ${file2patch} ${RST}\n"
        else
            echo -e "${INFO}Patching ${file2patch} ${RST}\n"
            sed -i 's@#pragma once@#pragma once\n#include <windows.h>@' $file2patch
            sed -i 's@\r@@' $file2patch
        fi
        make install CROSS_PREFIX=$cross_prefix DESTDIR= prefix=$mingwprefix || exit 1
        touch already_ran_make_install
        echo -e "${PASS}Successfully did make and install ${localdir} ${RST}\n"
    fi
    cd ${archdir}
}

build_libopenjpeg() {
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
    if [[ "$bits_target" = "32" ]]
    then
        do_configure "--target=generic-gnu --prefix=$mingwprefix --enable-static --disable-shared"
    else
        do_configure "--target=generic-gnu --prefix=$mingwprefix --enable-static --disable-shared"
    fi
    do_make_install "extralibs='-lpthread'"
    cd ${archdir}
}

build_libflite() {
    # There's still a problem with 64 bits builds of ffmpeg
    download_and_unpack_file http://www.speech.cs.cmu.edu/flite/packed/flite-1.4/flite-1.4-release.tar.bz2 flite-1.4-release
    cd flite-1.4-release
    sed -i "s|i386-mingw32-|$cross_prefix|" configure*
    generic_configure
    do_make
    make install # it fails in error...
    if [[ "$bits_target" = "32" ]]
    then
        cp ./build/i386-mingw32/lib/*.a $mingwprefix/lib || exit 1
    else
        cp ./build/x68_64-mingw32/lib/*.a $mingwprefix/lib || exit 1
    fi
    cd ${archdir}
}

build_libgsm() {
    download_and_unpack_file http://www.quut.com/gsm/gsm-1.0.13.tar.gz gsm-1.0-pl13
    if [[ ! -f $mingwprefix/include/gsm/gsm.h  || ! -f $mingwprefix/lib/libgsm.a ]]
    then
        cd ${archdir}/gsm-1.0-pl13
        # not really needed, but who wants toast gets toast ;-)
        sed -i -e '/HAS_FCHMOD/,+14d' src/toast.c
        sed -i -e '/HAS_FCHOWN/,+6d' src/toast.c
        make CC=${cross_prefix}gcc AR=${cross_prefix}ar RANLIB=${cross_prefix}ranlib INSTALL_ROOT=${mingwprefix}
        cp lib/libgsm.a $mingwprefix/lib || exit 1
        mkdir -p $mingwprefix/include/gsm
        cp inc/gsm.h $mingwprefix/include/gsm || exit 1
    fi
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

build_libfribidi() {
    local localpath="fribidi-0.19.4"
    download_and_unpack_file http://fribidi.org/download/fribidi-0.19.4.tar.bz2 ${localpath}
    cd ${archdir}/${localpath}
    if [[ ! -f already_ran_make ]]
    then
        # export symbols right...
        patch -f -p0 <<EOL
--- lib/fribidi-common.h	2008-02-04 21:30:46.000000000 +0000
+++ lib/fribidi-common.h	2008-02-04 21:32:25.000000000 +0000
@@ -53,11 +53,7 @@
 
 /* FRIBIDI_ENTRY is a macro used to declare library entry points. */
 #ifndef FRIBIDI_ENTRY
-# if (defined(WIN32)) || (defined(_WIN32_WCE))
-#  define FRIBIDI_ENTRY __declspec(dllimport)
-# else /* !WIN32 */
 #  define FRIBIDI_ENTRY		/* empty */
-# endif	/* !WIN32 */
 #endif /* !FRIBIDI_ENTRY */
 
 #if FRIBIDI_USE_GLIB+0

EOL
    fi
    generic_configure
    do_make_install
    cd ${archdir}
}

build_libass() {
  generic_download_and_install http://libass.googlecode.com/files/libass-0.10.0.tar.gz libass-0.10.0
  sed -i 's/-lass -lm/-lass -lfribidi -lm/' "$PKG_CONFIG_PATH/libass.pc"
  cd ${archdir}
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
    do_configure "--static --prefix=$mingwprefix"
    do_make_install "CC=$(echo $cross_prefix)gcc AR=$(echo $cross_prefix)ar RANLIB=$(echo $cross_prefix)ranlib"
    cd ${archdir}
}

build_libxvid() {
    download_and_unpack_file http://downloads.xvid.org/downloads/xvidcore-1.3.2.tar.gz xvidcore
    cd ${archdir}/xvidcore/build/generic
    if [ "$bits_target" = "64" ]
    then
        # kludgey work arounds for 64 bit
        local config_opts="--build=x86_64-unknown-linux-gnu --disable-assembly" 
    fi
    # no static option...
    do_configure "--host=$host_target --prefix=$mingwprefix $config_opts" 
    # remove old compiler flag that now apparently breaks us
    sed -i "s/-mno-cygwin//" platform.inc 
    do_make_install
    # force a static build after the fact
    if [[ -f "$mingwprefix/lib/xvidcore.dll" ]]
    then
        rm $mingwprefix/lib/xvidcore.dll || exit 1
        mv $mingwprefix/lib/xvidcore.a $mingwprefix/lib/libxvidcore.a || exit 1
    fi
    cd ${archdir}
}

build_fontconfig() {
    local localdir="fontconfig-2.10.1"
    download_and_unpack_file http://www.freedesktop.org/software/fontconfig/release/fontconfig-2.10.1.tar.gz ${localdir}
    cd ${localdir}
    if $libexeok && [ ! -f "${basedir}/lib" ]
    then
        ln -s "${libexepath}" "${basedir}/lib"
    fi
    generic_configure --disable-docs 
    do_make_install
    rm "${basedir}/lib"
    cd ${archdir}
    sed -i 's/-L${libdir} -lfontconfig[^l]*$/-L${libdir} -lfontconfig -lfreetype -lexpat/' "$PKG_CONFIG_PATH/fontconfig.pc"
}

build_openssl() {
    download_and_unpack_file http://www.openssl.org/source/openssl-1.0.1c.tar.gz openssl-1.0.1c
    cd ${archdir}/openssl-1.0.1c
    export cross="$cross_prefix"
    export CC="${cross}gcc"
    export AR="${cross}ar"
    export RANLIB="${cross}ranlib"
    if [ "$bits_target" = "32" ]
    then
        do_configure "--prefix=$mingwprefix no-shared mingw" ./Configure
    else
        do_configure "--prefix=$mingwprefix no-shared mingw64" ./Configure
    fi
    do_make_install
    unset cross
    unset CC
    unset AR
    unset RANLIB
    cd ${archdir}
}

build_libnut() {
    local localdir="libnut"
    if [[ -d "${archdir}/${localdir}" ]]
    then
        cd ${archdir}/${localdir}
        local githash_old=`git rev-parse --short HEAD`
        cd ${archdir}
    else
        local githash_old="0"
    fi
    do_git_checkout git://git.ffmpeg.org/nut ${localdir}
    cd ${archdir}/${localdir}
    local githash=`git rev-parse --short HEAD`
    if [[ "${githash_old}" != "${githash}" ]]
    then
        cd ${archdir}/${localdir}/src/trunk
        make clean 
        make CC="${cross_prefix}gcc" AR="${cross_prefix}ar" RANLIB="${cross_prefix}ranlib" && echo -e "${PASS}libnut built.${RST}" || echo -e "${WARN}Making libnut failed!${RST}"
        make install prefix="${mingwprefix}" && echo -e "${PASS}libnut installed.${RST}\n" || echo -e "${WARN}libnut install failed!.${RST}\n"
    fi
    cd ${archdir}
}

build_fdk_aac() {
    local localdir="fdk-aac"
    do_git_checkout git://github.com/mstorsjo/fdk-aac.git ${localdir}
    cd ${archdir}/${localdir}
    if [[ ! -f configure ]]
    then
        libtoolize
        aclocal
        autoheader
        automake --force-missing --add-missing --gnu
        autoconf
    fi
    generic_configure
    do_make_install
    cd ${archdir}
}

build_libexpat() {
  generic_download_and_install http://sourceforge.net/projects/expat/files/expat/2.1.0/expat-2.1.0.tar.gz/download expat-2.1.0 --with-gnu-ld
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
    sed -i "s/-mwindows//" "$mingwprefix/bin/sdl-config" 
    sed -i "s/-mwindows//" "$PKG_CONFIG_PATH/sdl.pc"
    # this is the only one in the PATH so use it for now
    cp "$mingwprefix/bin/sdl-config" "$bin_dir/${prefix}sdl-config" 
    cd ${archdir}
    rmdir temp
}

build_libopus() {
    local localdir="libopus"
    do_git_checkout git://git.opus-codec.org/opus.git ${localdir}
    cd ${archdir}/${localdir}
    do_configure "--host=$host_target --enable-static --disable-shared --prefix=$mingwprefix"
    do_make_install
    cd ${archdir}
}

build_faac() {
    generic_download_and_install http://downloads.sourceforge.net/faac/faac-1.28.tar.gz faac-1.28 "--with-mp4v2=no"
}

build_lame() {
    generic_download_and_install http://sourceforge.net/projects/lame/files/lame/3.99/lame-3.99.5.tar.gz/download lame-3.99.5
}

build_bz2() {
    local localdir="bzip2-1.0.6"
    download_and_unpack_file http://www.bzip.org/1.0.6/bzip2-1.0.6.tar.gz  ${localdir}
    cd ${localdir}
    if [ -f already_ran_make ]
    then
        file2patch="bzip2.c"
        if grep -Fxq "sys\\stat.h" $file2patch
        then
            echo -e "${INFO}Patching ${file2patch} ${RST}"
            sed -i 's@sys\\stat.h@sys/stat.h@' bzip2.c $file2patch
        else
            echo -e "${PASS}Already patched ${file2patch} ${RST}"
        fi
        if [ "$bits_target" = "64" ]
        then
            sed -i 's@all: libbz2.a bzip2 bzip2recover test@all: libbz2.a bzip2 bzip2recover@' Makefile
        fi
        make clean
        do_make "CC=$(echo $cross_prefix)gcc AR=$(echo $cross_prefix)ar RANLIB=$(echo $cross_prefix)ranlib"
        if [ ! -f already_ran_make_install ]
        then
            make install "PREFIX=${mingwprefix}"
            touch already_ran_make_install
            cd "${mingwprefix}/bin"
            mv -f bzip2 bzip2.exe
            mv -f bunzip2 bunzip2.exe
            mv -f bzcat bzcat.exe
            mv -f bzip2recover bzip2recover.exe
            cp -f bzgrep bzegrep.exe
            cp -f bzgrep bzfgrep.exe
            mv -f bzgrep bzgrep.exe
            cp -f bzmore bzless.exe
            mv -f bzmore bzmore.exe
            cp -f bzdiff bzcmp.exe
            mv -f bzdiff bzdiff.exe
            rm bzcmp bzegrep bzfgrep bzless
            touch 
        fi
    fi
    cd ${archdir}
}

build_ffmbc() {
    local localdir="FFmbc-0.7-rc7"
    local ffdate=`date +%Y%m%d`
    download_and_unpack_file http://ffmbc.googlecode.com/files/FFmbc-0.7-rc7.tar.bz2 ${localdir}
    cd ${localdir}
    local file2patch="libavcodec/dxva2_internal.h"
    if grep -Fxq "#include \"dxva.h\"" $file2patch
    then
        echo -e "${PASS}Already patched ${file2patch} ${RST}"
    else
        echo -e "${INFO}Patching ${file2patch} ${RST}"
        sed -i '28 i#include \"dxva.h\"' $file2patch
    fi
    file2patch="libavdevice/dshow_filter.c"
    if grep -Fxq "#define NO_DSHOW_STRSAFE" $file2patch
    then
        echo -e "${PASS}Already patched ${file2patch} ${RST}"
    else
        echo -e "${INFO}Patching ${file2patch} ${RST}"
        sed -i '22 i#define NO_DSHOW_STRSAFE' $file2patch
    fi
    local file2patch="libavdevice/dshow_pin.c"
    if grep -Fxq "#define NO_DSHOW_STRSAFE" $file2patch
    then
        echo -e "${PASS}Already patched ${file2patch} ${RST}"
    else
        echo -e "${INFO}Patching ${file2patch} ${RST}"
        sed -i '22 i#define NO_DSHOW_STRSAFE' $file2patch
    fi
    
    if [[ "$1" = "shared" ]]
    then 
        local ffshared="shared"
    else
        local ffshared="static"
    fi
    
    if [ "$bits_target" = "32" ]
    then
        local arch=x86
    else
        local arch=x86_64
    fi
    local ffarch="win${bits_target}"
    local ffinstalldir="${localdir}-${ffarch}-${ffshared}"
    if $ffvanilla
    then
        ffinstalldir="${ffinstalldir}-vanilla"
    fi
    local ffinstallpath="${buildir}/${ffinstalldir}"
    if [[ -d "${ffinstallpath}" ]]
    then
        rm -rf ${buildir}/${ffinstalldir}/*
    else
        mkdir -p "${ffinstallpath}"
    fi
    
    config_options="--prefix=$ffinstallpath --enable-memalign-hack --arch=$arch --enable-gpl --enable-avisynth --target-os=mingw32 --cross-prefix=$cross_prefix" 
    config_options="$config_options --pkg-config=pkg-config --enable-runtime-cpudetect --enable-cross-compile"
    if ! $ffvanilla
    then
        config_options="$config_options --enable-zlib --enable-bzlib --enable-libx264 --enable-libmp3lame --enable-libvpx --extra-libs=-lws2_32 --extra-libs=-lpthread" 
        config_options="$config_options --extra-libs=-lwinmm --extra-libs=-lgdi32 --enable-libnut"
        config_options="$config_options --enable-librtmp --enable-libvorbis --enable-libtheora --enable-libopenjpeg --enable-libspeex --enable-libgsm --enable-libfreetype --enable-libass"
        
        if $ffnonfree
        then
            config_options="$config_options --enable-nonfree --enable-libfaac"
        fi
    fi
    
    if [[ "$ffshared" = "shared" ]]
    then
        config_options="$config_options --disable-static --enable-shared"
    else
        config_options="$config_options"
    fi
    
    do_configure "$config_options"
    
    # just in case some library dependency was updated, force it to re-link
    rm -f *.exe 
    
    echo -e "\n${INFO} ffmbc: doing PATH=$PATH make${RST}\n"
    local cpucount=`grep -c ^processor /proc/cpuinfo`
    make clean
    make -j${cpucount} || exit 1
    make install && echo -e "${PASS} Successfully did make and install ${localdir} ${RST}\n"
    
    local localdir=$(pwd)
    cd ${buildir}
    #cp docs to install dir
    cp -r ${localdir}/doc ${ffinstallpath}/ 
    if [[ ! "${bz2dir}" = "" && ! "${ffinstalldir}" = "" ]]
    then
        make_dir "${bz2dir}"
        echo -e "${INFO} Compressing to ${ffinstalldir}.tar.bz2 ${RST}\n"
        tar -cjf "${bz2dir}"/${ffinstalldir}.tar.bz2 ${ffinstalldir} && rm -rf ${ffinstalldir}/* && rmdir ${ffinstalldir}
    fi 
    
    echo -e "${PASS} Done! You will find the bz2 packed binaries in ${bz2dir} ${RST}\n"
    
    cd ${archdir}
}

build_ffmpeg() {
    if [[ "$1" = "shared" ]]
    then 
        local ffshared="shared"
    else
        local ffshared="static"
    fi

    gitdir="ffmpeg_git"
    do_git_checkout git://source.ffmpeg.org/ffmpeg.git ${gitdir}
    cd ${gitdir}
      
    local ffgit=`git rev-parse --short HEAD` && echo -e "${PASS}ffmpeg git hash (short): ${ffgit}${RST}"
    local ffgitrev=`git rev-list HEAD | wc -l` && let ffgitrev-- && echo -e "${PASS} ffmpeg rev.: ${ffgitrev}${RST}\n" 
    local ffdate=`date +%Y%m%d`

    if [ "$bits_target" = "32" ]
    then
        local arch=x86
    else
        local arch=x86_64
    fi
    local ffarch="win${bits_target}"
    local ffinstalldir="ffmpeg-${ffdate}-${ffgitrev}-${ffgit}-${ffarch}-${ffshared}"
    if $ffvanilla
    then
        ffinstalldir="${ffinstalldir}-vanilla"
    fi
    local ffinstallpath="${buildir}/${ffinstalldir}"
    if [[ -d "${ffinstallpath}" ]]
    then
        rm -rf ${buildir}/${ffinstalldir}/*
    else
        mkdir -p "${ffinstallpath}"
    fi
    
    config_options="--prefix=$ffinstallpath --enable-memalign-hack --arch=$arch --enable-runtime-cpudetect --enable-gpl --enable-version3 --enable-avisynth" 
    config_options="$config_options --target-os=mingw32 --cross-prefix=$cross_prefix --pkg-config=pkg-config"
    if ! $ffvanilla
    then
        config_options="$config_options --enable-zlib --enable-bzlib --enable-libx264 --enable-libxvid --enable-libmp3lame --enable-libvo-aacenc --enable-libvpx"
        config_options="$config_options --extra-libs=-lws2_32 --extra-libs=-lpthread --extra-libs=-lwinmm --extra-libs=-lgdi32 --enable-libnut"
        config_options="$config_options --enable-librtmp --enable-libvorbis --enable-libtheora --enable-libspeex --enable-libopenjpeg --enable-libgsm --enable-libfreetype"
        # config_options="$config_options --enable-libutvideo"
        config_options="$config_options --enable-fontconfig --enable-libass --enable-libopus"
        
        if $ffnonfree
        then
            config_options="$config_options --enable-nonfree --enable-libfdk-aac" 
            # faac is less quality than fdk.aac and becomes the default -- comment the build_faac line to exclude it
            config_options="$config_options --enable-libfaac"
        fi
        
        if  $ffgnutls
        then
            config_options="$config_options --enable-gnutls "
        else
            config_options="$config_options --enable-openssl"
        fi
    fi
    
    if [[ "$ffshared" = "shared" ]]
    then
        config_options="$config_options --disable-static --enable-shared"
    fi
    
    do_configure "$config_options"
    
    # just in case some library dependency was updated, force it to re-link
    rm -f *.exe 
    
    echo -e "${INFO} ffmpeg: doing PATH=$PATH make${RST}\n"
    local cpucount=`grep -c ^processor /proc/cpuinfo`
    make clean
    make -j${cpucount} || exit 1
    make install && echo -e "${PASS} Successfully did make and install ${localdir} ${RST}\n"
    
    local localdir=$(pwd)
    cd ${buildir}
    #cp docs to install dir
    cp -r ${localdir}/doc ${ffinstallpath}/ 
    if [[ ! "${bz2dir}" = "" && ! "${ffinstalldir}" = "" ]]
    then
        make_dir "${bz2dir}"
        echo -e "${INFO} Compressing to ${ffinstalldir}.tar.bz2 ${RST}\n"
        tar -cjf "${bz2dir}"/${ffinstalldir}.tar.bz2 ${ffinstalldir} && rm -rf ${ffinstalldir}/* && rmdir ${ffinstalldir}
    fi 
    echo -e "${PASS} Done! You will find the bz2 packed binaries in ${bz2dir} ${RST}\n"
    cd ${archdir}
}

build_all() {
    if ! $ffvanilla
    then
        # rtmp depends on it [as well as ffmpeg's optional but handy --enable-zlib]
        build_zlib 
        build_bz2
        if $gnutls
        then
            build_gmp
            # needs gmp
            build_libnettle 
            # needs libnettle
            build_gnutls
        else
            build_openssl
        fi
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
        build_utvideo
        build_freetype
        build_libexpat
        #needs libexpat, freetype
        build_fontconfig
        build_libfribidi
        # needs libexpat, fontconfig, libfribidi, freetype
        build_libass
        build_libopus
        build_libopenjpeg
        build_libnut
        if $ffnonfree
        then
            build_fdk_aac
            build_faac
        fi
        # needs openssl or gnutls
        build_librtmp 
    fi
    
    if $ffbuildstatic
    then
        if $ffmbc 
        then
            build_ffmbc
        fi
        if $ffmpeg 
        then
            build_ffmpeg
        fi
    fi
    
    if $ffbuildshared
    then
        # only build vanilla shared libs, as others failATM
        if $ffmbc && $ffvanilla
        then
            build_ffmbc shared
        fi
        if $ffmpeg 
        then
            build_ffmpeg shared
        fi
    fi
}
################################################################################

# Main #########################################################################

if [[ $EUID -eq 0 ]] 
then
    echo -e "${WARN}This script must not be run as root!\nExiting!\n${PASS}Bye ;-)${RST}" && exit 1
fi

if $askmequestions 
then
    intro
fi

make_dir "${buildir}"  
cd "${buildir}"

# Always run this, too, since it adjust the PATH
install_cross_compiler 
setup_env
original_path="$PATH"

# 32bit
mingwdir="${buildir}/mingw-w64-i686"
if [ -d "${mingwdir}" ] && $ff32
then 
    echo -e "\n${PASS}===========================\nBuilding 32-bit ffmpeg...\n===========================\n${RST}"
    host_target='i686-w64-mingw32'
    mingwprefix="${mingwdir}/${host_target}"
    export PATH="${mingwdir}/bin:${basedir}:${original_path}"
    export PKG_CONFIG_PATH="${mingwprefix}/lib/pkgconfig"
    bits_target=32
    cross_prefix="${mingwdir}/bin/i686-w64-mingw32-"
    archdir="${buildir}/win32"
    mkdir -p ${archdir}
    cd ${archdir}
    build_all
    cd ${buildir}
else
    if $ff32
    then
        echo -e "${WARN}\nmingw-w64-i686 toolchain not present. Can not buitld 32bit ffmpeg${RST}\n "
    fi
fi

# 64bit
mingwdir="${buildir}/mingw-w64-x86_64"
if [ -d "${mingwdir}" ] && $ff64
then 
    echo -e "\n${PASS}===========================\nBuilding 64-bit ffmpeg...\n===========================\n${RST}"
    host_target='x86_64-w64-mingw32'
    mingwprefix="${mingwdir}/${host_target}"
    export PATH="${mingwdir}/bin:${basedir}:${original_path}"
    export PKG_CONFIG_PATH="${mingwprefix}/lib/pkgconfig"
    bits_target=64
    cross_prefix="${mingwdir}/bin/x86_64-w64-mingw32-"
    archdir="${buildir}/x86_64"
    mkdir -p ${archdir}
    cd ${archdir}
    build_all
    cd ${buildir}
else
    if $ff64
    then
        echo -e "${WARN}\nmingw-w64-x86_64 toolchain not present. Can not buitld 64bit ffmpeg${RST}\n "
    fi
fi

export PATH="${original_path}"
cd ${basedir}
echo -e "${PASS}\nAll complete. Ending ffmpeg cross compiler script.\n${PASS}Bye. ;-) ${RST}\n "

exit 0
