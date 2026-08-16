/// Web stub — no filesystem / Platform access.
bool get ttsHasEnvironmentCredentials => false;

String? get ttsEnvironmentCredentialsPath => null;

Future<String?> readTtsCredentialsFile(String path) async => null;

Future<String?> writeTtsCacheFile(String key, List<int> bytes, {String ext = 'mp3'}) async => null;

Future<({List<int> bytes, String path})?> readTtsCacheFile(String key, {String ext = 'mp3'}) async =>
    null;

Future<bool> cacheFileExists(String path) async => false;

Future<List<int>?> readFileBytes(String path) async => null;
