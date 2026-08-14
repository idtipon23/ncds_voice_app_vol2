import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart'; // 📍 1. อย่าลืมนำเข้า dotenv
import 'screens/home_screen.dart';
import 'screens/login_page.dart';
import 'services/patient_profile_service.dart';
import 'package:ncds_voice_app_vol1/services/notification_service.dart';
import 'screens/medication_history_screen.dart';
import 'services/auth/auth_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();  
  
  // 📍 2. โหลด Environment Variables ก่อนเป็นอันดับแรก
  try {
    await dotenv.load(fileName: ".env");
  } catch (e) {
    debugPrint('❌ ดึงไฟล์ .env ไม่สำเร็จ: $e');
  }

  // 📍 3. ดึงค่าตัวแปร (ใช้ ?? '' เพื่อป้องกัน Error แครชกรณีหาตัวแปรไม่เจอ)
  final String supabaseUrl = dotenv.env['SUPABASE_URL'] ?? '';
  final String supabaseAnonKey = dotenv.env['SUPABASE_ANON_KEY'] ?? '';
  final String lineChannelId = dotenv.env['LINE_CHANNEL_ID'] ?? '';
  final String liffId = dotenv.env['LIFF_ID'] ?? '';

  // 4. เปิดใช้งานระบบแจ้งเตือนกินยา
  try {
    await NotificationService().init();
  } catch (e) {
    debugPrint('Notification init error: $e');
  }

  // 5. ตั้งค่า Supabase
  if (supabaseUrl.isNotEmpty && supabaseAnonKey.isNotEmpty) {
    await Supabase.initialize(
      url: supabaseUrl,
      anonKey: supabaseAnonKey,
    );
  } else {
    debugPrint('❌ Supabase URL หรือ Key ว่างเปล่า!');
  }

  // 6. ตั้งค่า LINE SDK (Mobile) หรือ LINE LIFF (Web) อัตโนมัติตามสภาพแวดล้อม
  try {
    await getAuthService().initLineSdk(
      channelId: lineChannelId,
      liffId: liffId,
    );
  } catch (e) {
    debugPrint('❌ LINE/LIFF SDK Setup Error: $e');
  }

  // 7. ระบบตรวจสอบ Session และเช็ก Patient ID กับฐานข้อมูลจริง
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