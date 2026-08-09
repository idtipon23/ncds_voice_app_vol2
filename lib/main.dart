import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'screens/home_screen.dart';
import 'screens/login_page.dart';
import 'services/patient_profile_service.dart';
import 'package:ncds_voice_app_vol1/services/notification_service.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart'; // 📍 เพิ่มบรรทัดนี้
import 'screens/medication_history_screen.dart';
import 'screens/onboarding_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await dotenv.load(fileName: ".env");

  try {
    await NotificationService().init();
  } catch (e) {
    debugPrint('Notification init error: $e');
  }

  await Supabase.initialize(
    url: dotenv.env['SUPABASE_URL'] ?? '',
    anonKey: dotenv.env['SUPABASE_ANON_KEY'] ?? '',
  );

  // 4. 📍 ระบบตรวจสอบ Session และเช็ก Patient ID กับสถานะ Onboarding
  final profileService = PatientProfileService();
  bool hasValidSession = false;
  bool isOnboardingCompleted = false; // 📍 เพิ่มตัวแปรเช็กสถานะ Onboarding

  try {
    final patientId = await profileService.getCurrentPatientId();

    if (patientId != null && patientId.isNotEmpty) {
      // 🛠️ [Fix]: ดึงคอลัมน์ weight_kg และ height_cm มาเช็กด้วยว่าเคยทำ Onboarding หรือยัง
      final response = await Supabase.instance.client
          .from('patients')
          .select('id, weight_kg, height_cm')
          .eq('id', patientId)
          .maybeSingle();

      if (response != null) {
        hasValidSession = true;
        // ถ้ามีข้อมูลน้ำหนักหรือส่วนสูง ถือว่าผ่าน Onboarding แล้ว
        if (response['weight_kg'] != null || response['height_cm'] != null) {
          isOnboardingCompleted = true;
        }
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
    isOnboardingCompleted:
        isOnboardingCompleted, // 📍 ส่งสถานะ Onboarding เข้าไปในแอป
  ));
}

class MyApp extends StatelessWidget {
  final bool isRegistered;
  final bool isOnboardingCompleted; // 📍 รับพารามิเตอร์ใหม่

  const MyApp({
    super.key,
    required this.isRegistered,
    required this.isOnboardingCompleted, // 📍 รับพารามิเตอร์ใหม่
  });

  @override
  Widget build(BuildContext context) {
    // 🛠️ [Fix Flow Routing]:
    Widget initialScreen;
    if (!isRegistered) {
      initialScreen = const LoginPage(); // 1. ยังไม่ล็อกอิน ไปหน้า Login
    } else if (!isOnboardingCompleted) {
      initialScreen =
          const OnboardingScreen(); // 2. ล็อกอินแล้ว แต่ยังไม่มีข้อมูลสุขภาพ ไป Onboarding
    } else {
      initialScreen = const HomeScreen(); // 3. ทำครบทุกอย่าง ไป Dashboard
    }

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
        scaffoldBackgroundColor: const Color(0xFFF8FAFC),
        fontFamily: 'Sarabun',
      ),
      home: initialScreen,
    );
  }
}
