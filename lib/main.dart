import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

void main() {
  runApp(const MultiHopApp());
}

class MultiHopApp extends StatelessWidget{
  const MultiHopApp({super.key});

  @override
  Widget build(BuildContext context){
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'MultiHop Messenger',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.blue,
        ),
        useMaterial3:true,
      ),
      home: const HomeScreen(),
    );
  }
}

class HomeScreen extends StatefulWidget{
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>{
  static const channel = MethodChannel('multihop/bluetooth');

  String status = 'Waiting for action ...';

  Future<void> testKotlin() async{
    try{
      final result = await channel.invokeMethod<String>('testConnection');

      if (!mounted) return;

      setState(() {
        status = result ?? 'No response';
      });
    } on PlatformException catch (e){
      if (!mounted) return;
      setState(() {
        status = 'Error: ${e.message}';
      });
    } on MissingPluginException{
      if (!mounted) return;
      setState(() {
        status = 'Kotlin channel not found';
      });
    }
  }

  Future<void> checkBluetooth() async{
    try{
      final result = await channel.invokeMethod<String>('checkBluetooth');

      if (!mounted) return;

      setState(() {
        status = result ?? 'No responce';
      });
    } on PlatformException catch (e){
      if (!mounted) return;
      setState((){
        status = 'Error: ${e.message}';
      });
    } on MissingPluginException{
      if (!mounted) return;
      setState(() {
        status = 'Bluetooth method not found';
      });
    }
  }

  Future<void> requestBluetoothPermission() async{
    try{
      final result = await channel.invokeMethod<String>(
        'requestBluetoothPermission',
      );

      if (!mounted) return;

      setState(() {
        status = result ?? 'No response';
      });
    } on PlatformException catch (e){
      if (!mounted) return;
      setState(() {
        status = 'Error: ${e.message}';
      });
    }
  }

  @override
  Widget build(BuildContext context){
    return Scaffold(
      appBar: AppBar(
        title: const Text('MultiHop Messenger'),
      ),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.bluetooth,
              size: 70,
              color: Colors.blue,
            ),

            const SizedBox(height: 20),

            Text(
              status,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 18),
            ),

            const SizedBox(height: 30),

            ElevatedButton(
              onPressed: testKotlin,
              child: const Text('Test Kotlin Connection'),
            ),

            const SizedBox(height: 12),

            ElevatedButton(
              onPressed: checkBluetooth,
              child: const Text('Check Bluetooth'),
            ),

            const SizedBox (height: 12),

            ElevatedButton(
              onPressed: requestBluetoothPermission,
              child: const Text('Request Bluetooth Permission'),
            ),
          ],
        ),
      ),
    );

  }
}