import 'cabin_link.dart';
import 'backend/communication_client.dart';
import 'kit.dart';
import 'protocol.dart';

/// The passenger's place in the cabin: the seat, what the cabin has told us, and the live line to it.
/// One of these lives for the whole app, so the connection stays up while the passenger looks at cards or settings.
class CabinSession {
  final Profile profile;
  final CabinStore store;
  final CabinLink link;

  CabinSession(this.profile, this.store, this.link);

  /// A session for the profile's seat. The store and the link are made together so they always match.
  factory CabinSession.forProfile(
    Profile profile, {
    CabinLink Function(CabinStore)? makeLink,
  }) {
    final store = CabinStore(profile.seat);
    return CabinSession(profile, store, (makeLink ?? CabinLink.new)(store));
  }

  /// What the cabin is told about this phone when it connects or the profile changes.
  Map<String, dynamic> hello() => {
    'lang': profile.lang,
    'senior': profile.senior,
    'needs': profile.needs.toList(),
  };

  void connect(String baseUrl, {PairingCredentials? credentials}) =>
      link.start(baseUrl, hello, credentials: credentials);

  void dispose() => link.dispose();
}
