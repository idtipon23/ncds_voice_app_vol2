import 'package:flutter/material.dart';
import 'home_screen.dart';
// 📍 1. Import จากโฟลเดอร์ auth ใหม่ของเรา
import '../services/auth/auth_service.dart';
import '../services/patient_profile_service.dart';
import '../screens/identity_registration_screen.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  // 📍 2. เรียกใช้งานผ่าน getAuthService() (ระบบจะเลือก Web/Mobile ให้เองอัตโนมัติ)
  final authService = getAuthService();
  final PatientProfileService _profileService = PatientProfileService();

  bool _isLoading = false;

  Future<void> _handleEnterApp() async {
    setState(() {
      _isLoading = true;
    });

    try {
      // 📍 3. สั่งล็อกอินผ่านระบบ LINE Shadow Account ที่เราเพิ่งสร้าง
      final authResponse = await authService.signInWithLine();

      if (authResponse == null || authResponse.user == null) {
        throw Exception('การเข้าสู่ระบบผ่าน LINE ไม่สำเร็จ');
      }

      // 4. ตรวจสอบโปรไฟล์ผู้ป่วยในเครื่อง
      final profile = await _profileService.validateAndLoadProfile();

      if (!mounted) return;

      // 5. เช็กความสมบูรณ์ของโปรไฟล์
      if (_profileService.isProfileComplete(profile)) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (context) => const HomeScreen()),
        );
      } else {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
              builder: (context) => const IdentityRegistrationScreen()),
        );
      }
    } catch (e) {
      debugPrint('❌ Login Error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('เกิดข้อผิดพลาดในการเข้าสู่ระบบ: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(
                  Icons.health_and_safety_rounded,
                  size: 90,
                  color: Color(0xFF10B981),
                ),
                const SizedBox(height: 24),
                const Text(
                  'NCD Voice Application',
                  style: TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF1E293B),
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'ระบบบันทึกและติดตามสุขภาพสำหรับผู้สูงอายุ',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 16,
                    color: Colors.grey,
                  ),
                ),
                const SizedBox(height: 48),
                _isLoading
                    ? const Center(
                        child:
                            CircularProgressIndicator(color: Color(0xFF10B981)))
                    : ElevatedButton.icon(
                        onPressed: _handleEnterApp,
                        icon: const Icon(Icons.chat_bubble_rounded,
                            color: Colors.white),
                        label: const Text(
                          'เข้าสู่ระบบด้วย LINE',
                          style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Colors.white),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor:
                              const Color(0xFF06C755), // สีเขียว LINE Official
                          padding: const EdgeInsets.symmetric(
                              vertical: 16, horizontal: 32),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          elevation: 2,
                        ),
                      ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
