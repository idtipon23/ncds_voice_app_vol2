import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../config/app_config.dart';
import '../services/patient_profile_service.dart';
import '../services/patient_database_service.dart';
import '../services/voice_health_service.dart';

class LabResultsScreen extends StatefulWidget {
  const LabResultsScreen({super.key});

  @override
  State<LabResultsScreen> createState() => _LabResultsScreenState();
}

class _LabResultsScreenState extends State<LabResultsScreen> {
  final PatientProfileService _profileService = PatientProfileService();
  final PatientDatabaseService _dbService = PatientDatabaseService();
  late VoiceHealthService _voiceService;

  List<Map<String, dynamic>> _labResults = [];
  bool _isLoading = true;
  bool _isProcessingImage = false;

  static const Color emeraldColor = Color(0xFF10B981);
  static const Color slateColor = Color(0xFF334155);

  @override
  void initState() {
    super.initState();
    _voiceService = VoiceHealthService(AppConfig.geminiApiKey);
    _loadLabResults();
  }

  // 1. ดึงประวัติผลแล็บ (ใช้ Lazy Loading ผ่าน ListView.builder)
  Future<void> _loadLabResults() async {
    setState(() => _isLoading = true);
    try {
      final patientId = await _profileService.getCurrentPatientId();
      if (patientId != null) {
        final labs = await _dbService.getLabResults(patientId);
        setState(() => _labResults = labs);
      }
    } catch (e) {
      debugPrint("Load labs error: $e");
    } finally {
      setState(() => _isLoading = false);
    }
  }

