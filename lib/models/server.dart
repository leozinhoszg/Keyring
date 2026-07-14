class ServerSummary {
  final String id;
  final String name;
  final String? ip;
  final String? environment;
  final String? services;
  final bool isFavorite;
  final bool hasNotes;
  const ServerSummary({
    required this.id,
    required this.name,
    this.ip,
    this.environment,
    this.services,
    this.isFavorite = false,
    this.hasNotes = false,
  });
}

class ServerInput {
  final String name;
  final String? ip;
  final String? environment;
  final String? services;
  final String? notes;
  final bool isFavorite;
  const ServerInput({
    required this.name,
    this.ip,
    this.environment,
    this.services,
    this.notes,
    this.isFavorite = false,
  });
}
