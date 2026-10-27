import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/config/firestore_paths.dart';
import '../models/app_user.dart';
import 'user_repository.dart';

class FirestoreUserRepository implements UserRepository {
  FirestoreUserRepository(this._firestore);

  final FirebaseFirestore _firestore;

  @override
  Stream<AppUser?> watchUser(String uid) {
    return _firestore
        .collection(FirestorePaths.usuarios)
        .doc(uid)
        .snapshots()
        .map((doc) {
      final data = doc.data();
      return data == null ? null : AppUser.fromMap(doc.id, data);
    });
  }

  @override
  Future<void> markActivated(String uid) => _firestore
      .collection(FirestorePaths.usuarios)
      .doc(uid)
      .update({'activadoEn': FieldValue.serverTimestamp()});
}
