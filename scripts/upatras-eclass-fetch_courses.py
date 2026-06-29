"""
eClass Course Fetcher
Reads cookies from cookies.json and fetches enrolled courses from portfolio.

Install:
    pip install requests beautifulsoup4

Usage:
    python fetch_courses.py
    python fetch_courses.py --cookies cookies.json
"""

import os
import re
import json
import argparse
import requests
from bs4 import BeautifulSoup

ECLASS_URL = "https://eclass.upatras.gr"

def log(msg):
    print("[fetch-courses] %s" % msg)

# --------------------------------------------------
# Args
# --------------------------------------------------
parser = argparse.ArgumentParser()
parser.add_argument("--cookies", default="cookies.json", help="Path to cookies.json")
args = parser.parse_args()

# --------------------------------------------------
# Load cookies
# --------------------------------------------------
if not os.path.exists(args.cookies):
    print("ERROR: %s not found - run login.py first" % args.cookies)
    exit(1)

with open(args.cookies) as f:
    cookies_data = json.load(f)

log("Loaded cookies from %s (saved at %s)" % (args.cookies, cookies_data.get("saved_at", "?")))

session = requests.Session()
session.headers.update({
    "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36"
})
for k, v in cookies_data["cookies"].items():
    session.cookies.set(k, v, domain="eclass.upatras.gr")

# --------------------------------------------------
# Fetch portfolio
# --------------------------------------------------
url = "%s/main/portfolio.php" % ECLASS_URL
log("Fetching %s" % url)

r = session.get(url)
if "login_form" in r.url or "login_form" in r.text[:500]:
    print("ERROR: Session expired - run login.py again")
    exit(1)

soup = BeautifulSoup(r.text, "html.parser")

# --------------------------------------------------
# Parse courses
# --------------------------------------------------
courses = []
for row in soup.find_all("tr", class_="row-course"):
    link = row.find("a", class_="TextBold")
    if not link:
        continue
    name = link.get_text(strip=True)
    href = link.get("href", "")
    code_match = re.search(r"/courses/([^/]+)/", href)
    code = code_match.group(1) if code_match else ""
    if code:
        courses.append((code, name))

print("")
print("=" * 60)
print("  Enrolled Courses")
print("=" * 60)
print("")

for i, (code, name) in enumerate(courses, 1):
    print("  [%d] %s - %s" % (i, code, name))

print("")
log("Found %d courses" % len(courses))