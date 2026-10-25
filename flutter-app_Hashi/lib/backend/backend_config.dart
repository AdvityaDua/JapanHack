const configuredCabinBackendUrl = String.fromEnvironment('CABIN_BACKEND_URL');
const configuredCentralBackendUrl = String.fromEnvironment(
  'CENTRAL_BACKEND_URL',
);

String? get cabinBackendOverride =>
    configuredCabinBackendUrl.isEmpty ? null : configuredCabinBackendUrl;
