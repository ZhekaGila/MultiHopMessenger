
package com.example.multihop_messenger

import android.Manifest
import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothManager
import android.bluetooth.BluetoothServerSocket
import android.bluetooth.BluetoothSocket
import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import java.io.BufferedReader
import java.io.IOException
import java.io.InputStreamReader
import java.io.OutputStreamWriter
import java.io.BufferedWriter
import java.util.UUID

class MainActivity : FlutterActivity() {

    private val methodChannelName = "multihop/bluetooth"
    private val eventChannelName = "multihop/bluetooth_events"
    private val permissionRequestCode = 1001

    private val serviceName = "MultiHopMessenger"
    private val serviceUUID = UUID.fromString(
        "8b32a43c-7a5f-4a52-9a5e-6b80cde41f21"
    )

    private val lock = Any()

    private var serverSocket: BluetoothServerSocket? = null
    private var connectionSocket: BluetoothSocket? = null
    private var serverThread: Thread? = null
    private var connectThread: Thread? = null
    private var readerThread: Thread? = null

    private var writer: BufferedWriter? = null
    private var eventSink: EventChannel.EventSink? = null

    @Volatile
    private var serverRunning = false

    @Volatile
    private var connecting = false

    @Volatile
    private var connectionStatus = "Disconnected"

    private val bluetoothAdapter: BluetoothAdapter?
        get() {
            val manager = getSystemService(
                Context.BLUETOOTH_SERVICE
            ) as BluetoothManager
            return manager.adapter
        }

    private fun hasConnectPermission(): Boolean {
        return Build.VERSION.SDK_INT < 31 ||
            checkSelfPermission(
                Manifest.permission.BLUETOOTH_CONNECT
            ) == PackageManager.PERMISSION_GRANTED
    }

    private fun hasScanPermission(): Boolean {
        return Build.VERSION.SDK_INT < 31 ||
            checkSelfPermission(
                Manifest.permission.BLUETOOTH_SCAN
            ) == PackageManager.PERMISSION_GRANTED
    }

    private fun requestBluetoothPermission() {
        if (Build.VERSION.SDK_INT >= 31) {
            requestPermissions(
                arrayOf(
                    Manifest.permission.BLUETOOTH_CONNECT,
                    Manifest.permission.BLUETOOTH_SCAN
                ),
                permissionRequestCode
            )
        }
    }

    private fun sendEvent(
        type: String,
        value: String
    ) {
        runOnUiThread {
            eventSink?.success(
                mapOf(
                    "type" to type,
                    "value" to value
                )
            )
        }
    }

    private fun updateStatus(value: String) {
        connectionStatus = value
        sendEvent("status", value)
    }

    private fun closeServerSocket() {
        serverRunning = false

        try {
            serverSocket?.close()
        } catch (_: IOException) {
        }

        serverSocket = null
    }

    private fun closeConnection(
        expectedSocket: BluetoothSocket? = null
    ) {
        synchronized(lock) {
            if (
                expectedSocket != null &&
                connectionSocket !== expectedSocket
            ) {
                return
            }

            val socket = connectionSocket
            connectionSocket = null
            writer = null

            try {
                socket?.close()
            } catch (_: IOException) {
            }
        }
    }

    private fun startBluetoothServer(): String {
        if (!hasConnectPermission()) {
            return "Bluetooth permission required"
        }

        val adapter = bluetoothAdapter
            ?: return "Bluetooth not supported"

        if (!adapter.isEnabled) {
            return "Bluetooth is OFF"
        }

        if (serverRunning) {
            return "Server is already running"
        }

        if (connectionSocket != null || connecting) {
            return "Connection already active"
        }

        return try {
            val socket = adapter.listenUsingRfcommWithServiceRecord(
                serviceName,
                serviceUUID
            )

            serverSocket = socket
            serverRunning = true
            updateStatus("Waiting for connection...")

            serverThread = Thread {
                try {
                    val acceptedSocket = socket.accept()

                    if (serverRunning) {
                        serverRunning = false
                        startMessageReader(acceptedSocket)
                    } else {
                        acceptedSocket.close()
                    }

                } catch (e: IOException) {
                    if (serverRunning) {
                        updateStatus("Server error: ${e.message}")
                    }

                } finally {
                    closeServerSocket()
                }
            }

            serverThread?.start()
            "Waiting for connection..."

        } catch (e: Exception) {
            serverRunning = false
            updateStatus("Server error: ${e.message}")
            connectionStatus
        }
    }

    private fun getPairedDevices(): List<Map<String, String>> {
        if (!hasConnectPermission()) {
            throw SecurityException("Bluetooth permission required")
        }

        val adapter = bluetoothAdapter
            ?: throw IllegalStateException("Bluetooth not supported")

        if (!adapter.isEnabled) {
            throw IllegalStateException("Bluetooth is OFF")
        }

        return adapter.bondedDevices.map { device ->
            mapOf(
                "name" to (device.name ?: "Unknown device"),
                "address" to device.address
            )
        }.sortedBy { it["name"] }
    }

