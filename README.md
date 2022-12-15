# 里路好传界面

使用Flutter提供面向终端的应用.

## 开发

sqflite_common_ffi 需要安装依赖, [详见说明](https://pub.flutter-io.cn/packages/sqflite_common_ffi) .

原生平台交互, [参考文档](https://flutter.cn/docs/development/platform-integration/platform-channels?tab=android-channel-java-tab)
.

## 构建

Android:

```
flutter build apk  --debug
```

> 软件报路径 `build/app/outputs/flutter-apk/app-debug.apk` . 在电视上测试发现按钮可以获得焦点, 但方向键的中键(进入)没有响应!

Linux:

```
flutter build linux  --debug
```

> 软件包路径 `build/linux/x64/debug/bundle/` .

Windows:

```
flutter build windows  --debug
```

> 软件包路径 `build/windows/runner/Debug` .
