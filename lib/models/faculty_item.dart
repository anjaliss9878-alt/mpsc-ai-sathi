/// A faculty/instructor profile, stored in Firestore at `faculty/{id}`.
///
/// Referenced by [LiveClassItem.facultyId] so a live class can show the
/// instructor's name/photo without a second Firestore read (the class
/// document also stores a denormalized `facultyName`).
class FacultyItem {
  const FacultyItem({
    required this.id,
    required this.name,
    required this.designation,
    required this.subject,
    required this.photoUrl,
    required this.bio,
  });

  final String id;
  final String name;

  /// e.g. "MPSC Combine Expert Faculty".
  final String designation;

  /// Primary subject this faculty member teaches (e.g. "Polity").
  final String subject;
  final String photoUrl;
  final String bio;

  factory FacultyItem.fromMap(Map<String, dynamic> map, String id) {
    return FacultyItem(
      id: id,
      name: map['name'] as String? ?? '',
      designation: map['designation'] as String? ?? '',
      subject: map['subject'] as String? ?? '',
      photoUrl: map['photoUrl'] as String? ?? '',
      bio: map['bio'] as String? ?? '',
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'designation': designation,
      'subject': subject,
      'photoUrl': photoUrl,
      'bio': bio,
      'updatedAt': DateTime.now().toIso8601String(),
    };
  }
}
