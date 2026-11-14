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
import java.io.BufferedWriter
import java.io.IOException
import java.io.InputStreamReader
import java.io.OutputStreamWriter
import java.util.UUID

import android.bluetooth.BluetoothDevice
import android.content.BroadcastReceiver
import android.content.Intent
import android.content.IntentFilter
import android.app.Activity

class MainActivity : FlutterActivity() {
    private val methodChannelName = "multihop/bluetooth"
    private val eventChannelName = "multihop/bluetooth_events"
    private val permissionRequestCode = 1001
    private val serviceName = "MultiHopMessenger"
    private val serviceUUID = UUID.fromString("8b32a43c-7a5f-4a52-9a5e-6b80cde41f21")

    private val discoveredDevices = mutableMapOf<String, Map<String, String>>()
    private var discoveryReceiverRegistered = false

    private data class PeerConnection(
        val socket: BluetoothSocket,
        val writer: BufferedWriter
    )

    private val lock = Any()
    private val peers = mutableMapOf<String, PeerConnection>()
    private val connectingAddresses = mutableSetOf<String>()
    private var serverSocket: BluetoothServerSocket? = null
    @Volatile private var serverRunning = false
    @Volatile private var eventSink: EventChannel.EventSink? = null
    @Volatile private var connectionStatus = "Disconnected"


