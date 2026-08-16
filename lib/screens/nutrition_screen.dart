import 'dart:io';
import 'package:flutter/material.dart';
import 'package:record/record.dart';
import 'package:path_provider/path_provider.dart';
import '../services/patient_profile_service.dart';
import '../services/nutrition_service.dart';
import '../services/vital_repository.dart';

class NutritionScreen extends StatefulWidget {
  const NutritionScreen({super.key});

  @override
  State<NutritionScreen> createState() => _NutritionScreenState();
}

class _NutritionScreenState extends State<NutritionScreen> {
  final _profileService = PatientProfileService();
  final _nutritionService = NutritionService();
  final _vitalRepository = VitalRepository();
  final _foodInputController = TextEditingController();
  final _audioRecorder = AudioRecorder();

  bool _isLoading = true;
  bool _isAnalyzing = false;
  bool _isRecording = false;

  String? _patientId;
  String _underlyingDiseases = '';
  double _tdee = 2000.0;
  int _latestSystolic = 120;

  List<Map<String, dynamic>> _todayFoods = [];
  List<Map<String, dynamic>> _todayExercises = [];

  static const Color emeraldColor = Color(0xFF10B981);
  static const Color slateColor = Color(0xFF334155);

  @override
  void initState() {
    super.initState();
    _loadDashboardData();
  }

  @override
  void dispose() {
    _foodInputController.dispose();
    _audioRecorder.dispose();
    super.dispose();
  }

  Future<void> _loadDashboardData() async {
    setState(() => _isLoading = true);
    try {
      final patientId = await _profileService.getCurrentPatientId();
      final profile = await _profileService.getProfile();

      if (patientId != null) {
        _patientId = patientId;
        _tdee = (profile?['tdee'] as num?)?.toDouble() ?? 2000.0;
        _underlyingDiseases = profile?['underlying_diseases'] ?? '';

        final vitals = await _vitalRepository.getLast7Days(patientId);
        if (vitals.isNotEmpty) {
          _latestSystolic = (vitals.first['systolic'] as num?)?.toInt() ?? 120;
        }

        _todayFoods = await _nutritionService.getTodayFoodLogs(patientId);
        _todayExercises =
            await _nutritionService.getTodayExerciseLogs(patientId);
      }
    } catch (e) {
      debugPrint('Error loading nutrition dashboard: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // 🎙️ เริ่มอัดเสียงพูดชื่ออาหาร
  Future<void> _startRecording() async {
    try {
      if (await _audioRecorder.hasPermission()) {
        final dir = await getTemporaryDirectory();
        final filePath =
            '${dir.path}/food_voice_${DateTime.now().millisecondsSinceEpoch}.m4a';

        const config = RecordConfig(
            encoder: AudioEncoder.aacLc, bitRate: 128000, sampleRate: 44100);
        await _audioRecorder.start(config, path: filePath);

        setState(() => _isRecording = true);
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content: Text('กรุณาอนุญาตสิทธิ์ไมโครโฟนเพื่อบันทึกเสียง')),
          );
        }
      }
    } catch (e) {
      debugPrint('Error starting audio recording: $e');
    }
  }