    private fun connectToDevice(address: String): String {
        if (!hasConnectPermission()) {
            return "Bluetooth permission required"
        }

        val adapter = bluetoothAdapter
            ?: return "Bluetooth not supported"

        if (!adapter.isEnabled) {
            return "Bluetooth is OFF"
        }

        if (!BluetoothAdapter.checkBluetoothAddress(address)) {
            return "Invalid Bluetooth address"
        }

        if (connectionSocket != null || connecting) {
            return "Connection already active"
        }

        if (serverRunning) {
            return "Stop server before connecting"
        }

        connecting = true
        updateStatus("Connecting...")

        connectThread = Thread {
            var socket: BluetoothSocket? = null

            try {
                val device = adapter.getRemoteDevice(address)

                socket = device.createRfcommSocketToServiceRecord(
                    serviceUUID
                )

                if (hasScanPermission()) {
                    adapter.cancelDiscovery()
                }

                socket.connect()

                if (connecting) {
                    startMessageReader(socket)
                } else {
                    socket.close()
                }

            } catch (e: Exception) {
                try {
                    socket?.close()
                } catch (_: IOException) {
                }

                if (connecting) {
                    updateStatus("Connection failed: ${e.message}")
                }

            } finally {
                connecting = false
            }
        }

        connectThread?.start()
        return "Connecting..."
    }

    private fun startMessageReader(socket: BluetoothSocket) {
        synchronized(lock) {
            connectionSocket = socket
            writer = BufferedWriter(
                OutputStreamWriter(
                    socket.outputStream,
                    Charsets.UTF_8
                )
            )
        }

        updateStatus("Connected: ${socket.remoteDevice.address}")

        readerThread = Thread {
            try {
                val reader = BufferedReader(
                    InputStreamReader(
                        socket.inputStream,
                        Charsets.UTF_8
                    )
                )

                while (true) {
                    val message = reader.readLine() ?: break
                    sendEvent("message", message)
                }

            } catch (_: IOException) {
                // The connection was closed or interrupted.

            } finally {
                val wasCurrent = synchronized(lock) {
                    connectionSocket === socket
                }

                closeConnection(socket)

                if (wasCurrent) {
                    updateStatus("Disconnected")
                }
            }
        }

        readerThread?.start()
    }

    private fun sendMessage(message: String): String {
        if (message.isBlank()) {
            return "Message is empty"
        }

        if (message.contains('\n') || message.contains('\r')) {
            return "Multiline messages are not supported yet"
        }

        val socket = synchronized(lock) {
            connectionSocket
        } ?: return "Not connected"

        val currentWriter = synchronized(lock) {
            writer
        } ?: return "Not connected"

        return try {
            synchronized(currentWriter) {
                currentWriter.write(message)
                currentWriter.newLine()
                currentWriter.flush()
            }

            "Message sent"

        } catch (e: IOException) {
            closeConnection(socket)
            updateStatus("Disconnected: ${e.message}")
            "Send failed: ${e.message}"
        }
    }

    private fun disconnect(): String {
        connecting = false
        closeServerSocket()
        closeConnection()
        updateStatus("Disconnected")
        return "Disconnected"
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        EventChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            eventChannelName
        ).setStreamHandler(
            object : EventChannel.StreamHandler {
                override fun onListen(
                    arguments: Any?,
                    events: EventChannel.EventSink?
                ) {
                    eventSink = events
                    sendEvent("status", connectionStatus)
                }

                override fun onCancel(arguments: Any?) {
                    eventSink = null
                }
            }
        )

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            methodChannelName
        ).setMethodCallHandler { call, result ->

            when (call.method) {

                "checkBluetooth" -> {
                    val adapter = bluetoothAdapter

                    result.success(
                        when {
                            adapter == null ->
                                "Bluetooth not supported"

                            !hasConnectPermission() ->
                                "Bluetooth permission required"

                            adapter.isEnabled ->
                                "Bluetooth is ON"

                            else ->
                                "Bluetooth is OFF"
                        }
                    )
                }

                "requestBluetoothPermission" -> {
                    requestBluetoothPermission()
                    result.success("Permission request started")
                }

                "startServer" -> {
                    result.success(startBluetoothServer())
                }

                "stopServer" -> {
                    closeServerSocket()

                    if (connectionSocket == null) {
                        updateStatus("Server stopped")
                    }

                    result.success("Server stopped")
                }

                "getPairedDevices" -> {
                    try {
                        result.success(getPairedDevices())
                    } catch (e: Exception) {
                        result.error(
                            "BLUETOOTH_ERROR",
                            e.message,
                            null
                        )
                    }
                }

                "connectToDevice" -> {
                    val address = call.argument<String>("address")

                    if (address.isNullOrBlank()) {
                        result.error(
                            "INVALID_ADDRESS",
                            "Device address is missing",
                            null
                        )
                    } else {
                        result.success(connectToDevice(address))
                    }
                }

                "getConnectionStatus" -> {
                    result.success(connectionStatus)
                }

                "sendMessage" -> {
                    val message = call.argument<String>("message") ?: ""

                    Thread {
                        val response = sendMessage(message)
                        runOnUiThread {
                            result.success(response)
                        }
                    }.start()
                }

                "disconnect" -> {
                    result.success(disconnect())
                }

                else -> result.notImplemented()
            }
        }
    }

    override fun onDestroy() {
        disconnect()
        eventSink = null
        super.onDestroy()
    }
}
