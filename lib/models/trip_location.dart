class TripLocation {
  final String street;
  final String city;
  final String postalCode;
  final double latitude;
  final double longitude;

  TripLocation({
    required this.street,
    required this.city,
    required this.postalCode,
    required this.latitude,
    required this.longitude,
  });

  Map<String, dynamic> toJson() {
    return {
      'street': street,
      'city': city,
      'postalCode': postalCode,
      'latitude': latitude,
      'longitude': longitude,
    };
  }

  @override
  String toString() {
    return 'TripLocation{street: $street, city: $city, postalCode: $postalCode}';
  }

  static TripLocation fromJson(Map<String, dynamic> json) {
    return TripLocation(
      street: json['street'],
      city: json['city'],
      postalCode: json['postalCode'],
          latitude: (json['latitude'] ?? 0.0).toDouble(),
    longitude: (json['longitude'] ?? 0.0).toDouble(),

    );
  }
}
