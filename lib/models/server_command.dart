class ServerCommand {
  final String id;
  final String serverId;
  final String label;
  final String command;
  final int sortOrder;
  const ServerCommand({
    required this.id,
    required this.serverId,
    required this.label,
    required this.command,
    this.sortOrder = 0,
  });
}
