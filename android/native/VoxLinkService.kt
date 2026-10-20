package com.voxlink.app

import android.Manifest
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.content.pm.ServiceInfo
import android.media.AudioFormat
import android.media.AudioRecord
import android.media.MediaRecorder
import android.media.audiofx.AcousticEchoCanceler
import android.net.wifi.WifiManager
import android.os.Build
import android.os.IBinder
import android.os.PowerManager
import androidx.core.app.NotificationCompat
import androidx.core.content.ContextCompat
import java.io.BufferedOutputStream
import java.io.DataOutputStream
import java.net.InetSocketAddress
import java.net.Socket
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.util.concurrent.atomic.AtomicBoolean

class VoxLinkService : Service() {
    companion object {
        private const val RATE = 48000
        private const val FRAME_SAMPLES = 1024
        private const val FRAME_BYTES = FRAME_SAMPLES * 2
        private const val AUDIO_PORT = 27184

        @Volatile var running = false
        @Volatile var connected = false
        @Volatile var serverIp = ""
        @Volatile var lastError = ""
        @Volatile var framesSent = 0L
        @Volatile var aecStatus = "未启动"

        fun snapshot(ctx: Context): Map<String, Any> {
            val saved = ctx.getSharedPreferences("voxlink", Context.MODE_PRIVATE).getString("serverIp", "").orEmpty()
            return mapOf(
                "running" to running,
                "connected" to connected,
                "serverIp" to if (serverIp.isNotEmpty()) serverIp else saved,
                "lastError" to lastError,
                "framesSent" to framesSent,
                "echoCancellation" to ctx.getSharedPreferences("voxlink", Context.MODE_PRIVATE).getBoolean("echoCancellation", true),
                "aecStatus" to aecStatus
            )
        }
    }

    private val alive = AtomicBoolean(false)
    private var worker: Thread? = null
    private var wakeLock: PowerManager.WakeLock? = null
    private var wifiLock: WifiManager.WifiLock? = null
    private var recorder: AudioRecord? = null
    private var echoCanceler: AcousticEchoCanceler? = null
    private var useEchoCancellation = true
    private var socket: Socket? = null
    private var output: DataOutputStream? = null

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        createNotificationChannel()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        serverIp = intent?.getStringExtra("serverIp") ?: getSharedPreferences("voxlink", MODE_PRIVATE).getString("serverIp", "").orEmpty()
        getSharedPreferences("voxlink", MODE_PRIVATE).edit().putString("serverIp", serverIp).apply()

        if (ContextCompat.checkSelfPermission(this, Manifest.permission.RECORD_AUDIO) != PackageManager.PERMISSION_GRANTED) {
            lastError = "没有麦克风权限"
            stopSelf()
            return START_NOT_STICKY
        }

        val notification = buildNotification("无线麦克风正在运行")
        if (Build.VERSION.SDK_INT >= 29) {
            startForeground(1001, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_MICROPHONE)
        } else {
            startForeground(1001, notification)
        }

