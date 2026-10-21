local ffi = require("ffi") 
local cjson = require("cjson")
local env = require("android.jnienv")
local envu = require("android.jnienv-util")
local activity = require("android.jni-raw").activity
local socket = require("socket")
local UDP = assert(socket.udp())

local jarSrc = getWorkingDirectory() .. "/lib/webviews/WebViews.jar"

local function wvFileSize(p)
    local f = io.open(p, "rb")
    if not f then return nil end
    local n = f:seek("end")
    f:close()
    return n
end

local function wvPrepareJar(src)
    local pkg = getWorkingDirectory():match("/Android/media/([^/]+)/")
    if not pkg then return nil end
    local f = io.open(src, "rb")
    if not f then return nil end
    local data = f:read("*a")
    f:close()
    pcall(ffi.cdef, "int chmod(const char *path, unsigned int mode);")
    for _, dir in ipairs({ "/data/user/0/" .. pkg .. "/code_cache", "/data/user/0/" .. pkg .. "/cache", "/data/user/0/" .. pkg .. "/files" }) do
        local dst = dir .. "/WebViews.jar"
        os.remove(dst)
        local out = io.open(dst, "wb")
        if out then
            out:write(data)
            out:close()
            local ok, r = pcall(function() return ffi.C.chmod(dst, 292) end) -- 0444 = read-only
            if ok and r == 0 then return dst end
        end
    end
    return nil
end

local privJar = wvPrepareJar(jarSrc)
local code, class, cldr
local firstErr
if privJar then
    code, class, cldr = envu.InjectJar(privJar, "WebViews/Main", "init", "(Landroid/app/Activity;)V", activity)
    if type(class) == "string" then firstErr = class end
end
if not privJar or firstErr then
    code, class, cldr = envu.InjectJar(jarSrc, "WebViews/Main", "init", "(Landroid/app/Activity;)V", activity)
    if type(class) == "string" then
        error(string.format("WebViews: InjectJar gagal (%s) | src=%s size=%s | private=%s | err_private=%s",
            tostring(class), jarSrc, tostring(wvFileSize(jarSrc)), tostring(privJar), tostring(firstErr)), 0)
    end
end
print("[WebViews] jar loaded dari: " .. tostring((not firstErr and privJar) or jarSrc))
envu.LooperPrepare()
local webviews = {
    cldr = ffi.cast('jclass', env.NewGlobalRef(cldr))
}
env.DeleteLocalRef(cldr)

function toboolean(num) return num > 0 end

