
package com.example.multihop_messenger

import android.Manifest
import android.bluetooth.BluetoothManager
import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    private val channelName = "multihop/bluetooth"

    override fun configureFlutterEngine(
        flutterEngine: FlutterEngine
    ) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            channelName
        ).setMethodCallHandler { call, result ->

            when (call.method) {
                "testConnection" -> {
                    result.success("Hello from Kotlin!")
                }

                "checkBluetooth" -> {
                    val manager = getSystemService(
                        Context.BLUETOOTH_SERVICE
                    ) as BluetoothManager

                    val adapter = manager.adapter

                    if (adapter == null) {
                        result.success("Bluetooth not supported")
                    } else if (
                        Build.VERSION.SDK_INT >= 31 &&
                        checkSelfPermission(
                            Manifest.permission.BLUETOOTH_CONNECT
                        ) != PackageManager.PERMISSION_GRANTED
                    ) {
                        result.success("Bluetooth permission required")
                    } else {
                        result.success(
                            if (adapter.isEnabled)
                                "Bluetooth is ON"
                            else
                                "Bluetooth is OFF"
                        )
                    }
                }

                else -> result.notImplemented()
            }
        }
    }
}
