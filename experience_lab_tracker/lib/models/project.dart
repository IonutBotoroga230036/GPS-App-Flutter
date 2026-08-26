/// One research project as returned by `GET /projects`.
/// The server returns a list of objects with at least an id and a name.
class Project {
  final int id;
  final String name;

  const Project({required this.id, required this.name});

  factory Project.fromJson(Map<String, dynamic> json) {
    // The server has used a few key spellings over time; accept the common ones.
    final dynamic rawId = json['id'] ?? json['project_id'];
    final dynamic rawName =
        json['name'] ?? json['project_name'] ?? json['project'];
    return Project(
      id: rawId is int ? rawId : int.parse(rawId.toString()),
      name: rawName?.toString() ?? 'Unknown',
    );
  }
}
