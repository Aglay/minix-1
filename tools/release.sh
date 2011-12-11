#!/bin/sh

set -e

. release.functions

version_pretty="`sh tell_config OS_RELEASE . OS_VERSION | tr -dc 0-9.`"
version="`echo $version_pretty | tr . _`"

XBIN=usr/xbin
SRC=src

secs=`expr 32 '*' 64`
export SHELL=/bin/sh

PKG_ADD=/usr/pkg/sbin/pkg_add
PKG_INFO=/usr/pkg/sbin/pkg_info

if [ ! -x $PKG_ADD ]
then	echo Please install pkg_install from pkgsrc.
	exit 1
fi

RELEASEDIR=/usr/r-staging
RELEASEMNTDIR=/usr/r
RELEASEPACKAGE=${RELEASEDIR}/usr/install/packages

IMAGE=../boot/cdbootblock/cdbootblock
ROOTIMAGE=rootimage
CDFILES=/usr/tmp/cdreleasefiles
sh tell_config OS_RELEASE . OS_VERSION >/tmp/rel.$$
IMG_BASE=minix${version}_ide
BS=4096

HDEMU=0
COPY=0
JAILMODE=0
REVTAG=""
PACKAGES=1
MINIMAL=0
MAKEMAP=0
EXTRAS_INSTALL=0
EXTRAS_PATH=
COMPRESS=1
FILENAMEOUT=""

# Do we have git?
if git --version >/dev/null
then	if [ -d ../.git ]
	then	LOCAL_REVTAG="`git describe --always`"
		GITMODE=1
	fi
fi

usage()
{
cat <<_EOF_ >&2
Usage: `basename $0` [options] [configfile]
Options:
    -h		Build an HD image
    -u		Build a USB image
    -c		Copy current /usr/src instead of exporting git repository
    -t <tag>	Use <tag> for the repository checkout
    -p		Do not include optional binary packages in the image
    -j <dir>	Run in jail mode using directory <dir>
    -f <path>	Use <path> as filename for the image
    -m		Create a minimal image (removes /usr/src/.git)
    -M		Build the map
    -l		Use local packages
    -L <uri>	Use <uri> for packages
    -r <uri>	Set the pkgin repositories.conf to <uri>
    -e <path>	Copy extra files and directories from <path> onto the image
    -z		Do not compress the image
_EOF_
    exit 1
}

# ----
# Source in the default config settings
# ----
. release.default.conf

# ----
# If it exists, source in a ~/.releaserc on top of that
# ----
RELEASERC=$HOME/.releaserc

if [ -f $RELEASERC ]
then	. $RELEASERC
fi

set -- $RELOPTS $* $RELARGS

# ----
# Parse command line options but don't set their variables yet, just
# collect those settings in $options
# ----
options=""
error=0
while getopts "ce:f:hij:lL:mMpruz?" c
do
	case "$c" in
	\?)	error=1
		;;

	h)	echo " * Making HD image"
		options="${options}IMG_BASE='minix${version}_bios'; "
		options="${options}HDEMU=1; "
		;;

	u)	echo " * Making live USB-stick image"
		options="${options}IMG_BASE='minix${version}_usb'; "
		options="${options}HDEMU=1; "
		options="${options}USB=1; "
		;;

	c)	echo " * Copying, not SVN"
		options="${options}COPY=1; "
		;;

	p)	options="${options}PACKAGES=0; "
		;;

	j)	options="${options}RELEASEDIR='${OPTARG}'; "
		options="${options}JAILMODE=1; "
		;;

	f)	options="${options}FILENAMEOUT='${OPTARG}'; "
		;;

	m)	options="${options}MINIMAL=1; "
		options="${options}PACKAGES=0; "
		;;

	M)	options="${options}MAKEMAP=1; "
		;;

	l)	options="${options}PACKAGEURL='file://${PACKAGEDIR}/All'; "
		;;

	L)	options="${options}PACKAGEURL='${OPTARG}'; "
		;;

	r)	options="${options}PKGINREPOS='${OPTARG}'; "
		;;

	t)	options="${options}REVTAG='${OPTARG}'; "
		;;

	e)	options="${options}EXTRAS_INSTALL=1; "
		options="${options}EXTRAS_PATH='${OPTARG}'; "
		;;

	z)	options="${options}COMPRESS=0; "
	esac
done

# ----
# On command line errors, show usage and bail out
# ----
if [ $error -ne 0 ] ; then
    usage
fi

