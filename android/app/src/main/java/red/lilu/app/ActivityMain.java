package red.lilu.app;

import android.Manifest;
import android.content.Intent;
import android.content.pm.PackageManager;
import android.os.Build;
import android.os.Environment;
import android.provider.Settings;
import android.util.Log;

import androidx.annotation.NonNull;
import androidx.core.content.ContextCompat;

import com.google.android.material.dialog.MaterialAlertDialogBuilder;

import java.io.File;

import io.flutter.embedding.android.FlutterActivity;
import io.flutter.embedding.engine.FlutterEngine;
import io.flutter.plugin.common.MethodChannel;

import red.lilu.app.tool.Ctx;

public class ActivityMain extends FlutterActivity {
    private static final String T = "调试";
    private static final int REQUEST_CODE_PERMISSION_STORAGE = 1;
    private static final int REQUEST_CODE_PERMISSION_STORAGE_MANAGE = 2;
    private static final String CHANNEL = "app.lilu.red/flutter";

    @Override
    public void onRequestPermissionsResult(int requestCode, @NonNull String[] permissions, @NonNull int[] grantResults) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults);

        if (requestCode == REQUEST_CODE_PERMISSION_STORAGE) {
            if (grantResults.length > 0 && grantResults[0] == PackageManager.PERMISSION_GRANTED) {
                Log.i(T, "已经授予存储权限");
            } else {
                Log.w(T, "没有授予存储权限");
            }
        }
    }

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
                            } else if (call.method.equals("getPublicDownloadDirectory")) { // 获取公共下载文件夹
                                File dir = Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS);
                                Log.i(T, String.format("获取公共下载文件夹路径:%s", dir.getAbsolutePath()));
                                result.success(dir.getAbsolutePath());
                            } else if (call.method.equals("open")) { // 打开文件
                                String filePath = call.argument("filePath");
                                if (filePath == null) {
                                    Log.w(T, "没有设置文件路径参数");
                                    result.error("失败", "没有设置文件路径参数", null);
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
                            } else if (call.method.equals("requestStoragePermission")) { // 获取存储权限
                                Log.i(T, "获取存储权限");
                                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R && !Environment.isExternalStorageManager()) {
                                    startActivityForResult(
                                            new Intent(Settings.ACTION_MANAGE_ALL_FILES_ACCESS_PERMISSION),
                                            REQUEST_CODE_PERMISSION_STORAGE_MANAGE
                                    );

                                    result.success("没有权限");
                                    return;
                                }

                                if (
                                        Build.VERSION.SDK_INT >= Build.VERSION_CODES.M && Build.VERSION.SDK_INT < Build.VERSION_CODES.R
                                                && ContextCompat.checkSelfPermission(getApplicationContext(), Manifest.permission.WRITE_EXTERNAL_STORAGE) == PackageManager.PERMISSION_DENIED
                                ) {
                                    requestPermissions(
                                            new String[]{Manifest.permission.WRITE_EXTERNAL_STORAGE},
                                            REQUEST_CODE_PERMISSION_STORAGE
                                    );

                                    result.success("没有权限");
                                    return;
                                }

                                result.success("已有权限");
                            } else {
                                result.notImplemented();
                            }
                        }
                );
    }
}
