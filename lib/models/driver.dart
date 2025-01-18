import 'package:objectbox/objectbox.dart';
import 'package:uuid/uuid.dart';

enum DrivePermissions { business, personal, both }

@Entity()
class Driver {
  @Id()
  int id = 0;
  //bool isAuthorized = false;
  String drivePermissions = DrivePermissions.business.toString();
  final String firstName;
  final String lastName;

  @Index()
  @Unique()
  String uid;

  Driver({required this.firstName, required this.lastName})
      : uid = const Uuid().v4();

  @override
  String toString() {
    return 'Driver{id: $id, name: $firstName, surname: $lastName, drivePermissions: $drivePermissions, uid: $uid}';
  }
}
