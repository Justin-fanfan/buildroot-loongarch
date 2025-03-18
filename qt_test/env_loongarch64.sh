workdir=`pwd`

DEST=$workdir/../output/host

PATH=$DEST/bin:$PATH

#QMAKESPEC=$DEST/mkspecs/linux-g++/ 
QMAKESPEC=$DEST/mkspecs/linux-loongarch64-g++/ 

QTDIR=$DEST/loongarch64-buildroot-linux-gnu/sysroot/usr

LD_LIBRARY_PATH=$DEST/loongarch64-buildroot-linux-gnu/sysroot/usr/lib

export PATH QMAKESPEC QTDIR LD_LIBARY_PATH 