  // 2. ฟังก์ชันถ่ายภาพใบแล็บพร้อมจำกัดขนาด (Anti-OOM Protection เทียบเคียงระบบยา)
  Future<void> _scanLabReport() async {
    final ImagePicker picker = ImagePicker();
    final XFile? image = await picker.pickImage(
      source: ImageSource.camera,
      maxWidth: 1024,   // 🛡️ ป้องกันหน่วยความจำล้น
      maxHeight: 1024,  // 🛡️ ป้องกันหน่วยความจำล้น
      imageQuality: 70, // 🛡️ บีบอัดขนาดไฟล์
    );

    if (image == null) return;
    File imageFile = File(image.path);

    setState(() => _isProcessingImage = true);

    try {
      // ส่งรูปให้ AI สกัดค่าตัวเลขผลแล็บ
      final labData = await _voiceService.processLabReportImage(imageFile);

      if (labData != null && mounted) {
        _showConfirmLabDialog(labData, imageFile);
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('AI ไม่สามารถอ่านใบแล็บได้ กรุณาถ่ายภาพให้ชัดเจนขึ้น')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('เกิดข้อผิดพลาด: $e')));
      }
    } finally {
      setState(() => _isProcessingImage = false);
    }
  }

  // 3. Popup ยืนยันข้อมูลผลแล็บก่อนบันทึก
  void _showConfirmLabDialog(Map<String, dynamic> labData, File imageFile) {
    // 📍 แก้ไข: แปลงค่าที่ได้จาก AI (labData) ด้วย num? ป้องกันการแครช
    final double tcVal = (labData['total_cholesterol'] as num?)?.toDouble() ?? 0.0;
    final double hdlVal = (labData['hdl'] as num?)?.toDouble() ?? 0.0;
    final double ldlVal = (labData['ldl'] as num?)?.toDouble() ?? 0.0;
    final double fbsVal = (labData['fasting_blood_sugar'] as num?)?.toDouble() ?? 0.0;
    final double crVal = (labData['creatinine'] as num?)?.toDouble() ?? 0.0;

    // นำค่าไปใส่ใน Controller
    final tcCtrl = TextEditingController(text: tcVal > 0 ? tcVal.toString() : '');
    final hdlCtrl = TextEditingController(text: hdlVal > 0 ? hdlVal.toString() : '');
    final ldlCtrl = TextEditingController(text: ldlVal > 0 ? ldlVal.toString() : '');
    final fbsCtrl = TextEditingController(text: fbsVal > 0 ? fbsVal.toString() : '');
    final crCtrl = TextEditingController(text: crVal > 0 ? crVal.toString() : '');

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('ตรวจสอบผลตรวจเลือด (Lab)', style: TextStyle(color: slateColor, fontWeight: FontWeight.bold)),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Image.file(
                    imageFile,
                    height: 120,
                    width: double.infinity,
                    fit: BoxFit.cover,
                  ),
                ),
                const SizedBox(height: 12),
                const Text('AI ได้ดึงค่าตัวเลขจากใบแล็บ กรุณาตรวจสอบความถูกต้อง', style: TextStyle(fontSize: 12, color: Colors.grey)),
                const SizedBox(height: 12),
                TextField(controller: tcCtrl, decoration: const InputDecoration(labelText: 'Total Cholesterol (mg/dL)', border: OutlineInputBorder()), keyboardType: TextInputType.number),
                const SizedBox(height: 8),
                TextField(controller: hdlCtrl, decoration: const InputDecoration(labelText: 'HDL (mg/dL)', border: OutlineInputBorder()), keyboardType: TextInputType.number),
                const SizedBox(height: 8),
                TextField(controller: ldlCtrl, decoration: const InputDecoration(labelText: 'LDL (mg/dL)', border: OutlineInputBorder()), keyboardType: TextInputType.number),
                const SizedBox(height: 8),
                TextField(controller: fbsCtrl, decoration: const InputDecoration(labelText: 'Fasting Blood Sugar (mg/dL)', border: OutlineInputBorder()), keyboardType: TextInputType.number),
                const SizedBox(height: 8),
                TextField(controller: crCtrl, decoration: const InputDecoration(labelText: 'Creatinine (mg/dL)', border: OutlineInputBorder()), keyboardType: TextInputType.number),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('ยกเลิก', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: emeraldColor,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: () async {
              Navigator.pop(ctx);
              await _saveLabResult(
                double.tryParse(tcCtrl.text) ?? 0.0,
                double.tryParse(hdlCtrl.text) ?? 0.0,
                double.tryParse(ldlCtrl.text) ?? 0.0,
                double.tryParse(fbsCtrl.text) ?? 0.0,
                double.tryParse(crCtrl.text) ?? 0.0,
                imageFile,
              );
            },
            child: const Text('บันทึกผลแล็บ', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  // 4. บันทึกผลแล็บลง Database
  Future<void> _saveLabResult(double tc, double hdl, double ldl, double fbs, double cr, File imageFile) async {
    setState(() => _isLoading = true);
    try {
      final patientId = await _profileService.getCurrentPatientId();
      if (patientId == null) throw Exception('ไม่พบรหัสผู้ป่วย กรุณาเข้าสู่ระบบใหม่');

      // อัปโหลดรูปภาพใบแล็บ
      final imagePath = await _dbService.uploadMedicationImage(imageFile, patientId);

      await _dbService.saveLabResult(
        patientId: patientId,
        totalCholesterol: tc,
        hdl: hdl,
        ldl: ldl,
        fastingBloodSugar: fbs,
        creatinine: cr,
        imageUrl: imagePath,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('บันทึกผลแล็บสำเร็จ! พร้อมนำไปคำนวณ Thai CV Risk'), backgroundColor: emeraldColor),
        );
      }
      _loadLabResults();
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('เกิดข้อผิดพลาด: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        title: const Text('ผลตรวจสุขภาพและแล็บ', style: TextStyle(color: slateColor, fontWeight: FontWeight.bold)),
        leading: IconButton(icon: const Icon(Icons.arrow_back_ios_new_rounded, color: slateColor), onPressed: () => Navigator.pop(context)),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: emeraldColor))
          : _isProcessingImage
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const CircularProgressIndicator(color: emeraldColor),
                      const SizedBox(height: 16),
                      Text('AI กำลังสกัดค่าผลแล็บจากรูปภาพ...', style: TextStyle(color: Colors.grey.shade700)),
                    ],
                  ),
                )
              : _labResults.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.science_rounded, size: 80, color: Colors.grey.shade300),
                          const SizedBox(height: 16),
                          const Text('ยังไม่มีประวัติผลตรวจแล็บ', style: TextStyle(fontSize: 18, color: Colors.grey)),
                        ],
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: _labResults.length,
                      itemBuilder: (context, index) {
                        final lab = _labResults[index];
                        
                        // 📍 แก้ไข: ใช้ Type Casting อย่างปลอดภัยก่อนดึงไปแสดงผล
                        final double? tcVal = (lab['total_cholesterol'] as num?)?.toDouble();
                        final double? hdlVal = (lab['hdl'] as num?)?.toDouble();
                        final double? ldlVal = (lab['ldl'] as num?)?.toDouble();
                        final double? fbsVal = (lab['fasting_blood_sugar'] as num?)?.toDouble();

                        return Card(
                          margin: const EdgeInsets.only(bottom: 16),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                          elevation: 2,
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    const Text('ผลตรวจเลือด (Lab Report)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: slateColor)),
                                    Text(lab['test_date']?.toString().substring(0, 10) ?? '', style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
                                  ],
                                ),
                                const Divider(height: 16),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text('Total Cholesterol: ${tcVal != null ? tcVal.toStringAsFixed(1) : '-'} mg/dL'),
                                    Text('HDL: ${hdlVal != null ? hdlVal.toStringAsFixed(1) : '-'} mg/dL'),
                                  ],
                                ),
                                const SizedBox(height: 4),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text('LDL: ${ldlVal != null ? ldlVal.toStringAsFixed(1) : '-'} mg/dL'),
                                    Text('FBS: ${fbsVal != null ? fbsVal.toStringAsFixed(1) : '-'} mg/dL'),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: emeraldColor,
        onPressed: _scanLabReport,
        icon: const Icon(Icons.camera_alt, color: Colors.white),
        label: const Text('ถ่ายรูปใบแล็บ', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
      ),
    );
  }
}