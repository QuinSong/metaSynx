import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class UserService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// Check if user is already signed in elsewhere
  Future<bool> isUserSignedInElsewhere(String uid) async {
    final snapshot = await _firestore.collection('users').doc(uid).get();
    if (!snapshot.exists) return false;
    return snapshot.data()?['signedIn'] == true;
  }

  /// Set signedIn flag to true
  Future<void> setSignedIn(String uid, bool value) async {
    await _firestore.collection('users').doc(uid).update({
      'signedIn': value,
    });
  }

  // Get or create user document, returns assigned relay server
  Future<String> getOrAssignRelayServer(User user) async {
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
  }

  Future<String> _assignServerToUser(User user, DocumentReference userDoc) async {
    // Get the server with the lowest activeRooms
    final serverStats = await _firestore
        .collection('serverStats')
        .where('status', isEqualTo: 'active')
        .orderBy('activeRooms')
        .limit(1)
        .get();

    String assignedServer;

    if (serverStats.docs.isEmpty) {
      // No servers in database - use default
      assignedServer = 'server1.metasynx.io';
      
      // Create the serverStats document for future use
      await _firestore.collection('serverStats').doc(assignedServer).set({
        'activeRooms': 0,
        'maxRooms': 500,
        'status': 'active',
      }, SetOptions(merge: true));
    } else {
      assignedServer = serverStats.docs.first.id;
    }

    // Save user document with assigned server and signedIn flag
    await userDoc.set({
      'email': user.email,
      'relayServer': assignedServer,
      'signedIn': true,
      'createdAt': FieldValue.serverTimestamp(),
      'lastLogin': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    return assignedServer;
  }

  // Update last login timestamp
  Future<void> updateLastLogin(User user) async {
    await _firestore.collection('users').doc(user.uid).update({
      'lastLogin': FieldValue.serverTimestamp(),
    });
  }

  // Sign out - set signedIn to false
  Future<void> signOut(String uid) async {
    try {
      await _firestore.collection('users').doc(uid).update({
        'signedIn': false,
      });
    } catch (e) {
      // Ignore errors on sign out
    }
  }

  // Get user data
  Future<Map<String, dynamic>?> getUserData(String uid) async {
    final snapshot = await _firestore.collection('users').doc(uid).get();
    return snapshot.data();
  }
}