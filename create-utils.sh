#!/usr/bin/env bash

# General build dependencies: gawk grep lz4 zstd curl gcc make autoconf
# 	libtool pkgconf libcap fuse2 (or fuse3) lzo xz zlib findutils musl
#	kernel-headers-musl sed
#
# Dwarfs build dependencies: fuse2 (or fuse3) openssl jemalloc
# 	xxhash boost lz4 xz zstd libarchive libunwind google-glod gtest fmt
#	gflags double-conversion cmake ruby-ronn libevent libdwarf git utf8cpp
#
# Dwarfs compilation is optional and disabled by default.

script_dir="$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")"

# Set to true to compile dwarfs instead of squashfuse
build_dwarfs=true
squashfuse_version="0.5.2"
bwrap_version="0.10.0"
unionfs_fuse_version="3.3"
busybox_version="1.36.1"
bash_version="5.2.32"

export CC=clang
export CXX=clang++

export CFLAGS="-O3 -flto"
export CXXFLAGS="${CFLAGS}"
export LDFLAGS="-Wl,-O1,--sort-common,--as-needed"

mkdir -p "${script_dir}"/build-utils
cd "${script_dir}"/build-utils || exit 1


cp "${script_dir}"/init.c init.c

cd "${script_dir}"/build-utils || exit 1
mkdir utils

# Download patched bubblewrap (allows launching appimages inside conty) 
wget "https://bin.ajam.dev/x86_64_Linux/bwrap-patched" -O ./utils/bwrap

wget "https://bin.ajam.dev/x86_64_Linux/bash" -O ./utils/bash
wget "https://bin.ajam.dev/x86_64_Linux/Baseutils/busybox/busybox" -O ./utils/busybox
wget "https://bin.ajam.dev/x86_64_Linux/Baseutils/unionfs-fuse/unionfs" -O ./utils/unionfs
wget "https://bin.ajam.dev/x86_64_Linux/Baseutils/unionfs-fuse3/unionfs" -O ./utils/unionfs3
wget "https://bin.ajam.dev/x86_64_Linux/dwarfs-tools" -O ./utils/dwarfs-tools
ln -s dwarfs-tools ./utils/dwarfs
ln -s dwarfs-tools ./utils/mkdwarfs
ln -s dwarfs-tools ./utils/dwarfsextract
chmod +x ./utils/*

mv "${script_dir}"/build-utils/busybox-${busybox_version}/busybox utils
mv "${script_dir}"/build-utils/bash-${bash_version}/bash utils
mv "${script_dir}"/build-utils/init utils

if [ ! -f utils/ld-linux-x86-64.so.2 ]; then
    cp -L /lib64/ld-linux-x86-64.so.2 utils
fi

find utils -type f -exec strip --strip-unneeded {} \; 2>/dev/null

init_program_size=50000
conty_script_size="$(($(stat -c%s "${script_dir}"/conty-start.sh)+2000))"
bash_size="$(stat -c%s utils/bash)"

sed -i "s/#define SCRIPT_SIZE 0/#define SCRIPT_SIZE ${conty_script_size}/g" init.c
sed -i "s/#define BASH_SIZE 0/#define BASH_SIZE ${bash_size}/g" init.c
sed -i "s/#define PROGRAM_SIZE 0/#define PROGRAM_SIZE ${init_program_size}/g" init.c

musl-gcc -o init -static init.c
strip --strip-unneeded init

padding_size="$((init_program_size-$(stat -c%s init)))"

if [ "${padding_size}" -gt 0 ]; then
	dd if=/dev/zero of=padding bs=1 count="${padding_size}" &>/dev/null
	cat init padding > init_new
	rm -f init padding
	mv init_new init
fi

mv init utils

cat <<EOF > utils/info
bubblewrap ${bwrap_version}
unionfs-fuse ${unionfs_fuse_version}
busybox ${busybox_version}
bash ${bash_version}
lz4 ${lz4_version}
zstd ${zstd_version}
EOF

echo "https://bin.ajam.dev/x86_64_Linux/dwarfs-tools" >> utils/info
utils="utils_dwarfs.tar.gz"

tar -zvcf "${utils}" utils
mv "${script_dir}"/"${utils}" "${script_dir}"/"${utils}".old
mv "${utils}" "${script_dir}"
cd "${script_dir}" || exit 1
rm -rf build-utils

clear
echo "Done!"
