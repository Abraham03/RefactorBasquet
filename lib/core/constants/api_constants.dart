// lib/core/constants/api_constants.dart

/// Raíz del servidor. Debe terminar en '/' para que `Uri.resolve` funcione.
const String kServerBaseUrl = 'https://vanball.com.mx/';

/// Endpoint único de la API (enrutado por query param `action`).
const String kApiEndpoint = '${kServerBaseUrl}api.php';
