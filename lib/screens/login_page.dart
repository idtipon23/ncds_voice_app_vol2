import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/auth_service.dart';
import 'home_screen.dart';
import 'identity_registration_screen.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final AuthService _authService = AuthService();
  final TextEditingController _hnController = TextEditingController();
  final TextEditingController _pinController = TextEditingController();
  bool _isLoading = false;

  static const Color primaryColor =
      Color(0xFF10B981); // Emerald Green สไตล์ Medical
  static const Color slateColor = Color(0xFF334155);

  Future<void> _handleLogin() async {
    final hn = _hnController.text.trim();
    final pin = _pinController.text.trim();

    if (hn.isEmpty || pin.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('กรุณากรอก HN และ PIN ให้ครบถ้วน')),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      await _authService.signInWithHN(hn: hn, pin: pin);

      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (context) => const HomeScreen()),
        );
      }
    } on AuthException catch (_) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('เข้าสู่ระบบล้มเหลว: รหัส HN หรือ PIN ไม่ถูกต้อง')),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('เกิดข้อผิดพลาด: $e')),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.favorite_rounded,
                    size: 80, color: primaryColor),
                const SizedBox(height: 16),
                const Text(
                  'NCDs Voice App',
                  style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                      color: slateColor),
                ),
                const SizedBox(height: 8),
                const Text(
                  'เข้าสู่ระบบด้วยรหัสผู้ป่วย',
                  style: TextStyle(fontSize: 16, color: Colors.grey),
                ),
                const SizedBox(height: 40),

                // กรอบกรอกข้อมูล
                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                          color: Colors.black.withOpacity(0.05),
                          blurRadius: 20,
                          offset: const Offset(0, 4)),
                    ],
                  ),
                  child: Column(
                    children: [
                      TextField(
                        controller: _hnController,
                        keyboardType: TextInputType.text,
                        decoration: InputDecoration(
                          labelText: 'รหัสประจำตัวผู้ป่วย (HN)',
                          prefixIcon: const Icon(Icons.person_outline,
                              color: primaryColor),
                          border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        controller: _pinController,
                        keyboardType: TextInputType.number,
                        obscureText: true,
                        maxLength: 6,
                        decoration: InputDecoration(
                          labelText: 'รหัส PIN 6 หลัก',
                          prefixIcon: const Icon(Icons.lock_outline,
                              color: primaryColor),
                          border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12)),
                          counterText: "", // ซ่อนตัวนับความยาว
                        ),
                      ),
                      const SizedBox(height: 24),
                      SizedBox(
                        width: double.infinity,
                        height: 52,
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: primaryColor,
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12)),
                          ),
                          onPressed: _isLoading ? null : _handleLogin,
                          child: _isLoading
                              ? const CircularProgressIndicator(
                                  color: Colors.white)
                              : const Text('เข้าสู่ระบบ',
                                  style: TextStyle(
                                      fontSize: 18,
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold)),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                TextButton(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (context) =>
                              const IdentityRegistrationScreen()),
                    );
                  },
                  child: const Text(
                    'ผู้ป่วยใหม่? ลงทะเบียนที่นี่',
                    style: TextStyle(
                        fontSize: 16,
                        color: primaryColor,
                        fontWeight: FontWeight.bold),
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
