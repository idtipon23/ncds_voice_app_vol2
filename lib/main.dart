import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'screens/home_screen.dart';
import 'screens/login_page.dart';
import 'services/notification_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 1. โหลด Environment Variables
  try {
    await dotenv.load(fileName: ".env");
  } catch (e) {
    debugPrint("ไม่พบไฟล์ .env หรือโหลดไม่สำเร็จ: $e");
  }

  // 2. เริ่มต้นระบบแจ้งเตือน
  try {
    await NotificationService().init();
  } catch (e) {
    debugPrint('Notification init error: $e');
  }

  // 3. เริ่มต้น Supabase (ฐานข้อมูลและ Auth)
  await Supabase.initialize(
    url: dotenv.env['SUPABASE_URL'] ?? 'YOUR_SUPABASE_URL',
    anonKey: dotenv.env['SUPABASE_ANON_KEY'] ?? 'YOUR_SUPABASE_ANON_KEY',
  );

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'NCDs Voice App',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
            seedColor: const Color(0xFF10B981)), // Emerald Green
        useMaterial3: true,
      ),
      // 📍 เรียกใช้ AuthGate เพื่อตัดสินใจว่าจะไปหน้าไหนเป็นหน้าแรก
      home: const AuthGate(),
    );
  }
}

// ---------------------------------------------------------------------------
// 🚦 Widget: AuthGate (ระบบแยกเส้นทางอัตโนมัติ)
// ---------------------------------------------------------------------------
class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  bool _isLoading = true;
  bool _hasSession = false;

  @override
  void initState() {
    super.initState();
    _checkInitialSession();
  }

  Future<void> _checkInitialSession() async {
    // ตรวจสอบกับ Supabase ว่าผู้ใช้มี Session (ล็อกอินค้างไว้) หรือไม่
    final session = Supabase.instance.client.auth.currentSession;

    // หน่วงเวลาเล็กน้อยให้เห็นหน้าจอโหลด (สามารถปรับลดได้)
    await Future.delayed(const Duration(milliseconds: 600));

    if (mounted) {
      setState(() {
        _hasSession = session != null;
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    // 1. ระหว่างรอตรวจสอบ Session ให้แสดงหน้าจอสีเขียวโหลดดิ้ง
    if (_isLoading) {
      return const Scaffold(
        backgroundColor: Color(0xFF10B981),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.favorite_rounded, size: 80, color: Colors.white),
              SizedBox(height: 16),
              CircularProgressIndicator(color: Colors.white),
            ],
          ),
        ),
      );
    }

    // 2. ถ้ามี Session (เคยล็อกอินแล้ว) ไป Home | ถ้าไม่มีไป Login
    return _hasSession ? const HomeScreen() : const LoginPage();
  }
}
