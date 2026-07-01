import 'package:cloud_firestore/cloud_firestore.dart';

class EmergencyContact {
  final String name;
  final String phone;

  EmergencyContact({required this.name, required this.phone});

  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'phone': phone,
    };
  }

  factory EmergencyContact.fromMap(Map<String, dynamic> map) {
    return EmergencyContact(
      name: map['name'] ?? '',
      phone: map['phone'] ?? '',
    );
  }
}

class GoSaferUser {
  final String uid;
  final String fullName;
  final String email;
  final String phone;
  final List<EmergencyContact> emergencyContacts;
  final DateTime createdAt;
  final double? latitude;
  final double? longitude;
  final String? fcmToken;

  GoSaferUser({
    required this.uid,
    required this.fullName,
    required this.email,
    required this.phone,
    required this.emergencyContacts,
    required this.createdAt,
    this.latitude,
    this.longitude,
    this.fcmToken,
  });

  Map<String, dynamic> toMap() {
    return {
      'uid': uid,
      'fullName': fullName,
      'email': email,
      'phone': phone,
      'emergencyContacts': emergencyContacts.map((c) => c.toMap()).toList(),
      'createdAt': createdAt,
      'latitude': latitude,
      'longitude': longitude,
      'fcmToken': fcmToken,
    };
  }

  factory GoSaferUser.fromFirestore(DocumentSnapshot doc) {
    Map<String, dynamic> data = doc.data() as Map<String, dynamic>;
    return GoSaferUser(
      uid: data['uid'] ?? '',
      fullName: data['fullName'] ?? '',
      email: data['email'] ?? '',
      phone: data['phone'] ?? '',
      emergencyContacts: (data['emergencyContacts'] as List? ?? [])
          .map((c) => EmergencyContact.fromMap(c as Map<String, dynamic>))
          .toList(),
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      latitude: (data['latitude'] as num?)?.toDouble(),
      longitude: (data['longitude'] as num?)?.toDouble(),
      fcmToken: data['fcmToken'],
    );
  }
}
