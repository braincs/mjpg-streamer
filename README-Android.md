# mjpg-streamer 适配Android设备

Android平台实时推流的架构经过调研多以直播平台的方式为主，与目前的应用场景不一样；主要是设备间的低延迟（百毫秒）摄像头预览的推流。基本上RTSP/RTMP 的流式框架太重，且都进行了多次转码，对机器的性能要求较高。



采用嵌入式推流框架的mjpg-streamer框架进行Android平台适配：

优点：

- 低延迟
- 对机器性能要求低，占用机器资源少（必经在嵌入式设备上都可以跑）



缺点：

- 占用带宽要高于推流RTMP等架构
- 直接适配后需要root权限进行启动推流，集成到app还待验证



## 适配过程

仓库：https://github.com/jacksonliam/mjpg-streamer.git

### 编译脚本

采用cmake进行编译的，发现已有CMakeLists.txt，直接进行cmake编译即可

便携生成Android执行文件shell脚本

```bash
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
```

注意修改自己的NDK路径 export ANDROID_NDK=<你的ndk路径>



### jpeg库的适配

发现cmake中有对jpeg库的依赖，注释掉后，自己进行适配；所以注释掉这行如下：

```cmake
# find_library(JPEG_LIB jpeg)
```

将编译好的libjepg.so 和头文件放入到thirdparty 路径下，并进行cmake配置链接libjpeg库

```cmake
set(THIRDPARTY ${CMAKE_SOURCE_DIR}/thirdparty)
include_directories(${THIRDPARTY}/libjpeg/include)
```



### pthread库适配

报错：

```
/opt/android-ndk-r21e/toolchains/llvm/prebuilt/linux-x86_64/lib/gcc/aarch64-linux-android/4.9.x/../../../../aarch64-linux-android/bin/ld: cannot find -lpthread
clang: error: linker command failed with exit code 1 (use -v to see invocation)
```

在Linux平台下引入pthread库如下

```cmake
target_link_libraries(mjpg_streamer pthread dl)
```

但在Android上已经默认集成了pthread库，所以采用以下方式进行适配

```cmake
target_link_libraries(mjpg_streamer 
-pthread 
dl)
```



```bash
CMakeFiles/input_uvc.dir/input_uvc.c.o: In function `input_init':
/home/changshuai/cworkspace/mjpg-streamer/mjpg-streamer-experimental/plugins/input_uvc/input_uvc.c:254: undefined reference to `parse_resolution_opt'
/home/changshuai/cworkspace/mjpg-streamer/mjpg-streamer-experimental/plugins/input_uvc/input_uvc.c:(.text.input_init+0x8e4): undefined reference to `resolutions_help'
CMakeFiles/input_uvc.dir/input_uvc.c.o: In function `help':
/home/changshuai/cworkspace/mjpg-streamer/mjpg-streamer-experimental/plugins/input_uvc/input_uvc.c:531: undefined reference to `resolutions_help'
clang: error: linker command failed with exit code 1 (use -v to see invocation)
plugins/input_uvc/CMakeFiles/input_uvc.dir/build.make:173: recipe for target 'plugins/input_uvc/input_uvc.so' failed
make[2]: *** [plugins/input_uvc/input_uvc.so] Error 1
CMakeFiles/Makefile2:286: recipe for target 'plugins/input_uvc/CMakeFiles/input_uvc.dir/all' failed
make[1]: *** [plugins/input_uvc/CMakeFiles/input_uvc.dir/all] Error 2
Makefile:129: recipe for target 'all' failed
make: *** [all] Error 2
```



### plugins库适配

mjpg-streamer采用插件式的模式，所以对plugin插件很重要，plugins插件库中主要问题有2个：

1. Android的pthread库中没有`pthread_cancel` 方法，需要进行替换，替换成 `pthread_kill`
2. uvc的插件中有对外层的utils.c和utils.h 有依赖，需要调用对输入参考的解析，会报undefined symbol的错误。



解决办法

1替换 pthread_cancel

以 input_uvc.c为例

```c
/******************************************************************************
Description.: Stops the execution of worker thread
Input Value.: -
Return Value: always 0
******************************************************************************/
int input_stop(int id)
{
    input * in = &pglobal->in[id];
    context *pctx = (context*)in->context;
    
    DBG("will cancel camera thread #%02d\n", id);
    pthread_kill(pctx->threadID, 0); //替换这行
    return 0; 
}
```



替换的文件如下

```bash
modified:   plugins/input_control/input_uvc.c
        modified:   plugins/input_file/input_file.c
        modified:   plugins/input_http/input_http.c
        modified:   plugins/input_ptp2/input_ptp2.c
        modified:   plugins/input_uvc/input_uvc.c
        modified:   plugins/output_autofocus/output_autofocus.c
        modified:   plugins/output_file/output_file.c
        modified:   plugins/output_http/output_http.c
        modified:   plugins/output_rtsp/output_rtsp.c
        modified:   plugins/output_udp/output_udp.c
        modified:   plugins/output_viewer/output_viewer.c
