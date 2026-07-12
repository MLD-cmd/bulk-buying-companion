class AppUser {
  const AppUser({
    required this.uid,
    required this.eduEmail,
    this.displayName,
    this.hubId,
  });

  final String uid;
  final String eduEmail;
  final String? displayName;
  final String? hubId;

  AppUser copyWith({String? hubId}) {
    return AppUser(
      uid: uid,
      eduEmail: eduEmail,
      displayName: displayName,
      hubId: hubId ?? this.hubId,
    );
  }
}
