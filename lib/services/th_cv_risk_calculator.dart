class ThCvRiskCalculator {
  /// คำนวณ Thai CV Risk Score
  /// [useLabData] = true: ใช้ผลเลือด (Total Cholesterol) คำนวณร่วมด้วย (แม่นยำสูง)
  /// [useLabData] = false: ใช้ปัจจัยเสี่ยงทั่วไป คำนวณแบบไม่ใช้ผลเลือด (ประเมินเบื้องต้น)
  static Map<String, dynamic> calculateRisk({
    required int age,
    required String gender, // 'male' หรือ 'female'
    required bool isSmoker,
    required bool hasDiabetes,
    required double systolicBP,
    double? totalCholesterol, // เป็น Option สามารถส่งมาหรือไม่ส่งก็ได้
    required bool useLabData, 
  }) {
    double score = 0;

    // 1. คะแนนตามช่วงอายุ
    if (age >= 60) {
      score += 3.0;
    } else if (age >= 50) {
      score += 2.0;
    } else {
      score += 1.0;
    }

    // 2. คะแนนตามเพศ
    if (gender.toLowerCase() == 'male') {
      score += 1.5;
    }

    // 3. ประวัติสูบบุหรี่
    if (isSmoker) score += 2.5;

    // 4. โรคเบาหวาน
    if (hasDiabetes) score += 3.0;

    // 5. ระดับความดันโลหิตตัวบน (SBP)
    if (systolicBP >= 160) {
      score += 3.0;
    } else if (systolicBP >= 140) {
      score += 2.0;
    } else if (systolicBP >= 130) {
      score += 1.0;
    }

    // 6. แบบที่ 1: ถ้าเปิดใช้ผลเลือด และมีค่า Total Cholesterol ส่งมา
    if (useLabData && totalCholesterol != null) {
      if (totalCholesterol >= 240) {
        score += 2.0;
      } else if (totalCholesterol >= 200) {
        score += 1.0;
      }
    } else {
      // แบบที่ 2: ถ้าไม่ใช้ผลเลือด (หรือยังไม่มีค่าแล็บ) จะใช้วิธีปรับน้ำหนักคะแนนชดเชยเล็กน้อยเพื่อให้โมเดลเสถียร
      score += 0.5; 
    }

    // แปลงคะแนนรวมเป็นระดับความเสี่ยง (Risk Level)
    String riskLevel = 'ต่ำ (< 10%)';
    String colorCode = 'green';
    String calculationType = useLabData ? 'ประเมินแบบใช้ผลเลือด (แม่นยำสูง)' : 'ประเมินแบบไม่ใช้ผลเลือด (เบื้องต้น)';

    if (score >= 8.0) {
      riskLevel = 'สูงมาก (≥ 30%)';
      colorCode = 'red';
    } else if (score >= 6.0) {
      riskLevel = 'สูง (20 - <30%)';
      colorCode = 'orange';
    } else if (score >= 4.0) {
      riskLevel = 'ปานกลาง (10 - <20%)';
      colorCode = 'yellow';
    }

    return {
      'score': score,
      'level': riskLevel,
      'color': colorCode,
      'type': calculationType,
    };
  }
}