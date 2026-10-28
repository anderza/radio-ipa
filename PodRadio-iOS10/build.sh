#!/bin/bash
# Сборка PodRadio Lite (iOS 10+, armv7 + arm64) на Linux: тулчейн L1ghtmann (clang/ld64/lipo/ldid) и iPhoneOS10.3.sdk (theos/sdks)
set -e
cd "$(dirname "$0")"
TC=$(cd ${TC:-../tc/linux/iphone/bin} && pwd); SDK=${SDK:-../sdk/iPhoneOS10.3.sdk}
rm -rf out && mkdir -p out/Payload/PodRadio.app
A=out/Payload/PodRadio.app
for arch in armv7 arm64; do
  $TC/clang -target $arch-apple-ios10.0 -isysroot $SDK -fobjc-arc -O2 -fuse-ld=$TC/ld \
    -framework UIKit -framework WebKit -framework AVFoundation -framework MediaPlayer -framework Foundation -framework CoreGraphics \
    main.m -o out/PodRadio.$arch 2> >(grep -v "built for iOS Simulator" >&2)
done
$TC/lipo -create out/PodRadio.armv7 out/PodRadio.arm64 -output $A/PodRadio
cp Info.plist $A/ && cp res/*.png $A/ && cp -r www $A/www
printf 'APPL????' > $A/PkgInfo
$TC/ldid -S $A/PodRadio
(cd out && zip -qr PodRadio-iOS10.ipa Payload)
ls -l out/PodRadio-iOS10.ipa
