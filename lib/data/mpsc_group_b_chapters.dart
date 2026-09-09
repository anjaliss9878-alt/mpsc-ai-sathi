import 'package:mpsc_combine_ai/models/chapter_item.dart';
import 'package:mpsc_combine_ai/models/content_index.dart';
import 'package:mpsc_combine_ai/models/exam_item.dart';

/// Internal Group B chapters. Titles are exam-oriented study units, not
/// official MPSC syllabus headings.
List<ChapterItem> mpscGroupBCombinedChapters() {
  const examId = kGroupBCombinedExamId;
  const node = 'chapter';
  const desc =
      'Internal learning chapter for app organisation. Not an official MPSC heading.';

  ChapterItem ch({
    required String subjectId,
    required String area,
    required int order,
    required String titleEn,
  }) {
    final slug = _gbChapterSlug(area, titleEn);
    return ChapterItem(
      id: 'gbch_${subjectId}_$slug',
      subjectId: subjectId,
      title: titleEn,
      titleEn: titleEn,
      order: order,
      slug: slug,
      examId: examId,
      parentChapterId: '',
      nodeType: contentNodeTypeToString(ContentNodeType.chapter),
      published: true,
      tags: [area, node],
      description: desc,
    );
  }

  final out = <ChapterItem>[];

  var o = 0;
  for (final title in _gatCurrentAffairs) {
    out.add(ch(
      subjectId: kGroupBSubjectPrelimsGatId,
      area: 'current_affairs',
      order: o++,
      titleEn: title,
    ));
  }
  for (final title in _gatHistory) {
    out.add(ch(
      subjectId: kGroupBSubjectPrelimsGatId,
      area: 'history',
      order: o++,
      titleEn: title,
    ));
  }
  for (final title in _gatGeography) {
    out.add(ch(
      subjectId: kGroupBSubjectPrelimsGatId,
      area: 'geography',
      order: o++,
      titleEn: title,
    ));
  }
  for (final title in _gatEconomy) {
    out.add(ch(
      subjectId: kGroupBSubjectPrelimsGatId,
      area: 'economy',
      order: o++,
      titleEn: title,
    ));
  }
  for (final title in _gatPolity) {
    out.add(ch(
      subjectId: kGroupBSubjectPrelimsGatId,
      area: 'polity',
      order: o++,
      titleEn: title,
    ));
  }
  for (final title in _gatScience) {
    out.add(ch(
      subjectId: kGroupBSubjectPrelimsGatId,
      area: 'general_science',
      order: o++,
      titleEn: title,
    ));
  }
  for (final title in _gatIntelligence) {
    out.add(ch(
      subjectId: kGroupBSubjectPrelimsGatId,
      area: 'intelligence_arithmetic',
      order: o++,
      titleEn: title,
    ));
  }

  o = 0;
  for (final title in _mainsMarathi) {
    out.add(ch(
      subjectId: kGroupBSubjectMainsMarathiId,
      area: 'marathi',
      order: o++,
      titleEn: title,
    ));
  }
  o = 0;
  for (final title in _mainsEnglish) {
    out.add(ch(
      subjectId: kGroupBSubjectMainsEnglishId,
      area: 'english',
      order: o++,
      titleEn: title,
    ));
  }
  o = 0;
  for (final title in _mainsGs) {
    out.add(ch(
      subjectId: kGroupBSubjectMainsGsId,
      area: 'general_studies',
      order: o++,
      titleEn: title,
    ));
  }

  return out;
}

String _gbChapterSlug(String area, String titleEn) {
  final t = titleEn
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
      .replaceAll(RegExp(r'_+'), '_')
      .replaceAll(RegExp(r'^_|_$'), '');
  return '${area}_$t';
}

const _gatCurrentAffairs = [
  'Maharashtra Current Affairs',
  'India Current Affairs',
  'International Current Affairs',
  'Government Schemes',
  'Maharashtra Government Schemes',
  'Economy and Banking Updates',
  'Science and Technology Updates',
  'Environment and Climate Updates',
  'Awards and Honours',
  'Appointments and Important Persons',
  'Sports',
  'Books and Authors',
  'Important Reports and Indexes',
  'Important Days and Events',
  'Defence and Security Updates',
];

const _gatHistory = [
  'British Expansion in India',
  'Early British Administration',
  'Socio-Religious Reform Movements',
  'Social Reform in Maharashtra',
  'Education and Social Awakening',
  'Press and Public Awakening',
  'Economic Impact of British Rule',
  'Revolt of 1857',
  'Formation and Growth of Indian National Congress',
  'Moderate and Extremist Phases',
  'Swadeshi and National Movements',
  'Gandhian Era',
  'Revolutionary Movements',
  'Quit India Movement',
  'Maharashtra Contribution to Freedom Struggle',
  'Important Personalities of Modern Maharashtra',
];

