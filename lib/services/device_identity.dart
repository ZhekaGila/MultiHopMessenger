import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

class DeviceIdentity {
  static const String _deviceIdKey = 'device_uuid';


  static Future<String> getOrCreateDeviceId() async{
    final prefs = await SharedPreferences.getInstance();

    final savedId = prefs.getString(_deviceIdKey);

    if (savedId != null && savedId.isNotEmpty){
      return savedId;
    }

    final newId = const Uuid().v4();

    await prefs.setString(_deviceIdKey, newId);

    return newId;
  }
}