import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart'; // 📍 1. นำเข้า foundation เพื่อใช้คำสั่ง kIsWeb
import 'package:supabase_flutter/supabase_flutter.dart';
import 'screens/home_screen.dart';
import 'screens/login_page.dart';
import 'services/patient_profile_service.dart';
import 'package:ncds_voice_app_vol1/services/notification_service.dart';

import 'screens/medication_history_screen.dart';
import 'services/auth/auth_service.dart';
const String supabaseUrl = String.fromEnvironment('SUPABASE_URL');
const String supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');
const String lineChannelId = String.fromEnvironment('LINE_CHANNEL_ID');
const String liffId = String.fromEnvironment('LIFF_ID');

void main() async {
  WidgetsFlutterBinding.ensureInitialized();  
  
  
  // 1. เปิดใช้งานระบบแจ้งเตือนกินยา
  try {
    await NotificationService().init();
  } catch (e) {
    debugPrint('Notification init error: $e');
  }

  // 2. ตั้งค่า Supabase
  await Supabase.initialize(
  url: supabaseUrl,
  anonKey: supabaseAnonKey,
);

  // 📍 3. ตั้งค่า LINE SDK (Mobile) หรือ LINE LIFF (Web) อัตโนมัติตามสภาพแวดล้อม
  try {
    // LINE / LIFF
await getAuthService().initLineSdk(
  channelId: lineChannelId,
  liffId: liffId,
);
  } catch (e) {
    debugPrint('❌ LINE/LIFF SDK Setup Error: $e');
  }

  // 4. ระบบตรวจสอบ Session และเช็ก Patient ID กับฐานข้อมูลจริง
  final profileService = PatientProfileService();
  bool hasValidSession = false;

  try {
    final patientId = await profileService.getCurrentPatientId();
    if (patientId != null && patientId.isNotEmpty) {
      final isValid = await profileService.verifySessionInDatabase(patientId);
      if (isValid) {
        hasValidSession = true;
      } else {
        await profileService.clearLocalIdentity();
      }
    } else {
      await profileService.clearLocalIdentity();
    }
  } catch (e) {
    debugPrint('Error verifying session: $e');
    await profileService.clearLocalIdentity();
  }

  runApp(MyApp(
    isRegistered: hasValidSession,
  ));
}

class MyApp extends StatelessWidget {
  final bool isRegistered;

  const MyApp({
    super.key, 
    required this.isRegistered,
  });

  @override
  Widget build(BuildContext context) {
    Widget initialScreen = isRegistered ? const HomeScreen() : const LoginPage();

    return MaterialApp(
      navigatorKey: NotificationService.navigatorKey, 
      routes: {
        '/medication': (context) => const MedicationHistoryScreen(),
      },
      title: 'NCD Voice App',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF10B981),
        ),
      ),
      home: initialScreen,
    );
  }
}