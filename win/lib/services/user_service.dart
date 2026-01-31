import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

class UserService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// Check if user is already signed in elsewhere
  Future<bool> isUserSignedInElsewhere(String uid) async {
    try {
      final snapshot = await _firestore.collection('users').doc(uid).get();
      if (!snapshot.exists) return false;
      return snapshot.data()?['signedIn'] == true;
    } catch (e) {
      debugPrint('Error checking signedIn status: $e');
      return false;
    }
  }

  /// Set signedIn flag
  Future<void> setSignedIn(String uid, bool value) async {
    try {
      // Use set with merge to create doc if it doesn't exist
      await _firestore.collection('users').doc(uid).set({
        'signedIn': value,
      }, SetOptions(merge: true));
    } catch (e) {
      debugPrint('Error setting signedIn: $e');
    }
  }

  // Get or create user document, returns assigned relay server
  Future<String> getOrAssignRelayServer(User user) async {
    try {
      final userDoc = _firestore.collection('users').doc(user.uid);
      final snapshot = await userDoc.get();

      if (snapshot.exists) {
        final data = snapshot.data();
        final relayServer = data?['relayServer'] as String?;
        if (relayServer != null && relayServer.isNotEmpty) {
          // Mark user as signed in
          await setSignedIn(user.uid, true);
          return relayServer;
        }
      }

      // User doesn't have a server assigned - assign one
      final server = await _assignServerToUser(user, userDoc);
      return server;
    } catch (e) {
      debugPrint('Error in getOrAssignRelayServer: $e');
      // Return default server on error
      return 'server1.metasynx.io';
    }
  }

  Future<String> _assignServerToUser(User user, DocumentReference userDoc) async {
    try {
      // Default server - when you have multiple servers, add selection logic here
      const assignedServer = 'server1.metasynx.io';

      // Save user document with assigned server and signedIn flag
      debugPrint('Creating user document for ${user.uid}');
      await userDoc.set({
        'email': user.email,
        'relayServer': assignedServer,
        'signedIn': true,
        'createdAt': FieldValue.serverTimestamp(),
        'lastLogin': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      
      debugPrint('User document created successfully');
      return assignedServer;
    } catch (e) {
      debugPrint('Error in _assignServerToUser: $e');
      return 'server1.metasynx.io';
    }
  }

  // Update last login timestamp
  Future<void> updateLastLogin(User user) async {
    try {
      // Use set with merge in case document doesn't exist
      await _firestore.collection('users').doc(user.uid).set({
        'lastLogin': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (e) {
      debugPrint('Error updating lastLogin: $e');
    }
  }

  // Sign out - set signedIn to false
  Future<void> signOut(String uid) async {
    try {
      // Use set with merge in case document doesn't exist
      await _firestore.collection('users').doc(uid).set({
        'signedIn': false,
      }, SetOptions(merge: true));
    } catch (e) {
      debugPrint('Error in signOut: $e');
    }
  }

  // Get user data
  Future<Map<String, dynamic>?> getUserData(String uid) async {
    try {
      final snapshot = await _firestore.collection('users').doc(uid).get();
      return snapshot.data();
    } catch (e) {
      debugPrint('Error getting user data: $e');
      return null;
    }
  }

  /// Increment activeRooms for a server (call when mobile connects)
  Future<void> incrementActiveRooms(String server) async {
    try {
      await _firestore.collection('serverStats').doc(server).update({
        'activeRooms': FieldValue.increment(1),
      });
    } catch (e) {
      debugPrint('Error incrementing activeRooms: $e');
    }
  }

  /// Decrement activeRooms for a server (call when new room created/mobile disconnected)
  Future<void> decrementActiveRooms(String server) async {
    try {
      await _firestore.collection('serverStats').doc(server).update({
        'activeRooms': FieldValue.increment(-1),
      });
    } catch (e) {
      debugPrint('Error decrementing activeRooms: $e');
    }
  }
}