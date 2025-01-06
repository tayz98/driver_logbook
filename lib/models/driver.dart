// ignore_for_file: public_member_api_docs, sort_constructors_first
import 'dart:convert';

class Driver {
  final int selfAssignedId;
  bool isAuthorized = false;
  bool privateTrips = false;

  Driver({
    required this.selfAssignedId,
    required this.isAuthorized,
    required this.privateTrips,
  });

  Driver copyWith({
    int? selfAssignedId,
    bool? isAuthorized,
    bool? privateTrips,
  }) {
    return Driver(
      selfAssignedId: selfAssignedId ?? this.selfAssignedId,
      isAuthorized: isAuthorized ?? this.isAuthorized,
      privateTrips: privateTrips ?? this.privateTrips,
    );
  }

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'selfAssignedId': selfAssignedId,
      'isAuthorized': isAuthorized,
      'privateTrips': privateTrips,
    };
  }

  factory Driver.fromMap(Map<String, dynamic> map) {
    return Driver(
      selfAssignedId: map['selfAssignedId'] as int,
      isAuthorized: map['isAuthorized'] as bool,
      privateTrips: map['privateTrips'] as bool,
    );
  }

  String toJson() => json.encode(toMap());

  factory Driver.fromJson(String source) =>
      Driver.fromMap(json.decode(source) as Map<String, dynamic>);

  @override
  String toString() =>
      'Driver(selfAssignedId: $selfAssignedId, isAuthorized: $isAuthorized, privateTrips: $privateTrips)';

  @override
  bool operator ==(covariant Driver other) {
    if (identical(this, other)) return true;

    return other.selfAssignedId == selfAssignedId &&
        other.isAuthorized == isAuthorized &&
        other.privateTrips == privateTrips;
  }

  @override
  int get hashCode =>
      selfAssignedId.hashCode ^ isAuthorized.hashCode ^ privateTrips.hashCode;
}
