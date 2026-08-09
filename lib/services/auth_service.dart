import 'package:supabase_flutter/supabase_flutter.dart';

class AuthService {
  final SupabaseClient _supabase = Supabase.instance.client;

  // ฟังก์ชันจำลองการล็อกอินด้วย LINE (แปลง LINE UID เป็น Email อัตโนมัติ)
  Future<AuthResponse> signInWithLineMock({
    required String lineUserId,
    required String displayName,
  }) async {
    // สร้าง Email จำลองและรหัสผ่านเฉพาะตัวจาก LINE UID
    final email = '$lineUserId@ncds-tracking.local';
    final password = 'pwd_$lineUserId';

    try {
      // 1. ลองพยายามเข้าสู่ระบบก่อน (กรณีเคยสมัครไว้แล้ว)
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
        data: {'full_name': displayName, 'line_uid': lineUserId},
      );
      return response;
    }
  }

  // 📍 [เพิ่มเฉพาะจุดนี้]: ฟังก์ชันเข้าสู่ระบบด้วย HN + PIN (สำหรับ PWA / Web)
  Future<AuthResponse> signInWithHN({
    required String hn,
    required String pin,
  }) async {
    final cleanHn = hn.trim().toLowerCase();
    final email = 'hn_$cleanHn@ncds-tracking.local';
    final password = 'pin_$pin';

    try {
      // 1. พยายามเข้าสู่ระบบก่อน (กรณีเคยสมัครไว้แล้ว)
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
        data: {'hn': hn.trim(), 'login_method': 'hn_pin'},
      );
      return response;
    }
  }

  // ฟังก์ชันออกจากระบบ
  Future<void> signOut() async {
    await _supabase.auth.signOut();
  }

  // ดึงข้อมูล User ปัจจุบัน
  User? get currentUser => _supabase.auth.currentUser;
}
