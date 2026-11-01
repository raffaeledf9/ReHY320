#!/bin/sh
# Fetch Google's own avbtool and generate the key this projector's system will be signed with.
# Nothing here touches the projector or the golden backup.
set -e
command -v python2 >/dev/null || { echo '### installing python2 (avbtool 1.1.0 is a python2 script)'; apt-get install -y -qq python2 >/dev/null 2>&1; }
D=/usr/local/src/hy320-verity
mkdir -p $D
cd $D

if [ ! -f avbtool ]; then
  echo "### fetching avbtool from AOSP (android11-release)"
  URL="https://android.googlesource.com/platform/external/avb/+/refs/heads/android11-release/avbtool?format=TEXT"
  curl -fsSL "$URL" | base64 -d > avbtool
  chmod +x avbtool
fi
echo "### avbtool"
head -1 avbtool
python2 ./avbtool version
sha256sum avbtool

if [ ! -f hy320_avb.pem ]; then
  echo "### generating our signing key (2048-bit, exponent 65537, no passphrase)"
  openssl genrsa -out hy320_avb.pem 2048 2>/dev/null
  chmod 600 hy320_avb.pem
fi
echo "### key"
openssl rsa -in hy320_avb.pem -noout -text 2>/dev/null | head -2
openssl rsa -in hy320_avb.pem -noout -modulus | sha256sum | cut -c1-32 | sed 's/^/  modulus sha256: /'

if [ ! -f hy320_avb.avbpubkey ]; then
  python2 ./avbtool extract_public_key --key hy320_avb.pem --output hy320_avb.avbpubkey
fi
echo "### public key blob: $(stat -c %s hy320_avb.avbpubkey) bytes (the original chains carried 520)"
echo "### everything in $D:"
ls -l $D
