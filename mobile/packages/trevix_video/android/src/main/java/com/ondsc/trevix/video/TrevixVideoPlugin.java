package com.ondsc.trevix.video;

import android.content.Context;
import android.graphics.Bitmap;
import android.graphics.BitmapFactory;
import android.graphics.PointF;
import android.media.FaceDetector;
import android.media.MediaMetadataRetriever;
import android.net.Uri;
import android.os.Build;
import android.os.Handler;
import android.os.Looper;
import androidx.annotation.NonNull;
import androidx.annotation.OptIn;
import androidx.media3.common.Effect;
import androidx.media3.common.MediaItem;
import androidx.media3.common.MimeTypes;
import androidx.media3.common.audio.AudioProcessor;
import androidx.media3.common.util.UnstableApi;
import androidx.media3.effect.BitmapOverlay;
import androidx.media3.effect.OverlayEffect;
import androidx.media3.effect.OverlaySettings;
import androidx.media3.effect.Presentation;
import androidx.media3.effect.RgbMatrix;
import androidx.media3.effect.TextureOverlay;
import androidx.media3.transformer.Composition;
import androidx.media3.transformer.EditedMediaItem;
import androidx.media3.transformer.EditedMediaItemSequence;
import androidx.media3.transformer.Effects;
import androidx.media3.transformer.ExportException;
import androidx.media3.transformer.ExportResult;
import androidx.media3.transformer.ProgressHolder;
import androidx.media3.transformer.Transformer;
import com.google.common.collect.ImmutableList;
import io.flutter.embedding.engine.plugins.FlutterPlugin;
import io.flutter.plugin.common.MethodCall;
import io.flutter.plugin.common.MethodChannel;
import java.io.File;
import java.io.FileOutputStream;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;

/**
 * Edición de video de TREVIX con Media3 Transformer: recorte a una proporción, matriz de color, superposiciones PNG
 * que se mueven según claves de tiempo, imagen de cierre al final y sustitución del sonido por una canción.
 */
@OptIn(markerClass = UnstableApi.class)
public class TrevixVideoPlugin implements FlutterPlugin, MethodChannel.MethodCallHandler {
    private MethodChannel channel;
    private Context context;
    private Transformer transformer;
    private MethodChannel.Result pending;
    private String pendingOutput;
    private volatile boolean framesCancelled;
    private final Handler main = new Handler(Looper.getMainLooper());
    private final ExecutorService detectorThread = Executors.newSingleThreadExecutor();
    private FaceDetector detector;
    private int detectorW;
    private int detectorH;

    @Override
    public void onAttachedToEngine(@NonNull FlutterPluginBinding binding) {
        context = binding.getApplicationContext();
        channel = new MethodChannel(binding.getBinaryMessenger(), "trevix_video");
        channel.setMethodCallHandler(this);
    }

    @Override
    public void onDetachedFromEngine(@NonNull FlutterPluginBinding binding) {
        cancel();
        channel.setMethodCallHandler(null);
    }

    @Override
    public void onMethodCall(@NonNull MethodCall call, @NonNull MethodChannel.Result result) {
        switch (call.method) {
            case "render":
                if (transformer != null) {
                    result.error("busy", "Ya se está procesando otro video.", null);
                    return;
                }
                try {
                    render(call, result);
                } catch (Exception e) {
                    transformer = null;
                    if (pending == result) {
                        pending = null;
                        pendingOutput = null;
                    }
                    result.error("render", String.valueOf(e.getMessage()), null);
                }
                break;
            case "frames":
                framesCancelled = false;
                frames(call, result);
                break;
            case "faces":
                faces(call, result);
                break;
            case "progress":
                result.success(progress());
                break;
            case "cancel":
                cancel();
                result.success(null);
                break;
            default:
                result.notImplemented();
        }
    }

