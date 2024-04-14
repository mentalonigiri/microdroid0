--add_requires("blake3", {configs = {shared = true}})

add_rules("mode.release", "mode.debug")

target("glue")
set_kind("static")
add_includedirs("$(env ANDROID_NDK_ROOT)/sources/android/native_app_glue", {public = true})
add_files("$(env ANDROID_NDK_ROOT)/sources/android/native_app_glue/android_native_app_glue.c")

target("native-activity")
set_default(true)
add_files("main.cpp")
if is_plat("android") then
  set_kind("shared")
  add_deps("glue")
  
  after_build(function (target)
    for _, pkg in ipairs(target:orderpkgs()) do
      os.cp(path.join(pkg:installdir(), "lib", "*.so"), target:targetdir())
    end
  end)

  add_syslinks("android",
    "EGL",
    "GLESv1_CM",
    "log")
  add_shflags("-u ANativeActivity_onCreate")
end
