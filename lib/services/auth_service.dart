import 'package:supabase_flutter/supabase_flutter.dart';

class AuthService {
  final SupabaseClient _supabase = Supabase.instance.client;

  // Helper สร้าง Synthetic Email จาก HN เพื่อให้ใช้ Supabase Auth ได้โดยไม่เสีย RLS
  String _formatEmailFromHN(String hn) {
    final cleanHn =
        hn.trim().toLowerCase().replaceAll(RegExp(r'[^a-zA-Z0-9]'), '');
    return '$cleanHn@ncds.app';
  }

  // ---------------------------------------------------------------------------
  // 1. ลงทะเบียนผู้ป่วยใหม่ (Register Patient with HN & PIN)
  // ---------------------------------------------------------------------------
  Future<AuthResponse> registerPatientWithHN({
    required String hn,
    required String pin,
    required String firstName,
    required String lastName,
    required String hospitalId,
  }) async {
    final email = _formatEmailFromHN(hn);

    // 1.1 สร้าง User ใน Supabase Auth
    final response = await _supabase.auth.signUp(
      email: email,
      password: pin,
      data: {
        'hn': hn,
        'first_name': firstName,
        'last_name': lastName,
      },
    );

    final user = response.user;
    if (user == null) {
      throw Exception('ไม่สามารถสร้างบัญชีผู้ใช้ในระบบ Auth ได้');
    }

    // 1.2 สร้าง Record ในตาราง patients โดยใช้ id ตรงกับ auth.uid() เพื่อรักษา RLS
    await _supabase.from('patients').upsert({
      'id': user.id, // Patient UUID = Auth UID
      'hn': hn.trim(),
      'first_name': firstName.trim(),
      'last_name': lastName.trim(),
      'hospital_id': hospitalId.trim(),
      'created_at': DateTime.now().toIso8601String(),
    });

    return response;
  }

  // ---------------------------------------------------------------------------
  // 2. เข้าสู่ระบบด้วย HN & PIN (Sign In with HN & PIN)
  // ---------------------------------------------------------------------------
  Future<AuthResponse> signInWithHN({
    required String hn,
    required String pin,
  }) async {
    final email = _formatEmailFromHN(hn);

    // ล็อกอินผ่าน Supabase Auth
    final response = await _supabase.auth.signInWithPassword(
      email: email,
      password: pin,
    );

    return response;
  }

  // ---------------------------------------------------------------------------
  // 3. ตรวจสอบ Session และดึง Patient UUID ปัจจุบัน
  // ---------------------------------------------------------------------------
  User? get currentUser => _supabase.auth.currentUser;

  String? get currentPatientId => _supabase.auth.currentUser?.id;

  bool get isAuthenticated => _supabase.auth.currentSession != null;

  // ---------------------------------------------------------------------------
  // 4. ออกจากระบบ (Sign Out)
  // ---------------------------------------------------------------------------
  Future<void> signOut() async {
    await _supabase.auth.signOut();
  }
}
