import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import 'home_screen.dart';

class IdentityRegistrationScreen extends StatefulWidget {
  const IdentityRegistrationScreen({super.key});

  @override
  State<IdentityRegistrationScreen> createState() =>
      _IdentityRegistrationScreenState();
}

class _IdentityRegistrationScreenState
    extends State<IdentityRegistrationScreen> {
  final AuthService _authService = AuthService();
  final _formKey = GlobalKey<FormState>();

  final _hnController = TextEditingController();
  final _firstNameController = TextEditingController();
  final _lastNameController = TextEditingController();
  final _hospitalController =
      TextEditingController(); // หรือใช้ Dropdown ตามสะดวกครับ
  final _pinController = TextEditingController();
  final _confirmPinController = TextEditingController();

  bool _isLoading = false;
  static const Color primaryColor = Color(0xFF10B981);
  static const Color slateColor = Color(0xFF334155);

  Future<void> _handleRegister() async {
    if (!_formKey.currentState!.validate()) return;

    if (_pinController.text != _confirmPinController.text) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('รหัส PIN ไม่ตรงกัน กรุณาตรวจสอบอีกครั้ง')),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      // ค่าเริ่มต้นของโรงพยาบาล หากคุณหมอมีตาราง hospital_id เฉพาะ สามารถปรับแก้ตรงนี้ได้ครับ
      final hospitalId = _hospitalController.text.trim().isEmpty
          ? 'default_hospital_001'
          : _hospitalController.text.trim();

      await _authService.registerPatientWithHN(
        hn: _hnController.text.trim(),
        pin: _pinController.text.trim(),
        firstName: _firstNameController.text.trim(),
        lastName: _lastNameController.text.trim(),
        hospitalId: hospitalId,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('ลงทะเบียนสำเร็จ! เข้าสู่ระบบอัตโนมัติ')),
        );
        // ลงทะเบียนเสร็จ วิ่งเข้าหน้า Home เลย
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (context) => const HomeScreen()),
          (route) => false,
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('ลงทะเบียนล้มเหลว: $e')),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        title: const Text('ลงทะเบียนผู้ป่วยใหม่',
            style: TextStyle(color: slateColor, fontWeight: FontWeight.bold)),
        backgroundColor: Colors.white,
        elevation: 0,
        iconTheme: const IconThemeData(color: slateColor),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'ข้อมูลประจำตัวผู้ป่วย',
                  style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: primaryColor),
                ),
                const SizedBox(height: 16),
                _buildTextField(_hnController, 'รหัส HN', Icons.badge_outlined),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                        child: _buildTextField(_firstNameController, 'ชื่อ',
                            Icons.person_outline)),
                    const SizedBox(width: 16),
                    Expanded(
                        child: _buildTextField(_lastNameController, 'นามสกุล',
                            Icons.person_outline)),
                  ],
                ),
                const SizedBox(height: 16),
                _buildTextField(
                    _hospitalController,
                    'โรงพยาบาล / หน่วยบริการ (ระบุชื่อย่อ)',
                    Icons.local_hospital_outlined),
                const SizedBox(height: 32),
                const Text(
                  'ตั้งรหัสผ่านสำหรับเข้าใช้งาน',
                  style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: primaryColor),
                ),
                const SizedBox(height: 16),
                _buildPinField(_pinController, 'ตั้งรหัส PIN 6 หลัก'),
                const SizedBox(height: 16),
                _buildPinField(_confirmPinController, 'ยืนยันรหัส PIN 6 หลัก'),
                const SizedBox(height: 40),
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: primaryColor,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                    onPressed: _isLoading ? null : _handleRegister,
                    child: _isLoading
                        ? const CircularProgressIndicator(color: Colors.white)
                        : const Text('ยืนยันการลงทะเบียน',
                            style: TextStyle(
                                fontSize: 18,
                                color: Colors.white,
                                fontWeight: FontWeight.bold)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTextField(
      TextEditingController controller, String label, IconData icon) {
    return TextFormField(
      controller: controller,
      validator: (value) => value!.isEmpty ? 'กรุณากรอกข้อมูล' : null,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, color: primaryColor),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        filled: true,
        fillColor: Colors.white,
      ),
    );
  }

  Widget _buildPinField(TextEditingController controller, String label) {
    return TextFormField(
      controller: controller,
      keyboardType: TextInputType.number,
      obscureText: true,
      maxLength: 6,
      validator: (value) => value!.length < 6 ? 'PIN ต้องมี 6 หลัก' : null,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: const Icon(Icons.lock_outline, color: primaryColor),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        filled: true,
        fillColor: Colors.white,
        counterText: "",
      ),
    );
  }
}
