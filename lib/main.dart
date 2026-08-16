import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart'; // 📍 1. นำเข้า foundation เพื่อใช้คำสั่ง kIsWeb
import 'package:supabase_flutter/supabase_flutter.dart';
// 📍 2. นำเข้า LINE SDK แบบมีเงื่อนไข (ถ้าเป็นเว็บ จะไม่โหลดไฟล์นี้เลย ป้องกันเว็บพัง 100%)
import 'package:flutter_line_sdk/flutter_line_sdk.dart' if (dart.library.html) '';

import 'screens/home_screen.dart';
import 'screens/login_page.dart';
import 'services/patient_profile_service.dart';
import 'package:ncds_voice_app_vol1/services/notification_service.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'screens/medication_history_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await dotenv.load(fileName: ".env");
  
  // 1. เปิดใช้งานระบบแจ้งเตือนกินยา
  try {
    await NotificationService().init();
  } catch (e) {
    debugPrint('Notification init error: $e');
  }

  // 2. ตั้งค่า Supabase
  await Supabase.initialize(
    url: dotenv.env['SUPABASE_URL'] ?? '',
    anonKey: dotenv.env['SUPABASE_ANON_KEY'] ?? '',
  );

  // 📍 3. ตั้งค่า LINE SDK เฉพาะเมื่อรันบน Mobile (APK/iOS) เท่านั้น!
  if (!kIsWeb) {
    // แนะนำให้เพิ่ม LINE_CHANNEL_ID="รหัสของคุณ" ไว้ในไฟล์ .env ครับ
    final lineChannelId = dotenv.env['LINE_CHANNEL_ID'] ?? '';
    if (lineChannelId.isNotEmpty) {
      await LineSDK.instance.setup(lineChannelId).then((_) {
        debugPrint('✅ LINE SDK Setup Completed for Native App');
      }).catchError((e) {
        debugPrint('❌ LINE SDK Setup Error: $e');
      });
    }
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