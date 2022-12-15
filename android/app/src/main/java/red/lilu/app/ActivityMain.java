package red.lilu.app;

import android.util.Log;

import androidx.annotation.NonNull;

import java.io.File;

import io.flutter.embedding.android.FlutterActivity;
import io.flutter.embedding.engine.FlutterEngine;
import io.flutter.plugin.common.MethodChannel;
import red.lilu.app.tool.Ctx;

public class ActivityMain extends FlutterActivity {
    private static final String T = "调试";
    private static final String CHANNEL = "app.lilu.red/flutter";

    @Override
    public void configureFlutterEngine(@NonNull FlutterEngine flutterEngine) {
        super.configureFlutterEngine(flutterEngine);
        new MethodChannel(flutterEngine.getDartExecutor().getBinaryMessenger(), CHANNEL)
                .setMethodCallHandler(
                        (call, result) -> {
                            if (call.method.equals("getDirectory")) { // 获取文件夹
                                File dir = getFilesDir();
                                Log.i(T, String.format("获取文件夹路径:%s", dir.getAbsolutePath()));
                                result.success(dir.getAbsolutePath());
                            } else if (call.method.equals("open")) { // 打开文件
                                String filePath = call.argument("filePath");
                                if (filePath == null) {
                                    Log.w(T, "没有设置文件路径参数");
                                    return;
                                }

                                Log.i(T, String.format("打开文件路径:%s", filePath));
                                Ctx.view(
                                        ActivityMain.this,
                                        new File(filePath),
                                        "选择如何打开",
                                        error -> {
                                            result.error("失败", error, null);
                                        },
                                        done -> {
                                            result.success("成功");
                                        }
                                );
                            } else {
                                result.notImplemented();
                            }
                        }
                );
    }
}
