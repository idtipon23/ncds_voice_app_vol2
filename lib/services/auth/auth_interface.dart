import 'package:supabase_flutter/supabase_flutter.dart';

abstract class AuthStrategy {
  Future<AuthResponse?> signInWithLine();
  Future<void> signOut();
  User? get currentUser;
}