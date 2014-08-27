#!/bin/bash

# workdir
WORKDIR=~/work

CHANNEL=stable
CHROME_REPOSITORY=http://dl.google.com/linux/chrome/deb
CHROME_PACKAGE=google-chrome-$CHANNEL
XBPS_PACKAGE_PULL=git@github.com:voidlinux/xbps-packages.git
XBPS_PACKAGE_PUSH=git@github.com:voidlinux/xbps-packages.git
PKG_NAME=chromium-pepper-flash

die() {
	echo Error: $@
	exit 1;
}

debinfo() {
	pkg=$1
	field=$2

	apt-cache show $pkg | grep "^$field: " | cut -d " " -f 2-
}

templateinfo() {
	pkg=$1
	field=$2
	(
		# Fake xbps-src
		XBPS_TARGET_MACHINE=`uname -m`
		. xbps-packages/srcpkgs/$pkg/template
		eval "echo \$${field}"
	)
}

uri() {
	platform=$1
	platform=$1

	filename=`debinfo ${CHROME_PACKAGE} Filename`
	sha1=`debinfo ${CHROME_PACKAGE} SHA1`

	uri="${CHROME_REPOSITORY}/${filename}"
	uri_dir=`dirname -- "$uri"`
	file=`basename -- "$uri" | sed "s|\(^[^_]*_[^_]*_\)[^.]*|\1${platform}|"`
	
	echo "$uri_dir/$file"
}

download() {
	platform=$1
	wget -O ${platform}.deb "`uri $platform`"
}

#### INIT

for i in git apt-get apt-cache ar lzma wget; do
	type $i || die "tool $i not found"
done

FILESDIR=$(dirname $0 | xargs readlink -f)
mkdir -p $WORKDIR
cd $WORKDIR

# Make sure chrome repository is registered
echo deb ${CHROME_REPOSITORY} $CHANNEL main > /etc/apt/sources.list.d/chrome.list
apt-key add $FILESDIR/chrome.key

# Updating repository 
apt-get update -o Dir::Etc::sourcelist="sources.list.d/chrome.list" -o Dir::Etc::sourceparts="-" -o APT::Get::List-Cleanup="0"

# Init xbps-packages if not presend
if [ -d xbps-packages ]; then
	(
		cd xbps-packages
		git pull;
	);
else
	git clone $XBPS_PACKAGE_PULL xbps-packages
fi

chromeVersion=`debinfo ${CHROME_PACKAGE} Version`
templateChromeVersion=`templateinfo ${PKG_NAME} _chromeVersion`

if [ "$chromeVersion" = "$templateChromeVersion" ]; then
	echo template is up to date
	exit 0
fi

# Download the debs

download amd64
download i386

# Building Checksums
checksum_x64=`sha256sum amd64.deb | cut -d" " -f1`
checksum_i686=`sha256sum i386.deb | cut -d" " -f1`

# extracting deb

mkdir -p data
ar p "i386.deb" data.tar.lzma | lzma -d | tar x -C data

flashVersion=`cat data/opt/google/chrome/PepperFlash/manifest.json | grep '"version"' | sed 's/.*: "//;s/",.*//'`
templateFlashVersion=`templateinfo ${PKG_NAME} version`

rm -r data i386.deb amd64.deb

revision=`templateinfo ${PKG_NAME} revision`

if [ "$flashVersion" = "$templateFlashVersion" ]; then
	let revision=$revision+1
	reason="$PKG_NAME: new chrome version $chromeVersion (bot)"
else
	revision=1
	reason="$PKG_NAME: update to $flashVersion (bot)"
fi

baseUri=`uri | xargs dirname`
sed \
	-e "s|%PKG_NAME%|$PKG_NAME|g" \
	-e "s|%FLASH_VERSION%|$flashVersion|g" \
	-e "s|%FLASH_VERSION%|$flashVersion|g" \
	-e "s|%CHROME_VERSION%|$chromeVersion|g" \
	-e "s|%CHANNEL%|$CHANNEL|g" \
	-e "s|%BASE_URL%|$baseUri|g" \
	-e "s|%CHECKSUM_X64%|$checksum_x64|g" \
	-e "s|%CHECKSUM_I686%|$checksum_i686|g" \
	-e "s|%BASE_URL%|$baseUri|g" \
	-e "s|%REVISION%|$revision|g" \
	$FILESDIR/template.in \
	> xbps-packages/srcpkgs/$PKG_NAME/template

(
	cd xbps-packages;
	git add .
	git commit -m "$reason"
	git pull --rebase $XBPS_PACKAGE_PULL master
	git push $XBPS_PACKAGE_PUSH master
)
