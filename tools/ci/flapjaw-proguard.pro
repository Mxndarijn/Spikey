# R8 rules for the Android release build (tools/ci/patch_android_shrink.sh).
# The engine calls Godot's Java classes by name over JNI, so R8 can't see those uses.
-keep class org.godotengine.** { *; }
-dontwarn org.godotengine.**

# Godot plugins: found by class name from the manifest, called through JNI.
-keep class * extends org.godotengine.godot.plugin.GodotPlugin { *; }
-keep class com.godotx.** { *; }
-keep class com.poingstudios.godot.** { *; }

# Some SDK classes refer to optional libraries that aren't in the build. Warn, don't fail.
-ignorewarnings
