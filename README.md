# 里路好传界面

使用Flutter提供面向终端的应用.

## 构建

Android:

```
ANDROID_JKS_KEY_PASSWORD=12345678 ANDROID_JKS_STORE_PASSWORD=12345678 flutter build apk  --debug
```

> 软件报路径 `build/app/outputs/flutter-apk/app-debug.apk` .

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