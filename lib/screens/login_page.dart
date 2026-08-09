import 'package:flutter/material.dart';
import 'home_screen.dart';
import '../services/auth_service.dart';
import '../services/patient_profile_service.dart';
import '../screens/identity_registration_screen.dart';
import 'onboarding_screen.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final AuthService _authService = AuthService();
  final PatientProfileService _profileService = PatientProfileService();

  final TextEditingController _hnController = TextEditingController();
  final TextEditingController _pinController = TextEditingController();
  bool _isLoading = false;

  @override
  void dispose() {
    _hnController.dispose();
    _pinController.dispose();
    super.dispose();
  }

  Future<void> _handleHNLogin() async {
    final hn = _hnController.text.trim();
    final pin = _pinController.text.trim();

    if (hn.isEmpty || pin.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('กรุณากรอก HN และ PIN ให้ครบถ้วน',
                style: TextStyle(fontSize: 16))),
      );
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      await _authService.signInWithHN(hn: hn, pin: pin);

      final profile = await _profileService.validateAndLoadProfile();

      if (!mounted) return;

      if (profile == null) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
              builder: (context) => const IdentityRegistrationScreen()),
        );
      } else if (profile['weight_kg'] == null || profile['height_cm'] == null) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (context) => const OnboardingScreen()),
        );
      } else {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (context) => const HomeScreen()),
        );
      }
    } catch (e) {
      debugPrint('HN Login Error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('เข้าสู่ระบบล้มเหลว กรุณาตรวจสอบ HN และ PIN อีกครั้ง',
                style: TextStyle(fontSize: 16)),
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
            padding: const EdgeInsets.symmetric(horizontal: 24.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Icon(Icons.health_and_safety,
                    size: 80, color: Color(0xFF2E7D32)),
                const SizedBox(height: 24),
                const Text(
                  'NCDs Voice Assistant',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF2E7D32)),
                ),
                const SizedBox(height: 8),
                const Text(
                  'เข้าสู่ระบบ (สำหรับผู้ป่วย)',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 18, color: Colors.grey),
                ),
                const SizedBox(height: 48),
                if (_isLoading)
                  const Center(
                      child:
                          CircularProgressIndicator(color: Color(0xFF2E7D32)))
                else ...[
                  TextField(
                    controller: _hnController,
                    keyboardType: TextInputType.text,
                    style: const TextStyle(fontSize: 18),
                    decoration: InputDecoration(
                      labelText: 'หมายเลข HN ผู้ป่วย',
                      labelStyle: const TextStyle(fontSize: 16),
                      prefixIcon: const Icon(Icons.badge_outlined, size: 28),
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12)),
                      contentPadding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                  ),
                  const SizedBox(height: 20),
                  TextField(
                    controller: _pinController,
                    keyboardType: TextInputType.number,
                    obscureText: true,
                    maxLength: 6,
                    style: const TextStyle(fontSize: 18, letterSpacing: 4),
                    decoration: InputDecoration(
                      labelText: 'รหัส PIN (4-6 หลัก)',
                      labelStyle: const TextStyle(fontSize: 16),
                      prefixIcon: const Icon(Icons.lock_outline, size: 28),
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12)),
                      counterText: '',
                      contentPadding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                  ),
                  const SizedBox(height: 32),
                  ElevatedButton(
                    onPressed: _handleHNLogin,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF2E7D32),
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                      elevation: 2,
                    ),
                    child: const Text(
                      'เข้าสู่ระบบ',
                      style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: Colors.white),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
