#/bin/bash

export ANDROID_NDK=/opt/android-ndk-r21e

rm -r build
mkdir build && cd build 

cmake -DCMAKE_TOOLCHAIN_FILE=$ANDROID_NDK/build/cmake/android.toolchain.cmake \
    -DANDROID_ABI="arm64-v8a" \
    -DANDROID_NDK=$ANDROID_NDK \
    -DANDROID_PLATFORM=android-26 \
    ..

make #&& make install

cd ..