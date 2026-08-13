import 'package:flutter/foundation.dart';
import 'package:flutter_line_sdk/flutter_line_sdk.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'auth_interface.dart';

class AuthServiceImpl implements AuthStrategy {
  final SupabaseClient _supabase = Supabase.instance.client;

  @override
  Future<void> initLineSdk({String? channelId, String? liffId}) async {
    try {
      if (channelId == null || channelId.isEmpty) return;
      await LineSDK.instance.setup(channelId);
      debugPrint('✅ [MOBILE] LINE SDK Setup Completed');
    } catch (e) {
      debugPrint('❌ [MOBILE] LINE SDK Setup Error: $e');
    }
  }

  @override
  Future<AuthResponse?> signInWithLine() async {
    try {
      debugPrint('📱 [MOBILE] กำลังล็อกอินผ่าน Native LINE SDK');
      
      // 1. เรียกล็อกอินผ่านแอป LINE 
      final result = await LineSDK.instance.login(scopes: ["profile", "openid"]);
      final lineUserId = result.userProfile!.userId;
      
      // 2. สร้าง Shadow Account Data
      final shadowEmail = '$lineUserId@ncd-app.local';
      final shadowPassword = 'NCD_${lineUserId}_Secure99!';

      // 3. พยายามล็อกอินเข้า Supabase
      try {
        debugPrint('กำลังล็อกอิน Shadow Account: $shadowEmail');
        return await _supabase.auth.signInWithPassword(
          email: shadowEmail,
          password: shadowPassword,
        );
      } catch (e) {
        // 4. ถ้าล็อกอินไม่ผ่าน (ไม่มีบัญชี) ให้สมัครสมาชิกใหม่เงียบๆ
        debugPrint('ไม่พบบัญชีเดิม กำลังสร้าง Shadow Account ใหม่...');
        return await _supabase.auth.signUp(
          email: shadowEmail,
          password: shadowPassword,
        );
      }
    } catch (e) {
      debugPrint('❌ Mobile Auth Error: $e');
      return null;
    }
  }

  @override
  Future<void> signOut() async {
    try {
      await LineSDK.instance.logout();
      await _supabase.auth.signOut();
    } catch (e) {
      debugPrint('Logout Error: $e');
    }
  }

  @override
  User? get currentUser => _supabase.auth.currentUser;
}

AuthStrategy getAuthService() => AuthServiceImpl();