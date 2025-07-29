# Keep all Material Design components (required by Smartlook)
-keep class com.google.android.material.** { *; }
-keep interface com.google.android.material.** { *; }
-dontwarn com.google.android.material.**

# Keep all Smartlook SDK classes
-keep class com.smartlook.sdk.** { *; }
-dontwarn com.smartlook.sdk.**

# Optional: Keep Smartlook annotations (in case they're used)
-keep @interface com.smartlook.sdk.annotation.**
