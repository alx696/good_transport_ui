import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:clipboard/clipboard.dart';
import 'package:dpad_container/dpad_container.dart';
import 'package:filesize/filesize.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_easyloading/flutter_easyloading.dart';
import 'package:lilu_good_transport_ui/data.dart';
import 'package:logging/logging.dart';
import 'package:open_app_file/open_app_file.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:system_info2/system_info2.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

// TODO dpad_container 初步支持了电视遥控, 但是效果不理想, 比如获得焦点后没有高亮效果.
// TODO Windows中点击窗口关闭图标关闭时http服务进程没有终止, 再次启动时会报错! dispose() 从来都不会执行!

final l = Logger('调试');
const title = '里路好传';

void main() async {
  // 日志 https://pub.dev/packages/logging
  Logger.root.level = Level.ALL; // defaults to Level.INFO
  Logger.root.onRecord.listen((record) {
    if (kDebugMode) {
      print('${record.level.name}: ${record.time}: ${record.message}');
    }
  });
  l.config('日志已经设置');

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: title,
      theme: ThemeData(
        primarySwatch: Colors.green,
      ),
      home: MyHomePage(title: title),
      builder: EasyLoading.init(),
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key, required this.title});

  final String title;

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  static const platform = MethodChannel('app.lilu.red/flutter');
  late BuildContext bc;
  Widget _qrcode = Icon(
    Icons.qr_code_rounded,
    size: 128,
  );
  var _cardList = <Widget>[];
  var _gatewayAddress = '';
  late String rootDirectoryPath;
  late Process httpServerProcess;
  late WebSocketChannel wc;

  // 调用原生功能获取文件夹
  Future<String> _getDirectory() async {
    return await platform.invokeMethod('getDirectory');
  }

  // 调用原生功能获取公共下载文件夹
  Future<String> _getPublicDownloadDirectory() async {
    return await platform.invokeMethod('getPublicDownloadDirectory');
  }

  // 调用原生功能获取存储权限
  Future<bool> _getStoragePermission() async {
    String result = await platform.invokeMethod('requestStoragePermission');
    return result == "已有权限";
  }

  // 调用原生功能打开文件
  Future _platformOpenFile(String filePath) async {
    await platform.invokeMethod('open', {
      'filePath': filePath,
    });
  }

  // 打开文件
  _openFile(String filePath) {
    if (Platform.isAndroid) {
      _platformOpenFile(filePath);
      return;
    }

    OpenAppFile.open(filePath).then((result) {
      l.fine('打开结果 ${result.message}');
    });
  }

  // 复制到下载
  Future _copyToDownload(String filePath, String fileName) async {
    if (!Platform.isAndroid) {
      l.warning('暂时只支持Android使用此功能');
      return;
    }
    // 检查权限
    bool havePermission = await _getStoragePermission();
    if (!havePermission) {
      EasyLoading.showToast('没有存储权限');
      return;
    }
    // 复制文件
    String downloadDirectory = await _getPublicDownloadDirectory();
    File(filePath).copySync(join(downloadDirectory, fileName));
    EasyLoading.showToast('已经复制到下载文件夹中');
  }

  // 删除Card
  _deleteCard(String uuid, String filePath) {
    // 删除文件
    if (filePath != '') {
      File(filePath).delete();
    }
    // 删除数据
    delete(uuid);
    // 刷新数据
    _refresh();
  }

  // 复制文本
  _copyText(String text) {
    FlutterClipboard.copy(text).then((value) => {EasyLoading.showToast('已经复制')});
  }

  /// 生成卡片数组
  List<Card> generateCardList({
    required String directoryPath,
    List<Info> data = const <Info>[],
  }) {
    var fileDirectoryPath = join(directoryPath, 'file');
    var cardArray = <Card>[];
    for (final info in data) {
      var typeIcon = Icons.text_fields_rounded;
      var sizeText = '${info.size}个字符';
      var filePath = '';
      if (info.path != '') {
        filePath = join(fileDirectoryPath, info.path);
        typeIcon = Icons.file_present_rounded;
        sizeText = '${filesize(info.size)}大小';
      }

      Widget progressView = LinearProgressIndicator(
        value: 100,
        valueColor: AlwaysStoppedAnimation(Colors.white),
        backgroundColor: Colors.orange.shade200,
      );
      if (info.size != info.receiveSize) {
        // 显示进度条
        var progress = info.receiveSize / info.size;
        progressView = LinearProgressIndicator(
          value: progress,
          valueColor: AlwaysStoppedAnimation(Colors.blue),
          backgroundColor: Colors.orange.shade200,
        );
      }

      var actionArray = <Widget>[];
      if (filePath != '') {
        // 显示打开按钮
        actionArray.add(
          DpadContainer(
            child: ElevatedButton.icon(
              icon: Icon(Icons.open_in_browser_rounded),
              label: Text('打开'),
              onPressed: () {
                _openFile(filePath);
              },
            ),
            onClick: () {
              _openFile(filePath);
            },
            onFocus: (hasFocus) {
              l.fine('焦点变化: $hasFocus');
            },
          ),
        );
        // 显示复制到下载按钮
        if (Platform.isAndroid) {
          String fileName = info.txt;
          actionArray.add(
            DpadContainer(
              child: ElevatedButton.icon(
                icon: Icon(Icons.file_copy),
                label: Text('复到下载'),
                onPressed: () {
                  _copyToDownload(filePath, fileName);
                },
              ),
              onClick: () {
                _copyToDownload(filePath, fileName);
              },
              onFocus: (hasFocus) {
                l.fine('焦点变化: $hasFocus');
              },
            ),
          );
        }
      } else {
        // 显示复制按钮
        actionArray.add(
          DpadContainer(
            child: ElevatedButton.icon(
              icon: Icon(Icons.copy_rounded),
              label: Text('复制'),
              onPressed: () {
                _copyText(info.txt);
              },
            ),
            onClick: () {
              _copyText(info.txt);
            },
            onFocus: (hasFocus) {
              l.fine('焦点变化: $hasFocus');
            },
          ),
        );
      }

      // 添加删除按钮
      actionArray.add(
        DpadContainer(
          child: OutlinedButton.icon(
            icon: Icon(Icons.delete_forever_rounded),
            label: Text("删除"),
            onPressed: () {
              _deleteCard(info.uuid, filePath);
            },
          ),
          onClick: () {
            _deleteCard(info.uuid, filePath);
          },
          onFocus: (hasFocus) {
            l.fine('焦点变化: $hasFocus');
          },
        ),
      );

      cardArray.add(
        Card(
          child: Column(
            children: [
              ListTile(
                leading: Icon(typeIcon),
                title: Text(
                  info.txt,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text(sizeText),
              ),
              progressView,
              Container(
                padding: EdgeInsets.all(16),
                width: double.infinity,
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  alignment: WrapAlignment.end,
                  children: actionArray,
                ),
              ),
            ],
          ),
        ),
      );
    }
    return cardArray;
  }

  Future _dialog(String title, String message) {
    return showDialog<void>(
      context: bc,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text(title),
          content: Text(message),
          actions: [
            TextButton(
              style: TextButton.styleFrom(
                textStyle: Theme.of(context).textTheme.labelLarge,
              ),
              child: const Text('关闭'),
              onPressed: () {
                Navigator.of(context).pop();
              },
            ),
          ],
        );
      },
    );
  }

  Future _refresh() async {
    List<Info> dataList = await all();
    _cardList = generateCardList(directoryPath: rootDirectoryPath, data: dataList);
    setState(() {
      //
    });
  }

  Future<String> _getHttpServerAddress(HttpClient httpClient, int httpPort) async {
    // 间隔1秒连接1次直到连接成功
    try {
      var httpRequest = await httpClient.get('localhost', httpPort, '/server/info');
      var httpResponse = await httpRequest.close();
      if (httpResponse.statusCode == 200) {
        final serverInfoMap = jsonDecode(await httpResponse.transform(utf8.decoder).join());
        return serverInfoMap['http_address'];
      }
    } catch (e) {
      //
    }
    return "";
  }

  Future _init() async {
    // 准备数据文件夹
    Directory documentDirectory = await getApplicationDocumentsDirectory();
    rootDirectoryPath = join(documentDirectory.path, '里路好传');
    if (Platform.isAndroid) {
      rootDirectoryPath = join(await _getDirectory(), '里路好传');
    }

    l.config('文件夹路径: $rootDirectoryPath');
    await Directory(rootDirectoryPath).create(recursive: true);

    // 初始化数据库
    await initDb(directoryPath: rootDirectoryPath);

    // 首次加载
    _refresh();

    var httpClient = HttpClient();
    httpClient.idleTimeout = Duration(seconds: 3);
    try {
      // 准备模板文件
      var templatePath = join(rootDirectoryPath, 'template', 'index.html');
      if (FileSystemEntity.typeSync(templatePath) != FileSystemEntityType.notFound) {
        File(templatePath).deleteSync();
      }
      var templateFileData = await rootBundle.load('service/template/index.html');
      var templateFile = File(templatePath);
      templateFile.createSync(recursive: true);
      templateFile.writeAsBytesSync(templateFileData.buffer.asUint8List(templateFileData.offsetInBytes, templateFileData.lengthInBytes));

      // 准备服务文件
      l.fine('系统:${SysInfo.operatingSystemName}');
      l.fine('架构:${SysInfo.kernelArchitecture}');
      var serverFilename = 'gts-linux-64';
      if (SysInfo.kernelArchitecture == "x86") {
        serverFilename = 'gts-linux-32';
      }
      if (Platform.isWindows) {
        serverFilename = 'gts-windows-64.exe';
      } else if (Platform.isAndroid) {
        serverFilename = 'gts-android_arm64';
        // 支持x86 TV
        if (SysInfo.kernelArchitecture == "i686") {
          serverFilename = 'gts-linux-32';
        }
      }
      l.fine('服务文件名称 $serverFilename');
      var httpServerApplicationPath = join(rootDirectoryPath, serverFilename);
      if (FileSystemEntity.typeSync(httpServerApplicationPath) != FileSystemEntityType.notFound) {
        File(httpServerApplicationPath).deleteSync();
      }
      var serverFileData = await rootBundle.load('service/$serverFilename'); // 注意: 不要用join, 在windows里面会因为斜杠问题无法加载!!!
      var httpServerApplicationFile = File(httpServerApplicationPath);
      httpServerApplicationFile.createSync(recursive: true);
      httpServerApplicationFile.writeAsBytesSync(serverFileData.buffer.asUint8List(serverFileData.offsetInBytes, serverFileData.lengthInBytes));
      // TODO 其它平台需要测试是否需要
      if (Platform.isLinux || Platform.isAndroid) {
        // Linux , Android平台授予执行权限
        l.fine('HTTP服务程序授予执行权限');
        var result = await Process.run('chmod', ['+x', httpServerApplicationPath]);
        l.fine('HTTP服务程序授予执行权限结果: ${result.stdout} ${result.stderr}');
      }

      // 获取IP
      String ip = "";
      List<Map<String, dynamic>> ipArray = [];
      for (var ni in await NetworkInterface.list()) {
        l.fine('网络接口名称: ${ni.name}');
        for (var ia in ni.addresses) {
          l.fine('类型: ${ia.type.name} , 地址: ${ia.address}');
          int level = 10;
          if (ia.address.startsWith("192.168.")) {
            level = 1;
          }
          if (ia.address.startsWith("10.")) {
            level = 2;
          }
          if (ia.address.startsWith("172.")) {
            level = 3;
          }
          if (ia.address.startsWith("2") && ia.address.contains(":")) {
            level = 4;
          }
          ipArray.add({"ip":ia.address, "level": level});
        }
      }
      ipArray.sort((a, b) => a["level"].compareTo(b["level"]));
      //
      if (ipArray.length == 0) {
        l.warning('没有IP');
        _dialog('不好', '没有可用IP');
        return;
      }
      ip = ipArray[0]["ip"];
      if (ip.contains(":")) {
        ip = "[$ip]";
      }
      l.fine('使用IP:$ip');

      // 确定HTTP服务的端口
      int httpPort;
      var portFile = File(join(rootDirectoryPath, 'http-port.txt'));
      if (!portFile.existsSync()) {
        // 获取可用端口
        var freeSocket = await ServerSocket.bind('localhost', 0);
        httpPort = freeSocket.port;
        freeSocket.close();
        // 保存
        portFile.createSync();
        portFile.writeAsStringSync('$httpPort');
      } else {
        // 读取
        httpPort = int.parse(portFile.readAsStringSync());
      }
      l.fine('HTTP端口:$httpPort');

      // 启动HTTP服务
      httpServerProcess = await Process.start(httpServerApplicationPath, ['--d=$rootDirectoryPath', '--p=$httpPort']);
      httpServerProcess.stdout.transform(utf8.decoder).forEach((txt) {
        l.fine(txt);
      });
      httpServerProcess.stderr.transform(utf8.decoder).forEach((txt) {
        l.warning(txt);
      });

      // 获取服务信息
      // String httpAddress = await _getHttpServerAddress(httpClient, httpPort);
      // // 间隔1秒连接1次直到连接成功
      // while (httpAddress == '') {
      //   await Future.delayed(Duration(seconds: 1));
      //   httpAddress = await _getHttpServerAddress(httpClient, httpPort);
      // }
      String httpAddress = '$ip:$httpPort';
      l.fine('HTTP地址:$httpAddress');
      _gatewayAddress = 'http://$httpAddress';

      // 订阅 https://flutter.cn/docs/cookbook/networking/web-sockets
      wc = WebSocketChannel.connect(Uri.parse('ws://$httpAddress/feed'));
      wc.stream.listen(
        (message) {
          l.fine(message);
          Map<String, dynamic> pushMap = jsonDecode(message);

          if (pushMap['c'] == '文本') {
            Map<String, dynamic> textMap = jsonDecode(pushMap['t']!);
            String txt = textMap['text'];
            var txtLength = txt.length;
            insert(Info(textMap['id']!, txt, txtLength, '', txtLength));
            _refresh();
            return;
          }

          if (pushMap['c'] == '上传开始') {
            Map<String, dynamic> textMap = jsonDecode(pushMap['t']!);
            insert(Info(textMap['id']!, textMap['name']!, textMap['size']!, textMap['id']!, 0));
            _refresh();
            return;
          }

          if (pushMap['c'] == '上传进度') {
            Map<String, dynamic> textMap = jsonDecode(pushMap['t']!);
            updateReceiveSize(textMap['id']!, textMap['size']!);
            _refresh();
            return;
          }
        },
        onError: (error) {
          l.warning('订阅错误', error);
          _dialog('不好了', '后台出现了问题: $error');
        },
        onDone: () {
          l.fine('订阅结束');
        },
      );
      wc.sink.add('开始订阅');

      // 生成网址二维码
      var httpRequest = await httpClient.get('localhost', httpPort, '/qrcode?name=http.jpg&text=$_gatewayAddress');
      var httpResponse = await httpRequest.close();
      final qrcodePath = await httpResponse.transform(utf8.decoder).join();
      _qrcode = Image.file(
        File(qrcodePath),
        width: 128,
        height: 128,
      );

      // 显示网址
      setState(() {
        //
      });
    } catch (e) {
      l.warning(e);

      Future.delayed(Duration.zero, () {
        _dialog('出问题了', e.toString());
      });
    } finally {
      httpClient.close();
    }
  }

  _destroy() {
    l.fine('销毁资源');
    try {
      httpServerProcess.kill();
      wc.sink.close();
      closeDb();
    } catch (e) {
      //
    }
  }

  @override
  void initState() {
    super.initState();

    _init();
  }

  @override
  Widget build(BuildContext context) {
    bc = context;
    var bodyChildren = [
      Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Padding(
            padding: EdgeInsets.all(16),
            child: Text(
              '扫码或打开网址给我传东西',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
          _qrcode,
          Padding(
            padding: EdgeInsets.all(16),
            child: Text(
              _gatewayAddress,
              style: Theme.of(context).textTheme.bodyLarge,
            ),
          ),
          OutlinedButton.icon(
            icon: Icon(Icons.copy_rounded),
            label: Text("复制网址"),
            onPressed: () {
              FlutterClipboard.copy(_gatewayAddress).then((value) => {EasyLoading.showToast('已经复制')});
            },
          ),
          Padding(
            padding: EdgeInsets.all(16),
            child: Text(
              '打开网址 lilu.red 探索更多',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        ],
      ),
      Expanded(
        child: ListView(
          padding: EdgeInsets.all(8),
          children: _cardList,
        ),
      ),
    ];

    return Scaffold(
      appBar: AppBar(
        // Here we take the value from the MyHomePage object that was created by
        // the App.build method, and use it to set our appbar title.
        title: Text(widget.title),
        // 参考 https://medium.com/codechai/playing-with-appbar-in-flutter-3a8abd9b982a
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: IconButton(
              icon: Icon(
                Icons.exit_to_app,
                size: 24,
              ),
              onPressed: () {
                l.fine('点了退出');
                _destroy();

                if (Platform.isWindows) {
                  exit(0);
                } else {
                  // https://stackoverflow.com/questions/45109557/flutter-how-to-programmatically-exit-the-app
                  SystemChannels.platform.invokeMethod('SystemNavigator.pop');
                }
              },
            ),
          ),
        ],
      ),
      body: OrientationBuilder(
        builder: (buildContext, orientation) {
          if (orientation == Orientation.portrait) {
            l.fine('竖屏');
            return Column(
              children: bodyChildren,
            );
          }

          l.fine('横屏');
          return Row(
            children: bodyChildren,
          );
        },
      ),
    );
  }
}