    private void render(MethodCall call, MethodChannel.Result result) {
        String input = call.argument("input");
        String output = call.argument("output");
        int[] info = probe(input);
        if (output == null || info == null) {
            result.error("input", "No se pudo leer el video.", null);
            return;
        }

        float srcW = info[0];
        float srcH = info[1];
        float cropW = srcW;
        float cropH = srcH;
        Number aspect = call.argument("aspect");
        if (aspect != null && aspect.floatValue() > 0) {
            if (srcW / srcH > aspect.floatValue()) cropW = srcH * aspect.floatValue();
            else cropH = srcW / aspect.floatValue();
        }
        Number maxWidth = call.argument("maxWidth");
        float scale = Math.min(1f, (maxWidth == null ? 1080 : maxWidth.intValue()) / cropW);
        int outW = even(cropW * scale);
        int outH = even(cropH * scale);

        List<Effect> effects = new ArrayList<>();
        effects.add(Presentation.createForWidthAndHeight(outW, outH, Presentation.LAYOUT_SCALE_TO_FIT_WITH_CROP));
        List<Number> matrix = call.argument("colorMatrix");
        if (matrix != null && matrix.size() == 20) effects.add(rgbMatrix(matrix));
        List<Map<String, Object>> overlays = call.argument("overlays");
        if (overlays != null && !overlays.isEmpty()) {
            ImmutableList.Builder<TextureOverlay> list = ImmutableList.builder();
            for (Map<String, Object> o : overlays) {
                Bitmap bitmap = BitmapFactory.decodeFile((String) o.get("image"));
                @SuppressWarnings("unchecked")
                List<Map<String, Object>> keys = (List<Map<String, Object>>) o.get("keys");
                if (bitmap != null && keys != null && !keys.isEmpty()) list.add(new KeyedOverlay(bitmap, keys, outW));
            }
            ImmutableList<TextureOverlay> built = list.build();
            if (!built.isEmpty()) effects.add(new OverlayEffect(built));
        }

        String audio = call.argument("audio");
        Boolean keep = call.argument("keepAudio");
        boolean keepAudio = keep == null || keep;
        List<EditedMediaItem> items = new ArrayList<>();
        items.add(new EditedMediaItem.Builder(MediaItem.fromUri(Uri.fromFile(new File(input))))
                .setRemoveAudio(audio != null || !keepAudio)
                .setEffects(new Effects(ImmutableList.<AudioProcessor>of(), effects))
                .build());

        String outro = call.argument("outroImage");
        Number outroMsArg = call.argument("outroMs");
        long outroMs = outro == null || outroMsArg == null ? 0 : outroMsArg.longValue();
        if (outroMs > 0) {
            MediaItem image = new MediaItem.Builder()
                    .setUri(Uri.fromFile(new File(outro)))
                    .setMimeType(MimeTypes.IMAGE_PNG)
                    .setImageDurationMs(outroMs)
                    .build();
            items.add(new EditedMediaItem.Builder(image)
                    .setFrameRate(30)
                    .setEffects(new Effects(ImmutableList.<AudioProcessor>of(),
                            ImmutableList.<Effect>of(Presentation.createForWidthAndHeight(outW, outH, Presentation.LAYOUT_SCALE_TO_FIT_WITH_CROP))))
                    .build());
        }

        List<EditedMediaItemSequence> sequences = new ArrayList<>();
        sequences.add(new EditedMediaItemSequence(items));
        if (audio != null) {
            Number startArg = call.argument("audioStartMs");
            long start = startArg == null ? 0 : Math.max(0, startArg.longValue());
            MediaItem song = new MediaItem.Builder()
                    .setUri(Uri.fromFile(new File(audio)))
                    .setClippingConfiguration(new MediaItem.ClippingConfiguration.Builder()
                            .setStartPositionMs(start)
                            .setEndPositionMs(start + info[2] + outroMs)
                            .build())
                    .build();
            sequences.add(new EditedMediaItemSequence(ImmutableList.of(new EditedMediaItem.Builder(song).setRemoveVideo(true).build())));
        }

        Composition.Builder composition = new Composition.Builder(sequences)
                .setHdrMode(Composition.HDR_MODE_TONE_MAP_HDR_TO_SDR_USING_OPEN_GL);
        // La imagen del cierre no tiene sonido: se rellena con silencio para conservar el del video.
        if (audio == null && keepAudio && items.size() > 1) composition.experimentalSetForceAudioTrack(true);

        new File(output).delete();
        pending = result;
        pendingOutput = output;
        transformer = new Transformer.Builder(context)
                .setVideoMimeType(MimeTypes.VIDEO_H264)
                .setAudioMimeType(MimeTypes.AUDIO_AAC)
                .addListener(new Transformer.Listener() {
                    @Override
                    public void onCompleted(@NonNull Composition c, @NonNull ExportResult r) {
                        finish(null, output);
                    }

                    @Override
                    public void onError(@NonNull Composition c, @NonNull ExportResult r, @NonNull ExportException e) {
                        finish(e, output);
                    }
                })
                .build();
        transformer.start(composition.build(), output);
    }

