import 'package:flutter/material.dart';
import '../services/patient_profile_service.dart';
import '../services/vital_repository.dart';
import 'vital_sign_record_screen.dart';
import 'health_history_screen.dart';
import 'patient_profile_screen.dart';
import 'medication_history_screen.dart';
import 'login_page.dart';
import 'nutrition_screen.dart'; // 📍 เพิ่มบรรทัดนี้ด้านบน

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final PatientProfileService _profileService = PatientProfileService();
  final VitalRepository _vitalRepo = VitalRepository();

  static const Color emeraldColor = Color(0xFF10B981);
  static const Color slateColor = Color(0xFF334155);

  bool _isLoading = true;
  String _patientName = "ผู้ใช้งาน";
  double _avgSys7Days = 0;
  double _avgDia7Days = 0;
  bool _hasVitalData = false;

  @override
  void initState() {
    super.initState();
    _loadDashboardData();
  }

  // 📍 โหลดข้อมูล Profile และคำนวณค่าเฉลี่ย 7 วันล่าสุด
  Future<void> _loadDashboardData() async {
    setState(() => _isLoading = true);
    try {
      final patientId = await _profileService.getCurrentPatientId();
      if (patientId != null) {
        // 1. ดึงชื่อผู้ป่วย
        final profile = await _profileService.getProfile();
        if (profile != null && profile['first_name'] != null) {
          _patientName = profile['first_name'];
        }

        // 2. ดึงค่าวัด 7 วันล่าสุด (Lock เฉพาะ 7 วันตามโจทย์)
        final last7DaysVitals = await _vitalRepo.getLast7Days(patientId);
        if (last7DaysVitals.isNotEmpty) {
          double sumSys = 0;
          double sumDia = 0;
          for (var v in last7DaysVitals) {
            sumSys += (v['systolic'] as num).toDouble();
            sumDia += (v['diastolic'] as num).toDouble();
          }
          _avgSys7Days = sumSys / last7DaysVitals.length;
          _avgDia7Days = sumDia / last7DaysVitals.length;
          _hasVitalData = true;
        }
      }
    } catch (e) {
      debugPrint("Error loading dashboard: $e");
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _confirmLogout() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.logout, color: Colors.redAccent),
            SizedBox(width: 8),
            Text('ยืนยันการออกจากระบบ',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
          ],
        ),
        content: const Text('คุณต้องการออกจากระบบและกลับไปหน้าหลักหรือไม่?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('ยกเลิก', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () async {
              Navigator.pop(ctx);
              await _profileService.clearLocalIdentity();
              if (mounted) {
                Navigator.pushAndRemoveUntil(
                  context,
                  MaterialPageRoute(builder: (context) => const LoginPage()),
                  (route) => false,
                );
              }
            },
            child:
                const Text('ออกจากระบบ', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true, // ให้ฉากหลังทะลุไปถึงขอบจอบน
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          IconButton(
            icon: Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.8), shape: BoxShape.circle),
              child: const Icon(Icons.logout_rounded,
                  color: Colors.redAccent, size: 20),
            ),
            onPressed: _confirmLogout,
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Stack(
        children: [
          // 🖼️ 1. ฉากหลังภาพคลินิกแบบบางๆ (Premium Medical Background)
          Container(
            decoration: BoxDecoration(
              image: DecorationImage(
                // ใช้ภาพ Stock คลินิกสะอาดๆ (คุณพยาบาลสามารถเปลี่ยน URL เป็นภาพที่ต้องการได้)
                image: const NetworkImage(
                    'https://images.unsplash.com/photo-1519494026892-80bbd2d6fd0d?q=80&w=1000&auto=format&fit=crop'),
                fit: BoxFit.cover,
                // ปรับแสงให้ขาว/สว่างขึ้น 85% เพื่อให้ดูบางๆ สบายตา ไม่แย่งซีนตัวหนังสือ
                colorFilter: ColorFilter.mode(
                    Colors.white.withOpacity(0.88), BlendMode.lighten),
              ),
            ),
          ),

          // 📋 2. เนื้อหาหลักของหน้าจอ
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

                        // --- 📊 ส่วน Indicator ค่าเฉลี่ย 7 วัน ---
                        _buildHealthIndicatorCard(),
                        const SizedBox(height: 32),

                        // --- 🗂️ ส่วนเมนูหลัก (Modern Grid) ---
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
                          childAspectRatio: 1.1,
                          children: [
                            _buildMenuCard(
                              title: 'บันทึกความดัน',
                              subtitle: 'ด้วยเสียง/กล้อง',
                              icon: Icons.monitor_heart_rounded,
                              color: emeraldColor,
                              onTap: () => Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                      builder: (_) =>
                                          const VitalSignRecordScreen())),
                            ),
                            _buildMenuCard(
                              title: 'ห้องยา',
                              subtitle: 'ประวัติและเตือนกินยา',
                              icon: Icons.medication_liquid_rounded,
                              color: Colors.blue.shade500,
                              onTap: () => Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                      builder: (_) =>
                                          const MedicationHistoryScreen())),
                            ),
                            // 🥗 เมนูใหม่: โภชนาการ & กิจกรรม (TDEE, Food AI, Calorie Deficit)
                            _buildMenuCard(
                              title: 'โภชนาการ & กิจกรรม',
                              subtitle: 'คำนวณแคล/ออกกำลัง',
                              icon: Icons.restaurant_menu_rounded,
                              color: Colors.deepOrange.shade400,
                              onTap: () => Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                      builder: (_) => const NutritionScreen())),
                            ),
                            _buildMenuCard(
                              title: 'สมุดสุขภาพ',
                              subtitle: 'กราฟและผลแล็บ',
                              icon: Icons.history_edu_rounded,
                              color: Colors.orange.shade500,
                              onTap: () => Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                      builder: (_) =>
                                          const HealthHistoryScreen())),
                            ),
                            _buildMenuCard(
                              title: 'โปรไฟล์ของฉัน',
                              subtitle: 'TDEE และความเสี่ยง',
                              icon: Icons.person_rounded,
                              color: Colors.purple.shade400,
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

  // 🎛️ Widget: แท่ง Indicator สุขภาพ 7 วันล่าสุด (เงาสะท้อน)
  Widget _buildHealthIndicatorCard() {
    // กำหนดตำแหน่งเข็มชี้บนแท่ง (ช่วงความดัน 90 ถึง 180)
    double positionPercent = 0.0;
    String statusText = "ไม่มีข้อมูล";
    Color statusColor = Colors.grey;

    if (_hasVitalData) {
      // คำนวณเปอร์เซ็นต์ (Clamp ไว้ที่ 0.0 - 1.0)
      positionPercent = ((_avgSys7Days - 90) / (180 - 90)).clamp(0.0, 1.0);

      if (_avgSys7Days < 130) {
        statusText = "ควบคุมได้ดี";
        statusColor = Colors.green.shade600;
      } else if (_avgSys7Days < 140) {
        statusText = "เริ่มสูง (เฝ้าระวัง)";
        statusColor = Colors.orange.shade600;
      } else {
        statusText = "สูง (อันตราย)";
        statusColor = Colors.red.shade600;
      }
    }

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.9), // Glassmorphism อ่อนๆ
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 15,
              offset: const Offset(0, 5)),
        ],
        border: Border.all(color: Colors.white, width: 2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('🩺 ค่าความดันเฉลี่ย (7 วันล่าสุด)',
                  style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: slateColor)),
              if (_hasVitalData)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                      color: statusColor.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(12)),
                  child: Text(statusText,
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: statusColor)),
                ),
            ],
          ),
          const SizedBox(height: 16),
          if (!_hasVitalData)
            const Center(
                child: Padding(
              padding: EdgeInsets.symmetric(vertical: 10),
              child: Text('ยังไม่มีประวัติการวัดความดันใน 7 วันที่ผ่านมา',
                  style: TextStyle(color: Colors.grey)),
            ))
          else ...[
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(_avgSys7Days.toStringAsFixed(0),
                    style: const TextStyle(
                        fontSize: 36,
                        fontWeight: FontWeight.w900,
                        color: slateColor,
                        height: 1)),
                const Text(' / ',
                    style: TextStyle(
                        fontSize: 24, color: Colors.grey, height: 1.2)),
                Text(_avgDia7Days.toStringAsFixed(0),
                    style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: slateColor,
                        height: 1.2)),
                const SizedBox(width: 6),
                const Text('mmHg',
                    style: TextStyle(
                        fontSize: 14, color: Colors.grey, height: 1.6)),
              ],
            ),
            const SizedBox(height: 20),

            // 🌟 แถบ Indicator 3 สี (มีเงาสะท้อน Glossy แนวนอน)
            LayoutBuilder(
              builder: (context, constraints) {
                final barWidth = constraints.maxWidth;
                return Stack(
                  clipBehavior: Clip.none,
                  alignment: Alignment.centerLeft,
                  children: [
                    // แท่งสีพื้น (เขียว -> เหลือง -> แดง)
                    Container(
                      height: 20,
                      width: double.infinity,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(10),
                        gradient: const LinearGradient(
                          colors: [
                            Color(0xFF10B981),
                            Color(0xFFF59E0B),
                            Color(0xFFEF4444)
                          ], // Green, Yellow, Red
                          stops: [0.3, 0.6, 1.0],
                        ),
                        boxShadow: [
                          BoxShadow(
                              color: Colors.black.withOpacity(0.1),
                              blurRadius: 4,
                              offset: const Offset(0, 2))
                        ],
                      ),
                      // 🌟 เพิ่มเงาสะท้อน (Glossy Effect) ด้านบนแท่ง
                      foregroundDecoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(10),
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.white.withOpacity(0.5),
                            Colors.white.withOpacity(0.1),
                            Colors.black.withOpacity(0.1),
                          ],
                          stops: const [0.0, 0.4, 1.0],
                        ),
                      ),
                    ),

                    // เข็มชี้ (Indicator Pin)
                    Positioned(
                      left:
                          (barWidth - 16) * positionPercent, // คำนวณตำแหน่งเข็ม
                      child: Container(
                        width: 16,
                        height: 28,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: slateColor, width: 2),
                          boxShadow: [
                            BoxShadow(
                                color: Colors.black.withOpacity(0.2),
                                blurRadius: 4,
                                offset: const Offset(0, 2))
                          ],
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
            const SizedBox(height: 8),
            const Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('ปกติ',
                    style: TextStyle(
                        fontSize: 11,
                        color: Colors.grey,
                        fontWeight: FontWeight.bold)),
                Text('เริ่มสูง',
                    style: TextStyle(
                        fontSize: 11,
                        color: Colors.grey,
                        fontWeight: FontWeight.bold)),
                Text('อันตราย',
                    style: TextStyle(
                        fontSize: 11,
                        color: Colors.grey,
                        fontWeight: FontWeight.bold)),
              ],
            ),
          ]
        ],
      ),
    );
  }

  // 🎴 Widget: การ์ดเมนูทันสมัย (Modern Menu Card)
  Widget _buildMenuCard(
      {required String title,
      required String subtitle,
      required IconData icon,
      required Color color,
      required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.95), // Glassmorphism ขาวขุ่น
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
                color: color.withOpacity(0.1),
                blurRadius: 15,
                offset: const Offset(0, 8)),
          ],
          border: Border.all(color: Colors.white, width: 2),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                  color: color.withOpacity(0.15), shape: BoxShape.circle),
              child: Icon(icon, color: color, size: 28),
            ),
            const Spacer(),
            Text(title,
                style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: slateColor)),
            const SizedBox(height: 2),
            Text(subtitle,
                style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
          ],
        ),
      ),
    );
  }
}
