/// Diagnostic (placement) questions — not PYQs and never stored as PYQs.
class DiagnosticQuestion {
  const DiagnosticQuestion({
    required this.id,
    required this.areaId,
    required this.question,
    required this.options,
    required this.correctIndex,
    this.explanation = '',
  });

  final String id;
  final String areaId;
  final String question;
  final List<String> options;
  final int correctIndex;
  final String explanation;
}

/// 30 diagnostic questions covering major MPSC Group B Combined areas.
List<DiagnosticQuestion> groupBDiagnosticQuestions() => const [
      DiagnosticQuestion(
        id: 'diag_ca_1',
        areaId: 'current_affairs',
        question:
            'The Union Budget of India is presented by which office?',
        options: [
          'Prime Minister',
          'Finance Minister',
          'RBI Governor',
          'NITI Aayog CEO',
        ],
        correctIndex: 1,
      ),
      DiagnosticQuestion(
        id: 'diag_ca_2',
        areaId: 'current_affairs',
        question: 'NITI Aayog replaced which earlier planning body?',
        options: [
          'Finance Commission',
          'Planning Commission',
          'Election Commission',
          'UPSC',
        ],
        correctIndex: 1,
      ),
      DiagnosticQuestion(
        id: 'diag_ca_3',
        areaId: 'current_affairs',
        question:
            'Which organisation publishes the Human Development Report?',
        options: ['World Bank', 'IMF', 'UNDP', 'WTO'],
        correctIndex: 2,
      ),
      DiagnosticQuestion(
        id: 'diag_ca_4',
        areaId: 'current_affairs',
        question: 'GST in India is administered as which type of tax?',
        options: [
          'Only a Central tax',
          'Only a State tax',
          'A dual Central and State tax',
          'A municipal tax',
        ],
        correctIndex: 2,
      ),
      DiagnosticQuestion(
        id: 'diag_his_1',
        areaId: 'history',
        question: 'Who was the founder of the Maratha Swaraj?',
        options: [
          'Peshwa Bajirao I',
          'Chhatrapati Shivaji Maharaj',
          'Sambhaji Maharaj',
          'Mahadji Shinde',
        ],
        correctIndex: 1,
      ),
      DiagnosticQuestion(
        id: 'diag_his_2',
        areaId: 'history',
        question: 'The Revolt of 1857 began at which place?',
        options: ['Meerut', 'Delhi', 'Kanpur', 'Jhansi'],
        correctIndex: 0,
      ),
      DiagnosticQuestion(
        id: 'diag_his_3',
        areaId: 'history',
        question: 'Who started the newspaper Kesari?',
        options: [
          'Gopal Krishna Gokhale',
          'Bal Gangadhar Tilak',
          'Mahatma Gandhi',
          'Dadabhai Naoroji',
        ],
        correctIndex: 1,
      ),
      DiagnosticQuestion(
        id: 'diag_his_4',
        areaId: 'history',
        question: 'The Battle of Panipat (1761) was fought between?',
        options: [
          'Marathas and Ahmad Shah Abdali',
          'Marathas and the British',
          'Mughals and the Portuguese',
          'Nizam and Hyder Ali',
        ],
        correctIndex: 0,
      ),
      DiagnosticQuestion(
        id: 'diag_geo_1',
        areaId: 'geography',
        question: 'Which river is known as the lifeline of Maharashtra?',
        options: ['Godavari', 'Krishna', 'Tapi', 'Narmada'],
        correctIndex: 0,
      ),
      DiagnosticQuestion(
        id: 'diag_geo_2',
        areaId: 'geography',
        question: 'The Western Ghats in Maharashtra are also called?',
        options: ['Aravali', 'Sahyadri', 'Vindhya', 'Satpura'],
        correctIndex: 1,
      ),
      DiagnosticQuestion(
        id: 'diag_geo_3',
        areaId: 'geography',
        question: 'Black soil in Maharashtra is mainly associated with?',
        options: ['Rice', 'Cotton', 'Tea', 'Jute'],
        correctIndex: 1,
      ),
      DiagnosticQuestion(
        id: 'diag_geo_4',
        areaId: 'geography',
        question: 'Which plateau covers a large part of Maharashtra?',
        options: [
          'Malwa Plateau',
          'Deccan Plateau',
          'Chota Nagpur Plateau',
          'Shillong Plateau',
        ],
        correctIndex: 1,
      ),
      DiagnosticQuestion(
        id: 'diag_eco_1',
        areaId: 'economy',
        question: 'RBI is the central bank of India. Where is it headquartered?',
        options: ['New Delhi', 'Kolkata', 'Mumbai', 'Chennai'],
        correctIndex: 2,
      ),
      DiagnosticQuestion(
        id: 'diag_eco_2',
        areaId: 'economy',
        question: 'Which of the following is a direct tax?',
        options: ['GST', 'Customs duty', 'Income tax', 'Excise duty'],
        correctIndex: 2,
      ),
      DiagnosticQuestion(
        id: 'diag_eco_3',
        areaId: 'economy',
        question: 'MSP in Indian agriculture mainly refers to?',
        options: [
          'Maximum Selling Price',
          'Minimum Support Price',
          'Market Subsidy Price',
          'Monthly Stock Price',
        ],
        correctIndex: 1,
      ),
      DiagnosticQuestion(
        id: 'diag_eco_4',
        areaId: 'economy',
        question: 'Which sector contributes most to Maharashtra’s GSDP?',
        options: [
          'Primary (agriculture)',
          'Secondary (industry)',
          'Tertiary (services)',
          'Mining only',
        ],
        correctIndex: 2,
      ),
      DiagnosticQuestion(
        id: 'diag_pol_1',
        areaId: 'polity',
        question: 'The Constitution of India came into force on?',
        options: [
          '15 August 1947',
          '26 January 1950',
          '26 November 1949',
          '2 October 1949',
        ],
        correctIndex: 1,
      ),
      DiagnosticQuestion(
        id: 'diag_pol_2',
        areaId: 'polity',
        question: 'Fundamental Rights are contained in which Part of the Constitution?',
        options: ['Part II', 'Part III', 'Part IV', 'Part IVA'],
        correctIndex: 1,
      ),
      DiagnosticQuestion(
        id: 'diag_pol_3',
        areaId: 'polity',
        question: 'Who is the constitutional head of a State in India?',
        options: [
          'Chief Minister',
          'Governor',
          'Speaker',
          'Chief Secretary',
        ],
        correctIndex: 1,
      ),
      DiagnosticQuestion(
        id: 'diag_pol_4',
        areaId: 'polity',
        question: 'The 73rd Constitutional Amendment is related to?',
        options: [
          'Municipalities',
          'Panchayati Raj',
          'GST Council',
          'Finance Commission',
        ],
        correctIndex: 1,
      ),
      DiagnosticQuestion(
        id: 'diag_pol_5',
        areaId: 'polity',
        question: 'Which Schedule of the Constitution lists official languages?',
        options: ['Seventh', 'Eighth', 'Ninth', 'Tenth'],
        correctIndex: 1,
      ),
      DiagnosticQuestion(
        id: 'diag_sci_1',
        areaId: 'general_science',
        question: 'Photosynthesis in plants mainly takes place in?',
        options: ['Roots', 'Leaves', 'Flowers', 'Seeds'],
        correctIndex: 1,
      ),
      DiagnosticQuestion(
        id: 'diag_sci_2',
        areaId: 'general_science',
        question: 'Vitamin C deficiency causes?',
        options: ['Beriberi', 'Scurvy', 'Rickets', 'Night blindness'],
        correctIndex: 1,
      ),
      DiagnosticQuestion(
        id: 'diag_sci_3',
        areaId: 'general_science',
        question: 'The SI unit of electric current is?',
        options: ['Volt', 'Ohm', 'Ampere', 'Watt'],
        correctIndex: 2,
      ),
      DiagnosticQuestion(
        id: 'diag_sci_4',
        areaId: 'general_science',
        question: 'Which gas is used by plants during photosynthesis?',
        options: ['Oxygen', 'Nitrogen', 'Carbon dioxide', 'Hydrogen'],
        correctIndex: 2,
      ),
      DiagnosticQuestion(
        id: 'diag_ia_1',
        areaId: 'intelligence_arithmetic',
        question: 'What is 15% of 200?',
        options: ['15', '20', '30', '45'],
        correctIndex: 2,
      ),
      DiagnosticQuestion(
        id: 'diag_ia_2',
        areaId: 'intelligence_arithmetic',
        question: 'If 2x + 4 = 12, then x is?',
        options: ['2', '4', '6', '8'],
        correctIndex: 1,
      ),
      DiagnosticQuestion(
        id: 'diag_ia_3',
        areaId: 'intelligence_arithmetic',
        question:
            'Find the next number: 2, 6, 12, 20, 30, ?',
        options: ['36', '40', '42', '44'],
        correctIndex: 2,
      ),
      DiagnosticQuestion(
        id: 'diag_ia_4',
        areaId: 'intelligence_arithmetic',
        question: 'A train covers 120 km in 2 hours. Its average speed is?',
        options: ['40 km/h', '50 km/h', '60 km/h', '80 km/h'],
        correctIndex: 2,
      ),
      DiagnosticQuestion(
        id: 'diag_ia_5',
        areaId: 'intelligence_arithmetic',
        question:
            'If all roses are flowers and some flowers fade quickly, which is definitely true?',
        options: [
          'All flowers are roses',
          'Some roses may fade quickly',
          'No rose is a flower',
          'All fading things are roses',
        ],
        correctIndex: 1,
      ),
    ];