const _gatGeography = [
  'Earth and Basic Geography',
  'Latitude and Longitude',
  'Major Geographical Divisions of the World',
  'Physical Geography of Maharashtra',
  'Physiographic Regions of Maharashtra',
  'Climate of Maharashtra',
  'Rainfall Distribution',
  'Rivers of Maharashtra',
  'Water Resources',
  'Soil Types of Maharashtra',
  'Agriculture of Maharashtra',
  'Major Crops',
  'Forests and Natural Resources',
  'Population and Settlements',
  'Important Cities of Maharashtra',
  'Industries of Maharashtra',
  'Transport and Connectivity',
  'Regional Geography of Maharashtra',
];

const _gatEconomy = [
  'Basics of Indian Economy',
  'National Income',
  'Economic Growth and Development',
  'Agriculture and Rural Economy',
  'Industry',
  'Foreign Trade',
  'Banking System',
  'Financial System',
  'Money',
  'Inflation',
  'Population and Demography',
  'Poverty',
  'Unemployment',
  'Monetary Policy',
  'Fiscal Policy',
  'Government Budget',
  'Public Finance',
  'Accounts and Audit',
  'Maharashtra Economy',
];

const _gatPolity = [
  'Constitution of India',
  'Constitutional Development',
  'Preamble',
  'Fundamental Rights',
  'Directive Principles',
  'Fundamental Duties',
  'Union Executive',
  'Parliament',
  'Judiciary',
  'State Executive',
  'State Legislature',
  'Centre-State Relations',
  'Constitutional Bodies',
  'State Administration',
  'District Administration',
  'Local Self Government',
  'Panchayati Raj',
  'Village Administration',
  'Maharashtra Administration',
];

const _gatScience = [
  'Basic Physics',
  'Motion and Force',
  'Work Energy and Power',
  'Heat and Temperature',
  'Light',
  'Sound',
  'Electricity',
  'Magnetism',
  'Basic Chemistry',
  'Matter and Chemical Reactions',
  'Acids Bases and Salts',
  'Metals and Non-metals',
  'Botany',
  'Zoology',
  'Human Biology',
  'Hygiene and Health',
  'Nutrition and Diseases',
  'Environment-related Science',
];

const _gatIntelligence = [
  'Number System',
  'Simplification',
  'Fractions',
  'Percentages',
  'Ratio and Proportion',
  'Average',
  'Profit and Loss',
  'Simple Interest',
  'Time and Work',
  'Time Speed and Distance',
  'Series',
  'Algebra',
  'Geometry',
  'Data Interpretation',
  'Logical Reasoning',
  'Analytical Reasoning',
  'Classification',
  'Coding-Decoding',
  'Direction Test',
  'Basic Mental Ability',
];

const _mainsMarathi = [
  'Vocabulary',
  'Synonyms and Antonyms',
  'One-word Substitution',
  'Idioms and Proverbs',
  'Sentence Structure',
  'Types of Sentences',
  'Parts of Speech',
  'Tense and Verb Forms',
  'Sandhi and Samas Basics',
  'Spelling and Punctuation',
  'Error Correction',
  'Sentence Transformation',
  'Reading Comprehension',
  'Unseen Passage Practice',
  'Summary and Precis Skills',
  'Official Correspondence Basics',
];

const _mainsEnglish = [
  'Common Vocabulary',
  'Synonyms and Antonyms',
  'One-word Substitution',
  'Idioms and Phrases',
  'Sentence Structure',
  'Parts of Speech',
  'Tenses',
  'Articles and Prepositions',
  'Subject-Verb Agreement',
  'Active and Passive Voice',
  'Direct and Indirect Speech',
  'Error Spotting',
  'Sentence Improvement',
  'Reading Comprehension',
  'Cloze Test',
  'Fill in the Blanks',
];

const _mainsGs = [
  'Indian Constitution and Polity',
  'Maharashtra State Administration',
  'Local Self Government and Panchayati Raj',
  'Indian Economy Basics',
  'Maharashtra Economy',
  'Geography of Maharashtra',
  'Modern Indian History',
  'Maharashtra in the Freedom Struggle',
  'Current Affairs for Mains',
  'Government Schemes',
  'Science in Everyday Life',
  'Environment and Ecology',
  'Quantitative Aptitude',
  'Logical and Analytical Ability',
  'Data Interpretation',
  'Rural and Urban Development',
  'Human Resource and Social Issues',
  'Decision Making and Problem Solving',
];
