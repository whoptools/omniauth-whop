"""Exercise the deployed demo's HTTP boundary without contacting Whop."""
import http.client
import re
import urllib.parse

connection = http.client.HTTPConnection('127.0.0.1', 9292, timeout=10)
def request(method, path, body=None, headers=None):
    connection.request(method, path, body, {'X-Forwarded-Proto': 'https', **(headers or {})})
    response = connection.getresponse()
    return response.status, dict(response.getheaders()), response.read().decode(errors='replace')

assert request('GET', '/health')[0] == 200
status, headers, body = request('GET', '/')
assert status == 200 and 'Sign in with Whop' in body
cookie = next(value for key, value in headers.items() if key.lower() == 'set-cookie')
assert all(value.lower() in cookie.lower() for value in ['secure', 'httponly', 'samesite=lax'])
token = re.search(r'name="authenticity_token" value="([^"]+)"', body).group(1)
assert request('POST', '/auth/whop', '', {'Content-Type':'application/x-www-form-urlencoded'})[0] == 403
status, headers, _ = request('POST', '/auth/whop', urllib.parse.urlencode({'authenticity_token': token}), {
    'Cookie': cookie.split(';')[0], 'Content-Type': 'application/x-www-form-urlencoded',
    'X-Forwarded-Host': 'untrusted.example', 'Host': 'untrusted.example',
})
assert status == 302
location = next(value for key, value in headers.items() if key.lower() == 'location')
params = urllib.parse.parse_qs(urllib.parse.urlparse(location).query)
assert params['redirect_uri'] == ['https://omniauth.whoptools.com/auth/whop/callback']
assert params['code_challenge_method'] == ['S256']
assert request('GET', '/assets/whoptools/whoptools.css')[0] == 200
assert request('GET', '/assets/whoptools/inter-latin-wght-normal.woff2')[0] == 200
assert request('GET', '/assets/app.css')[0] == 200
assert request('GET', '/.env')[0] == 404
print('Demo health, assets, secure session, CSRF, PKCE and canonical callback passed.')