    private void finish(Exception error, String output) {
        MethodChannel.Result r = pending;
        pending = null;
        pendingOutput = null;
        transformer = null;
        if (r == null) return;
        if (error == null) {
            r.success(output);
        } else {
            new File(output).delete();
            r.error("render", String.valueOf(error.getMessage()), null);
        }
    }

    /** Fotogramas exactos (no el fotograma clave más cercano) cada intervalMs, en un hilo aparte. */
    private void frames(MethodCall call, MethodChannel.Result result) {
        String input = call.argument("input");
        String dir = call.argument("dir");
        Number intervalArg = call.argument("intervalMs");
        Number sideArg = call.argument("maxSide");
        int interval = Math.max(40, intervalArg == null ? 200 : intervalArg.intValue());
        int side = Math.max(64, sideArg == null ? 480 : sideArg.intValue());
        new Thread(() -> {
            List<Map<String, Object>> out = new ArrayList<>();
            MediaMetadataRetriever r = new MediaMetadataRetriever();
            try {
                r.setDataSource(input);
                long duration = parse(r.extractMetadata(MediaMetadataRetriever.METADATA_KEY_DURATION));
                for (long ms = 0; ms < duration && !framesCancelled; ms += interval) {
                    Bitmap frame = Build.VERSION.SDK_INT >= 27
                            ? r.getScaledFrameAtTime(ms * 1000, MediaMetadataRetriever.OPTION_CLOSEST, side, side)
                            : r.getFrameAtTime(ms * 1000, MediaMetadataRetriever.OPTION_CLOSEST);
                    if (frame == null) continue;
                    float k = Math.min(1f, side / (float) Math.max(frame.getWidth(), frame.getHeight()));
                    if (k < 1f) {
                        Bitmap scaled = Bitmap.createScaledBitmap(frame, Math.max(1, Math.round(frame.getWidth() * k)),
                                Math.max(1, Math.round(frame.getHeight() * k)), true);
                        frame.recycle();
                        frame = scaled;
                    }
                    File file = new File(dir, "frame_" + ms + ".jpg");
                    try (FileOutputStream os = new FileOutputStream(file)) {
                        frame.compress(Bitmap.CompressFormat.JPEG, 80, os);
                    }
                    Map<String, Object> item = new HashMap<>();
                    item.put("ms", ms);
                    item.put("path", file.getPath());
                    item.put("width", frame.getWidth());
                    item.put("height", frame.getHeight());
                    out.add(item);
                    frame.recycle();
                }
                main.post(() -> result.success(out));
            } catch (Exception e) {
                main.post(() -> result.error("frames", String.valueOf(e.getMessage()), null));
            } finally {
                try {
                    r.release();
                } catch (Exception ignored) {
                }
            }
        }).start();
    }

