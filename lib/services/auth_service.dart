import 'package:supabase_flutter/supabase_flutter.dart';

class AuthService {
  final SupabaseClient _supabase = Supabase.instance.client;

  // 📍 ฟังก์ชันเข้าสู่ระบบด้วย HN + PIN (สำหรับ PWA / Web ล้วนๆ)
  Future<AuthResponse> signInWithHN({
    required String hn,
    required String pin,
  }) async {
    final cleanHn = hn.trim().toLowerCase();

    // สร้าง Email และ Password จำลองจาก HN และ PIN เพื่อให้เข้ากันได้กับระบบ Auth ของ Supabase
    final email = 'hn_$cleanHn@ncds-tracking.local';
    final password = 'pin_$pin';

    try {
      // 1. พยายามเข้าสู่ระบบก่อน (กรณีคนไข้เคยล็อกอิน/สมัครไว้แล้ว)
      final response = await _supabase.auth.signInWithPassword(
        email: email,
        password: password,
      );
      return response;
    } catch (e) {
      // 2. ถ้ายังไม่เคยมีบัญชี ให้ทำการสมัครสมาชิกใหม่อัตโนมัติทันที
      final response = await _supabase.auth.signUp(
        email: email,
        password: password,
        data: {'full_name': 'ผู้ป่วย HN: $cleanHn', 'login_type': 'hn_pin'},
      );
      return response;
    }
  }

  // 📍 ฟังก์ชันสำหรับออกจากระบบ (Sign Out)
  Future<void> signOut() async {
    await _supabase.auth.signOut();
  }
}
