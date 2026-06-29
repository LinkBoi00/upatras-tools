"""
eClass Group Poller
Polls a specific group category for changes every 10 minutes.

Install:
    pip install requests beautifulsoup4 python-dotenv

Usage:
    python upatras-eclass_poll_groups.py
    python upatras-eclass_poll_groups.py --cookies cookies.json --interval 10
"""

import os
import re
import json
import time
import argparse
import subprocess
import requests
from bs4 import BeautifulSoup
from datetime import datetime

ECLASS_URL = "https://eclass.upatras.gr"

def log(msg):
    print("[poll] %s" % msg)

def ts():
    return datetime.now().strftime("%H:%M:%S")

# --------------------------------------------------
# Args
# --------------------------------------------------
parser = argparse.ArgumentParser()
parser.add_argument("--cookies",  default="cookies.json", help="Path to cookies.json")
parser.add_argument("--interval", default=10, type=int, help="Poll interval in minutes")
args = parser.parse_args()

# --------------------------------------------------
# Session helpers
# --------------------------------------------------
def load_cookies():
    if not os.path.exists(args.cookies):
        return None
    with open(args.cookies) as f:
        return json.load(f)

def session_from_cookies(cookies_data):
    session = requests.Session()
    session.headers.update({
        "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36"
    })
    for k, v in cookies_data["cookies"].items():
        session.cookies.set(k, v, domain="eclass.upatras.gr")
    return session

def ensure_logged_in():
    cookies_data = load_cookies()
    if not cookies_data:
        log("No cookies found - running upatras-upnetid_login.py...")
        subprocess.run(["python", "upatras-upnetid_login.py"], check=True)
        cookies_data = load_cookies()
    return session_from_cookies(cookies_data)

def fetch_page(session, url):
    r = session.get(url)
    if "login_form" in r.url or "login_form" in r.text[:500]:
        return None
    return BeautifulSoup(r.text, "html.parser")

def fetch_with_relogin(url):
    session = ensure_logged_in()
    soup = fetch_page(session, url)
    if soup is None:
        log("Session expired - re-logging in...")
        subprocess.run(["python", "upatras-upnetid_login.py"], check=True)
        session = ensure_logged_in()
        soup = fetch_page(session, url)
    return soup

# --------------------------------------------------
# Course selection
# --------------------------------------------------
def pick_course():
    log("Fetching enrolled courses...")
    soup = fetch_with_relogin("%s/main/portfolio.php" % ECLASS_URL)

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
    for i, (code, name) in enumerate(courses, 1):
        print("  [%d] %s - %s" % (i, code, name))
    print("")

    while True:
        choice = input("  Select course number: ").strip()
        if choice.isdigit() and 1 <= int(choice) <= len(courses):
            return courses[int(choice) - 1]
        print("  Invalid selection, try again.")

# --------------------------------------------------
# Category selection
# --------------------------------------------------
def pick_category(course_code):
    log("Fetching group categories for %s..." % course_code)
    base_url = "%s/modules/group/index.php?course=%s&show=list" % (ECLASS_URL, course_code)
    soup = fetch_with_relogin(base_url)

    category_table = soup.find("table", class_="category-links")
    if not category_table:
        print("ERROR: No categories found for %s" % course_code)
        exit(1)

    categories = []
    for th in category_table.find_all("th", class_="category-link"):
        link = th.find("a")
        if not link:
            continue
        name = link.get_text(strip=True)
        href = link.get("href", "")
        urlview_match = re.search(r"urlview=([01]+)", href)
        urlview = urlview_match.group(1) if urlview_match else None
        if urlview:
            categories.append((name, urlview))

    print("")
    print("=" * 60)
    print("  Group Categories")
    print("=" * 60)
    for i, (name, urlview) in enumerate(categories, 1):
        print("  [%d] %s" % (i, name))
    print("")

    while True:
        choice = input("  Select category number to poll: ").strip()
        if choice.isdigit() and 1 <= int(choice) <= len(categories):
            return categories[int(choice) - 1], base_url
        print("  Invalid selection, try again.")

# --------------------------------------------------
# Fetch slots for a category
# --------------------------------------------------
def fetch_slots(base_url, urlview):
    url = "%s&urlview=%s" % (base_url, urlview)
    soup = fetch_with_relogin(url)
    slots = {}
    category_table = soup.find("table", class_="category-links")
    if not category_table:
        return slots
    for row in category_table.find_all("tr"):
        if row.find("th", class_="category-link"):
            continue
        tds = row.find_all("td")
        if not tds:
            continue
        name    = tds[0].get_text(strip=True) if tds else ""
        current = tds[2].get_text(strip=True) if len(tds) > 2 else ""
        maximum = tds[3].get_text(strip=True) if len(tds) > 3 else ""
        if name:
            slots[name] = (current, maximum)
    return slots

def print_slots(slots):
    for name, (current, maximum) in slots.items():
        print("    - %s (%s/%s)" % (name, current, maximum))

def diff_slots(old, new):
    changes = []
    for name, (cur, mx) in new.items():
        if name not in old:
            changes.append("NEW GROUP: %s (%s/%s)" % (name, cur, mx))
        elif old[name] != (cur, mx):
            changes.append("CHANGED: %s %s/%s -> %s/%s" % (name, old[name][0], old[name][1], cur, mx))
    for name in old:
        if name not in new:
            changes.append("REMOVED: %s" % name)
    return changes

# --------------------------------------------------
# Main
# --------------------------------------------------
course_code, course_name = pick_course()
(cat_name, urlview), base_url = pick_category(course_code)

print("")
print("=" * 60)
print("  Polling: %s" % cat_name)
print("  Course:  %s - %s" % (course_code, course_name))
print("  Every:   %d minutes" % args.interval)
print("  Press Ctrl+C to stop")
print("=" * 60)

previous_slots = None

while True:
    print("\n[%s] Fetching..." % ts())
    current_slots = fetch_slots(base_url, urlview)

    if previous_slots is None:
        print("  Initial state:")
        print_slots(current_slots)
    else:
        changes = diff_slots(previous_slots, current_slots)
        if changes:
            print("  CHANGES DETECTED:")
            for c in changes:
                print("  *** %s" % c)
        else:
            print("  No changes (%d groups)" % len(current_slots))

    previous_slots = current_slots
    print("  Next check in %d minutes..." % args.interval)
    time.sleep(args.interval * 60)