  // ⏹️ หยุดอัดเสียง และส่งให้ Gemini ถอดเสียง + วิเคราะห์สารอาหาร
  Future<void> _stopRecordingAndAnalyze() async {
    try {
      final path = await _audioRecorder.stop();
      setState(() {
        _isRecording = false;
        _isAnalyzing = true;
      });

      if (path != null && _patientId != null) {
        final audioFile = File(path);
        if (await audioFile.exists()) {
          final result = await _nutritionService.analyzeFoodFromAudio(
            audioFile: audioFile,
            underlyingDiseases: _underlyingDiseases,
          );

          if (result != null && mounted) {
            _showFoodConfirmDialog(result);
          } else {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                    content: Text(
                        'AI ไม่สามารถถอดเสียงหรือคำนวณอาหารได้ กรุณาลองใหม่')),
              );
            }
          }
        }
      }
    } catch (e) {
      debugPrint('Error stopping recording: $e');
    } finally {
      if (mounted) setState(() => _isAnalyzing = false);
    }
  }

  // 📝 สั่ง AI วิเคราะห์อาหารจากข้อความพิมพ์
  Future<void> _analyzeAndLogFoodFromText() async {
    final text = _foodInputController.text.trim();
    if (text.isEmpty || _patientId == null) return;

    setState(() => _isAnalyzing = true);
    try {
      final result = await _nutritionService.analyzeFoodInput(
        textInput: text,
        underlyingDiseases: _underlyingDiseases,
      );

      if (result != null && mounted) {
        _showFoodConfirmDialog(result);
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content: Text('ไม่สามารถวิเคราะห์ข้อมูลอาหารได้ กรุณาลองใหม่')),
          );
        }
      }
    } finally {
      if (mounted) setState(() => _isAnalyzing = false);
    }
  }

  // ⚠️ Pop-up ยืนยันข้อมูลอาหาร + คำเตือน NCDs
  void _showFoodConfirmDialog(Map<String, dynamic> foodData) {
    final warnings = List<String>.from(foodData['warning_flags'] ?? []);

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: const [
            Icon(Icons.restaurant_menu, color: emeraldColor),
            SizedBox(width: 8),
            Text('ผลการวิเคราะห์อาหาร',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(foodData['food_name'] ?? 'อาหาร',
                  style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: slateColor)),
              const SizedBox(height: 8),
              Text('🔥 พลังงาน: ${foodData['calories']} kcal',
                  style: const TextStyle(
                      fontSize: 16,
                      color: Colors.deepOrange,
                      fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              Text(
                  'คาร์บ: ${foodData['carbs_g']}g | โปรตีน: ${foodData['protein_g']}g | ไขมัน: ${foodData['fat_g']}g',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade700)),
              Text(
                  'โซเดียม: ${foodData['sodium_mg']} mg | น้ำตาล: ${foodData['sugar_g']}g',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade700)),
              if (warnings.isNotEmpty) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                      color: Colors.red.shade50,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.red.shade200)),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: const [
                          Icon(Icons.warning_amber_rounded,
                              color: Colors.red, size: 18),
                          SizedBox(width: 6),
                          Text('ข้อควรระวังสำหรับผู้ป่วย',
                              style: TextStyle(
                                  color: Colors.red,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12)),
                        ],
                      ),
                      const SizedBox(height: 4),
                      ...warnings.map((w) => Text('• $w',
                          style: TextStyle(
                              fontSize: 11, color: Colors.red.shade900))),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child:
                  const Text('ยกเลิก', style: TextStyle(color: Colors.grey))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: emeraldColor),
            onPressed: () async {
              Navigator.pop(context);
              _foodInputController.clear();
              await _nutritionService.saveFoodLog(
                  patientId: _patientId!, foodData: foodData);
              await _loadDashboardData();
            },
            child: const Text('บันทึกมื้อนี้',
                style: TextStyle(
                    color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  // 🏃‍♂️ Quick Exercise Dialog
  void _showAddExerciseDialog() {
    final nameCtrl = TextEditingController(text: 'เดินเร็ว / กายบริหารเบาๆ');
    final minCtrl = TextEditingController(text: '30');

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('บันทึกการออกกำลังกาย',
            style: TextStyle(fontWeight: FontWeight.bold, color: slateColor)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
                controller: nameCtrl,
                decoration: const InputDecoration(
                    labelText: 'กิจกรรม', border: OutlineInputBorder())),
            const SizedBox(height: 12),
            TextField(
                controller: minCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                    labelText: 'ระยะเวลา (นาที)',
                    border: OutlineInputBorder())),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child:
                  const Text('ยกเลิก', style: TextStyle(color: Colors.grey))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: emeraldColor),
            onPressed: () async {
              final mins = int.tryParse(minCtrl.text) ?? 30;
              final burned = mins * 4.0;
              Navigator.pop(context);
              await _nutritionService.saveExerciseLog(
                patientId: _patientId!,
                exerciseName: nameCtrl.text.trim(),
                durationMinutes: mins,
                caloriesBurned: burned,
              );
              await _loadDashboardData();
            },
            child: const Text('บันทึก',
                style: TextStyle(
                    color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final totalFoodCals = _todayFoods.fold<double>(0.0,
        (sum, item) => sum + ((item['calories'] as num?)?.toDouble() ?? 0.0));
    final totalBurnedCals = _todayExercises.fold<double>(
        0.0,
        (sum, item) =>
            sum + ((item['calories_burned'] as num?)?.toDouble() ?? 0.0));
    final netCals = totalFoodCals - totalBurnedCals;
    final targetDeficit = (_tdee - 400).clamp(1200.0, 9999.0);

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: const Text('โภชนาการ & กิจกรรมสุขภาพ',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        backgroundColor: emeraldColor,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: emeraldColor))
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // 1. การ์ดพลังงานรวม Calorie Deficit Bar
                  _buildCalorieBalanceCard(
                      totalFoodCals, totalBurnedCals, netCals, targetDeficit),
                  const SizedBox(height: 16),

                  // 2. Clinical Guard แนะนำการออกกำลังกายตามความดัน
                  _buildExerciseClinicalGuardCard(),
                  const SizedBox(height: 16),

                  // 3. Card บันทึกอาหารด้วยเสียง & ข้อความ AI
                  _buildVoiceAndTextFoodLoggerCard(),
                  const SizedBox(height: 16),

                  // 4. รายการอาหารวันนี้
                  _buildSectionHeader(
                      'รายการอาหารวันนี้ (${_todayFoods.length})',
                      Icons.fastfood_outlined),
                  if (_todayFoods.isEmpty)
                    const Padding(
                        padding: EdgeInsets.symmetric(vertical: 8),
                        child: Text('ยังไม่มีการบันทึกอาหารวันนี้',
                            style: TextStyle(color: Colors.grey)))
                  else
                    ..._todayFoods.map((f) => Card(
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                          child: ListTile(
                            leading: const Icon(Icons.lunch_dining,
                                color: emeraldColor),
                            title: Text(f['food_name'] ?? '',
                                style: const TextStyle(
                                    fontWeight: FontWeight.bold)),
                            subtitle: Text(
                                'โซเดียม: ${f['sodium_mg']} mg | น้ำตาล: ${f['sugar_g']}g'),
                            trailing: Text('${f['calories']} kcal',
                                style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: Colors.deepOrange,
                                    fontSize: 15)),
                          ),
                        )),
                  const SizedBox(height: 16),

                  // 5. รายการออกกำลังกายวันนี้
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      _buildSectionHeader(
                          'การออกกำลังกาย (${_todayExercises.length})',
                          Icons.directions_run),
                      TextButton.icon(
                        onPressed: _showAddExerciseDialog,
                        icon: const Icon(Icons.add,
                            color: emeraldColor, size: 18),
                        label: const Text('เพิ่มกิจกรรม',
                            style: TextStyle(
                                color: emeraldColor,
                                fontWeight: FontWeight.bold)),
                      ),
                    ],
                  ),
                  if (_todayExercises.isEmpty)
                    const Padding(
                        padding: EdgeInsets.symmetric(vertical: 8),
                        child: Text('ยังไม่มีการบันทึกกิจกรรมวันนี้',
                            style: TextStyle(color: Colors.grey)))
                  else
                    ..._todayExercises.map((ex) => Card(
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                          child: ListTile(
                            leading: const Icon(Icons.fitness_center,
                                color: Colors.blue),
                            title: Text(ex['exercise_name'] ?? '',
                                style: const TextStyle(
                                    fontWeight: FontWeight.bold)),
                            subtitle: Text('${ex['duration_minutes']} นาที'),
                            trailing: Text('-${ex['calories_burned']} kcal',
                                style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: Colors.green,
                                    fontSize: 15)),
                          ),
                        )),
                  const SizedBox(height: 32),
                ],
              ),
            ),
    );
  }

  // 🎙️ Card สำหรับบันทึกด้วยเสียง AI + ช่องพิมพ์
  Widget _buildVoiceAndTextFoodLoggerCard() {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: const [
                Text('บันทึกอาหารด้วยเสียง & AI',
                    style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: slateColor)),
                Icon(Icons.auto_awesome, color: emeraldColor),
              ],
            ),
            const SizedBox(height: 16),

            // ปุ่มไมโครโฟนอัดเสียงขนาดใหญ่
            GestureDetector(
              onTap: _isAnalyzing
                  ? null
                  : () {
                      if (_isRecording) {
                        _stopRecordingAndAnalyze();
                      } else {
                        _startRecording();
                      }
                    },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 18),
                decoration: BoxDecoration(
                  color: _isRecording ? Colors.red.shade500 : emeraldColor,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: (_isRecording ? Colors.red : emeraldColor)
                          .withOpacity(0.3),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (_isAnalyzing)
                      const SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(
                              color: Colors.white, strokeWidth: 2.5))
                    else
                      Icon(
                          _isRecording
                              ? Icons.stop_circle_rounded
                              : Icons.mic_rounded,
                          color: Colors.white,
                          size: 28),
                    const SizedBox(width: 10),
                    Text(
                      _isAnalyzing
                          ? 'AI กำลังฟังเสียงและวิเคราะห์...'
                          : (_isRecording
                              ? 'กำลังฟังเสียง... (กดเพื่อส่งวิเคราะห์)'
                              : 'กดปุ่มนี้ แล้วพูดชื่ออาหาร'),
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Divider หรือพิมพ์ข้อความ
            Row(
              children: const [
                Expanded(child: Divider()),
                Padding(
                    padding: EdgeInsets.symmetric(horizontal: 10),
                    child: Text('หรือพิมพ์รายการอาหาร',
                        style: TextStyle(color: Colors.grey, fontSize: 12))),
                Expanded(child: Divider()),
              ],
            ),
            const SizedBox(height: 12),

            // ช่องพิมพ์ข้อความ
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _foodInputController,
                    decoration: InputDecoration(
                      hintText: 'เช่น สลัดอกไก่ 7-11 หรือ เกาเหลาเลือดหมู',
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12)),
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 12),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  icon: const Icon(Icons.send_rounded, color: emeraldColor),
                  onPressed: _isAnalyzing ? null : _analyzeAndLogFoodFromText,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCalorieBalanceCard(
      double food, double burned, double net, double target) {
    final progress = (net / target).clamp(0.0, 1.0);
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('สมดุลพลังงานสุทธิวันนี้ (Net Calories)',
                    style: TextStyle(
                        fontWeight: FontWeight.bold, color: slateColor)),
                Text(
                    '${net.toStringAsFixed(0)} / ${target.toStringAsFixed(0)} kcal',
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, color: emeraldColor)),
              ],
            ),
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: LinearProgressIndicator(
                value: progress,
                minHeight: 12,
                backgroundColor: Colors.grey.shade200,
                valueColor: AlwaysStoppedAnimation<Color>(
                    net > target ? Colors.red : emeraldColor),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildCalMiniInfo('รับประทาน',
                    '${food.toStringAsFixed(0)} kcal', Colors.deepOrange),
                _buildCalMiniInfo('เผาผลาญ',
                    '-${burned.toStringAsFixed(0)} kcal', Colors.green),
                _buildCalMiniInfo('เป้าหมาย Deficit',
                    '${target.toStringAsFixed(0)} kcal', slateColor),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCalMiniInfo(String label, String val, Color c) {
    return Column(
      children: [
        Text(label, style: const TextStyle(fontSize: 11, color: Colors.grey)),
        const SizedBox(height: 2),
        Text(val,
            style:
                TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: c)),
      ],
    );
  }

  Widget _buildExerciseClinicalGuardCard() {
    final isHighBp = _latestSystolic >= 160;
    final isLowBp = _latestSystolic <= 90;

    Color cardBg = isHighBp
        ? Colors.red.shade50
        : (isLowBp ? Colors.orange.shade50 : Colors.teal.shade50);
    Color borderColor = isHighBp
        ? Colors.red.shade200
        : (isLowBp ? Colors.orange.shade200 : Colors.teal.shade200);
    IconData icon = isHighBp
        ? Icons.warning_rounded
        : (isLowBp ? Icons.info_outline : Icons.check_circle_outline);
    Color iconColor =
        isHighBp ? Colors.red : (isLowBp ? Colors.orange : Colors.teal);

    String title = isHighBp
        ? '⚠️ ความดันตัวบนวันนี้สูง ($_latestSystolic mmHg) - งดออกแรงหนัก'
        : (isLowBp
            ? '⚠️ ความดันตัวบนค่อนข้างต่ำ ($_latestSystolic mmHg) - ระวังหน้ามืด'
            : '✅ ความดันปกติ ($_latestSystolic mmHg) - ออกกำลังกายได้ปลอดภัย');

    String desc = isHighBp
        ? 'งดการวิ่งหรือยกน้ำหนักหนักในวันนี้ แนะนำฝึกสมาธิ กำหนดลมหายใจ และพักผ่อน'
        : (isLowBp
            ? 'ควรจิบน้ำบ่อยๆ หลีกเลี่ยงการเปลี่ยนท่าทางกะทันหัน เน้นการยืดเหยียดเบาๆ'
            : 'แนะนำออกกำลังกายแบบแอโรบิกปานกลาง เช่น เดินเร็ว 20-30 นาที/วัน');

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
          color: cardBg,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: borderColor)),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: iconColor, size: 24),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: iconColor)),
                const SizedBox(height: 4),
                Text(desc,
                    style:
                        TextStyle(fontSize: 12, color: Colors.grey.shade800)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title, IconData icon) {
    return Row(
      children: [
        Icon(icon, color: emeraldColor, size: 20),
        const SizedBox(width: 8),
        Text(title,
            style: const TextStyle(
                fontSize: 16, fontWeight: FontWeight.bold, color: slateColor)),
      ],
    );
  }
}