        if (alive.compareAndSet(false, true)) {
            useEchoCancellation = getSharedPreferences("voxlink", MODE_PRIVATE).getBoolean("echoCancellation", true)
            aecStatus = "正在初始化"
            running = true
            connected = false
            framesSent = 0L
            lastError = ""
            acquireLocks()
            worker = Thread({ audioLoop() }, "VoxLinkAudio").also { it.start() }
        }
        return START_STICKY
    }

    private fun acquireLocks() {
        try {
            val pm = getSystemService(POWER_SERVICE) as PowerManager
            wakeLock = pm.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "VoxLink:Microphone").apply { acquire() }
        } catch (_: Exception) {}
        try {
            val wm = applicationContext.getSystemService(WIFI_SERVICE) as WifiManager
            val mode = if (Build.VERSION.SDK_INT >= 29) WifiManager.WIFI_MODE_FULL_LOW_LATENCY else WifiManager.WIFI_MODE_FULL_HIGH_PERF
            wifiLock = wm.createWifiLock(mode, "VoxLink:WiFi").apply { acquire() }
        } catch (_: Exception) {}
    }

    private fun createRecorder(): AudioRecord {
        val min = AudioRecord.getMinBufferSize(RATE, AudioFormat.CHANNEL_IN_MONO, AudioFormat.ENCODING_PCM_16BIT)
        val bufferBytes = maxOf(min * 2, FRAME_BYTES * 6)
        val source = if (useEchoCancellation) MediaRecorder.AudioSource.VOICE_COMMUNICATION else MediaRecorder.AudioSource.VOICE_RECOGNITION
        return if (Build.VERSION.SDK_INT >= 23) {
            AudioRecord.Builder()
                .setAudioSource(source)
                .setAudioFormat(
                    AudioFormat.Builder()
                        .setEncoding(AudioFormat.ENCODING_PCM_16BIT)
                        .setSampleRate(RATE)
                        .setChannelMask(AudioFormat.CHANNEL_IN_MONO)
                        .build()
                )
                .setBufferSizeInBytes(bufferBytes)
                .build()
        } else {
            @Suppress("DEPRECATION")
            AudioRecord(source, RATE, AudioFormat.CHANNEL_IN_MONO, AudioFormat.ENCODING_PCM_16BIT, bufferBytes)
        }
    }

    private fun configureEchoCancellation(record: AudioRecord) {
        if (!useEchoCancellation) {
            aecStatus = "原始模式（未请求回声消除）"
            return
        }
        try {
            if (!AcousticEchoCanceler.isAvailable()) {
                aecStatus = "通话模式：设备未提供独立回声消除接口"
                return
            }
            val effect = AcousticEchoCanceler.create(record.audioSessionId)
            echoCanceler = effect
            if (effect == null) {
                aecStatus = "通话模式：回声消除创建失败"
                return
            }
            val result = effect.setEnabled(true)
            aecStatus = if (result == 0 && effect.enabled) "通话模式：系统回声消除已启用" else "通话模式：系统回声消除未能启用"
        } catch (e: Exception) {
            aecStatus = "通话模式：回声消除不可用（${e.javaClass.simpleName}）"
        }
    }

    private fun audioLoop() {
        try {
            recorder = createRecorder()
            if (recorder?.state != AudioRecord.STATE_INITIALIZED) {
                lastError = "麦克风初始化失败"
                return
            }
            configureEchoCancellation(recorder!!)
            recorder!!.startRecording()
            val samples = ShortArray(FRAME_SAMPLES)
            val packet = ByteBuffer.allocate(FRAME_BYTES).order(ByteOrder.LITTLE_ENDIAN)

            while (alive.get()) {
                if (!ensureSocket()) {
                    Thread.sleep(400)
                    continue
                }

                var offset = 0
                var failed = false
                while (offset < FRAME_SAMPLES && alive.get()) {
                    val n = if (Build.VERSION.SDK_INT >= 23) {
                        recorder!!.read(samples, offset, FRAME_SAMPLES - offset, AudioRecord.READ_BLOCKING)
                    } else {
                        recorder!!.read(samples, offset, FRAME_SAMPLES - offset)
                    }
                    if (n <= 0) {
                        failed = true
                        lastError = "麦克风读取失败：$n"
                        break
                    }
                    offset += n
                }
                if (failed || offset != FRAME_SAMPLES) continue

                packet.clear()
                for (s in samples) packet.putShort(s)

                try {
                    val out = output ?: throw IllegalStateException("no stream")
                    out.writeInt(FRAME_BYTES)
                    out.write(packet.array())
                    out.flush()
                    connected = true
                    lastError = ""
                    framesSent++
                } catch (e: Exception) {
                    connected = false
                    lastError = e.message ?: "连接中断"
                    closeSocket()
                }
            }
        } catch (e: Exception) {
            lastError = e.message ?: e.javaClass.simpleName
        } finally {
            connected = false
            try { recorder?.stop() } catch (_: Exception) {}
            try { echoCanceler?.release() } catch (_: Exception) {}
            echoCanceler = null
            try { recorder?.release() } catch (_: Exception) {}
            recorder = null
            closeSocket()
        }
    }

    private fun ensureSocket(): Boolean {
        val current = socket
        if (current != null && current.isConnected && !current.isClosed && output != null) return true
        closeSocket()
        if (serverIp.isBlank()) {
            lastError = "电脑 IP 为空"
            return false
        }
        return try {
            val s = Socket()
            s.tcpNoDelay = true
            s.keepAlive = true
            s.sendBufferSize = 32 * 1024
            s.connect(InetSocketAddress(serverIp, AUDIO_PORT), 1300)
            socket = s
            output = DataOutputStream(BufferedOutputStream(s.getOutputStream(), 16 * 1024))
            connected = true
            lastError = ""
            true
        } catch (e: Exception) {
            connected = false
            lastError = e.message ?: "连接失败"
            closeSocket()
            false
        }
    }

    private fun closeSocket() {
        try { output?.flush() } catch (_: Exception) {}
        try { output?.close() } catch (_: Exception) {}
        try { socket?.close() } catch (_: Exception) {}
        output = null
        socket = null
    }

    override fun onDestroy() {
        alive.set(false)
        running = false
        connected = false
        closeSocket()
        try { worker?.join(1000) } catch (_: Exception) {}
        try { wakeLock?.let { if (it.isHeld) it.release() } } catch (_: Exception) {}
        try { wifiLock?.let { if (it.isHeld) it.release() } } catch (_: Exception) {}
        if (Build.VERSION.SDK_INT >= 24) {
            stopForeground(STOP_FOREGROUND_REMOVE)
        } else {
            @Suppress("DEPRECATION")
            stopForeground(true)
        }
        super.onDestroy()
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= 26) {
            val ch = NotificationChannel("voxlink_mic", "VoxLink 麦克风", NotificationManager.IMPORTANCE_LOW)
            (getSystemService(NOTIFICATION_SERVICE) as NotificationManager).createNotificationChannel(ch)
        }
    }

    private fun buildNotification(text: String): Notification {
        val openIntent = packageManager.getLaunchIntentForPackage(packageName) ?: Intent(this, MainActivity::class.java)
        val pending = PendingIntent.getActivity(this, 0, openIntent, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        return NotificationCompat.Builder(this, "voxlink_mic")
            .setSmallIcon(android.R.drawable.ic_btn_speak_now)
            .setContentTitle("VoxLink")
            .setContentText(text)
            .setContentIntent(pending)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .build()
    }
}
