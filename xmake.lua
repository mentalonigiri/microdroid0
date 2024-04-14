--add_requires("blake3", {configs = {shared = true}})

add_rules("mode.release", "mode.debug")

if (is_plat("android") and os.getenv("ANDROID_NDK_ROOT")) then
target("glue")
set_kind("static")
set_default(false)
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

end

target("build-android")
set_kind("phony")
on_run(function()

local function setEnv(env_key, default_env_value)
	local val = os.getenv(env_key) or default_env_value
	os.setenv(env_key, val)
	return val
end

local data = {}

local function f(s)
   s = s:gsub("\n", " ")
   return (s:gsub('($%b{})', function(w) return data[w:sub(3, -2)] or w end))
end


data.home = setEnv("HOME", "C:\\")
data.android_home = setEnv("ANDROID_HOME", path.join(f("${home}"), "Android/Sdk"))
data.ndk_version = setEnv("ANDROID_NDK_VERSION", "26.2.11394342")
data.build_for_archs = setEnv("BUILD_FOR_ARCHS", "x86_64,armeabi-v7a,arm64-v8a")
data.buildtools_version = setEnv("ANDROID_BUILDTOOLS_VERSION",
	"34.0.0")
data.android_legacy_platform = setEnv("ANDROID_LEGACY_PLATFORM", "21")
data.android_target_platform = setEnv("ANDROID_TARGET_PLATFORM", "34")
data.android_host_os = setEnv("ANDROID_HOST_OS", os.host() .. "-" .. os.arch())

data.debug_ks = path.join(f("${home}"), ".cache/androiddev-debug-keystore.ks")
data.key_store = setEnv("KEY_STORE", f("${debug_ks}"))
data.key_store_pass = setEnv("KEY_STORE_PASS", "mypassword")
data.key_alias = setEnv("KEY_ALIAS", "debug")
data.key_pass = setEnv("KEY_PASS", "mypassword")
data.cmake_version = setEnv("ANDROID_CMAKE_VERSION", "3.22.1")
data.bundle_tool = setEnv("BUNDLE_TOOL", 
	path.join(f("${home}"), ".cache/bundletool.jar"))
data.version = setEnv("APP_VERSION", (os.time() - 1713081821) % 2100000000)

os.mkdir(path.directory(data.bundle_tool))


data.ndk_root = path.join(f("${android_home}"), "ndk", f("${ndk_version}"))
data.toolchain_path = path.join(f("${ndk_root}"), "toolchains/llvm/prebuilt",
	f("${android_host_os}"), "bin")
data.buildtools_path = path.join(f("${android_home}"), "build-tools", f("${buildtools_version}"))
data.path = os.getenv("PATH")

data.needed_sdk_dirs = {
	f("ndk/${ndk_version}"),
	f("build-tools/${buildtools_version}"),
	f("cmake/${cmake_version}"),
	f("platform-tools"),
	f("tools"),
	f("platforms/android-${android_target_platform}")
}
data.begindir = os.workingdir()
os.cd(os.scriptdir())

os.setenv("PATH", f("${toolchain_path}:${buildtools_path}:${path}"))
os.setenv("ANDROID_HOME", data.android_home)
os.setenv("ANDROID_SDK_ROOT", data.android_home)
os.setenv("ANDROID_NDK_ROOT", data.ndk_root)
os.setenv("ANDROID_TARGET_PLATFORM", data.android_target_platform)

local want_sdk = false
for _, component in ipairs(data.needed_sdk_dirs) do
	if (not os.exists(path.join(data.android_home, component))) then
		want_sdk = true
	end
end

local sdkmanager_license_command = f([[
sdkmanager --sdk_root="${android_home}" --licenses
]])
local sdkmanager_install_command = f([[
sdkmanager --sdk_root="${android_home}"
"build-tools;${buildtools_version}"
"cmake;${cmake_version}"
"ndk;${ndk_version}"
"platform-tools"
"platforms;android-${android_target_platform}"
"tools"
]])

os.mkdir("build")
if not os.exists("build/y.txt") then
	io.writefile("build/y.txt", "y\r\ny\r\ny\r\ny\r\ny\r\ny\r\ny\r\ny\r\ny\r\ny\r\n")
end

local function installAndroidSdk()
	os.mkdir(f("${android_home}"))
	os.execv("sdkmanager", {
		f([[--sdk_root=${android_home}]]),
		f([[build-tools;${buildtools_version}]]),
		f([[cmake;${cmake_version}]]),
		f([[ndk;${ndk_version}]]),
		f([[platform-tools]]),
		f([[platforms;android-${android_target_platform}]]),
		f([[tools]])},
		{stdin="build/y.txt"})
	os.exec(sdkmanager_install_command)
end

if want_sdk then
	installAndroidSdk()
end

import("net.http")

if not os.exists(data.bundle_tool) then
	http.download("https://github.com/google/bundletool/releases/download/1.15.6/bundletool-all-1.15.6.jar",
		data.bundle_tool .. ".loading")
	os.mv(data.bundle_tool .. ".loading", data.bundle_tool)
end

local function main()

-- build ndk libs from xmake.lua
for arch in string.gmatch(data.build_for_archs, "[^,]+") do
	data.arch = arch
	os.exec(f(
	[[xmake f -P . 
	--ndk_sdkver=${android_legacy_platform} -vDy -p android
	-m release -a ${arch}]]))
	os.exec([[xmake build -P . -vDy]])
	os.mkdir(f("build/apk/lib/${arch}"))
	os.cp(f("build/android/${arch}/**.so"), f("build/apk/lib/${arch}"))
end

-- make empty res dir
data.resdir = os.exists("res") and "res" or "build/res"
os.mkdir("build/res")

-- compile resources to build/res.zip
os.run(f([[aapt2 compile --dir ${resdir} -o build/res.zip]]))

-- link into format suitable for aab
os.run(f([[
aapt2 link 
--version-name "${version}.0" 
--version-code ${version} 
--min-sdk-version ${android_legacy_platform} 
--target-sdk-version ${android_target_platform} 
--proto-format -o build/aab-unaligned.apk 
-I "${android_home}/platforms/android-${android_target_platform}/android.jar"
--manifest AndroidManifest.xml 
--java src/main/java 
build/res.zip --auto-add-overlay
]]))

-- link into format suitable for apk
os.run(f([[
aapt2 link 
--version-name "${version}.0" 
--version-code ${version} 
--min-sdk-version ${android_legacy_platform} 
--target-sdk-version ${android_target_platform} 
-o build/apk-unaligned.apk 
-I "${android_home}/platforms/android-${android_target_platform}/android.jar"
--manifest AndroidManifest.xml 
--java src/main/java 
build/res.zip --auto-add-overlay
]]))

os.mkdir("build/dex")
-- build java/scala/kotlin using sbt if build.sbt exists
if os.exists("build.sbt") then
	os.run("sbt compile")
	os.run(f([[
d8 --release
--min-api ${android_legacy_platform}
--lib "${android_home}/platforms/android-${android_target_platform}/android.jar" 
--output build/dex target/scala-*/classes/**/**/**/*.class
	]]))
	os.cd("build/dex")
	os.run([[zip -r ../apk-unaligned.apk *]])
	os.cd("../..")
end

os.cd("build")
if os.exists("lib") then
	os.rmdir("lib")
end
os.mv("apk/lib", "lib")

os.run([[zip -r apk-unaligned.apk lib]])
os.run([[jar xf aab-unaligned.apk resources.pb AndroidManifest.xml res]])
os.mkdir("manifest")
os.mv("AndroidManifest.xml", "manifest/AndroidManifest.xml")

data.assetsdir = os.exists("../assets") and "../assets" or ""
os.run(f("jar cMf base.zip manifest lib dex res ${assetsdir} resources.pb"))
os.rm("../app.aab")
os.run(f([[
java -jar ${bundle_tool} build-bundle 
--modules=base.zip --output=../app.aab
]]))

os.cd("..")

if not os.exists(data.key_store) then
os.run(f([[
keytool -genkey -v 
-keystore "${key_store}" 
-alias ${key_alias} 
-keyalg RSA -keysize 2048 -validity 10000 
-storepass "${key_store_pass}" 
-keypass "${key_pass}" 
-dname "CN=John Doe, OU=Mobile Development, O=My Company, L=New York, ST=NY, C=US" -noprompt
]]))

end

os.run(f([[
jarsigner -keystore ${key_store} 
-storepass ${key_store_pass} -keypass ${key_pass} 
app.aab ${key_alias}
]]))

os.run(f([[
zipalign -f 4 build/apk-unaligned.apk build/apk-unsigned.apk
]]))

os.run(f([[
apksigner sign 
--ks ${key_store} 
--ks-pass pass:${key_store_pass} --key-pass pass:${key_pass} 
--out app.apk build/apk-unsigned.apk
]]))

-- cleanup
for _, thing in ipairs({"src", "build", ".xmake"}) do
	os.rm(thing)
end

end

main()

os.cd(data.begindir)

end)

