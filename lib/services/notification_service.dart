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
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
      matchDateTimeComponents: matchTime, // 🚀 ใช้ค่าที่ส่งมาแทนการบังคับตายตัว
      payload: 'medication_screen',
    );
  }

  Future<void> stopSnoozeForToday(
      {required int baseId,
      required DateTime scheduledTime,
      required String title,
      required String body}) async {
    // 1. 🚀 ล้าง Ghost Alarms เผื่อไว้ 15 ID ป้องกันบั๊กเวอร์ชันเก่าค้างในเครื่องผู้ป่วย
    for (int i = 0; i <= 15; i++) {
      await flutterLocalNotificationsPlugin.cancel(baseId + i);
    }

    final now = tz.TZDateTime.now(tz.local);
    // 2. สร้างแจ้งเตือนใหม่สำหรับวันพรุ่งนี้
    for (int i = 0; i < 4; i++) {
      tz.TZDateTime targetTimeToday = tz.TZDateTime(
        tz.local,
        now.year,
        now.month,
        now.day,
        scheduledTime.hour,
        scheduledTime.minute,
      ).add(Duration(minutes: i * 15));

      tz.TZDateTime tomorrowTime = targetTimeToday.add(const Duration(days: 1));

      // 🚀 ลอจิกสำคัญ:
      // หากเวลารอบนั้นผ่านไปแล้ว -> ใช้ Daily ได้ (OS จะข้ามไปพรุ่งนี้ให้เอง)
      // หากเวลารอบนั้นยังมาไม่ถึง (เช่น Snooze) -> ต้องใช้ One-off (null) ป้องกัน OS ลากมาดังวันนี้!
      bool isSafeForDaily = now.isAfter(targetTimeToday);

      await _scheduleSingleAlarm(
        id: baseId + i,
        title: i == 0 ? title : '⏳ แจ้งเตือนซ้ำ: $title',
        body: body,
        targetTime: tomorrowTime,
        matchTime: isSafeForDaily ? DateTimeComponents.time : null,
      );
    }
  }

  Future<void> cancelAllAlarmsForMeal(int baseId) async {
    // 🚀 ล้าง Ghost Alarms ให้หมดจด
    for (int i = 0; i <= 15; i++) {
      await flutterLocalNotificationsPlugin.cancel(baseId + i);
    }
  }
}