# ----
# If an optional config file was specified, source that in
# ----
shift $((OPTIND-1))
if [ $# -ge 2 ] ; then
    usage
fi
if [ $# -eq 1 ] ; then
.   $1
fi

# ----
# Finally override anything with the command line options
# ----
eval "$options"

# ----
# Translate the packag paths in the list files into package names
# ----
PREINSTALLED_PACKAGES=`pkgpaths2pkgnames $PREINSTALLEDLIST`

if [ $GITMODE -ne 1 -a $COPY -ne 1 ]
then	echo "Need git to retrieve latest minix! Copying src instead!"
	COPY=1
fi

if [ ! "$ZIP" ]
then	ZIP=bzip2
fi

if [ $PACKAGES -ne 0 ]
then	mkdir -p $PACKAGEDIR/All || true
	retrieve $PACKAGEDIR/All $PACKAGELIST packages/`uname -p`/$VERSION_PRETTY
fi

TMPDISKUSR=/dev/ram0
TMPDISKROOT=/dev/ram1

if [ ! -b $TMPDISKUSR -o ! $TMPDISKROOT ]
then	echo "$TMPDISKUSR or $TMPDISKROOT is not a block device.."
	exit 1
fi

if [ $TMPDISKUSR = $TMPDISKROOT ]
then
	echo "Temporary devices can't be equal."
	exit
fi

if [ $JAILMODE = 0 ]
then	echo " * Cleanup old files"
	umount $TMPDISKUSR || true
	umount $TMPDISKROOT || true
	umount $RELEASEMNTDIR/usr || true
	umount $RELEASEMNTDIR || true
fi

rm -rf $RELEASEDIR $RELEASEMNTDIR $IMG $ROOTIMAGE $CDFILES image*
rm -f minix${version}_*.iso
rm -f minix${version}_*.iso.*
mkdir -p $CDFILES || exit
mkdir -p $RELEASEDIR $RELEASEMNTDIR 
mkdir -m 755 $RELEASEDIR/usr
mkdir -m 1777 $RELEASEDIR/tmp

mkdir -p $RELEASEDIR/tmp
mkdir -p $RELEASEDIR/usr/tmp
mkdir -p $RELEASEDIR/$XBIN
mkdir -p $RELEASEDIR/usr/bin
mkdir -p $RELEASEDIR/bin
mkdir -p $RELEASEPACKAGE

echo " * Transfering bootstrap dirs to $RELEASEDIR"
cp -p /bin/* /usr/bin/* /usr/sbin/* /sbin/* $RELEASEDIR/$XBIN
cp -rp /usr/lib $RELEASEDIR/usr
cp -rp /bin/sh /bin/echo /bin/install /bin/rm \
    /bin/date /bin/ls $RELEASEDIR/bin
cp -rp /usr/bin/make /usr/bin/yacc /usr/bin/lex /usr/bin/asmconv \
	/usr/bin/grep /usr/bin/egrep /usr/bin/awk /usr/bin/sed $RELEASEDIR/usr/bin

CONFIGHEADER=$RELEASEDIR/usr/src/common/include/minix/sys_config.h

copy_local_packages

# Make sure compilers and libraries are root-owned
chown -R root $RELEASEDIR/usr/lib
chmod -R u+w $RELEASEDIR/usr/lib

if [ "$COPY" -ne 1 ]
then
	echo "Retrieving latest minix repo from $REPO."
	srcdir=$RELEASEDIR/usr/src
	git clone $REPO $srcdir
	if [ "$REVTAG" ]
	then	echo "Doing checkout of $REVTAG."
		(cd $srcdir && git checkout $REVTAG )
		REVCOMMIT=`(cd $srcdir && git show-ref $REVTAG -s10)`
	else	REVCOMMIT=`(cd $srcdir && git show-ref HEAD -s10)`
		echo "Retrieved repository head is $REVCOMMIT."
	fi
	if [ $MINIMAL -ne 0 ]
	then	rm -r $srcdir/.git
	fi
	echo "
/* Added by release script  */
#ifndef _VCS_REVISION
#define _VCS_REVISION \"$REVCOMMIT\"
#endif" >>$CONFIGHEADER
	DATE=`date +%Y%m%d`
	# output image name
	if [ "$USB" -ne 0 ]; then
		IMG=${IMG_BASE}_${DATE}_${REVCOMMIT}.img
	else
		IMG=${IMG_BASE}_${DATE}_${REVCOMMIT}.iso
	fi
else
	echo "Copying contents from current src dir."
	( cd .. && make depend && make clean )
	srcdir=/usr/$SRC
	( cd $srcdir && tar --exclude .svn -cf - .  ) | ( cd $RELEASEDIR/usr && mkdir $SRC && cd $SRC && tar xf - )
	REVTAG=copy
	REVCOMMIT=copy
	REVISION=unknown
	IMG=${IMG_BASE}_copy.iso
	if [ $MINIMAL -ne 0 ]
	then	rm -r $srcdir/.git
	fi
fi

echo " * Fixups for owners and modes of dirs and files"
chown -R root $RELEASEDIR/usr/$SRC
chmod -R u+w $RELEASEDIR/usr/$SRC 
find $RELEASEDIR/usr/$SRC -type d | xargs chmod 755
find $RELEASEDIR/usr/$SRC -type f | xargs chmod 644
find $RELEASEDIR/usr/$SRC -name configure | xargs chmod 755
find $RELEASEDIR/usr/$SRC/commands -name build | xargs chmod 755
# Bug tracking system not for on cd
rm -rf $RELEASEDIR/usr/$SRC/doc/bugs

# Make sure the CD knows it's a CD, unless it's not
if [ "$USB" -eq 0 ]
then	date >$RELEASEDIR/CD
fi
echo " * Bootstrap /usr/share/mk files"
# Need /usr/share/mk in the new system to invoke make. Real ownerships
# and permissions will be set by its own src/share/mk/Makefile.
mkdir -p $RELEASEDIR/usr/share/mk
chmod 755 $RELEASEDIR/usr/share/mk
cp $RELEASEDIR/usr/src/share/mk/* $RELEASEDIR/usr/share/mk/
chown -R root $RELEASEDIR/usr/share/mk
cp chrootmake.sh $RELEASEDIR/usr/$SRC/tools/chrootmake.sh

echo " * Make hierarchy"
chroot $RELEASEDIR "PATH=/$XBIN:/usr/pkg/bin sh -x /usr/$SRC/tools/chrootmake.sh etcfiles" || exit 1

for p in $PREINSTALLED_PACKAGES
do	echo " * Pre-installing: $p from $PACKAGEURL"
    $PKG_ADD -f -P $RELEASEDIR $PACKAGEURL/$p
done

echo $PKGINREPOS >$RELEASEDIR/usr/pkg/etc/pkgin/repositories.conf

echo " * Chroot build"
chroot $RELEASEDIR "PATH=/$XBIN:/usr/pkg/bin MAKEMAP=$MAKEMAP sh -x /usr/$SRC/tools/chrootmake.sh" || exit 1
# Copy built images for cd booting
cp $RELEASEDIR/boot/image_big image
echo " * Chroot build done"
echo " * Removing bootstrap files"
rm -rf $RELEASEDIR/$XBIN
# The build process leaves some file in $SRC as bin.
chown -R root $RELEASEDIR/usr/src*
cp issue.install $RELEASEDIR/etc/issue

echo $version_pretty, SVN revision $REVISION, generated `date` >$RELEASEDIR/etc/version
rm -rf $RELEASEDIR/tmp/*

if [ $MINIMAL -ne 0 ]
then
	if [ "$MAKEMAP" -ne 0 ]
	then
		echo " * Copying symbol map to ${IMG}-symbols.txt"
		cp $RELEASEDIR/usr/src/symbols.txt ${IMG}-symbols.txt
		$ZIP -f ${IMG}-symbols.txt
	fi

	echo " * Removing files to create minimal image"
	rm -rf $RELEASEDIR/boot/image/* $RELEASEDIR/usr/man/man*/* 	\
		$RELEASEDIR/usr/share/zoneinfo* $RELEASEDIR/usr/src
	mkdir -p $RELEASEDIR/usr/src/tools
	ln $RELEASEDIR/boot/image_big $RELEASEDIR/boot/image/$version
fi

if [ $EXTRAS_INSTALL -ne 0 ] ; then
    echo " * Copying files from $EXTRAS_PATH"
    cp -Rv $EXTRAS_PATH/* $RELEASEDIR
fi

# If we are making a jail, all is done!
if [ $JAILMODE = 1 ]
then	echo "Created new minix install in $RELEASEDIR."
	echo "Enter it by typing: "
	echo "# chroot $RELEASEDIR /bin/sh"
	exit 0
fi

echo " * Counting files"
extrakb=`du -s $RELEASEDIR/usr/install | awk '{ print $1 }'`
find $RELEASEDIR/usr | fgrep -v /install/ | wc -l >$RELEASEDIR/.usrfiles
find $RELEASEDIR -print -path $RELEASEDIR/usr -prune | wc -l >$RELEASEDIR/.rootfiles

echo " * Writing fstab"
if [ "$USB" -ne 0 ]
then
    echo "/dev/c0d7p0s0	/	mfs	rw	0 1" > $RELEASEDIR/etc/fstab
    echo "/dev/c0d7p0s2	/usr	mfs	rw	0 2" >>$RELEASEDIR/etc/fstab
elif [ "$HDEMU" -ne 0 ]
then
    echo "/dev/c0d7p0s0	/	mfs	rw	0 1" > $RELEASEDIR/etc/fstab
    echo "/dev/c0d7p0s2	/usr	mfs	ro	0 2" >>$RELEASEDIR/etc/fstab
fi

echo " * Mounting $TMPDISKROOT as $RELEASEMNTDIR"
fitfs $RELEASEDIR $TMPDISKROOT 64 256 "$ROOTMB"
ROOTBLOCKS=$blocks
ROOTSECTS="`expr $blocks \* \( $BS / 512 \)`"
mount $TMPDISKROOT $RELEASEMNTDIR || exit

echo " * Mounting $TMPDISKUSR as $RELEASEMNTDIR/usr"
fitfs $RELEASEDIR/usr $TMPDISKUSR 0 0 "$USRMB"
USRBLOCKS=$blocks
USRSECTS="`expr $blocks \* \( $BS / 512 \)`"
mkdir -m 755 $RELEASEMNTDIR/usr
mount $TMPDISKUSR $RELEASEMNTDIR/usr || exit

echo " * Copying files from staging to image"
synctree -f $RELEASEDIR $RELEASEMNTDIR > /dev/null || true
expr `df $TMPDISKUSR | tail -1 | awk '{ print $4 }'` - $extrakb >$RELEASEMNTDIR/.usrkb

echo " * Unmounting $TMPDISKUSR from $RELEASEMNTDIR/usr"
umount $TMPDISKUSR || exit
echo " * Unmounting $TMPDISKROOT from $RELEASEMNTDIR"
umount $TMPDISKROOT || exit
rm -r $RELEASEMNTDIR

echo " * Making image bootable"
if [ "$USB" -ne 0 ]
then
	usb_root_changes
elif [ "$HDEMU" -ne 0 ]
then
	hdemu_root_changes
else
	cd_root_changes
fi

# Clean up: RELEASEDIR no longer needed
rm -r $RELEASEDIR

(cd ../boot && make)
dd if=$TMPDISKROOT of=$ROOTIMAGE bs=$BS count=$ROOTBLOCKS
cp release/cd/* $CDFILES || true
echo "This is Minix version $version_pretty prepared `date`." >$CDFILES/VERSION.TXT

boottype=-n
bootimage=$IMAGE
if [ "$HDEMU" -ne 0 ]; then
	make_hdimage
	boottype='-h'
	bootimage=hdimage
fi

if [ "$USB" -ne 0 ]; then
	mv $bootimage $IMG
else
	cp ../boot/boot/boot $CDFILES
	writeisofs -s0x0 -l MINIX -a boot -b $bootimage $boottype $CDFILES $IMG || exit 1

	if [ "$HDEMU" -eq 0 ]
	then
		echo "Appending Minix root and usr filesystem"
		# Pad ISO out to cylinder boundary
		isobytes=`stat -f %z $IMG`
		isosects=`expr $isobytes / 512`
		isopad=`expr $secs - '(' $isosects % $secs ')'`
		dd if=/dev/zero count=$isopad >>$IMG
		# number of sectors
		isosects=`expr $isosects + $isopad`
		( cat $IMG $ROOTIMAGE ;
			dd if=$TMPDISKUSR bs=$BS count=$USRBLOCKS ) >m
		mv m $IMG
		# Make CD partition table
		installboot -m $IMG /usr/mdec/masterboot
		# Make sure there is no hole..! Otherwise the ISO format is
		# unreadable.
		partition -m $IMG 0 81:$isosects 81:$ROOTSECTS 81:$USRSECTS
	fi
fi

if [ $COMPRESS -ne 0 ] ; then
    echo " * ${ZIP}ping $IMG"
    $ZIP -f $IMG
fi

if [ "$FILENAMEOUT" ]
then	echo "$IMG" >$FILENAMEOUT
fi

echo " * Freeing up memory used by ramdisks"
ramdisk 1 $TMPDISKROOT
ramdisk 1 $TMPDISKUSR
