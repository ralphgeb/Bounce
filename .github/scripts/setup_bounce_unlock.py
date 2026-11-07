"""Creates "Unlock all games" in App Store Connect, so Bounce can sell it with Apple's own payment
sheet (and TestFlight testers can buy it in the sandbox, where nothing is charged).

Safe to run again: anything that already exists is left as it is.

  - a one-time (non-consumable) in-app purchase com.ralphgeb.bounce.unlock on the app com.ralphgeb.bounce
  - its name and description in English (US and UK)
  - on sale everywhere, at £1.99 in the UK and Apple's equivalent elsewhere ($1.99 in the US)

Apple also needs the Paid Applications Agreement signed (App Store Connect > Business) before
any purchase works, even in the sandbox; this script can't do that part.
"""
import os
import sys
import time

import jwt
import requests

API = "https://api.appstoreconnect.apple.com"
BUNDLE_ID = "com.ralphgeb.bounce"
PRODUCT_ID = "com.ralphgeb.bounce.unlock"
PRICE = "1.99"
BASE = "GBR"


def token() -> str:
    now = int(time.time())
    return jwt.encode(
        {"iss": os.environ["ASC_ISSUER_ID"].strip(), "iat": now, "exp": now + 1200, "aud": "appstoreconnect-v1"},
        os.environ["ASC_PRIVATE_KEY"],
        algorithm="ES256",
        headers={"kid": os.environ["ASC_KEY_ID"].strip(), "typ": "JWT"},
    )


S = requests.Session()
S.headers.update({"Authorization": f"Bearer {token()}", "Content-Type": "application/json"})


def get(path, **params):
    r = S.get(f"{API}{path}", params=params, timeout=60)
    if r.status_code != 200:
        raise SystemExit(f"::error::GET {path} answered {r.status_code}: {r.text[:400]}")
    return r.json()


def post(path, document, ok_conflict=False):
    r = S.post(f"{API}{path}", json=document, timeout=60)
    if r.status_code in (200, 201):
        return r.json()["data"]
    if ok_conflict and r.status_code == 409:
        print(f"(already there: {path})")
        return None
    raise SystemExit(f"::error::POST {path} answered {r.status_code}: {r.text[:700]}")


def rel(kind, ident):
    return {"data": {"type": kind, "id": ident}}


def main() -> int:
    apps = get("/v1/apps", **{"filter[bundleId]": BUNDLE_ID})["data"]
    if not apps:
        raise SystemExit(f"::error::No app with bundle ID {BUNDLE_ID} in App Store Connect")
    app = apps[0]["id"]
    print(f"App: {apps[0]['attributes'].get('name')} ({app})")

    # The in-app purchase
    existing = get(f"/v1/apps/{app}/inAppPurchasesV2", **{"filter[productId]": PRODUCT_ID, "limit": 50})["data"]
    iap = existing[0]["id"] if existing else None
    if not iap:
        iap = post("/v2/inAppPurchases", {"data": {"type": "inAppPurchases", "attributes": {
            "name": "Unlock all games", "productId": PRODUCT_ID, "inAppPurchaseType": "NON_CONSUMABLE",
            "familySharable": False,
            "reviewNote": "Unlocks the games Maze, Switch and Hue with every level. Bounce is free. "
                          "Open any locked game on the menu (the padlock) or Settings > Unlock all games."},
            "relationships": {"app": rel("apps", app)}}})["id"]
        print("Created the in-app purchase")

    # Names
    have = {l["attributes"]["locale"] for l in get(f"/v2/inAppPurchases/{iap}/inAppPurchaseLocalizations", limit=50)["data"]}
    for locale in ("en-US", "en-GB"):
        if locale not in have:
            post("/v1/inAppPurchaseLocalizations", {"data": {"type": "inAppPurchaseLocalizations", "attributes": {
                "locale": locale, "name": "Unlock all games",
                "description": "Maze, Switch and Hue, with every level."},
                "relationships": {"inAppPurchaseV2": rel("inAppPurchases", iap)}}}, ok_conflict=True)
            print(f"Added the {locale} name")

    # On sale everywhere
    r = S.get(f"{API}/v2/inAppPurchases/{iap}/inAppPurchaseAvailability", timeout=60)
    if r.status_code != 200 or not r.json().get("data"):
        territories = [t["id"] for t in get("/v1/territories", limit=200)["data"]]
        post("/v1/inAppPurchaseAvailabilities", {"data": {"type": "inAppPurchaseAvailabilities",
             "attributes": {"availableInNewTerritories": True},
             "relationships": {"inAppPurchase": rel("inAppPurchases", iap),
                               "availableTerritories": {"data": [{"type": "territories", "id": t} for t in territories]}}}},
             ok_conflict=True)
        print(f"On sale in {len(territories)} territories")

    # Price: £1.99 in the UK; Apple sets the equivalent everywhere else
    r = S.get(f"{API}/v2/inAppPurchases/{iap}/iapPriceSchedule", timeout=60)
    if r.status_code != 200 or not r.json().get("data"):
        points = get(f"/v2/inAppPurchases/{iap}/pricePoints", **{"filter[territory]": BASE, "limit": 200})["data"]
        pp = next((p["id"] for p in points if p["attributes"].get("customerPrice") == PRICE), None)
        if not pp:
            raise SystemExit(f"::error::No {PRICE} price point in {BASE}")
        post("/v1/inAppPurchasePriceSchedules", {
            "data": {"type": "inAppPurchasePriceSchedules", "relationships": {
                "inAppPurchase": rel("inAppPurchases", iap),
                "baseTerritory": rel("territories", BASE),
                "manualPrices": {"data": [{"type": "inAppPurchasePrices", "id": "${price}"}]}}},
            "included": [{"type": "inAppPurchasePrices", "id": "${price}", "attributes": {"startDate": None},
                          "relationships": {"inAppPurchaseV2": rel("inAppPurchases", iap),
                                            "inAppPurchasePricePoint": rel("inAppPurchasePricePoints", pp)}}]},
            ok_conflict=True)
        print(f"Price set: {PRICE} in {BASE}, equivalents elsewhere")

    state = get(f"/v2/inAppPurchases/{iap}")["data"]["attributes"].get("state")
    print(f"::notice::Unlock all games ({PRODUCT_ID}) is set up; its state is {state}. "
          "TestFlight testers can buy it in the sandbox (no charge) once the Paid Applications Agreement is signed "
          "in App Store Connect > Business.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
