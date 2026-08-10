# Custom ProGuard rules
#
# Smartlook-specific -dontwarn rules were removed when Smartlook was retired.
#
# FlutterActivity loads the generated registrant during engine startup, and
# plugins attach MethodChannels through the engine binary messenger. Preserve
# these narrow bridge entry points while allowing R8 to shrink their unused
# Android/Firebase dependencies.
-keep class com.tsepo.pasella.MainActivity { *; }
-keep class io.flutter.plugins.GeneratedPluginRegistrant { *; }
-keep,allowoptimization class * implements io.flutter.embedding.engine.plugins.FlutterPlugin { *; }
-keepnames class io.flutter.embedding.engine.FlutterEngine
-keepnames class io.flutter.embedding.engine.FlutterEngineGroup
-keepnames class io.flutter.plugin.common.MethodChannel
