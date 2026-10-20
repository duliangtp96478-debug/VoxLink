package com.voxlink.app

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import org.json.JSONObject
import java.net.DatagramPacket
import java.net.DatagramSocket
import java.net.InetAddress
import java.net.NetworkInterface

class MainActivity : FlutterActivity() {
    private val channelName = "voxlink/native"
    private var pendingMicResult: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "requestMic" -> requestMic(result)
                    "start" -> {
                        val ip = call.argument<String>("ip")?.trim().orEmpty()
                        if (ip.isEmpty()) {
                            result.error("BAD_IP", "电脑 IP 不能为空", null)
                            return@setMethodCallHandler
                        }
                        if (ContextCompat.checkSelfPermission(this, Manifest.permission.RECORD_AUDIO) != PackageManager.PERMISSION_GRANTED) {
                            result.error("NO_MIC", "没有麦克风权限", null)
                            return@setMethodCallHandler
                        }
                        getSharedPreferences("voxlink", MODE_PRIVATE).edit().putString("serverIp", ip).apply()
                        val intent = Intent(this, VoxLinkService::class.java).putExtra("serverIp", ip)
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) startForegroundService(intent) else startService(intent)
                        requestNotificationPermissionIfNeeded()
                        result.success(true)
                    }
                    "stop" -> {
                        stopService(Intent(this, VoxLinkService::class.java))
                        result.success(true)
                    }
                    "setEchoCancellation" -> {
                        if (VoxLinkService.running) {
                            result.error("BUSY", "请先停止麦克风再切换模式", null)
                        } else {
                            val enabled = call.argument<Boolean>("enabled") ?: true
                            getSharedPreferences("voxlink", MODE_PRIVATE).edit().putBoolean("echoCancellation", enabled).apply()
                            result.success(true)
                        }
                    }
                    "getState" -> result.success(VoxLinkService.snapshot(this))
                    "discover" -> Thread {
                        val found = discoverPc()
                        runOnUiThread { result.success(found) }
                    }.start()
                    else -> result.notImplemented()
                }
            }
    }

    private fun requestMic(result: MethodChannel.Result) {
        if (ContextCompat.checkSelfPermission(this, Manifest.permission.RECORD_AUDIO) == PackageManager.PERMISSION_GRANTED) {
            result.success(true)
            return
        }
        if (pendingMicResult != null) {
            result.success(false)
            return
        }
        pendingMicResult = result
        ActivityCompat.requestPermissions(this, arrayOf(Manifest.permission.RECORD_AUDIO), 2001)
    }

    private fun requestNotificationPermissionIfNeeded() {
        if (Build.VERSION.SDK_INT >= 33 && ContextCompat.checkSelfPermission(this, Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED) {
            ActivityCompat.requestPermissions(this, arrayOf(Manifest.permission.POST_NOTIFICATIONS), 2002)
        }
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == 2001) {
            val granted = grantResults.isNotEmpty() && grantResults[0] == PackageManager.PERMISSION_GRANTED
            pendingMicResult?.success(granted)
            pendingMicResult = null
        }
    }

    private fun discoverPc(): List<Map<String, Any>> {
        val found = mutableListOf<Map<String, Any>>()
        val seen = mutableSetOf<String>()
        var socket: DatagramSocket? = null
        try {
            socket = DatagramSocket()
            socket.broadcast = true
            socket.soTimeout = 220
            val payload = "VOXLINK_DISCOVER_V1".toByteArray()
            val targets = mutableSetOf<InetAddress>()
            targets.add(InetAddress.getByName("255.255.255.255"))
            try {
                val interfaces = NetworkInterface.getNetworkInterfaces()
                while (interfaces.hasMoreElements()) {
                    val ni = interfaces.nextElement()
                    if (!ni.isUp || ni.isLoopback) continue
                    for (ia in ni.interfaceAddresses) ia.broadcast?.let { targets.add(it) }
                }
            } catch (_: Exception) {}

            for (address in targets) {
                try { socket.send(DatagramPacket(payload, payload.size, address, 27182)) } catch (_: Exception) {}
            }

            val end = System.currentTimeMillis() + 1100L
            while (System.currentTimeMillis() < end) {
                try {
                    val buf = ByteArray(2048)
                    val packet = DatagramPacket(buf, buf.size)
                    socket.receive(packet)
                    val ip = packet.address.hostAddress ?: continue
                    if (!seen.add(ip)) continue
                    val json = JSONObject(String(packet.data, 0, packet.length))
                    if (json.optString("app") != "VoxLink") continue
                    found.add(mapOf("ip" to ip, "name" to json.optString("name", ip)))
                } catch (_: Exception) {}
            }
        } catch (_: Exception) {
        } finally {
            try { socket?.close() } catch (_: Exception) {}
        }
        return found
    }
}