    /**
     * Caras con el detector del sistema (android.media.FaceDetector, en el teléfono): da el punto entre los ojos y su
     * distancia, con los que se estima el recuadro de la cara. Un hilo propio, una imagen a la vez.
     */
    private void faces(MethodCall call, MethodChannel.Result result) {
        String path = call.argument("path");
        byte[] gray = call.argument("gray");
        Number width = call.argument("width");
        Number height = call.argument("height");
        detectorThread.execute(() -> {
            try {
                Bitmap bmp = null;
                if (path != null) {
                    BitmapFactory.Options o = new BitmapFactory.Options();
                    o.inPreferredConfig = Bitmap.Config.RGB_565;
                    bmp = BitmapFactory.decodeFile(path, o);
                } else if (gray != null && width != null && height != null) {
                    int w = width.intValue();
                    int h = height.intValue();
                    if (w > 0 && h > 0 && gray.length >= w * h) {
                        int[] px = new int[w * h];
                        for (int i = 0; i < px.length; i++) {
                            int g = gray[i] & 0xff;
                            px[i] = 0xff000000 | (g << 16) | (g << 8) | g;
                        }
                        bmp = Bitmap.createBitmap(px, w, h, Bitmap.Config.RGB_565);
                    }
                }
                List<Map<String, Object>> out = new ArrayList<>();
                if (bmp != null) {
                    if (bmp.getConfig() != Bitmap.Config.RGB_565) bmp = bmp.copy(Bitmap.Config.RGB_565, false);
                    if (bmp.getWidth() % 2 != 0) bmp = Bitmap.createBitmap(bmp, 0, 0, bmp.getWidth() - 1, bmp.getHeight());
                    int w = bmp.getWidth();
                    int h = bmp.getHeight();
                    if (detector == null || detectorW != w || detectorH != h) {
                        detector = new FaceDetector(w, h, 4);
                        detectorW = w;
                        detectorH = h;
                    }
                    FaceDetector.Face[] found = new FaceDetector.Face[4];
                    int n = detector.findFaces(bmp, found);
                    PointF mid = new PointF();
                    for (int i = 0; i < n; i++) {
                        FaceDetector.Face f = found[i];
                        if (f == null || f.confidence() < 0.35f) continue;
                        f.getMidPoint(mid);
                        float d = f.eyesDistance();
                        float fw = d * 2.4f;
                        float fh = d * 2.9f;
                        float cy = mid.y + d * 0.25f;
                        Map<String, Object> m = new HashMap<>();
                        m.put("x", (double) (mid.x - fw / 2) / w);
                        m.put("y", (double) (cy - fh / 2) / h);
                        m.put("w", (double) fw / w);
                        m.put("h", (double) fh / h);
                        m.put("ex", (double) mid.x / w);
                        m.put("ey", (double) mid.y / h);
                        out.add(m);
                    }
                }
                main.post(() -> result.success(out));
            } catch (Exception e) {
                main.post(() -> result.error("faces", String.valueOf(e.getMessage()), null));
            }
        });
    }

    private void cancel() {
        framesCancelled = true;
        Transformer t = transformer;
        transformer = null;
        if (t != null) t.cancel();
        MethodChannel.Result r = pending;
        pending = null;
        if (pendingOutput != null) new File(pendingOutput).delete();
        pendingOutput = null;
        if (r != null) r.error("cancelled", "Cancelado.", null);
    }

    private double progress() {
        Transformer t = transformer;
        if (t == null) return -1;
        ProgressHolder holder = new ProgressHolder();
        return t.getProgress(holder) == Transformer.PROGRESS_STATE_AVAILABLE ? holder.progress / 100.0 : -1;
    }

