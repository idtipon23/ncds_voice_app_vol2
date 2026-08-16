import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tz;
import 'dart:io' show Platform;

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
      FlutterLocalNotificationsPlugin();

  // 🚀 เพิ่ม GlobalKey สำหรับบังคับเปลี่ยนหน้าจอเมื่อกดการแจ้งเตือน
  static final GlobalKey<NavigatorState> navigatorKey =
      GlobalKey<NavigatorState>();

  Future<void> init() async {
    tz.initializeTimeZones();
    tz.setLocalLocation(tz.getLocation('Asia/Bangkok'));

    const AndroidInitializationSettings initializationSettingsAndroid =
        AndroidInitializationSettings('@mipmap/ic_launcher');

    const InitializationSettings initializationSettings =
        InitializationSettings(android: initializationSettingsAndroid);

    // 🚀 เพิ่ม onDidReceiveNotificationResponse ดักจับตอนคนไข้จิ้มแจ้งเตือน
    await flutterLocalNotificationsPlugin.initialize(
      initializationSettings,
      onDidReceiveNotificationResponse: (NotificationResponse response) {
        if (response.payload == 'medication_screen') {
          // เมื่อกดแจ้งเตือน ให้พาไปที่หน้ายา
          navigatorKey.currentState?.pushNamed('/medication');
        }
      },
    );

    if (Platform.isAndroid) {
      final androidImplementation =
          flutterLocalNotificationsPlugin.resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>();
      if (androidImplementation != null) {
        await androidImplementation.requestNotificationsPermission();
        await androidImplementation.requestExactAlarmsPermission();
      }
    }
  }

  Future<void> scheduleMedicationWithSnooze({
    required int baseId,
    required String title,
    required String body,
    required DateTime scheduledTime,
  }) async {
    final now = tz.TZDateTime.now(tz.local);

    for (int i = 0; i < 4; i++) {
      tz.TZDateTime targetTime = tz.TZDateTime(
        tz.local,
        now.year,
        now.month,
        now.day,
        scheduledTime.hour,
        scheduledTime.minute,
      ).add(Duration(minutes: i * 15));

      if (targetTime.isBefore(now)) {
        targetTime = targetTime.add(const Duration(days: 1));
      }

      await _scheduleSingleAlarm(
        id: baseId + i,
        title: i == 0 ? title : '⏳ แจ้งเตือนซ้ำ: $title',
        body: body,
        targetTime: targetTime,
        // 🚀 ตั้งปลุกครั้งแรก เป็น Daily ทั้งหมด
        matchTime: DateTimeComponents.time,
      );
    }
  }

  // 🚀 เพิ่มพารามิเตอร์ matchTime เพื่อให้เลือกระหว่าง Daily หรือ One-off
  Future<void> _scheduleSingleAlarm({
    required int id,
    required String title,
    required String body,
    required tz.TZDateTime targetTime,
    DateTimeComponents? matchTime,
  }) async {
    // 🛠️ [Fix]: ตรวจสอบสิทธิ์ Exact Alarm บน Android ก่อนตั้งเวลา
    // เพื่อป้องกันแอป Crash (Silent Error) หากสิทธิ์ถูกบล็อกโดย OS
    AndroidScheduleMode scheduleMode = AndroidScheduleMode.exactAllowWhileIdle;

    if (Platform.isAndroid) {
      final androidImplementation =
          flutterLocalNotificationsPlugin.resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>();

      final hasExactAlarm =
          await androidImplementation?.canScheduleExactNotifications() ?? false;

      if (!hasExactAlarm) {
        // 🚀 ถ้าเครื่องบล็อก Exact Alarm ให้ใช้ Inexact แทน รับประกันการตั้งเตือนสำเร็จ 100%
        scheduleMode = AndroidScheduleMode.inexactAllowWhileIdle;
        debugPrint(
            '⚠️ ขาดสิทธิ์ Exact Alarm -> สลับไปใช้ Inexact Mode อัตโนมัติ');
      }
    }
    try {
      await flutterLocalNotificationsPlugin.zonedSchedule(
        id, title, body, targetTime,
        const NotificationDetails(
          android: AndroidNotificationDetails(
            'medication_channel',
            'Medication Reminders',
            channelDescription: 'แจ้งเตือนการรับประทานยา',
            importance: Importance.max,
            priority: Priority.max,
            category: AndroidNotificationCategory.alarm,
            fullScreenIntent: true,
            visibility: NotificationVisibility.public,
            autoCancel: false,
            enableVibration: true,
            playSound: true,
          ),
        ),
        androidScheduleMode:
            scheduleMode, // 🚀 ใช้ค่าโหมดที่ผ่านการป้องกัน Crash แล้ว
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
        matchDateTimeComponents:
            matchTime, // 🚀 ใช้ค่าที่ส่งมาแทนการบังคับตายตัว
        payload: 'medication_screen',
      );
    } catch (e) {
      debugPrint('❌ Notification Error: $e');
      // ถ้าระบบแจ้งเตือนพัง ให้เตะ Error ออกไปให้หน้าจอ UI จัดการ
      rethrow;
    }
  }

  Future<void> stopSnoozeForToday({
    required int baseId,
    required DateTime scheduledTime,
    required String title,
    required String body,
  }) async {
    // 1. 🚀 ล้าง Ghost Alarms เผื่อไว้ 15 ID พร้อมห่อ try-catch ป้องกัน Plugin Crash รายตัว
    for (int i = 0; i <= 15; i++) {
      try {
        await flutterLocalNotificationsPlugin.cancel(baseId + i);
      } catch (cancelError) {
        debugPrint(
            '⚠️ Non-fatal cancel error for snooze ID ${baseId + i}: $cancelError');
      }
    }

    try {
      final now = tz.TZDateTime.now(tz.local);
      // 2. สร้างแจ้งเตือนใหม่สำหรับวันพรุ่งนี้ (รักษา Logic Snooze 4 ตัว ห่างกัน 15 นาทีตามเดิม)
      for (int i = 0; i < 4; i++) {
        tz.TZDateTime targetTimeToday = tz.TZDateTime(
          tz.local,
          now.year,
          now.month,
          now.day,
          scheduledTime.hour,
          scheduledTime.minute,
        ).add(Duration(minutes: i * 15));

        tz.TZDateTime tomorrowTime =
            targetTimeToday.add(const Duration(days: 1));

        // 🚀 ลอจิกสำคัญเดิม:
        // หากเวลารอบนั้นผ่านไปแล้ว -> ใช้ Daily ได้ (OS จะข้ามไปพรุ่งนี้ให้เอง)
        // หากเวลารอบนั้นยังมาไม่ถึง (เช่น Snooze) -> ต้องใช้ One-off (null) ป้องกัน OS ลากมาดังวันนี้!
        bool isSafeForDaily = now.isAfter(targetTimeToday);

        try {
          await _scheduleSingleAlarm(
            id: baseId + i,
            title: i == 0 ? title : '⏳ แจ้งเตือนซ้ำ: $title',
            body: body,
            targetTime: tomorrowTime,
            matchTime: isSafeForDaily ? DateTimeComponents.time : null,
          );
        } catch (scheduleError) {
          debugPrint(
              '⚠️ Non-fatal schedule error for ID ${baseId + i}: $scheduleError');
        }
      }
    } catch (e, stack) {
      debugPrint('❌ Error in stopSnoozeForToday execution: $e\n$stack');
    }
  }

  Future<void> cancelAllAlarmsForMeal(int baseId) async {
    // 🚀 ล้าง Ghost Alarms ให้หมดจด พร้อมป้องกัน Exception หาก ID ไม่มีอยู่จริงใน Cache
    for (int i = 0; i <= 15; i++) {
      try {
        await flutterLocalNotificationsPlugin.cancel(baseId + i);
      } catch (cancelError) {
        debugPrint(
            '⚠️ Non-fatal cancel error for meal ID ${baseId + i}: $cancelError');
      }
    }
  }
}
