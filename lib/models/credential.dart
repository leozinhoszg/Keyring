class CredentialSummary {
  final String id;
  final String title;
  final String? url;
  final String? project;
  final bool isFavorite;
  final List<String> tags; // ids
  final bool hasUsername;
  final bool hasPassword;
  final int? strengthScore;
  final String? expiresAt;
  const CredentialSummary({
    required this.id,
    required this.title,
    this.url,
    this.project,
    this.isFavorite = false,
    this.tags = const [],
    this.hasUsername = false,
    this.hasPassword = false,
    this.strengthScore,
    this.expiresAt,
  });
}

class CredentialInput {
  final String title;
  final String? username;
  final String? password;
  final String? url;
  final String? notes;
  final String? project;
  final List<String> tagIds;
  final bool isFavorite;
  final String? expiresAt;
  final int? strengthScore;
  const CredentialInput({
    required this.title,
    this.username,
    this.password,
    this.url,
    this.notes,
    this.project,
    this.tagIds = const [],
    this.isFavorite = false,
    this.expiresAt,
    this.strengthScore,
  });
}
