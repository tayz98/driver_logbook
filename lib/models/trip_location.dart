class TripLocation {
  final String street;
  final String city;
  final String postalCode;

  TripLocation({
    required this.street,
    required this.city,
    required this.postalCode,
  });

  Map<String, dynamic> toJson() {
    return {
      'street': street,
      'city': city,
      'postalCode': postalCode,
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
    );
  }
}
