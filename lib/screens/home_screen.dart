import 'package:flutter/material.dart';
import '../services/patient_profile_service.dart';
import '../services/vital_repository.dart';
import '../services/nutrition_service.dart'; // 📍 นำเข้า NutritionService
import 'vital_sign_record_screen.dart';
import 'health_history_screen.dart';
import 'patient_profile_screen.dart';
import 'medication_history_screen.dart';
import 'nutrition_screen.dart';
import 'ht_consult_screen.dart'; // 📍 นำเข้าหน้า HT Consult

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final PatientProfileService _profileService = PatientProfileService();
  final VitalRepository _vitalRepo = VitalRepository();
  final NutritionService _nutritionService = NutritionService();

  static const Color emeraldColor = Color(0xFF10B981);
  static const Color slateColor = Color(0xFF334155);

  bool _isLoading = true;
  String _patientName = "ผู้ใช้งาน";
  double _avgSys7Days = 0;
  double _avgDia7Days = 0;
  bool _hasVitalData = false;

  Map<String, dynamic>? _profileData;

  // 📍 ตัวแปรสำหรับคำแนะนำรายวัน
  List<Map<String, dynamic>> _todayFoodLogs = [];

  @override
  void initState() {
    super.initState();
    _loadDashboardData();
  }

  // 📍 โหลดข้อมูล Profile, ค่าวัดสัญญาณชีพเฉลี่ย 7 วัน, และข้อมูลอาหารวันนี้
  Future<void> _loadDashboardData() async {
    setState(() => _isLoading = true);
    try {
      final patientId = await _profileService.getCurrentPatientId();
      final profile = await _profileService.getProfile();

      _profileData = await _profileService.getProfile();

      if (profile != null) {
        _patientName = profile['first_name'] ?? profile['name'] ?? "ผู้ใช้งาน";
      }

      if (patientId != null && patientId.isNotEmpty) {
        // 1. ดึงค่าวัดสัญญาณชีพ 7 วันล่าสุด
        final vitals = await _vitalRepo.getLast7Days(patientId);
        if (vitals.isNotEmpty) {
          _hasVitalData = true;
          double sumSys = 0;
          double sumDia = 0;
          for (var v in vitals) {
            sumSys += (v['systolic'] as num?)?.toDouble() ?? 0;
            sumDia += (v['diastolic'] as num?)?.toDouble() ?? 0;
          }
          _avgSys7Days = sumSys / vitals.length;
          _avgDia7Days = sumDia / vitals.length;
        }

        // 2. ดึงรายการอาหารของวันนี้
        try {
          _todayFoodLogs = await _nutritionService.getTodayFoodLogs(patientId);
        } catch (e) {
          debugPrint('Error loading today food logs: $e');
        }
      }
    } catch (e) {
      debugPrint('Error loading dashboard: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      body: Stack(
        children: [
          // 🎨 Background Decorative Gradient
          Positioned(
            top: -100,
            right: -100,
            child: Container(
              width: 300,
              height: 300,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: emeraldColor.withOpacity(0.15),
              ),
            ),
          ),

          // 📋 เนื้อหาหลักของหน้าจอ
          SafeArea(
            child: _isLoading
                ? const Center(
                    child: CircularProgressIndicator(color: emeraldColor))
                : SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 20, vertical: 10),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // --- ส่วนหัว (Greeting) ---
                        Text('สวัสดีครับ 👋',
                            style: TextStyle(
                                fontSize: 16, color: Colors.grey.shade700)),
                        Text(
                          'คุณ $_patientName',
                          style: const TextStyle(
                              fontSize: 28,
                              fontWeight: FontWeight.bold,
                              color: slateColor),
                        ),
                        const SizedBox(height: 24),

                        // --- 📊 ส่วน Indicator ค่าเฉลี่ย 7 วัน + สัญลักษณ์เชิงสุขภาพ ---
                        _buildHealthIndicatorCard(),
                        const SizedBox(height: 32),

                        // --- 🗂️ ส่วนเมนูหลัก (Modern Grid 6 เมนู) ---
                        const Text('เมนูบริการ',
                            style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: slateColor)),
                        const SizedBox(height: 16),
                        GridView.count(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          crossAxisCount: 2,
                          crossAxisSpacing: 16,
                          mainAxisSpacing: 16,
                          childAspectRatio: 1.08,
                          children: [
                            // เมนูที่ 1: บันทึกความดัน
                            _buildMenuCard(
                              title: 'บันทึกความดัน',
                              subtitle: 'ถอดเสียงพูด / ถ่ายรูปจอ LCD',
                              icon: Icons.monitor_heart_rounded,
                              color: const Color(0xFF059669), // เขียวมรกตเข้ม
                              onTap: () => Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                      builder: (_) =>
                                          const VitalSignRecordScreen())),
                            ),

                            // เมนูที่ 2: ห้องยาประจำตัว
                            _buildMenuCard(
                              title: 'ห้องยาประจำตัว',
                              subtitle: 'สแกนฉลากยา & ตั้งเตือนทานยา',
                              icon: Icons.medication_rounded,
                              color: const Color(0xFF2563EB), // น้ำเงินสดใส
                              onTap: () => Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                      builder: (_) =>
                                          const MedicationHistoryScreen())),
                            ),

                            // เมนูที่ 3: โภชนาการ & กิจกรรม
                            _buildMenuCard(
                              title: 'อาหาร & กิจกรรม',
                              subtitle: 'พูดบันทึกมื้ออาหาร / เช็กโซเดียม',
                              icon: Icons.restaurant_menu_rounded,
                              color: const Color(0xFFEA580C), // ส้มอิฐเด่น
                              onTap: () => Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                      builder: (_) => const NutritionScreen())),
                            ),

                            // เมนูที่ 4: ปรึกษาหมอ AI
                            _buildMenuCard(
                              title: 'ปรึกษาหมอ AI',
                              subtitle: 'ถามตอบอิง HT Guideline 2567',
                              icon: Icons.chat_bubble_rounded,
                              color: const Color(0xFF0D9488), // ฟ้าอมเขียวสด
                              onTap: () => Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                      builder: (_) => const HtConsultScreen())),
                            ),

                            // เมนูที่ 5: สมุดสุขภาพ
                            _buildMenuCard(
                              title: 'สมุดสุขภาพ',
                              subtitle: 'ดูกราฟ 7 วัน & ประวัติความเสี่ยง',
                              icon: Icons.bar_chart_rounded,
                              color: const Color(0xFFD97706), // ส้มทอง
                              onTap: () => Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                      builder: (_) =>
                                          const HealthHistoryScreen())),
                            ),

                            // เมนูที่ 6: ข้อมูลส่วนตัว
                            _buildMenuCard(
                              title: 'ข้อมูลของฉัน',
                              subtitle: 'คำนวณ TDEE & คัดกรองโรค',
                              icon: Icons.person_pin_rounded,
                              color: const Color(0xFF7C3AED), // ม่วงพรีเมียม
                              onTap: () => Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                      builder: (_) =>
                                          const PatientProfileScreen())),
                            ),
                          ],
                        ),
                        const SizedBox(height: 40),
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  // 📍 การ์ดประเมินสุขภาพเชิงสัญลักษณ์ + คำแนะนำไดนามิก
  Widget _buildHealthIndicatorCard() {
    final int sys = _avgSys7Days.round();
    final int dia = _avgDia7Days.round();

    // 📍 1. ประเมินข้อมูลใหม่ โดยดึง profileData เข้าไปคำนวณด้วย
    final feedback = HealthFeedbackEvaluator.evaluate(
      systolicAvg: sys,
      diastolicAvg: dia,
      hasData: _hasVitalData,
      todayFoodLogs: _todayFoodLogs,
      profile:
          _profileData, // ต้องมีตัวแปร Map<String, dynamic>? _profileData ประกาศไว้ด้านบนสุดของ _HomeScreenState
    );

    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      elevation: 2,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: feedback.bgColor,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
              color: feedback.themeColor.withOpacity(0.4), width: 1.5),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('ความดันเฉลี่ย 7 วันล่าสุด',
                        style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey,
                            fontWeight: FontWeight.w600)),
                    const SizedBox(height: 4),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.baseline,
                      textBaseline: TextBaseline.alphabetic,
                      children: [
                        Text(
                          _hasVitalData ? '$sys/$dia' : '--/--',
                          style: TextStyle(
                              fontSize: 28,
                              fontWeight: FontWeight.bold,
                              color: feedback.themeColor),
                        ),
                        const SizedBox(width: 4),
                        const Text('mmHg',
                            style: TextStyle(fontSize: 12, color: Colors.grey)),
                      ],
                    ),
                  ],
                ),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                      color: feedback.themeColor.withOpacity(0.15),
                      shape: BoxShape.circle),
                  child: Icon(feedback.iconData,
                      size: 40, color: feedback.themeColor),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // 📍 2. กล่องคำแนะนำ Actionable Advice (ออกแบบใหม่ให้อ่านง่าย เด่นชัด)
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                      color: feedback.themeColor.withOpacity(0.1),
                      blurRadius: 8,
                      offset: const Offset(0, 2))
                ],
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.lightbulb_circle_rounded,
                      size: 24, color: feedback.themeColor),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          feedback.statusTitle,
                          style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              color: feedback.themeColor),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          feedback.adviceText,
                          style: const TextStyle(
                              fontSize: 13,
                              color: slateColor,
                              height: 1.4,
                              fontWeight: FontWeight.w500),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // 🌟 ฟังก์ชันการ์ดเมนูใหม่: เพิ่มมิติเงา 2 ชั้น (Double Shadow) + เส้นขอบสี + มิติปุ่มกด
  Widget _buildMenuCard({
    required String title,
    required String subtitle,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          // 📍 มิติความนูนเงา 2 ชั้น (Soft Ambient + Colored Glow)
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.04),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
            BoxShadow(
              color: color.withOpacity(0.16),
              blurRadius: 16,
              offset: const Offset(0, 6),
            ),
          ],
          // 📍 เส้นขอบสีบางๆ ให้การ์ดตัดกับพื้นหลัง ไม่ดูขาวกลืน
          border: Border.all(
            color: color.withOpacity(0.2),
            width: 1.5,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ส่วนหัวของการ์ด: ไอคอนสีเด่น + ลูกศรบอกทิศทาง
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Container(
                  padding: const EdgeInsets.all(9),
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(icon, color: color, size: 26),
                ),
                Icon(
                  Icons.arrow_forward_ios_rounded,
                  size: 13,
                  color: Colors.grey.shade400,
                ),
              ],
            ),
            const Spacer(),
            // 📍 ชื่อเมนูตัวหนา คมชัด
            Text(
              title,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.bold,
                color: Color(0xFF1E293B),
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 3),
            // 📍 คำบรรยายสั้นๆ อธิบายหน้าที่ชัดเจน
            Text(
              subtitle,
              style: TextStyle(
                fontSize: 11,
                color: Colors.blueGrey.shade600,
                fontWeight: FontWeight.w500,
                height: 1.2,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}

/// 🧠 Helper Class ประเมินสถานะเชิงสัญลักษณ์และคำแนะนำรายวัน
class HealthFeedbackModel {
  final String statusTitle;
  final String adviceText;
  final IconData iconData;
  final Color themeColor;
  final Color bgColor;

  HealthFeedbackModel({
    required this.statusTitle,
    required this.adviceText,
    required this.iconData,
    required this.themeColor,
    required this.bgColor,
  });
}

class HealthFeedbackEvaluator {
  static HealthFeedbackModel evaluate({
    required int systolicAvg,
    required int diastolicAvg,
    required bool hasData,
    required List<Map<String, dynamic>> todayFoodLogs,
    required Map<String, dynamic>? profile, // 📍 เพิ่มการรับข้อมูล Profile
  }) {
    if (!hasData) {
      return HealthFeedbackModel(
        statusTitle: 'ยังไม่มีข้อมูลความดัน',
        adviceText:
            'แนะนำวัดความดันช่วงเช้า (หลังตื่นนอน) อย่างน้อยวันละ 1 ครั้งครับ',
        iconData: Icons.add_chart_rounded,
        themeColor: const Color(0xFF10B981),
        bgColor: const Color(0xFFECFDF5),
      );
    }

    // 1. จำแนกเกรดความดันตาม Guideline 2567
    int tier = 4;
    if (systolicAvg >= 180 || diastolicAvg >= 110) {
      tier = 1; // วิกฤติ
    } else if (systolicAvg >= 140 || diastolicAvg >= 90) {
      tier = 2; // สูง
    } else if (systolicAvg >= 130 || diastolicAvg >= 85) {
      tier = 3; // ค่อนข้างสูง (เฝ้าระวัง)
    } else {
      tier = 4; // ปกติ
    }

    // 2. วิเคราะห์บริบทผู้ป่วย (Contextual Profile)
    final String diseases =
        (profile?['underlying_diseases'] ?? '').toString().toLowerCase();
    final bool hasDM = diseases.contains('เบาหวาน');
    final bool hasCKD = diseases.contains('ไต');
    final bool isSmoker = profile?['smokes'] == true;
    final double bmi = (profile?['bmi'] as num?)?.toDouble() ?? 0.0;

    String actionAdvice = '';

    // 3. สร้างคำแนะนำแบบ Actionable (สั้น กระชับ อิง Guideline 2567)
    if (tier == 1) {
      actionAdvice =
          '🚨 อันตราย! ความดันสูงวิกฤติ งดกิจกรรมหนัก สังเกตอาการหน้ามืด/เจ็บอก และรีบพบแพทย์ด่วน';
    } else if (todayFoodLogs.isNotEmpty && _hasWarningInFoods(todayFoodLogs)) {
      // ดึงเตือนจากอาหารวันนี้ก่อน ถ้ามีกินของอันตราย
      actionAdvice =
          '⚠️ อาหารวันนี้โซเดียม/น้ำตาลสูง: ระวังบวมน้ำและความดันพุ่ง พรุ่งนี้เน้นทานจืดและผักให้มากขึ้น';
    } else if (tier == 2) {
      actionAdvice =
          '💊 ความดันยังสูง: ทานยาให้ตรงเวลาอย่างเคร่งครัด และงดปรุงรส/น้ำปลา/ซีอิ๊ว (ลดเค็มลดความดันได้ 5 mmHg)';
    } else {
      // กรณีความดันเริ่มคุมได้ (Tier 3, 4) ให้แนะนำตามความเสี่ยง (Risk Factors)
      if (isSmoker) {
        actionAdvice =
            '🚬 งดสูบบุหรี่: ช่วยลดความเสี่ยงโรคหัวใจและหลอดเลือดสมองตีบเฉียบพลันได้เห็นผลที่สุด';
      } else if (hasCKD) {
        actionAdvice =
            '💧 ถนอมไต: หลีกเลี่ยงยาแก้ปวดกลุ่ม NSAIDs (เช่น ไอบูโพรเฟน) และงดอาหารหมักดองเด็ดขาด';
      } else if (hasDM) {
        actionAdvice =
            '🥗 คุมน้ำตาล: เน้นทานอาหารสูตร 2:1:1 (ผักครึ่งจาน ข้าว 1 ส่วน เนื้อ 1 ส่วน) ป้องกันหลอดเลือดอักเสบ';
      } else if (bmi >= 25.0) {
        actionAdvice =
            '🏃‍♂️ ระวังอ้วนลงพุง: การลดน้ำหนัก 1 กก. ช่วยลดความดันโลหิตได้ถึง 1 mmHg พยายามขยับร่างกายบ่อยๆ';
      } else {
        actionAdvice =
            '✨ สุขภาพอยู่ในเกณฑ์ดี: ดื่มน้ำเปล่าให้เพียงพอ และเดินแกว่งแขน 30 นาที/วัน เพื่อหลอดเลือดที่แข็งแรง';
      }
    }

    // 4. คืนค่าโมเดลสีและไอคอน
    switch (tier) {
      case 1:
        return HealthFeedbackModel(
          statusTitle: 'วิกฤติ! ต้องพบแพทย์',
          adviceText: actionAdvice,
          iconData: Icons.warning_amber_rounded,
          themeColor: const Color(0xFFEF4444),
          bgColor: const Color(0xFFFEF2F2),
        );
      case 2:
        return HealthFeedbackModel(
          statusTitle: 'ความดันระดับสูง',
          adviceText: actionAdvice,
          iconData: Icons.sentiment_dissatisfied_rounded,
          themeColor: const Color(0xFFF97316),
          bgColor: const Color(0xFFFFF7ED),
        );
      case 3:
        return HealthFeedbackModel(
          statusTitle: 'เฝ้าระวัง (ค่อนข้างสูง)',
          adviceText: actionAdvice,
          iconData: Icons.sentiment_neutral_rounded,
          themeColor: const Color(0xFFEAB308),
          bgColor: const Color(0xFFFEFCE8),
        );
      case 4:
      default:
        return HealthFeedbackModel(
          statusTitle: 'ความดันปกติ (ดีเยี่ยม)',
          adviceText: actionAdvice,
          iconData: Icons.sentiment_very_satisfied_rounded,
          themeColor: const Color(0xFF10B981),
          bgColor: const Color(0xFFECFDF5),
        );
    }
  }

  static bool _hasWarningInFoods(List<Map<String, dynamic>> logs) {
    for (var log in logs) {
      if (log['warning_flags'] != null &&
          (log['warning_flags'] as List).isNotEmpty) return true;
    }
    return false;
  }
}
