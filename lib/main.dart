import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:clipboard/clipboard.dart';
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
import 'package:web_socket_channel/web_socket_channel.dart';

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
      home: const MyHomePage(title: title),
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

  // 调用原生功能打开文件
  Future _openFile(String filePath) async {
    await platform.invokeMethod('open', {
      'filePath': filePath,
    });
  }

  // 调用原生功能获取文件夹
  Future<String> _getDirectory() async {
    return await platform.invokeMethod('getDirectory');
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

      var actionArray = <Widget>[];
      if (info.size != info.receiveSize) {
        // 显示进度条
        var progress = info.receiveSize / info.size;
        actionArray.add(
          Expanded(
            child: LinearProgressIndicator(
              value: progress,
              valueColor: AlwaysStoppedAnimation(Colors.blue),
              backgroundColor: Colors.orange.shade200,
            ),
          ),
        );
      } else if (info.path != '') {
        // 显示打开按钮
        actionArray.add(
          ElevatedButton.icon(
            icon: Icon(Icons.open_in_browser_rounded),
            label: Text('打开'),
            onPressed: () {
              if (Platform.isAndroid) {
                _openFile(filePath);
              } else {
                OpenAppFile.open(filePath).then((result) {
                  l.fine('打开结果 ${result.message}');
                });
              }
            },
          ),
        );
      } else {
        // 显示复制按钮
        actionArray.add(
          ElevatedButton.icon(
            icon: Icon(Icons.copy_rounded),
            label: Text('复制'),
            onPressed: () {
              FlutterClipboard.copy(info.txt)
                  .then((value) => {EasyLoading.showToast('已经复制')});
            },
          ),
        );
      }

      // 添加间距空间
      actionArray.add(
        SizedBox(width: 8),
      );

      // 添加删除按钮
      actionArray.add(
        OutlinedButton.icon(
          icon: Icon(Icons.delete_forever_rounded),
          label: Text("删除"),
          onPressed: () {
            if (filePath != '') {
              File(filePath).delete();
            }
            delete(info.uuid);
            refresh();
          },
        ),
      );

      cardArray.add(Card(
        child: Column(
          mainAxisSize: MainAxisSize.min,
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
            Padding(
              padding: EdgeInsets.all(16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: actionArray,
              ),
            ),
          ],
        ),
      ));
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

  Future refresh() async {
    List<Info> dataList = await all();
    _cardList =
        generateCardList(directoryPath: rootDirectoryPath, data: dataList);
    setState(() {
      //
    });
  }

  Future init() async {
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
    refresh();

    var httpClient = HttpClient();
    try {
      // 准备模板文件
      var templateFile =
          File(join(rootDirectoryPath, 'template', 'index.html'));
      if (templateFile.existsSync()) {
        templateFile.deleteSync();
      }
      templateFile.createSync(recursive: true);
      var templateFileData =
          await rootBundle.load('service/template/index.html');
      var templateFileDataBuffer = templateFileData.buffer;
      templateFile.writeAsBytesSync(templateFileDataBuffer.asUint8List(
          templateFileData.offsetInBytes, templateFileData.lengthInBytes));

      // 准备服务文件
      var serverFilename = 'gts-amd64';
      if (Platform.isWindows) {
        serverFilename = 'gts-amd64.exe';
      } else if (Platform.isAndroid) {
        serverFilename = 'gts-android_arm64';
      }
      l.fine('服务文件名称 $serverFilename');
      var serverFile = File(join(rootDirectoryPath, serverFilename));
      if (serverFile.existsSync()) {
        serverFile.deleteSync();
      }
      serverFile.createSync(recursive: true);
      var serverFileData =
          await rootBundle.load(join('service', serverFilename));
      var serverFileDataBuffer = serverFileData.buffer;
      serverFile.writeAsBytesSync(serverFileDataBuffer.asUint8List(
          serverFileData.offsetInBytes, serverFileData.lengthInBytes));
      // TODO 其它平台需要测试是否需要?
      if (Platform.isLinux || Platform.isAndroid) {
        // Linux , Android平台授予执行权限
        l.fine('HTTP服务程序授予执行权限');
        var result = await Process.run('chmod', ['+x', serverFile.path]);
        l.fine('HTTP服务程序授予执行权限结果: ${result.stdout} ${result.stderr}');
      }

      // 启动HTTP服务
      httpServerProcess =
          await Process.start(serverFile.path, ['--d=$rootDirectoryPath']);
      httpServerProcess.stdout.transform(utf8.decoder).forEach((txt) {
        l.fine(txt);
      });
      httpServerProcess.stderr.transform(utf8.decoder).forEach((txt) {
        l.warning(txt);
      });

      // 获取端口信息
      var portFile = File(join(rootDirectoryPath, 'port.txt'));
      while (!portFile.existsSync()) {
        l.fine('没有找到端口文件, HTTP服务没有就绪');
        await Future.delayed(Duration(seconds: 1), () {
          l.fine('再次检查端口文件是否存在');
        });
      }
      var portText = portFile.readAsStringSync();
      l.fine('HTTP服务端口: $portText');

      // 获取服务信息
      var httpRequest = await httpClient.get(
          'localhost', int.parse(portText), '/server/info');
      var httpResponse = await httpRequest.close();
      var serverInfoMap =
          jsonDecode(await httpResponse.transform(utf8.decoder).join());
      l.fine('服务器信息 $serverInfoMap');
      var httpAddress = serverInfoMap['http_address'];
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
            refresh();
            return;
          }

          if (pushMap['c'] == '上传开始') {
            Map<String, dynamic> textMap = jsonDecode(pushMap['t']!);
            insert(Info(textMap['id']!, textMap['name']!, textMap['size']!,
                textMap['id']!, 0));
            refresh();
            return;
          }

          if (pushMap['c'] == '上传进度') {
            Map<String, dynamic> textMap = jsonDecode(pushMap['t']!);
            updateReceiveSize(textMap['id']!, textMap['size']!);
            refresh();
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
      httpRequest = await httpClient.get('localhost', int.parse(portText),
          '/qrcode?name=http.jpg&text=$_gatewayAddress');
      httpResponse = await httpRequest.close();
      var qrcodePath = await httpResponse.transform(utf8.decoder).join();
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

  @override
  void initState() {
    super.initState();

    init();
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
              FlutterClipboard.copy(_gatewayAddress)
                  .then((value) => {EasyLoading.showToast('已经复制')});
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
            child: GestureDetector(
              onTap: () {
                l.fine('点了退出');
                // https://stackoverflow.com/questions/45109557/flutter-how-to-programmatically-exit-the-app
                SystemChannels.platform.invokeMethod('SystemNavigator.pop');
              },
              child: const Icon(
                Icons.exit_to_app,
                size: 24,
              ),
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

  @override
  void dispose() {
    httpServerProcess.kill();
    wc.sink.close();
    closeDb();
    super.dispose();
  }
}
