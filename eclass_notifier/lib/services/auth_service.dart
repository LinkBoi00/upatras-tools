import 'package:http/http.dart' as http;
import 'package:beautiful_soup_dart/beautiful_soup.dart';
import 'package:logger/logger.dart';
import 'storage_service.dart';

final _log = Logger();

class AuthService {
  static const _eclassUrl = 'https://eclass.upatras.gr';
  static const _idpBase = 'https://idp.upnet.gr';

  static const _userAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36';

  static Map<String, String> _cookies = {};

  static Map<String, String> get _baseHeaders => {
    'User-Agent': _userAgent,
    if (_cookies.isNotEmpty)
      'Cookie': _cookies.entries.map((e) => '${e.key}=${e.value}').join('; '),
  };

  static void _updateCookies(http.Response r) {
    final setCookie = r.headers['set-cookie'];
    if (setCookie == null) return;
    for (final part in setCookie.split(RegExp(r',(?=[^ ])'))) {
      final nameValue = part.split(';').first.trim();
      final idx = nameValue.indexOf('=');
      if (idx == -1) continue;
      final key = nameValue.substring(0, idx).trim();
      final val = nameValue.substring(idx + 1).trim();
      _cookies[key] = val;
    }
  }

  static Future<http.Response> _get(String url) async {
    var uri = Uri.parse(url);
    int redirects = 0;

    while (redirects < 10) {
      final request = http.Request('GET', uri)..followRedirects = false;
      request.headers.addAll(_baseHeaders);
      final streamed  = await request.send();
      final response  = await http.Response.fromStream(streamed);
      _updateCookies(response);

      _log.d('[auth] GET $uri -> ${response.statusCode}');

      if (response.statusCode == 301 ||
          response.statusCode == 302 ||
          response.statusCode == 303) {
        final location = response.headers['location'] ?? '';
        uri = location.startsWith('http')
            ? Uri.parse(location)
            : uri.resolve(location);
        redirects++;
        continue;
      }
      return response;
    }
    throw Exception('Too many redirects');
  }

  static Future<http.Response> _post(String url, Map<String, String> body) async {
    final uri = Uri.parse(url);
    final req = http.Request('POST', uri)..followRedirects = false;
    req.headers.addAll(_baseHeaders);
    req.headers['Content-Type'] = 'application/x-www-form-urlencoded';
    req.bodyFields = body;
    final streamed = await req.send();
    final r        = await http.Response.fromStream(streamed);
    _updateCookies(r);

    _log.d('[auth] POST $uri -> ${r.statusCode}');

    if (r.statusCode == 302 || r.statusCode == 301) {
      final location = r.headers['location'] ?? '';
      final next = location.startsWith('http')
          ? location
          : '${uri.scheme}://${uri.host}$location';
      return _get(next);
    }
    return r;
  }

  // --------------------------------------------------
  // Login
  // --------------------------------------------------
  static Future<bool> login(String username, String password) async {
    try {
      _cookies = {};

      // STEP 1: GET /secure -> IDP login form
      final r1   = await _get('$_eclassUrl/secure/');
      final soup1 = BeautifulSoup(r1.body);
      final form  = soup1.find('form', attrs: {'class': 'form-signin'});
      _log.d('[auth] STEP 1: ${r1.statusCode} | form found: ${form != null}');

      if (form == null) return false;

      final action   = form.attributes['action'] ?? '';
      final loginUrl = '$_idpBase$action';

      // STEP 2: POST credentials
      final r2 = await _post(loginUrl, {
        'j_username':       username,
        'j_password':       password,
        '_eventId_proceed': '',
      });
      _log.d('[auth] STEP 2: ${r2.statusCode}');

      // STEP 3: Parse SAMLResponse
      final soup2      = BeautifulSoup(r2.body);
      final samlInput  = soup2.find('input', attrs: {'name': 'SAMLResponse'});
      final relayInput = soup2.find('input', attrs: {'name': 'RelayState'});
      final samlForm   = soup2.find('form');
      _log.d('[auth] STEP 3: SAMLResponse found: ${samlInput != null}');

      if (samlInput == null) return false;

      final samlResponse = samlInput.attributes['value'] ?? '';
      final relayState   = relayInput?.attributes['value'] ?? '';
      final postUrl      = samlForm?.attributes['action']
          ?? '$_eclassUrl/Shibboleth.sso/SAML2/POST';

      // STEP 4: POST SAMLResponse -> eclass session
      final r3 = await _post(postUrl, {
        'SAMLResponse': samlResponse,
        'RelayState':   relayState,
      });
      _log.d('[auth] STEP 4: ${r3.statusCode}');

      // STEP 5: Verify
      final r4 = await _get('$_eclassUrl/main/portfolio.php');
      final ok = r4.realUrl.contains('portfolio');
      _log.i('[auth] Login ${ok ? 'successful' : 'failed'}');

      if (!ok) return false;

      await StorageService.saveCookies(_cookies);
      return true;
    } catch (e) {
      _log.e('[auth] Login error', error: e);
      return false;
    }
  }

  // --------------------------------------------------
  // Load saved session
  // --------------------------------------------------
  static Future<void> loadSession() async {
    _cookies = await StorageService.getCookies();
    _log.d('[auth] Session loaded: ${_cookies.isNotEmpty}');
  }

  // --------------------------------------------------
  // Check if session is still valid
  // --------------------------------------------------
  static Future<bool> isSessionValid() async {
    if (_cookies.isEmpty) await loadSession();
    if (_cookies.isEmpty) return false;
    try {
      final r  = await _get('$_eclassUrl/main/portfolio.php');
      final ok = r.realUrl.contains('portfolio') && !r.body.contains('login_form');
      _log.d('[auth] Session valid: $ok');
      return ok;
    } catch (e) {
      _log.e('[auth] Session check error', error: e);
      return false;
    }
  }

  // --------------------------------------------------
  // Ensure logged in (relogin if needed)
  // --------------------------------------------------
  static Future<bool> ensureLoggedIn(String username, String password) async {
    if (await isSessionValid()) return true;
    _log.i('[auth] Session invalid, re-logging in');
    return login(username, password);
  }

  // --------------------------------------------------
  // GET with session (for eclass_service)
  // --------------------------------------------------
  static Future<String?> getPage(String url) async {
    try {
      final r = await _get(url);
      if (r.body.contains('login_form')) {
        _log.w('[auth] Session expired on getPage');
        return null;
      }
      return r.body;
    } catch (e) {
      _log.e('[auth] getPage error', error: e);
      return null;
    }
  }
}

extension on http.Response {
  String get realUrl => request?.url.toString() ?? '';
}