import 'dart:io';

import 'package:google_sign_in/google_sign_in.dart';
import 'package:googleapis/drive/v3.dart' as ga;
import 'package:http/http.dart' as http;

class GoogleDriveService {
  static final GoogleDriveService _instance = GoogleDriveService._internal();
  factory GoogleDriveService() => _instance;
  GoogleDriveService._internal();

  static const List<String> _scopes = ['https://www.googleapis.com/auth/drive.appdata'];

  final GoogleSignIn _googleSignIn = GoogleSignIn(scopes: _scopes);
  GoogleSignInAccount? _currentUser;

  /// आखिरी गलती का साफ़ संदेश (UI में दिखाने के लिए)
  String? lastError;

  String _friendly(Object e) {
    final s = e.toString();
    if (s.contains('access_denied') || s.contains('403')) {
      return 'Google ने पहुँच रोकी: अपना Gmail OAuth consent screen में "Test users" में जोड़ें, और Drive API चालू करें।';
    }
    if (s.contains('accessNotConfigured') || s.contains('has not been used')) {
      return 'Google Drive API इस project में चालू नहीं है। Google Cloud Console में Enable करें।';
    }
    if (s.contains('ApiException: 10') || s.contains('DEVELOPER_ERROR')) {
      return 'SHA-1 या package name मेल नहीं खाता। Android OAuth client जाँचें।';
    }
    if (s.contains('network') || s.contains('SocketException')) {
      return 'इंटरनेट कनेक्शन नहीं है।';
    }
    return s.length > 180 ? s.substring(0, 180) : s;
  }

  /// Google लॉगिन + Drive अनुमति
  Future<bool> signIn() async {
    lastError = null;
    try {
      _currentUser = await _googleSignIn.signInSilently() ?? await _googleSignIn.signIn();
      if (_currentUser == null) {
        lastError = 'Google लॉगिन रद्द हुआ।';
        return false;
      }
      final granted = await _googleSignIn.requestScopes(_scopes);
      if (!granted) {
        lastError = 'Drive की अनुमति नहीं दी गई। लॉगिन दोबारा करें और Drive access स्वीकार करें।';
        return false;
      }
      return true;
    } catch (e) {
      lastError = _friendly(e);
      return false;
    }
  }

  Future<void> signOut() async {
    await _googleSignIn.signOut();
    _currentUser = null;
  }

  Future<bool> uploadBackup(File backupFile, String fileName) async {
    lastError = null;
    if (_currentUser == null) {
      final ok = await signIn();
      if (!ok) return false;
    }

    try {
      final authHeaders = await _currentUser!.authHeaders;
      final client = _GoogleHttpClient(authHeaders);
      final driveApi = ga.DriveApi(client);

      final existing = await driveApi.files.list(
        q: "name = '$fileName' and trashed = false",
        spaces: 'appDataFolder',
      );
      if (existing.files != null && existing.files!.isNotEmpty) {
        await driveApi.files.delete(existing.files!.first.id!);
      }

      final metadata = ga.File()
        ..name = fileName
        ..parents = ['appDataFolder'];

      await driveApi.files.create(
        metadata,
        uploadMedia: ga.Media(backupFile.openRead(), backupFile.lengthSync()),
      );
      client.close();
      return true;
    } catch (e) {
      lastError = _friendly(e);
      return false;
    }
  }
}

class _GoogleHttpClient extends http.BaseClient {
  final Map<String, String> _headers;
  final http.Client _client = http.Client();

  _GoogleHttpClient(this._headers);

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    request.headers.addAll(_headers);
    return _client.send(request);
  }

  @override
  void close() {
    _client.close();
    super.close();
  }
}
