import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import '../models/user_model.dart';

class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // Stream of auth state changes
  Stream<User?> get userStream => _auth.authStateChanges();

  // Registration
  Future<User?> register({
    required String fullName,
    required String email,
    required String password,
    required String phone,
    required List<EmergencyContact> emergencyContacts,
  }) async {
    try {
      // 1. Create Auth User
      UserCredential result = await _auth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );
      User? user = result.user;

      if (user != null) {
        // 2. Add Display Name to Auth
        await user.updateDisplayName(fullName);

        // 3. Create Firestore User Document
        GoSaferUser newUser = GoSaferUser(
          uid: user.uid,
          fullName: fullName,
          email: email,
          phone: phone,
          emergencyContacts: emergencyContacts,
          createdAt: DateTime.now(),
        );

        await _firestore.collection('users').doc(user.uid).set(newUser.toMap());
      }
      return user;
    } catch (e) {
      debugPrint('Registration Error: $e');
      rethrow;
    }
  }

  // Login
  Future<User?> signIn(String email, String password) async {
    try {
      UserCredential result = await _auth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );
      return result.user;
    } catch (e) {
      debugPrint('Login Error: $e');
      rethrow;
    }
  }

  // Sign Out
  Future<void> signOut() async {
    await _auth.signOut();
  }

  // Get current user data from Firestore
  Future<GoSaferUser?> getCurrentUserData() async {
    User? user = _auth.currentUser;
    if (user != null) {
      DocumentSnapshot doc = await _firestore.collection('users').doc(user.uid).get();
      if (doc.exists) {
        return GoSaferUser.fromFirestore(doc);
      }
    }
    return null;
  }

  // Update user location in Firestore
  Future<void> updateUserLocation(double lat, double lng) async {
    User? user = _auth.currentUser;
    if (user != null) {
      await _firestore.collection('users').doc(user.uid).update({
        'latitude': lat,
        'longitude': lng,
      });
    }
  }

  // Update FCM token in Firestore
  Future<void> updateFcmToken(String token) async {
    User? user = _auth.currentUser;
    if (user != null) {
      await _firestore.collection('users').doc(user.uid).update({
        'fcmToken': token,
      });
    }
  }

  // Add an emergency contact
  Future<void> addEmergencyContact(EmergencyContact contact) async {
    User? user = _auth.currentUser;
    if (user != null) {
      await _firestore.collection('users').doc(user.uid).update({
        'emergencyContacts': FieldValue.arrayUnion([contact.toMap()]),
      });
    }
  }

  // Update all emergency contacts
  Future<void> updateEmergencyContacts(List<EmergencyContact> contacts) async {
    User? user = _auth.currentUser;
    if (user != null) {
      await _firestore.collection('users').doc(user.uid).update({
        'emergencyContacts': contacts.map((c) => c.toMap()).toList(),
      });
    }
  }
}
