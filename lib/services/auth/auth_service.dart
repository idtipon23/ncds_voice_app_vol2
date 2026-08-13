// ถ้ารันบน Web จะไปดึง auth_web.dart 
// ถ้าไม่ใช่ Web จะไปดึง auth_mobile.dart (ค่าเริ่มต้น)
export 'auth_mobile.dart'
    if (dart.library.html) 'auth_web.dart';