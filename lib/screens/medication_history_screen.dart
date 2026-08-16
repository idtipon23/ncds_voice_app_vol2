import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../config/app_config.dart';
import '../services/patient_profile_service.dart';
import '../services/voice_health_service.dart';
import '../services/notification_service.dart';

class MedicationHistoryScreen extends StatefulWidget {
  const MedicationHistoryScreen({super.key});

  @override
  State<MedicationHistoryScreen> createState() =>
      _MedicationHistoryScreenState();
}

class _MedicationHistoryScreenState extends State<MedicationHistoryScreen> {
  final PatientProfileService _profileService = PatientProfileService();
  final SupabaseClient _supabase = Supabase.instance.client;
  late VoiceHealthService voiceService;

  List<Map<String, dynamic>> _medications = [];
  List<Map<String, dynamic>> _todayAdherence = [];
  bool _isLoading = true;
  bool _isProcessingImage = false;

  static const Color emeraldColor = Color(0xFF10B981);
  static const Color slateColor = Color(0xFF334155);

  TimeOfDay stringToTimeOfDay(String? timeString) {
    if (timeString == null || !timeString.contains(':')) {
      return const TimeOfDay(hour: 8, minute: 0);
    }
    final parts = timeString.split(':');
    return TimeOfDay(
      hour: int.tryParse(parts[0]) ?? 8,
      minute: int.tryParse(parts[1]) ?? 0,
    );
  }

  String timeOfDayToString(TimeOfDay time) {
    return '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
  }

  @override
  void initState() {
    super.initState();
    voiceService = VoiceHealthService(AppConfig.geminiApiKey);
    _loadInitialData();
  }

  Future<void> _loadInitialData() async {
    setState(() => _isLoading = true);
    await _loadMedications();
    await _loadAdherenceLogs();
    if (mounted) setState(() => _isLoading = false);
  }

  Future<void> _loadMedications() async {
    try {
      final patientId = await _profileService.getCurrentPatientId();
      if (patientId != null) {
        final response = await _supabase
            .from('medication_logs')
            .select()
            .eq('patient_id', patientId)
            .order('recorded_at', ascending: false);
        _medications = List<Map<String, dynamic>>.from(response);
      }
    } catch (e) {
      debugPrint('Error loading medications: $e');
    }
  }

  Future<void> _loadAdherenceLogs() async {
    try {
      final patientId = await _profileService.getCurrentPatientId();
      if (patientId != null) {
        final now = DateTime.now();
        final startOfDay = DateTime(
          now.year,
          now.month,
          now.day,
        ).toUtc().toIso8601String();

        final response = await _supabase
            .from('medication_adherence_logs')
            .select()
            .eq('patient_id', patientId)
            .gte('taken_at', startOfDay);
        _todayAdherence = List<Map<String, dynamic>>.from(response);
      }
    } catch (e) {
      debugPrint('Error loading adherence logs: $e');
    }
  }

  int _generateBaseId(String medId, String mealType) {
    int stableHash = 0;
    for (int i = 0; i < medId.length; i++) {
      stableHash = (31 * stableHash + medId.codeUnitAt(i)) & 0x7FFFFFFF;
    }

    int mealOffset = mealType == 'morning'
        ? 100000
        : mealType == 'noon'
            ? 200000
            : 300000;
    return (stableHash % 10000) + mealOffset;
  }

