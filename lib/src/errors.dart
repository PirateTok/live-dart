/// Base exception for all PirateTok errors.
sealed class PirateTokError implements Exception {
  final String message;
  const PirateTokError(this.message);

  @override
  String toString() => message;
}

class UserNotFoundError extends PirateTokError {
  final String username;
  UserNotFoundError(this.username)
      : super('user "$username" does not exist');
}

class HostNotOnlineError extends PirateTokError {
  final String username;
  HostNotOnlineError(this.username)
      : super('user "$username" is not currently live');
}

class TikTokBlockedError extends PirateTokError {
  final int statusCode;
  TikTokBlockedError(this.statusCode)
      : super('tiktok blocked (HTTP $statusCode)');
}

class TikTokApiError extends PirateTokError {
  final int code;
  TikTokApiError(this.code) : super('tiktok API error: statusCode=$code');
}

class DeviceBlockedError extends PirateTokError {
  const DeviceBlockedError()
      : super('device blocked — ttwid was flagged, fetch a fresh one');
}

class AgeRestrictedError extends PirateTokError {
  const AgeRestrictedError()
      : super(
          'age-restricted stream: 18+ room — pass session cookies to fetchRoomInfo()',
        );
}