    /** Ancho, alto (ya girados) y duración en ms del video. */
    private static int[] probe(String path) {
        if (path == null) return null;
        MediaMetadataRetriever r = new MediaMetadataRetriever();
        try {
            r.setDataSource(path);
            int w = parse(r.extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_WIDTH));
            int h = parse(r.extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_HEIGHT));
            int rotation = parse(r.extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_ROTATION));
            int duration = parse(r.extractMetadata(MediaMetadataRetriever.METADATA_KEY_DURATION));
            if (w <= 0 || h <= 0) return null;
            if (rotation == 90 || rotation == 270) {
                int s = w;
                w = h;
                h = s;
            }
            return new int[] {w, h, duration};
        } catch (Exception e) {
            return null;
        } finally {
            try {
                r.release();
            } catch (Exception ignored) {
            }
        }
    }

    private static int parse(String s) {
        try {
            return s == null ? 0 : Integer.parseInt(s.trim());
        } catch (NumberFormatException e) {
            return 0;
        }
    }

    private static int even(float v) {
        return Math.max(2, Math.round(v / 2f) * 2);
    }

    /** Matriz 4×5 de Flutter (desplazamientos en 0–255) → matriz 4×4 de Media3 por columnas sobre (r, g, b, 1). */
    private static RgbMatrix rgbMatrix(List<Number> m) {
        float[] out = new float[16];
        for (int row = 0; row < 3; row++) {
            for (int col = 0; col < 3; col++) out[col * 4 + row] = m.get(row * 5 + col).floatValue();
            out[12 + row] = m.get(row * 5 + 4).floatValue() / 255f;
        }
        out[15] = 1f;
        return (presentationTimeUs, useHdr) -> out;
    }

    private static float num(Object o, float fallback) {
        return o instanceof Number ? ((Number) o).floatValue() : fallback;
    }

    /** Superposición cuya posición, tamaño, giro y opacidad se interpolan entre claves de tiempo. */
    private static final class KeyedOverlay extends BitmapOverlay {
        private final Bitmap bitmap;
        private final int outW;
        private final float[] t;
        private final float[] x;
        private final float[] y;
        private final float[] w;
        private final float[] r;
        private final float[] a;

        KeyedOverlay(Bitmap bitmap, List<Map<String, Object>> keys, int outW) {
            this.bitmap = bitmap;
            this.outW = outW;
            int n = keys.size();
            t = new float[n];
            x = new float[n];
            y = new float[n];
            w = new float[n];
            r = new float[n];
            a = new float[n];
            for (int i = 0; i < n; i++) {
                Map<String, Object> k = keys.get(i);
                t[i] = num(k.get("ms"), 0);
                x[i] = num(k.get("x"), .5f);
                y[i] = num(k.get("y"), .5f);
                w[i] = num(k.get("width"), .2f);
                r[i] = num(k.get("rotation"), 0);
                a[i] = num(k.get("alpha"), 1);
            }
        }

        @Override
        public Bitmap getBitmap(long presentationTimeUs) {
            return bitmap;
        }

        @Override
        public OverlaySettings getOverlaySettings(long presentationTimeUs) {
            float ms = presentationTimeUs / 1000f;
            int i = 0;
            while (i < t.length - 1 && t[i + 1] <= ms) i++;
            int j = i;
            float f = 0;
            if (i < t.length - 1 && ms > t[i]) {
                j = i + 1;
                f = (ms - t[i]) / Math.max(1f, t[j] - t[i]);
            }
            float width = w[i] + (w[j] - w[i]) * f;
            float scale = Math.max(.0001f, width * outW / bitmap.getWidth());
            float alpha = a[i] + (a[j] - a[i]) * f;
            return new OverlaySettings.Builder()
                    .setBackgroundFrameAnchor((x[i] + (x[j] - x[i]) * f) * 2 - 1, 1 - (y[i] + (y[j] - y[i]) * f) * 2)
                    .setScale(scale, scale)
                    .setRotationDegrees(r[i] + (r[j] - r[i]) * f)
                    .setAlphaScale(Math.max(0f, Math.min(1f, alpha)))
                    .build();
        }
    }
}