  // 📍 1. ฟังก์ชันสแกน และแสดง Pop-up ยืนยันข้อมูล AI
  Future<void> _scanMedication() async {
    final picker = ImagePicker();
    final XFile? photo = await picker.pickImage(
      source: ImageSource.camera,
      imageQuality: 80,
      maxWidth: 1024,
      maxHeight: 1024,
    );

    if (photo != null) {
      setState(() => _isProcessingImage = true);
      try {
        final patientId = await _profileService.getCurrentPatientId();
        if (patientId == null || patientId.isEmpty) {
          throw Exception('ไม่พบรหัสผู้ป่วย กรุณาลงทะเบียนใหม่');
        }

        final File imageFile = File(photo.path);
        final extractedData =
            await voiceService.processDrugLabelImage(imageFile);
        setState(() => _isProcessingImage = false);

        if (extractedData != null && extractedData.isNotEmpty) {
          _showEditMedicationDialog(patientId, extractedData);
        } else {
          throw Exception(
              'AI ไม่สามารถอ่านข้อมูลจากฉลากยานี้ได้ กรุณาลองใหม่อีกครั้ง');
        }
      } catch (e) {
        setState(() => _isProcessingImage = false);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
                content: Text('เกิดข้อผิดพลาด: $e'),
                backgroundColor: Colors.red),
          );
        }
      }
    }
  }

  // 📍 2. Pop-up Dialog สำหรับแก้ไขและยืนยันข้อมูลจาก AI
  void _showEditMedicationDialog(
      String patientId, Map<String, dynamic> aiData) {
    TextEditingController nameController =
        TextEditingController(text: aiData['medication_name'] ?? '');
    TextEditingController descController =
        TextEditingController(text: aiData['dosage_instruction'] ?? '');

    bool mActive = aiData['is_morning_active'] ?? true;
    bool nActive = aiData['is_noon_active'] ?? false;
    bool eActive = aiData['is_evening_active'] ?? true;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return AlertDialog(
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16)),
              title: const Text('ตรวจสอบข้อมูลยา (จาก AI)',
                  style: TextStyle(
                      color: emeraldColor, fontWeight: FontWeight.bold)),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                        controller: nameController,
                        decoration: const InputDecoration(
                            labelText: 'ชื่อยา', border: OutlineInputBorder())),
                    const SizedBox(height: 12),
                    TextField(
                        controller: descController,
                        decoration: const InputDecoration(
                            labelText: 'วิธีใช้ (คำสั่งแพทย์)',
                            border: OutlineInputBorder()),
                        maxLines: 2),
                    const SizedBox(height: 16),
                    const Text('มื้อยาที่ต้องทาน:',
                        style: TextStyle(fontWeight: FontWeight.bold)),
                    SwitchListTile(
                        title: const Text('มื้อเช้า'),
                        value: mActive,
                        activeColor: emeraldColor,
                        onChanged: (val) => setModalState(() => mActive = val)),
                    SwitchListTile(
                        title: const Text('มื้อกลางวัน'),
                        value: nActive,
                        activeColor: emeraldColor,
                        onChanged: (val) => setModalState(() => nActive = val)),
                    SwitchListTile(
                        title: const Text('มื้อเย็น'),
                        value: eActive,
                        activeColor: emeraldColor,
                        onChanged: (val) => setModalState(() => eActive = val)),
                  ],
                ),
              ),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('ยกเลิก',
                        style: TextStyle(color: Colors.grey))),
                ElevatedButton(
                  style:
                      ElevatedButton.styleFrom(backgroundColor: emeraldColor),
                  onPressed: () async {
                    Navigator.pop(context);
                    setState(() => _isLoading = true);
                    try {
                      final now = DateTime.now();
                      await _supabase.from('medication_logs').insert({
                        'patient_id': patientId,
                        'medication_name': nameController.text.trim(),
                        'dosage_instruction': descController.text.trim(),
                        'is_morning_active': mActive,
                        'time_morning': aiData['time_morning'] ?? '08:00',
                        'is_noon_active': nActive,
                        'time_noon': aiData['time_noon'] ?? '12:00',
                        'is_evening_active': eActive,
                        'time_evening': aiData['time_evening'] ?? '18:00',
                        'recorded_at': now.toUtc().toIso8601String(),
                        'created_at': now.toIso8601String(),
                      });
                      await _loadMedications();
                      if (mounted)
                        ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                                content: Text('บันทึกข้อมูลยาสำเร็จ'),
                                backgroundColor: emeraldColor));
                    } catch (e) {
                      if (mounted)
                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                            content: Text('Error: $e'),
                            backgroundColor: Colors.red));
                    } finally {
                      setState(() => _isLoading = false);
                    }
                  },
                  child: const Text('บันทึก',
                      style: TextStyle(
                          color: Colors.white, fontWeight: FontWeight.bold)),
                ),
              ],
            );
          },
        );
      },
    );
  }

  // 📍 3. ฟังก์ชันลบยา
  Future<void> _deleteMedication(Map<String, dynamic> med) async {
    bool confirm = await showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('ยืนยันการลบยา',
                style: TextStyle(color: Colors.red)),
            content: Text(
                'คุณต้องการลบยา "${med['medication_name']}" ออกจากระบบใช่หรือไม่?'),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('ยกเลิก',
                      style: TextStyle(color: slateColor))),
              ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('ลบทิ้ง',
                      style: TextStyle(color: Colors.white))),
            ],
          ),
        ) ??
        false;

    if (confirm) {
      setState(() => _isLoading = true);
      try {
        final String medUuid = med['id'].toString();
        await _supabase
            .from('medication_adherence_logs')
            .delete()
            .eq('medication_id', medUuid);
        await _supabase.from('medication_logs').delete().eq('id', medUuid);

        for (String meal in ['morning', 'noon', 'evening']) {
          final int baseId = _generateBaseId(medUuid, meal);
          await NotificationService().cancelAllAlarmsForMeal(baseId);
        }

        await _loadMedications();
        await _loadAdherenceLogs();
        if (mounted)
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text('ลบรายการยาสำเร็จ'),
              backgroundColor: emeraldColor));
      } catch (e) {
        if (mounted)
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text('ลบไม่สำเร็จ: $e'), backgroundColor: Colors.red));
      } finally {
        if (mounted) setState(() => _isLoading = false);
      }
    }
  }

  bool _isMedicationTakenToday(String medicationId, String mealType) {
    final String todayDate = DateTime.now().toIso8601String().split('T')[0];
    return _todayAdherence.any(
      (log) =>
          log['medication_id'].toString() == medicationId.toString() &&
          log['meal_type']?.toString() == mealType &&
          (log['taken_date']?.toString() == todayDate ||
              (log['taken_at'] != null &&
                  log['taken_at'].toString().startsWith(todayDate))),
    );
  }

  // 🎯 ปรับ Logic: หากเพิ่งเพิ่มยาวันนี้ และเลยเวลามื้อนั้นไปแล้ว จะไม่ขึ้นสีแดงย้อนหลัง
  bool _isTimeToAlert(String? timeStr, bool isActive, bool isTaken,
      {dynamic createdAt}) {
    if (!isActive || isTaken || timeStr == null || !timeStr.contains(':')) {
      return false;
    }

    final DateTime now = DateTime.now();
    final parts = timeStr.split(':');
    final DateTime scheduledTime = DateTime(
      now.year,
      now.month,
      now.day,
      int.parse(parts[0]),
      int.parse(parts[1]),
    );

    if (now.isBefore(scheduledTime)) {
      return false;
    }

    // ตรวจสอบว่าเพิ่งสร้าง "วันนี้" หลังจากเลยเวลากินยาไปแล้วหรือไม่
    if (createdAt != null) {
      try {
        final DateTime createdDateTime =
            DateTime.parse(createdAt.toString()).toLocal();
        if (createdDateTime.year == now.year &&
            createdDateTime.month == now.month &&
            createdDateTime.day == now.day &&
            createdDateTime.isAfter(scheduledTime)) {
          return false; // 🟢 เป็นมื้อที่ผ่านไปแล้วก่อนเพิ่มยา ไม่ต้องเตือนสีแดง
        }
      } catch (e) {
        debugPrint('Error parsing created_at in _isTimeToAlert: $e');
      }
    }

    return true; // 🔴 เตือนสีแดงเมื่อถึงเวลาจริง
  }

  Future<void> _updateMedicationSettings(Map<String, dynamic> med) async {
    try {
      await _supabase.from('medication_logs').update({
        'is_morning_active': med['is_morning_active'],
        'time_morning': med['time_morning'],
        'is_noon_active': med['is_noon_active'],
        'time_noon': med['time_noon'],
        'is_evening_active': med['is_evening_active'],
        'time_evening': med['time_evening'],
      }).eq('id', med['id']);

      final now = DateTime.now();
      for (var meal in ['morning', 'noon', 'evening']) {
        final int baseId = _generateBaseId(med['id'].toString(), meal);
        await NotificationService().cancelAllAlarmsForMeal(baseId);
        if (med['is_${meal}_active'] == true &&
            med['time_$meal'] != null &&
            med['time_$meal'].toString().contains(':')) {
          final parts = med['time_$meal'].toString().split(':');
          final scheduledTime = DateTime(
            now.year,
            now.month,
            now.day,
            int.parse(parts[0]),
            int.parse(parts[1]),
          );
          String label = meal == 'morning'
              ? 'เช้า'
              : meal == 'noon'
                  ? 'กลางวัน'
                  : 'เย็น';
          await NotificationService().scheduleMedicationWithSnooze(
            baseId: baseId,
            title: '💊 ได้เวลาทานยา ($label)',
            body: 'อย่าลืมทานยา: ${med['medication_name']}',
            scheduledTime: scheduledTime,
          );
        }
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('บันทึกเวลาเตือนสำเร็จ'),
              backgroundColor: emeraldColor),
        );
      }
    } catch (e) {
      debugPrint('❌ Error in _updateMedicationSettings: $e');
    }
  }

  Future<void> _markAsTaken(
      Map<String, dynamic> med, String mealType, String timeStr) async {
    try {
      final patientId = await _profileService.getCurrentPatientId();
      if (patientId == null) throw Exception('ไม่พบรหัสผู้ป่วย');

      final String medUuid = med['id'].toString();
      final DateTime now = DateTime.now();
      final String todayDate = now.toIso8601String().split('T')[0];

      setState(() {
        if (!_todayAdherence.any((log) =>
            log['medication_id'].toString() == medUuid &&
            log['meal_type'] == mealType)) {
          _todayAdherence.add({
            'medication_id': medUuid,
            'meal_type': mealType,
            'taken_date': todayDate,
            'taken_at': now.toIso8601String(),
          });
        }
      });

      try {
        await _supabase.from('medication_adherence_logs').upsert({
          'patient_id': patientId,
          'medication_id': medUuid,
          'medication_name': med['medication_name'].toString(),
          'meal_type': mealType,
          'taken_date': todayDate,
          'taken_at': now.toUtc().toIso8601String(),
        }, onConflict: 'patient_id, medication_id, meal_type, taken_date');
      } catch (dbError) {
        debugPrint('❌ Supabase Upsert Error: $dbError');
        await _loadAdherenceLogs();
        if (mounted) setState(() {});
        return;
      }

      try {
        final int baseId = _generateBaseId(medUuid, mealType);
        final parts = timeStr.split(':');
        final scheduledTime = DateTime(now.year, now.month, now.day,
            int.parse(parts[0]), int.parse(parts[1]));
        String mealLabel = mealType == 'morning'
            ? 'เช้า'
            : mealType == 'noon'
                ? 'กลางวัน'
                : 'เย็น';

        await NotificationService().stopSnoozeForToday(
          baseId: baseId,
          scheduledTime: scheduledTime,
          title: '💊 ได้เวลาทานยา ($mealLabel)',
          body: 'อย่าลืมทานยา: ${med['medication_name']}',
        );
      } catch (notifError) {
        debugPrint('❌ Notification Lifecycle Error: $notifError');
      }

      await _loadAdherenceLogs();
      if (mounted) setState(() {});
    } catch (e) {
      debugPrint('❌ Fatal Error in _markAsTaken: $e');
      await _loadAdherenceLogs();
      if (mounted) setState(() {});
    }
  }

  Future<void> _selectTime(
      BuildContext context, Map<String, dynamic> med, String timeKey) async {
    TimeOfDay initialTime = TimeOfDay.now();
    if (med[timeKey] != null && med[timeKey].toString().contains(':')) {
      final parts = med[timeKey].toString().split(':');
      initialTime =
          TimeOfDay(hour: int.parse(parts[0]), minute: int.parse(parts[1]));
    }
    final TimeOfDay? picked = await showTimePicker(
      context: context,
      initialTime: initialTime,
      builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true),
          child: child!),
    );
    if (picked != null) {
      setState(() {
        med[timeKey] =
            '${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}';
        if (timeKey == 'time_morning') med['is_morning_active'] = true;
        if (timeKey == 'time_noon') med['is_noon_active'] = true;
        if (timeKey == 'time_evening') med['is_evening_active'] = true;
      });
      _updateMedicationSettings(med);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: const Text('รายการยาและการแจ้งเตือน',
            style: TextStyle(color: slateColor, fontWeight: FontWeight.bold)),
        backgroundColor: Colors.white,
        elevation: 0,
        iconTheme: const IconThemeData(color: slateColor),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: emeraldColor))
          : _isProcessingImage
              ? const Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      CircularProgressIndicator(color: emeraldColor),
                      SizedBox(height: 16),
                      Text('กำลังให้ AI วิเคราะห์ฉลากยา...',
                          style: TextStyle(color: slateColor)),
                    ],
                  ),
                )
              : _medications.isEmpty
                  ? const Center(
                      child: Text('ยังไม่มีรายการยาในระบบ',
                          style: TextStyle(color: Colors.grey)))
                  : ListView.builder(
                      // 📍 เพิ่ม bottom padding 90 ป้องกันปุ่มล่างสุดบัง Card ยา
                      padding: const EdgeInsets.only(
                          left: 16, right: 16, top: 16, bottom: 90),
                      itemCount: _medications.length,
                      itemBuilder: (context, index) {
                        final med = _medications[index];
                        return Card(
                          margin: const EdgeInsets.only(bottom: 16),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16)),
                          elevation: 2,
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    const Icon(Icons.medication_liquid_rounded,
                                        color: emeraldColor, size: 30),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Text(
                                        med['medication_name'] ??
                                            'ไม่ทราบชื่อยา',
                                        style: const TextStyle(
                                            fontSize: 18,
                                            fontWeight: FontWeight.bold,
                                            color: slateColor),
                                      ),
                                    ),
                                    IconButton(
                                      icon: const Icon(Icons.delete_outline,
                                          color: Colors.red),
                                      onPressed: () => _deleteMedication(med),
                                    ),
                                  ],
                                ),
                                if (med['dosage_instruction'] != null &&
                                    med['dosage_instruction']
                                        .toString()
                                        .isNotEmpty) ...[
                                  const SizedBox(height: 8),
                                  Text('วิธีใช้: ${med['dosage_instruction']}',
                                      style: TextStyle(
                                          color: Colors.grey.shade700)),
                                ],
                                const Divider(height: 24, thickness: 1),
                                _buildTimeRow(
                                    context,
                                    med,
                                    'เช้า',
                                    'time_morning',
                                    'is_morning_active',
                                    'morning'),
                                _buildTimeRow(context, med, 'กลางวัน',
                                    'time_noon', 'is_noon_active', 'noon'),
                                _buildTimeRow(
                                    context,
                                    med,
                                    'เย็น',
                                    'time_evening',
                                    'is_evening_active',
                                    'evening'),
                              ],
                            ),
                          ),
                        );
                      },
                    ),

      // 📍 2. ย้ายปุ่มมาวางตรงกลางจอด้านล่างคู่กันอย่างสวยงาม ไม่บังปุ่มตั้งเวลา
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
      floatingActionButton: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(
          children: [
            // ปุ่มเพิ่มยาแบบพิมพ์เอง (Manual)
            Expanded(
              child: FloatingActionButton.extended(
                heroTag: 'btn_manual_add_med',
                backgroundColor: Colors.white,
                elevation: 3,
                onPressed: () => _showAddMedicationDialog(context),
                icon: const Icon(Icons.edit_note_rounded, color: emeraldColor),
                label: const Text(
                  'พิมพ์เพิ่มเอง',
                  style: TextStyle(
                      color: emeraldColor, fontWeight: FontWeight.bold),
                ),
              ),
            ),
            const SizedBox(width: 12),

            // ปุ่มถ่ายรูปฉลากยา (AI)
            Expanded(
              child: FloatingActionButton.extended(
                heroTag: 'btn_camera_add_med',
                backgroundColor: emeraldColor,
                elevation: 3,
                onPressed: _scanMedication,
                icon: const Icon(Icons.camera_alt, color: Colors.white),
                label: const Text(
                  'ถ่ายรูปฉลากยา',
                  style: TextStyle(
                      color: Colors.white, fontWeight: FontWeight.bold),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTimeRow(
    BuildContext context,
    Map<String, dynamic> med,
    String label,
    String timeKey,
    String activeKey,
    String mealType,
  ) {
    final bool isActive = med[activeKey] == true;
    final String timeStr = med[timeKey] ?? 'เลือกเวลา';
    final bool isTaken =
        _isMedicationTakenToday(med['id'].toString(), mealType);

    // 📍 ส่งค่าเวลาที่บันทึกยา (รองรับทั้ง created_at และ recorded_at)
    final bool shouldAlert = _isTimeToAlert(
      med[timeKey],
      isActive,
      isTaken,
      createdAt: med['created_at'] ?? med['recorded_at'],
    );

    Color bgColor = isActive
        ? (isTaken
            ? emeraldColor.withOpacity(0.1)
            : (shouldAlert
                ? Colors.red.shade50
                : emeraldColor.withOpacity(0.1)))
        : Colors.grey.shade100;
    Color textColor = isActive
        ? (isTaken
            ? emeraldColor
            : (shouldAlert ? Colors.red.shade700 : emeraldColor))
        : Colors.grey;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Icon(Icons.access_time_rounded,
                      size: 20, color: isActive ? textColor : Colors.grey),
                  const SizedBox(width: 8),
                  Text(
                    label,
                    style: TextStyle(
                        fontSize: 16,
                        color: isActive ? slateColor : Colors.grey,
                        fontWeight:
                            isActive ? FontWeight.w600 : FontWeight.normal),
                  ),
                ],
              ),
              Row(
                children: [
                  InkWell(
                    onTap: () => _selectTime(context, med, timeKey),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                          color: bgColor,
                          borderRadius: BorderRadius.circular(8)),
                      child: Text(timeStr,
                          style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: textColor)),
                    ),
                  ),
                  Switch(
                    value: isActive,
                    activeColor: emeraldColor,
                    onChanged: (val) {
                      setState(() => med[activeKey] = val);
                      _updateMedicationSettings(med);
                    },
                  ),
                ],
              ),
            ],
          ),
        ),
        if (shouldAlert)
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: () => _markAsTaken(med, mealType, timeStr),
              icon: const Icon(Icons.warning_amber_rounded,
                  color: Colors.red, size: 20),
              label: const Text('ถึงเวลาทานยา (กดเพื่อบันทึก)',
                  style: TextStyle(
                      color: Colors.red, fontWeight: FontWeight.bold)),
              style: TextButton.styleFrom(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                backgroundColor: Colors.red.shade50,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20)),
              ),
            ),
          ),
        if (isActive && isTaken)
          Align(
            alignment: Alignment.centerRight,
            child: Padding(
              padding:
                  const EdgeInsets.symmetric(vertical: 8.0, horizontal: 12.0),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: const [
                  Icon(Icons.check_circle, color: emeraldColor, size: 20),
                  SizedBox(width: 6),
                  Text('ทานยานี้แล้ว',
                      style: TextStyle(
                          color: emeraldColor, fontWeight: FontWeight.bold)),
                ],
              ),
            ),
          ),
        const SizedBox(height: 8),
      ],
    );
  }

  Future<void> _showAddMedicationDialog(BuildContext context) async {
    final nameController = TextEditingController();
    final dosageController = TextEditingController();

    TimeOfDay morningTime = const TimeOfDay(hour: 8, minute: 0);
    TimeOfDay noonTime = const TimeOfDay(hour: 12, minute: 0);
    TimeOfDay eveningTime = const TimeOfDay(hour: 18, minute: 0);

    bool isMorningActive = true;
    bool isNoonActive = false;
    bool isEveningActive = true;

    await showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            String formatTime(TimeOfDay time) {
              return '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
            }

            return AlertDialog(
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16)),
              title: Row(
                children: const [
                  Icon(Icons.medication, color: emeraldColor),
                  SizedBox(width: 8),
                  Text('เพิ่มยาใหม่ (Manual)',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                ],
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextField(
                      controller: nameController,
                      decoration: const InputDecoration(
                        labelText: 'ชื่อยา *',
                        hintText: 'เช่น พาราเซตามอล 500mg',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: dosageController,
                      decoration: const InputDecoration(
                        labelText: 'วิธีรับประทาน / คำแนะนำ',
                        hintText: 'เช่น รับประทานครั้งละ 1 เม็ด หลังอาหาร',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 16),
                    const Text('ตั้งเวลารับประทานยา:',
                        style: TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 15)),
                    const SizedBox(height: 8),
                    CheckboxListTile(
                      title: Text('เช้า (${formatTime(morningTime)})'),
                      value: isMorningActive,
                      activeColor: emeraldColor,
                      onChanged: (val) =>
                          setDialogState(() => isMorningActive = val ?? false),
                      secondary: IconButton(
                        icon: const Icon(Icons.access_time),
                        onPressed: () async {
                          final picked = await showTimePicker(
                              context: context, initialTime: morningTime);
                          if (picked != null)
                            setDialogState(() => morningTime = picked);
                        },
                      ),
                    ),
                    CheckboxListTile(
                      title: Text('กลางวัน (${formatTime(noonTime)})'),
                      value: isNoonActive,
                      activeColor: emeraldColor,
                      onChanged: (val) =>
                          setDialogState(() => isNoonActive = val ?? false),
                      secondary: IconButton(
                        icon: const Icon(Icons.access_time),
                        onPressed: () async {
                          final picked = await showTimePicker(
                              context: context, initialTime: noonTime);
                          if (picked != null)
                            setDialogState(() => noonTime = picked);
                        },
                      ),
                    ),
                    CheckboxListTile(
                      title: Text('เย็น (${formatTime(eveningTime)})'),
                      value: isEveningActive,
                      activeColor: emeraldColor,
                      onChanged: (val) =>
                          setDialogState(() => isEveningActive = val ?? false),
                      secondary: IconButton(
                        icon: const Icon(Icons.access_time),
                        onPressed: () async {
                          final picked = await showTimePicker(
                              context: context, initialTime: eveningTime);
                          if (picked != null)
                            setDialogState(() => eveningTime = picked);
                        },
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('ยกเลิก',
                        style: TextStyle(color: Colors.grey))),
                ElevatedButton(
                  style:
                      ElevatedButton.styleFrom(backgroundColor: emeraldColor),
                  onPressed: () async {
                    if (nameController.text.trim().isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('กรุณากรอกชื่อยา')));
                      return;
                    }

                    await _saveManualMedication(
                      name: nameController.text.trim(),
                      dosage: dosageController.text.trim(),
                      timeMorning: formatTime(morningTime),
                      isMorningActive: isMorningActive,
                      timeNoon: formatTime(noonTime),
                      isNoonActive: isNoonActive,
                      timeEvening: formatTime(eveningTime),
                      isEveningActive: isEveningActive,
                    );

                    if (context.mounted) Navigator.pop(context);
                  },
                  child: const Text('บันทึก',
                      style: TextStyle(color: Colors.white)),
                ),
              ],
            );
          },
        );
      },
    );
  }

  // 📍 1. แก้ชื่อตารางเป็น medication_logs และบันทึกเวลา recorded_at
  Future<void> _saveManualMedication({
    required String name,
    required String dosage,
    required String timeMorning,
    required bool isMorningActive,
    required String timeNoon,
    required bool isNoonActive,
    required String timeEvening,
    required bool isEveningActive,
  }) async {
    try {
      final patientId = await _profileService.getCurrentPatientId();
      if (patientId == null) throw Exception('ไม่พบรหัสผู้ป่วย');

      final now = DateTime.now();

      await _supabase.from('medication_logs').insert({
        'patient_id': patientId,
        'medication_name': name,
        'dosage_instruction': dosage,
        'time_morning': timeMorning,
        'is_morning_active': isMorningActive,
        'time_noon': timeNoon,
        'is_noon_active': isNoonActive,
        'time_evening': timeEvening,
        'is_evening_active': isEveningActive,
        'recorded_at': now.toUtc().toIso8601String(), // ⚠️ คอลัมน์หลักฝั่ง .apk
        'created_at': now.toIso8601String(),
      });

      if (mounted) {
        await _loadMedications();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('เพิ่มข้อมูลยาเรียบร้อยแล้ว'),
              backgroundColor: emeraldColor),
        );
      }
    } catch (e) {
      debugPrint('❌ Error saving manual medication: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('เกิดข้อผิดพลาดในการบันทึกยา: $e'),
              backgroundColor: Colors.red),
        );
      }
    }
  }
}