```



2增加对libjpeg库的连接

只有uvc库对libjpeg有依赖，所以在uvc插件库的CMakeLists.txt中进行修改

plugins/input_uvc/CMakeLists.txt

```cmake

check_include_files(linux/videodev2.h HAVE_LINUX_VIDEODEV2_H)

MJPG_STREAMER_PLUGIN_OPTION(input_uvc "Video 4 Linux input plugin"
                            ONLYIF HAVE_LINUX_VIDEODEV2_H)

if (PLUGIN_INPUT_UVC)
    
    add_definitions(-DLINUX -D_GNU_SOURCE)
    
    find_library(V4L2_LIB v4l2)
    # message("${THIRDPARTY}/libjpeg/lib")
    find_library(JPEG_LIB NAMES jpeg PATHS ${THIRDPARTY}/libjpeg/lib NO_DEFAULT_PATH)
    
    if (V4L2_LIB)
        message("---V4L2_LIB")
        add_definitions(-DUSE_LIBV4L2)
    endif (V4L2_LIB)
    
    if (NOT JPEG_LIB)
        message("---not JPEG_LIB")
        add_definitions(-DNO_LIBJPEG)
    endif (NOT JPEG_LIB)

    message("----------${JPEG_LIB}")
    MJPG_STREAMER_PLUGIN_COMPILE(input_uvc dynctrl.c
                                           input_uvc.c
                                           jpeg_utils.c
                                           v4l2uvc.c
                                           utils.c)

    if (V4L2_LIB)
        target_link_libraries(input_uvc ${V4L2_LIB})
    endif (V4L2_LIB)

    if (JPEG_LIB)
        message("---JPEG_LIB, link ${THIRDPARTY}/libjpeg/lib/libjpeg.so")
        target_link_libraries(input_uvc ${JPEG_LIB})
    endif (JPEG_LIB)
    target_link_libraries(input_uvc ${THIRDPARTY}/libjpeg/lib/libjpeg.so) # 这行是关键


endif()

```

发现用find_library的方式适配有点问题，直接强行在最后加入链接了



## 使用

测试机器：RK3399的一块开发板，带USB摄像头

脚本：将使用的程序+so库+www资源文件推到设备上

```bash
# 将build产物推到机器上
adb shell mkdir /data/local/tmp/mstreamer
adb push ./build/mjpg_streamer /data/local/tmp/mstreamer/
adb push ./build/plugins/input_uvc/input_uvc.so /data/local/tmp/mstreamer/
adb push ./build/plugins/output_http/output_http.so /data/local/tmp/mstreamer/
adb push ./mjpg-streamer-experimental/www /data/local/tmp/mstreamer/
```



adb 进入机器执行：

```bash
adb shell
cd /data/local/tmp/mstreamer/
export LD_LIBRARY_PATH="$(pwd):$LD_LIBRARY_PATH"
./mjpg_streamer -i "./input_uvc.so" -o "./output_http.so -w ./www"
```

