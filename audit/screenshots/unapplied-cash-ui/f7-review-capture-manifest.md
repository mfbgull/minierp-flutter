# F7 current-build capture manifest

Capture date: 2026-10-18 (Asia/Karachi). The current Flutter release web build
was served from `http://127.0.0.1:4517` against the disposable fixture API at
`http://127.0.0.1:4327/api`. The fixture customer had two unused 500-unit
receipts. No canonical database was written or repaired.

Build command:

```sh
flutter build web --release --no-pub \
  --dart-define=API_BASE_URL=http://127.0.0.1:4327/api \
  --output=/tmp/minierp-cash-review-web
```

Release artifact SHA-256:

- `main.dart.js`: `7159ca43a0aae1e37dd8b04d4596e24a516e59f2ff2db7f7b808700c1a8ed0dc`
- `lib/widgets/movable_dialog.dart`: `8f6a6dca1a7c6030ea83f49144e3efe6fae50ff17f7a75b5c1d1506d7543b4ed`
- `lib/features/customers/customer_unapplied_cash_tab.dart`: `2000bfa3a8d7f80dabac99b2987b85fbaaf4aaa42620d16571cf0c7ee5e8b3ee`

| Capture | Viewport | SHA-256 |
|---|---:|---|
| `f7-en-dark-desktop-workspace.png` | 1280×900 | `918925e5a237cf9dff5f5e66afbcac5adf203181f020f36ee265132b6ecea9a8` |
| `f7-en-dark-phone-workspace.png` | 390×844, top | `f8a40a0e781bc630da324a8ab34c103d3589ffd73a8b1ad4f8b9fb3ebdc75e0e` |
| `f7-en-dark-phone-workspace-end.png` | 390×844, end | `78029457987ddb598c8ba79f0b42f88a6b29ce61f2c4c44d8af1ec9bf85699c5` |
| `f7-ur-dark-phone-workspace.png` | 390×844, top | `bc9eeca91d52af96e67adadf9b5d24d6aa0347c996468094a6177343229c7c22` |
| `f7-ur-dark-phone-workspace-end.png` | 390×844, end | `039d661ef9185c68f1f718775f99ce96d173376b81c83a652d3b58a943fadb68` |
| `f7-ur-light-phone-workspace.png` | 390×844, top | `0c800a2bcc572f6362d89d016388a867df320e2724e54d52ee7ed7e7ac393314` |
| `f7-ur-light-phone-workspace-end.png` | 390×844, end | `e1be794fa70b0349d67e1ceeb9817a50d75fdc08a177c93f9cc6411a6d52f0a8` |

Phone captures were checked visually at distinct workspace positions. Flutter's
semantic scroll node exposes `scrollTop` without always repainting the canvas;
the Urdu dark start/end pair was therefore recaptured using actual browser scroll
gestures and verified to differ. The desktop capture uses 1280×900, not the
1440×900 size used by some older matrix images.
