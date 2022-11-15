import 'dart:async';
import 'dart:io';

import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class Info {
  String uuid = '';

  // 文本内容 或 文件名称
  String txt = '';

  // 文本长度 或 文件字节数量
  int size = 0;

  // 文件路径, 为空字符时说明是这是文本
  String path = '';

  // 已经收到文件字节数量, 数值小于 size 时说明还在接收, 相等时说明传输完毕.
  int receiveSize = 0;

  // 时间戳
  int ts = DateTime.now().millisecondsSinceEpoch;

  Info(this.uuid, this.txt, this.size, this.path, this.receiveSize);

  // Convert a Dog into a Map. The keys must correspond to the names of the
  // columns in the database.
  Map<String, dynamic> toMap() {
    return {
      'uuid': uuid,
      'txt': txt,
      'size': size,
      'path': path,
      'receiveSize': receiveSize,
      'ts': ts,
    };
  }

  // Implement toString to make it easier to see information about
  // each dog when using the print statement.
  // 重写 toString 方法，以便使用 print 方法查看每个狗狗信息的时候能更清晰。
  @override
  String toString() {
    return 'Info{uuid: $uuid, txt: $txt, size: $size, path: $path, receiveSize: $receiveSize, ts: $ts}';
  }
}

late Database db;

initDb({
  String directoryPath = '',
}) async {
  var dbPath = join(directoryPath, 'info.db');
  // 注意: 桌面端和移动端需要不同的库提供支持!
  if (Platform.isAndroid || Platform.isIOS || Platform.isMacOS) {
    db = await openDatabase(
      dbPath,
      version: 1,
      onCreate: (Database db, int version) async {
        await db.execute(
          'CREATE TABLE IF NOT EXISTS info(uuid TEXT PRIMARY KEY, txt TEXT, size INTEGER, path TEXT, receiveSize INTEGER, ts INTEGER)',
        );
      },
    );
  } else {
    // Init ffi loader if needed.
    sqfliteFfiInit();
    var databaseFactory = databaseFactoryFfi;
    db = await databaseFactory.openDatabase(dbPath);
    await db.execute(
      'CREATE TABLE IF NOT EXISTS info(uuid TEXT PRIMARY KEY, txt TEXT, size INTEGER, path TEXT, receiveSize INTEGER, ts INTEGER)',
    );
  }
}

closeDb() async {
  await db.close();
}

Future insert(Info data) async {
  await db.insert(
    'info',
    data.toMap(),
    conflictAlgorithm: ConflictAlgorithm.replace,
  );
}

Future update(Info data) async {
  await db.update(
    'info',
    data.toMap(),
    where: 'uuid = ?',
    whereArgs: [data.uuid],
  );
}

Future updateReceiveSize(String uuid, int receiveSize) async {
  await db.update(
    'info',
    {
      'receiveSize': receiveSize,
    },
    where: 'uuid = ?',
    whereArgs: [uuid],
  );
}

Future delete(String uuid) async {
  await db.delete(
    'info',
    where: 'uuid = ?',
    whereArgs: [uuid],
  );
}

Future<List<Info>> all() async {
  // Query the table for all
  final List<Map<String, dynamic>> maps =
      await db.query('info', orderBy: 'ts desc');
  // Convert the List<Map<String, dynamic> into a List<Info>
  return List.generate(maps.length, (i) {
    return Info(
      maps[i]['uuid'],
      maps[i]['txt'],
      maps[i]['size'],
      maps[i]['path'],
      maps[i]['receiveSize'],
    );
  });
}