local async = {}
function webviews.setClickableAsync(id, bool) if bool then table.insert(async, id) else for i, value in ipairs(async) do if value == id then table.remove(async, i) end end end end
function webviews.createBrowserFromFile(id, file) envu.CallStaticVoidMethod(class, "createBrowserFromFile", "(ILjava/lang/String;)V", ffi.cast("jint", id), env.NewStringUTF(file)) end
function webviews.createBrowser(id, url) envu.CallStaticVoidMethod(class, "createBrowser", "(ILjava/lang/String;)V", ffi.cast("jint", id), env.NewStringUTF(url)) end
function webviews.executeJS(id, msg) envu.CallStaticVoidMethod(class, "executeJS", "(ILjava/lang/String;)V", ffi.cast("jint", id), env.NewStringUTF(msg)) end
function webviews.changeUrl(id, url) envu.CallStaticVoidMethod(class, "changeUrl", "(ILjava/lang/String;)V", ffi.cast("jint", id), env.NewStringUTF(url)) end
function webviews.setClickable(id, bool) envu.CallStaticVoidMethod(class, "setClickable", "(IZ)V", ffi.cast("jint", id), bool) end
function webviews.setVisible(id, bool) envu.CallStaticVoidMethod(class, "setVisible", "(IZ)V", ffi.cast("jint", id), bool) end
function webviews.setPos(id, x, y) envu.CallStaticVoidMethod(class, "resizeBrowser", "(IZII)V", ffi.cast("jint", id), true, ffi.cast("jint", x), ffi.cast("jint", y)) end
function webviews.setSize(id, x, y) envu.CallStaticVoidMethod(class, "resizeBrowser", "(IZII)V", ffi.cast("jint", id), false, ffi.cast("jint", x), ffi.cast("jint", y)) end
function webviews.deleteBrowser(id) envu.CallStaticVoidMethod(class, "deleteBrowser", "(I)V", ffi.cast("jint", id)) end
function webviews.showCloseButton(id, bool) envu.CallStaticVoidMethod(class, "showCloseButton", "(IZ)V", ffi.cast("jint", id), bool) end
function webviews.setSetting(id, name, bool) envu.CallStaticVoidMethod(class, "setSetting", "(ILjava/lang/String;Z)V", ffi.cast("jint", id), env.NewStringUTF(name), bool) end
function webviews.addLog(log) envu.CallStaticVoidMethod(class, "addLog", "(Ljava/lang/String;)V", env.NewStringUTF(log)) end 
function webviews.sendClick(id, type, clickid, x, y) envu.CallStaticVoidMethod(class, "sendClick", "(IIIII)V", ffi.cast("jint", id), ffi.cast("jint", type), ffi.cast("jint", clickid), ffi.cast("jint", x), ffi.cast("jint", y)) end 
function webviews.resetPort() return envu.CallStaticIntMethod(class, "resetUDPPort", "()I") end
function webviews.getPort() return envu.CallStaticIntMethod(class, "getUDPPort", "()I") end
function webviews.canGoForward(id) return toboolean(envu.CallStaticBooleanMethod(class, "goPage", "(IZZ)Z", ffi.cast("jint", id), true, true)) end
function webviews.canGoBack(id) return toboolean(envu.CallStaticBooleanMethod(class, "goPage", "(IZZ)Z", ffi.cast("jint", id), false, true)) end
function webviews.goForward(id) return toboolean(envu.CallStaticBooleanMethod(class, "goPage", "(IZZ)Z", ffi.cast("jint", id), true, false)) end
function webviews.goBack(id) return toboolean(envu.CallStaticBooleanMethod(class, "goPage", "(IZZ)Z", ffi.cast("jint", id), false, false)) end
function webviews.getJSValue(id, msg) return envu.FromJString(envu.CallStaticObjectMethod(class, "getJSValue", "(ILjava/lang/String;)Ljava/lang/String;", ffi.cast("jint", id), env.NewStringUTF(msg))) end
function webviews.getStatus(id) return toboolean(envu.CallStaticBooleanMethod(class, "getStatus", "(I)Z", ffi.cast("jint", id))) end
function webviews.getVersion() return cjson.decode(envu.FromJString(envu.CallStaticObjectMethod(class, "getVersion", "()Ljava/lang/String;"))) end
function webviews.getBrowsers() return cjson.decode(envu.FromJString(envu.CallStaticObjectMethod(class, "getBrowsers", "()Ljava/lang/String;"))) end
function webviews.getScreen(id) return envu.FromJString(envu.CallStaticObjectMethod(class, "getScreen", "(I)Ljava/lang/String;", ffi.cast("jint", id))) end
function webviews.onAction(action) return action end
function webviews.restartCallback()
    if udpCallback ~= nil then udpCallback:terminate() end
	udpCallback = lua_thread.create(function()
	    webviews.resetPort()
		UDP:settimeout(0)
		wait(500)
		UDP:setpeername("127.0.0.1", webviews.getPort())
		wait(500)
		UDP:send('CONNECT')
		while true do
		    wait(0)
		    local data = UDP:receive()
		    if data ~= nil then
		      local success, data = pcall(cjson.decode, data) 
		      if success then webviews.onAction(data) end
		    end
		end 
	end)
end


function onTouch(type, id, x, y)
	for i, value in ipairs(async) do
	    webviews.sendClick(value, type, id, x, y)
	end
end

local udpCallback = lua_thread.create(function()
	UDP:settimeout(0)
	wait(500)
	UDP:setpeername("127.0.0.1", webviews.getPort())
	wait(500)
	UDP:send('CONNECT')
	while true do
	    wait(0)
	    local data = UDP:receive()
	    if data ~= nil then
	      local success, data = pcall(cjson.decode, data) 
		  if success then webviews.onAction(data) 
		  else print("failed to decode: ", data) end
	    end
	end 
end)

return webviews