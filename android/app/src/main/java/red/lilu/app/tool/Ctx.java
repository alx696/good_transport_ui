package red.lilu.app.tool;

import android.content.ComponentName;
import android.content.Context;
import android.content.Intent;
import android.net.Uri;
import android.os.Build;
import android.util.Log;

import androidx.annotation.Nullable;
import androidx.core.content.FileProvider;

import java.io.File;

/**
 * 上下文通用功能
 */
public abstract class Ctx {

    private static final String T = "调试-上下文通用功能";

    /**
     * 通过文件后缀猜测MimeType
     *
     * @param extension 文件后缀, 例如 png
     * @return Mime Type, 例如 application/vnd.android.package-archive
     */
    public static String mimeTypeFromExtension(String extension) {
        // 支持的媒体格式
        // https://developer.android.com/guide/topics/media/media-formats?hl=zh-cn

        if (extension.equals("apk")) {
            Log.d(T, "根据文件后缀猜测文件是APK");
            return "application/vnd.android.package-archive";
        }

        if (extension.equals("jpg") || extension.equals("jpeg") || extension.equals("png") || extension.equals("bmp") || extension.equals("webp") || extension.equals("heif")) {
            return "image/*";
        }

        if (extension.equals("mp4") || extension.equals("avi") || extension.equals("webm") || extension.equals("mkv") || extension.equals("3gp")) {
            return "video/*";
        }

        if (extension.equals("flac") || extension.equals("mp3") || extension.equals("wav") || extension.equals("ogg")) {
            return "audio/*";
        }

        return "*/*";
    }

    /**
     * 查看文件
     *
     * @param activityContext Activity
     * @param file            文件
     * @param title           可选, 不为NULL时显示选择应用界面
     * @param onError         error -> {}
     */
    public static void view(Context activityContext,
                            File file,
                            @Nullable String title,
                            java9.util.function.Consumer<String> onError,
                            java9.util.function.Consumer<String> onSuccess) {
        try {
            // 设置Intent
            Intent intent = new Intent(Intent.ACTION_VIEW);

            // 准备URI
            Uri uri;
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                // 首先,生成Provider的Content Uri
                // 注意: 文件目录必须配置, 否则抛 IllegalArgumentException: Failed to find configured root that contains
                // 注意: Intent需要设置 FLAG_GRANT_READ_URI_PERMISSION 或 FLAG_GRANT_WRITE_URI_PERMISSION
                uri = FileProvider.getUriForFile(
                        activityContext,
                        String.format("%s.file_provider", activityContext.getPackageName()),
                        file
                );
                // 接着, 标记赋予读权限(否则某些系统中调用的应用无法获取文件内容)
                intent.setFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION);
            } else {
                uri = Uri.fromFile(file);
            }

            // 设置内容
            String mimeType = activityContext.getContentResolver().getType(uri);
            if (mimeType != null) {
                Log.d(T, String.format("文件类型: %s", mimeType));
            } else {
                String extension = "";
                int indexOfPoint = file.getName().lastIndexOf(".");
                if (indexOfPoint < file.getName().length()) {
                    extension = file.getName().substring(indexOfPoint + 1);
                }
                mimeType = mimeTypeFromExtension(extension);
                Log.d(T, String.format("文件类型无法直接识别, 根据后缀 %s 推测类型是 %s", extension, mimeType));
            }
            intent.setDataAndType(uri, mimeType);
            if (mimeType.equals("application/vnd.android.package-archive")) {
                Log.d(T, "文件是APK时设置未知源扩展");
                intent.putExtra(Intent.EXTRA_NOT_UNKNOWN_SOURCE, true);
            }

            // 检查是否有可以处理文件的应用
            // https://developer.android.com/guide/components/intents-filters#imatch
            ComponentName resolveActivity = intent.resolveActivity(activityContext.getPackageManager());
            if (resolveActivity == null) {
                onError.accept("不支持此操作");
                return;
            }

            // 打开界面
            intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
            if (title != null) {
                // 强制选择
                activityContext.startActivity(
                        Intent.createChooser(intent, title)
                );
            } else {
                // 使用默认
                activityContext.startActivity(intent);
            }
            onSuccess.accept("");
        } catch (Exception e) {
            onError.accept(e.getMessage());
        }
    }

}
