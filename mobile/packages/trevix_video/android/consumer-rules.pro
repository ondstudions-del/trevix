# R8 reescribe el paso del LogSessionId (nulo antes de Android 12) con un check-cast a android.media.metrics.LogSessionId,
# que no existe en Android 11 o anterior: la app se cierra al empezar a renderizar. https://github.com/androidx/media/issues/2535
-keep class androidx.media3.transformer.** { *; }
-dontwarn android.media.metrics.**
