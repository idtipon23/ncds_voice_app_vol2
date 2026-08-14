// ไฟล์นี้จะทำหน้าที่เป็น "ชุมทาง" สลับไฟล์ให้อัตโนมัติ
export 'auth_stub.dart'
    if (dart.library.html) 'auth_web.dart'
    if (dart.library.io) 'auth_mobile.dart';