import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'auth_interface.dart';

class AuthServiceImpl implements AuthStrategy {
  final SupabaseClient _supabase = Supabase.instance.client;

  @override
  Future<AuthResponse?> signInWithLine() async {
    try {
      debugPrint('🌐 [WEB] กำลังล็อกอินผ่าน LIFF SDK');
      
      // 📍 TODO: ในอนาคตเราจะใช้ JS Interop ดึง liff.getProfile() ตรงนี้
      // เบื้องต้นใช้ mock id สำหรับทดสอบการคอมไพล์โค้ด
      final mockLineUserId = 'U_WEB_MOCK_1234567890'; 
      
      final shadowEmail = '$mockLineUserId@ncd-app.local';
      final shadowPassword = 'NCD_${mockLineUserId}_Secure99!';

      try {
        return await _supabase.auth.signInWithPassword(
          email: shadowEmail,
          password: shadowPassword,
        );
      } catch (e) {
        return await _supabase.auth.signUp(
          email: shadowEmail,
          password: shadowPassword,
        );
      }
    } catch (e) {
      debugPrint('❌ Web Auth Error: $e');
      return null;
    }
  }

  @override
  Future<void> signOut() async {
    await _supabase.auth.signOut();
  }

  @override
  User? get currentUser => _supabase.auth.currentUser;
}

AuthStrategy getAuthService() => AuthServiceImpl();