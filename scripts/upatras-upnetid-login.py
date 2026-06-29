"""
eClass SAML2 Login Debug Script
Login to eclass.upatras.gr via UpnetID (SAML2)

Install:
    pip install requests beautifulsoup4 python-dotenv

Usage:
    python upatras-upnetid-login.py
"""

import os
import json
import requests
from datetime import datetime
from bs4 import BeautifulSoup
from dotenv import load_dotenv

load_dotenv()

USERNAME = os.getenv("UPNET_USERNAME")
PASSWORD = os.getenv("UPNET_PASSWORD")
COOKIES_FILE = os.getenv("COOKIES_FILE", "cookies.json")

if not USERNAME or not PASSWORD:
    print("ERROR: UPNET_USERNAME and UPNET_PASSWORD must be set in .env")
    exit(1)

ECLASS_URL = "https://eclass.upatras.gr"
IDP_BASE   = "https://idp.upnet.gr"

def log(step, msg):
    print("")
    print("-" * 60)
    print("  [upnetid-login] STEP %d: %s" % (step, msg))
    print("-" * 60)

def log_response(r):
    print("  URL:    %s" % r.url)
    print("  Status: %d" % r.status_code)
    if r.headers.get("Location"):
        print("  Location: %s" % r.headers["Location"])
    print("  Cookies: %s" % list(dict(r.cookies).keys()))

session = requests.Session()
session.headers.update({
    "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36"
})

# --------------------------------------------------
# STEP 1: GET /secure -> redirects -> IDP login form
# --------------------------------------------------
log(1, "GET /secure -> IDP login form")

r1 = session.get("%s/secure/" % ECLASS_URL, allow_redirects=True)
log_response(r1)

soup = BeautifulSoup(r1.text, "html.parser")
form = soup.find("form", class_="form-signin")

if not form:
    print("  ERROR: Login form not found")
    print(r1.text[:500])
    exit(1)

login_url = IDP_BASE + form.get("action")
print("  Login URL: %s" % login_url)

# --------------------------------------------------
# STEP 2: POST credentials to IDP
# --------------------------------------------------
log(2, "POST credentials -> IDP")

r2 = session.post(
    login_url,
    data={
        "j_username": USERNAME,
        "j_password": PASSWORD,
        "_eventId_proceed": "",
    },
    allow_redirects=True
)
log_response(r2)

# --------------------------------------------------
# STEP 3: Parse SAMLResponse
# --------------------------------------------------
log(3, "Parse SAMLResponse + RelayState")

soup2 = BeautifulSoup(r2.text, "html.parser")
saml_input  = soup2.find("input", {"name": "SAMLResponse"})
relay_input = soup2.find("input", {"name": "RelayState"})
saml_form   = soup2.find("form")

if not saml_input:
    print("  ERROR: SAMLResponse not found - check credentials")
    exit(1)

saml_response = saml_input.get("value")
relay_state   = relay_input.get("value") if relay_input else ""
saml_post_url = saml_form.get("action") if saml_form else "%s/Shibboleth.sso/SAML2/POST" % ECLASS_URL

print("  SAMLResponse: %s..." % saml_response[:60])
print("  RelayState:   %s" % relay_state[:60])
print("  POST URL:     %s" % saml_post_url)

# --------------------------------------------------
# STEP 4: POST SAMLResponse -> eclass session
# --------------------------------------------------
log(4, "POST SAMLResponse -> eclass")

r3 = session.post(
    saml_post_url,
    data={"SAMLResponse": saml_response, "RelayState": relay_state},
    allow_redirects=True
)
log_response(r3)

# --------------------------------------------------
# STEP 5: Verify login
# --------------------------------------------------
log(5, "Verify login")

r4 = session.get("%s/main/portfolio.php" % ECLASS_URL)
print("  URL:    %s" % r4.url)
print("  Status: %d" % r4.status_code)

soup3 = BeautifulSoup(r4.text, "html.parser")
login_link = soup3.find("a", href=lambda h: h and "login_form" in (h or ""))

if "portfolio" in r4.url and not login_link:
    print("  LOGIN OK")
    print("  Session cookies: %s" % list(dict(session.cookies).keys()))
else:
    print("  LOGIN FAILED")
    exit(1)

# --------------------------------------------------
# STEP 6: Save cookies
# --------------------------------------------------
log(6, "Save cookies")

cookies_data = {
    "saved_at": datetime.now().isoformat(),
    "domain": "eclass.upatras.gr",
    "cookies": dict(session.cookies)
}

with open(COOKIES_FILE, "w") as f:
    json.dump(cookies_data, f, indent=2)

print("  Saved to %s" % COOKIES_FILE)
print("  Keys: %s" % list(cookies_data["cookies"].keys()))