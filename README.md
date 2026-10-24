# Kantemba POS (mobile app)

Flutter app for the POS backend in `../pos-backend`: barcode-first checkout, product and stock management,
customers, reports and settings. Android is the primary target.

## Run it

```bash
flutter pub get
flutter run --dart-define=KANTEMBA_API_URL=http://<backend-ip>:8081/api/v1
```

- On the Android emulator the host machine is `10.0.2.2` (`http://10.0.2.2:8081/api/v1`).
- On a phone use the computer's Wi-Fi address and allow port 8081 through its firewall.
- The URL can also be changed in the app under **Settings**.
- Start the backend first (`../pos-backend`, `POS_SEED_DEMO=true ./gradlew bootRun` loads demo products with barcodes).
  Demo logins: `admin/admin123` (full access), `manager/manager123`, `cashier/cashier123`.

## Barcode scanning

| Where | What it does |
|---|---|
| **Sales tab** | The camera is the primary way to build a sale. Each scan is looked up on the server (`GET /products/by-barcode`), so name, price and stock are always the backend's. The product is added to the cart immediately; scanning it again adds one more unit. |
| **Pay** | Sends the items and the payment in a single request. The server calculates VAT and totals, checks and deducts stock, and records the payment atomically. The total shown while scanning is an estimate; the receipt dialog shows the server's. Retrying after a connection error is safe (one `clientSaleId` per attempt). |
| **Products tab** | Managers (and admins) can scan a barcode into the product form, type it by hand, or scan to find a product (edit it, or add stock). Cashiers see the list and can scan to look up price and stock. |
| **Duplicate barcodes** | If a barcode already belongs to a product, no duplicate is created: the form offers to open that product, add stock to it, or use another barcode. |

Fallbacks: every scanner has a manual entry field (barcode or product name), and if the camera is unavailable or
permission is denied a message explains it and manual entry keeps working.

Supported symbologies: EAN-13, EAN-8, UPC-A, UPC-E, Code 128. Barcodes are 3-64 characters of letters, digits and
`. _ / + -`, stored upper-case (the same rules as the backend; see `../pos-backend/docs/api-documentation.md#barcodes`).

Permissions: the app declares `CAMERA` (requested when the scanner first opens) and does not require camera hardware.
The Sales camera is released while another tab is showing.

## Code layout

```
lib/
  core/
    scanning/    BarcodeNormalizer, ScanDeduplicator (no UI, no network)
    checkout/    Cart, ScanCheckoutController (scan -> lookup -> cart), CheckoutService (atomic sale), ProductLookup
    catalog/     BarcodeAssignmentChecker (is this barcode free?)
    api/         ApiClient, ApiException, TokenStore
    session/     Session, SessionScope
  data/          models and typed API services
  ui/            screens; ui/widgets/barcode_scanner_view.dart is the only camera code
test/            unit tests + widget tests that run the screens against a fake server (test/support)
```

The camera widget only forwards raw values; duplicate suppression, lookups, stock rules and ordering live in
`ScanCheckoutController`, which is tested without a camera.

## Test

```bash
flutter analyze
flutter test
flutter build apk --debug      # confirms the Android build, camera permission and scanner plugin compile
```

The camera itself cannot run in automated tests; the checkout widget tests pause the scanner and enter barcodes through
the manual field, which uses the same lookup/cart/payment path as the camera.
