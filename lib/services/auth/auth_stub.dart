import 'auth_interface.dart';

// ไฟล์นี้มีไว้หลอก Compiler ตอนที่มันยังไม่รู้ว่าเป็น Web หรือ Mobile
AuthStrategy getAuthService() => throw UnsupportedError('Cannot create an auth service');