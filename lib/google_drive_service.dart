import 'dart:io';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:googleapis/drive/v3.dart' as ga;
import 'package:http/http.dart' as http;

class GoogleDriveService {
  static final GoogleDriveService _instance = GoogleDriveService._internal();
  factory GoogleDriveService() => _instance;
  GoogleDriveService._internal();

  final GoogleSignIn _googleSignIn = GoogleSignIn(
    scopes: [
      'https://www.googleapis.com/auth/drive.appdata', // WhatsApp जैसा छिपा फोल्डर
    ],
  );

  GoogleSignInAccount? _currentUser;

  // 1. Google लॉगिन
  Future<bool> signIn() async {
    try {
      _currentUser = await _googleSignIn.signIn();
      return _currentUser != null;
    } catch (e) {
      print('Sign in error: $e');
      return false;
    }
  }

  // 2. लॉगआउट
  Future<void> signOut() async {
    await _googleSignIn.signOut();
    _currentUser = null;
  }

  // 3. Google Drive में बैकअप अपलोड करना
  Future<bool> uploadBackup(File backupFile, String fileName) async {
    if (_currentUser == null) {
      final signedIn = await signIn();
      if (!signedIn) return false;
    }

    try {
      final authHeaders = await _currentUser!.authHeaders;
      final client = _GoogleHttpClient(authHeaders);
      final driveApi = ga.DriveApi(client);

      // पुरानी बैकअप फाइल को डिलीट करें (ताकि डुप्लीकेट न हों)
      final existingFiles = await driveApi.files.list(
        q: "name = '$fileName' and trashed = false",
        spaces: 'appDataFolder',
      );

      if (existingFiles.files != null && existingFiles.files!.isNotEmpty) {
        await driveApi.files.delete(existingFiles.files!.first.id!);
      }

      // नई फाइल को छिपे हुए App Data फोल्डर में अपलोड करें
      final fileMetadata = ga.File()
        ..name = fileName
        ..parents = ['appDataFolder'];

      await driveApi.files.create(
        fileMetadata,
        uploadMedia: ga.Media(
          backupFile.openRead(),
          backupFile.lengthSync(),
        ),
      );

      return true;
    } catch (e) {
      print('Upload error: $e');
      return false;
    }
  }
}

// Google API के लिए जरूरी हेल्पर
class _GoogleHttpClient extends http.BaseClient {
  final Map<String, String> _headers;
  final http.Client _client = http.Client();

  _GoogleHttpClient(this._headers);

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    request.headers.addAll(_headers);
    return _client.send(request);
  }
}
