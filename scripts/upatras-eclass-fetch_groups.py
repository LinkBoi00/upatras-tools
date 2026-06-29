"""
eClass Group Fetcher
Reads cookies from cookies.json and fetches groups for a given course.
Fetches each category individually for clean output.

Install:
    pip install requests beautifulsoup4

Usage:
    python upatras-eclass-fetch_groups.py --course CEID1092
    python upatras-eclass-fetch_groups.py --course CEID1092 --cookies cookies.json
"""

import os
import re
import json
import argparse
import requests
from bs4 import BeautifulSoup

ECLASS_URL = "https://eclass.upatras.gr"

def log(msg):
    print("[fetch-groups] %s" % msg)

# --------------------------------------------------
# Args
# --------------------------------------------------
parser = argparse.ArgumentParser()
parser.add_argument("--course",  required=True, help="Course code e.g. CEID1092")
parser.add_argument("--cookies", default="cookies.json", help="Path to cookies.json")
args = parser.parse_args()

# --------------------------------------------------
# Load cookies
# --------------------------------------------------
if not os.path.exists(args.cookies):
    print("ERROR: %s not found - run upatras-upnetid_login.py first" % args.cookies)
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

def fetch_page(url):
    r = session.get(url)
    if "login_form" in r.url or "login_form" in r.text[:500]:
        print("ERROR: Session expired - run upatras-upnetid_login.py again")
        exit(1)
    return BeautifulSoup(r.text, "html.parser")

def parse_general_groups(soup):
    general_table = soup.find("table", class_="table-default")
    if not general_table or "category-links" in general_table.get("class", []):
        return
    print("\n  General Groups:")
    print("  " + "-" * 40)
    rows = general_table.find("tbody").find_all("tr") if general_table.find("tbody") else []
    for row in rows:
        cols = row.find_all("td")
        if not cols:
            continue
        name_el = cols[0].find("a") or cols[0].find("p")
        name    = name_el.get_text(strip=True) if name_el else cols[0].get_text(strip=True)
        is_mine = bool(cols[0].find("span", class_="Success-200-bg"))
        members = ""
        if len(cols) > 2:
            badge = cols[2].find("span", class_="Primary-600-bg")
            if badge:
                members = badge.get_text(strip=True)
        mine_tag = " [my group]" if is_mine else ""
        print("  %s%s - %s" % (name, mine_tag, members))

def parse_category_list(soup):
    category_table = soup.find("table", class_="category-links")
    if not category_table:
        return []
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
    return categories

def parse_slots(soup):
    slots = []
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
            slots.append((name, current, maximum))
    return slots

def fetch_category(i, name, urlview, base_url):
    cat_url = "%s&urlview=%s" % (base_url, urlview)
    cat_soup = fetch_page(cat_url)
    slots = parse_slots(cat_soup)
    print("\n  [%d] %s" % (i, name))
    if not slots:
        print("    (no groups)")
    for slot_name, current, maximum in slots:
        print("    - %s (%s/%s)" % (slot_name, current, maximum))

# --------------------------------------------------
# Main
# --------------------------------------------------
base_url = "%s/modules/group/index.php?course=%s&show=list" % (ECLASS_URL, args.course)
log("Fetching %s" % base_url)

soup = fetch_page(base_url)

print("")
print("=" * 60)
print("  Course: %s" % args.course)
print("=" * 60)

parse_general_groups(soup)

categories = parse_category_list(soup)

# --------------------------------------------------
# Category Index
# --------------------------------------------------
print("\n  Category Index:")
print("  " + "-" * 40)
for i, (name, urlview) in enumerate(categories, 1):
    print("  [%d] %s" % (i, name))

# --------------------------------------------------
# User selection
# --------------------------------------------------
print("")
selection = input("  Fetch category (number, comma-separated, or A for all): ").strip().upper()

print("\n  Category Details:")
print("  " + "-" * 40)

if selection == "A":
    log("Fetching all %d categories..." % len(categories))
    for i, (name, urlview) in enumerate(categories, 1):
        fetch_category(i, name, urlview, base_url)
else:
    chosen = []
    for part in selection.split(","):
        part = part.strip()
        if part.isdigit():
            idx = int(part)
            if 1 <= idx <= len(categories):
                chosen.append(idx)
            else:
                print("  WARNING: %d is out of range, skipping" % idx)
        else:
            print("  WARNING: '%s' is not a valid number, skipping" % part)

    log("Fetching %d categories..." % len(chosen))
    for idx in chosen:
        name, urlview = categories[idx - 1]
        fetch_category(idx, name, urlview, base_url)

print("")