    private val discoveryReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context, intent: Intent) {
            when (intent.action) {
                BluetoothDevice.ACTION_FOUND -> {
                    if (!hasConnectPermission()) return

                    val device = if (Build.VERSION.SDK_INT >= 33) {
                        intent.getParcelableExtra(
                            BluetoothDevice.EXTRA_DEVICE,
                            BluetoothDevice::class.java
                        )
                    } else {
                        @Suppress("DEPRECATION")
                        intent.getParcelableExtra<BluetoothDevice>(
                            BluetoothDevice.EXTRA_DEVICE
                        )
                    } ?: return

                    val address = device.address
                    val name = device.name ?: "Unknown device"

                    val info = mapOf(
                        "name" to name,
                        "address" to address
                    )

                    discoveredDevices[address] = info

                    runOnUiThread {
                        eventSink?.success(
                            mapOf(
                                "type" to "deviceFound",
                                "value" to info
                            )
                        )
                    }
                }

                BluetoothAdapter.ACTION_DISCOVERY_FINISHED -> {
                    sendEvent("discoveryFinished", "Discovery finished")
                }
            }
        }
    }

    private fun startDiscovery(): String {
        if (!hasScanPermission() || !hasConnectPermission()) {
            return "Bluetooth permissions required"
        }

        val adapter = bluetoothAdapter
            ?: return "Bluetooth not supported"

        if (!adapter.isEnabled) {
            return "Bluetooth is OFF"
        }

        if (!discoveryReceiverRegistered) {
            val filter = IntentFilter().apply {
                addAction(BluetoothDevice.ACTION_FOUND)
                addAction(BluetoothAdapter.ACTION_DISCOVERY_FINISHED)
            }

            if (Build.VERSION.SDK_INT >= 33) {
                registerReceiver(
                    discoveryReceiver,
                    filter,
                    Context.RECEIVER_EXPORTED
                )
            } else {
                registerReceiver(discoveryReceiver, filter)
            }

            discoveryReceiverRegistered = true
        }

        discoveredDevices.clear()

        if (adapter.isDiscovering) {
            adapter.cancelDiscovery()
        }

        return if (adapter.startDiscovery()) {
            "Discovery started"
        } else {
            "Failed to start discovery"
        }
    }

    private fun requestDiscoverable(): String {
        if (!hasConnectPermission()) {
            return "Bluetooth connect permission required"
        }

        val adapter = bluetoothAdapter
            ?: return "Bluetooth not supported"

        if (!adapter.isEnabled) {
            return "Bluetooth is OFF"
        }

        val intent = Intent(
            BluetoothAdapter.ACTION_REQUEST_DISCOVERABLE
        ).apply {
            putExtra(
                BluetoothAdapter.EXTRA_DISCOVERABLE_DURATION,
                300
            )
        }

        return try {
            startActivity(intent)
            "Discoverability request started"
        } catch (e: Exception) {
            "Discoverability request failed: ${e.message}"
        }
    }
        


    private fun stopDiscovery(): String {
        if (!hasScanPermission()) {
            return "Bluetooth scan permission required"
        }

        val adapter = bluetoothAdapter
            ?: return "Bluetooth not supported"

        if (adapter.isDiscovering) {
            adapter.cancelDiscovery()
        }

        return "Discovery stopped"
    }

    private val bluetoothAdapter: BluetoothAdapter?
        get() = (getSystemService(Context.BLUETOOTH_SERVICE) as BluetoothManager).adapter

    private fun hasConnectPermission() = Build.VERSION.SDK_INT < 31 ||
        checkSelfPermission(Manifest.permission.BLUETOOTH_CONNECT) == PackageManager.PERMISSION_GRANTED

    private fun hasScanPermission() = Build.VERSION.SDK_INT < 31 ||
        checkSelfPermission(Manifest.permission.BLUETOOTH_SCAN) == PackageManager.PERMISSION_GRANTED

    private fun requestBluetoothPermission() {
        if (Build.VERSION.SDK_INT >= 31) {
            requestPermissions(
                arrayOf(Manifest.permission.BLUETOOTH_CONNECT, Manifest.permission.BLUETOOTH_SCAN, Manifest.permission.BLUETOOTH_ADVERTISE),
                permissionRequestCode
            )
        }
    }

    private fun sendEvent(type: String, value: String, address: String? = null) {
        runOnUiThread {
            val event = mutableMapOf<String, String>("type" to type, "value" to value)
            if (address != null) event["address"] = address
            eventSink?.success(event)
        }
    }

    private fun refreshStatus() {
        val count = synchronized(lock) { peers.size }
        connectionStatus = if (count > 0) "Connected ($count)" else if (serverRunning) "Waiting for connection..." else "Disconnected"
        sendEvent("status", connectionStatus)
        sendEvent("peersChanged", count.toString())
    }

    private fun closeServerSocket() {
        serverRunning = false
        val socket = synchronized(lock) {
            val old = serverSocket
            serverSocket = null
            old
        }
        try { socket?.close() } catch (_: IOException) { }
    }

    private fun closePeer(address: String, expected: BluetoothSocket? = null) {
        val peer = synchronized(lock) {
            val current = peers[address]
            if (current == null || (expected != null && current.socket !== expected)) null
            else peers.remove(address)
        } ?: return
        try { peer.socket.close() } catch (_: IOException) { }
        sendEvent("peerDisconnected", address, address)
        refreshStatus()
    }

    private fun registerPeer(socket: BluetoothSocket) {
        if (!hasConnectPermission()) {
            try { socket.close() } catch (_: IOException) { }
            return
        }
        val address = socket.remoteDevice.address
        val writer = try {
            BufferedWriter(OutputStreamWriter(socket.outputStream, Charsets.UTF_8))
        } catch (_: IOException) {
            try { socket.close() } catch (_: IOException) { }
            return
        }
        val inserted = synchronized(lock) {
            if (peers.containsKey(address)) false
            else {
                peers[address] = PeerConnection(socket, writer)
                true
            }
        }
        if (!inserted) {
            try { socket.close() } catch (_: IOException) { }
            return
        }
        sendEvent("peerConnected", address, address)
        refreshStatus()
        Thread {
            try {
                val reader = BufferedReader(InputStreamReader(socket.inputStream, Charsets.UTF_8))
                while (true) {
                    val line = reader.readLine() ?: break
                    sendEvent("message", line, address)
                }
            } catch (_: IOException) {
                // Remote device disconnected.
            } finally {
                closePeer(address, socket)
            }
        }.start()
    }

    private fun startBluetoothServer(): String {
        if (!hasConnectPermission()) return "Bluetooth permission required"
        val adapter = bluetoothAdapter ?: return "Bluetooth not supported"
        if (!adapter.isEnabled) return "Bluetooth is OFF"
        if (serverRunning) return "Server is already running"
        return try {
            val listener = adapter.listenUsingRfcommWithServiceRecord(serviceName, serviceUUID)
            synchronized(lock) { serverSocket = listener }
            serverRunning = true
            refreshStatus()
            Thread {
                try {
                    while (serverRunning) {
                        val incoming = listener.accept()
                        if (serverRunning) registerPeer(incoming)
                        else try { incoming.close() } catch (_: IOException) { }
                    }
                } catch (e: IOException) {
                    if (serverRunning) sendEvent("error", "Server error: ${e.message}")
                } finally {
                    // Do not close a newer listener from an older server thread.
                    synchronized(lock) {
                        if (serverSocket === listener) {
                            serverSocket = null
                            serverRunning = false
                        }
                    }
                    try { listener.close() } catch (_: IOException) { }
                    refreshStatus()
                }
            }.start()
            "Waiting for connection..."
        } catch (e: Exception) {
            sendEvent("error", "Server error: ${e.message}")
            "Server error: ${e.message}"
        }
    }

    private fun getPairedDevices(): List<Map<String, String>> {
        if (!hasConnectPermission()) throw SecurityException("Bluetooth permission required")
        val adapter = bluetoothAdapter ?: throw IllegalStateException("Bluetooth not supported")
        if (!adapter.isEnabled) throw IllegalStateException("Bluetooth is OFF")
        return adapter.bondedDevices.map { device ->
            mapOf("name" to (device.name ?: "Unknown device"), "address" to device.address)
        }.sortedBy { it["name"] }
    }

    private fun connectToDevice(address: String): String {
        if (!hasConnectPermission()) return "Bluetooth permission required"
        val adapter = bluetoothAdapter ?: return "Bluetooth not supported"
        if (!adapter.isEnabled) return "Bluetooth is OFF"
        if (!BluetoothAdapter.checkBluetoothAddress(address)) return "Invalid Bluetooth address"
        synchronized(lock) {
            if (peers.containsKey(address)) return "Already connected"
            if (!connectingAddresses.add(address)) return "Already connecting"
        }
        Thread {
            var socket: BluetoothSocket? = null
            try {
                val device = adapter.getRemoteDevice(address)
                socket = device.createRfcommSocketToServiceRecord(serviceUUID)
                if (hasScanPermission()) adapter.cancelDiscovery()
                socket.connect()
                registerPeer(socket)
                socket = null // Ownership transferred to registerPeer.
            } catch (e: Exception) {
                sendEvent("error", "Connection failed ($address): ${e.message}", address)
            } finally {
                try { socket?.close() } catch (_: IOException) { }
                synchronized(lock) { connectingAddresses.remove(address) }
            }
        }.start()
        return "Connecting..."
    }

    private fun sendMessageToDevice(address: String, message: String): String {
        if (message.isBlank()) return "Message is empty"
        if (message.contains('\n') || message.contains('\r')) return "Multiline messages are not supported yet"
        val peer = synchronized(lock) { peers[address] } ?: return "Not connected: $address"
        return try {
            synchronized(peer.writer) {
                peer.writer.write(message)
                peer.writer.newLine()
                peer.writer.flush()
            }
            "Message sent"
        } catch (e: IOException) {
            closePeer(address, peer.socket)
            "Send failed: ${e.message}"
        }
    }

    private fun sendMessage(message: String): String {
        val addresses = synchronized(lock) { peers.keys.toList() }
        return when (addresses.size) {
            0 -> "Not connected"
            1 -> sendMessageToDevice(addresses.first(), message)
            else -> "Multiple devices connected; use sendMessageToDevice"
        }
    }

    private fun getConnectedDevices(): List<Map<String, String>> = synchronized(lock) {
        peers.keys.map { address -> mapOf("address" to address) }
    }

    private fun disconnect(): String {
        closeServerSocket()
        val addresses = synchronized(lock) { peers.keys.toList() }
        addresses.forEach { closePeer(it) }
        refreshStatus()
        return "Disconnected"
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, eventChannelName)
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    eventSink = events
                    refreshStatus()
                }
                override fun onCancel(arguments: Any?) { eventSink = null }
            })

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, methodChannelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "startDiscovery" -> {
                        result.success(startDiscovery())
                    }
                    "requestDiscoverable" -> {
                        result.success(requestDiscoverable())
                    }
                    "stopDiscovery" -> {
                        result.success(stopDiscovery())
                    }
                    "getDiscoveredDevices" -> {
                        result.success(discoveredDevices.values.toList())
                    }
                    "checkBluetooth" -> {
                        val adapter = bluetoothAdapter
                        result.success(when {
                            adapter == null -> "Bluetooth not supported"
                            !hasConnectPermission() -> "Bluetooth permission required"
                            adapter.isEnabled -> "Bluetooth is ON"
                            else -> "Bluetooth is OFF"
                        })
                    }
                    "requestBluetoothPermission" -> {
                        requestBluetoothPermission()
                        result.success("Permission request started")
                    }
                    "startServer" -> result.success(startBluetoothServer())
                    "stopServer" -> {
                        closeServerSocket()
                        refreshStatus()
                        result.success("Server stopped")
                    }
                    "getPairedDevices" -> try {
                        result.success(getPairedDevices())
                    } catch (e: Exception) {
                        result.error("BLUETOOTH_ERROR", e.message, null)
                    }
                    "connectToDevice" -> {
                        val address = call.argument<String>("address")
                        if (address.isNullOrBlank()) result.error("INVALID_ADDRESS", "Device address is missing", null)
                        else result.success(connectToDevice(address))
                    }
                    "getConnectionStatus" -> result.success(connectionStatus)
                    "getConnectedDevices" -> result.success(getConnectedDevices())
                    "sendMessage" -> {
                        val message = call.argument<String>("message") ?: ""
                        Thread {
                            val response = sendMessage(message)
                            runOnUiThread { result.success(response) }
                        }.start()
                    }
                    "sendMessageToDevice" -> {
                        val address = call.argument<String>("address")
                        val message = call.argument<String>("message") ?: ""
                        if (address.isNullOrBlank()) result.error("INVALID_ADDRESS", "Device address is missing", null)
                        else Thread {
                            val response = sendMessageToDevice(address, message)
                            runOnUiThread { result.success(response) }
                        }.start()
                    }
                    "disconnectDevice" -> {
                        val address = call.argument<String>("address")
                        if (address.isNullOrBlank()) result.error("INVALID_ADDRESS", "Device address is missing", null)
                        else {
                            closePeer(address)
                            result.success("Disconnected: $address")
                        }
                    }
                    "disconnect" -> result.success(disconnect())
                    else -> result.notImplemented()
                }
            }
    }

    override fun onDestroy() {
        disconnect()
        eventSink = null
        if (discoveryReceiverRegistered) {
            unregisterReceiver(discoveryReceiver)
            discoveryReceiverRegistered = false
        }
        super.onDestroy()
    }
}
