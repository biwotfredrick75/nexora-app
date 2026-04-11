# Wakulima — Dairy ERP Mobile App

> A production-ready Flutter ERP for dairy collection centres, cooperatives, and agri-businesses in Kenya and East Africa.

---

## 📱 Modules

| Module | Status | Description |
|--------|--------|-------------|
| Collection Lite | ✅ Phase 1 | BLE scale + milk collection, offline-first |
| Dairy | ✅ Phase 1 | Full dairy collection management |
| Farmers | ✅ Phase 1 | Farmer profiles, M-Pesa payment info |
| Sales | ✅ Phase 2 | Customer sales, invoicing, M-Pesa reconcile |
| Purchases | ✅ Phase 2 | Supplier POs, GRN, payments |
| Inventory | ✅ Phase 2 | Stock management, low-stock alerts |
| Dispatch | ✅ Phase 2 | Product dispatching and delivery |
| Driver | ✅ Phase 2 | Driver management and routing |
| Merchandising | ✅ Phase 2 | Field merchandising activities |
| Manufacturing | ✅ Phase 3 | Production and processing |
| Dairy Admin | ✅ Phase 3 | Admin functions, payroll |
| Analytics | ✅ Phase 3 | Business intelligence dashboard |
| Quality Control | ✅ Phase 3 | QA and product testing |
| Location | 🔒 Locked | Location tracking (admin-only) |
| Sales Management | 🔒 Locked | Advanced sales analytics (admin-only) |

---

## 🏗️ Architecture

```
lib/
├── core/
│   ├── theme/          # Colors, typography, ThemeData
│   ├── router/         # GoRouter config + module registry
│   ├── database/       # Isar local DB + all models
│   ├── ble/            # BLE scale service (flutter_blue_plus)
│   ├── sync/           # Offline-first sync engine
│   ├── network/        # Dio API client + error handling
│   ├── utils/          # Riverpod providers
│   └── widgets/        # Shared UI components
│
└── features/
    ├── auth/           # Login, splash, session
    ├── dashboard/      # Module grid home screen
    ├── collection/     # Milk collection + BLE
    ├── farmers/        # Farmer management
    ├── sales/          # Sales module
    ├── purchases/      # Purchases module
    ├── inventory/      # Inventory management
    ├── dispatch/       # Dispatch module
    ├── driver/         # Driver management
    ├── merchandising/  # Merchandising
    ├── manufacturing/  # Manufacturing
    ├── dairy_admin/    # Dairy administration
    ├── analytics/      # Analytics & reports
    ├── quality/        # Quality control
    ├── location/       # Location tracking
    └── settings/       # App settings
```

Each feature follows **Clean Architecture**:
```
feature/
├── data/
│   ├── models/         # Isar models + JSON serialization
│   └── repositories/   # Repository implementations
├── domain/
│   ├── entities/       # Pure Dart business entities
│   └── usecases/       # Business logic (single-responsibility)
└── presentation/
    ├── screens/        # Full-page UI
    ├── widgets/        # Feature-specific widgets
    └── providers/      # Riverpod providers/notifiers
```

---

## 🔧 Tech Stack

| Concern | Package | Why |
|---------|---------|-----|
| Navigation | `go_router` | Declarative, deep links, nested routes |
| State | `flutter_riverpod` | Lightweight, tree-shakes well, 2GB RAM friendly |
| Local DB | `isar` | Written in Rust, runs off UI thread, 3-5× faster than sqflite |
| Settings | `hive_flutter` | Zero-overhead key-value, pure Dart |
| BLE | `flutter_blue_plus` | Production-grade, works on Android 5+ |
| HTTP | `dio` | Interceptors, retry, auth token injection |
| Offline | custom `SyncEngine` | Queue writes, flush on connectivity |
| Error handling | `dartz` (Either) | Typed failures, no exceptions |
| Background BLE | `flutter_foreground_task` | Keeps scale connected on Android Go |
| PDF export | `pdf` + `printing` | KRA-ready reports |
| CSV export | `csv` | Pure Dart, no native code |
| Charts | `fl_chart` | Smooth, low-memory chart library |

---

## 🚀 Getting Started

### Prerequisites
- Flutter 3.19+ (`flutter --version`)
- Dart 3.0+
- Android Studio / VS Code

### Install
```bash
flutter pub get
flutter pub run build_runner build --delete-conflicting-outputs
```

### Run (debug)
```bash
flutter run
```

### Build release APK (split by ABI — ~8 MB per arch)
```bash
flutter build apk --release --split-per-abi
```
Output files:
```
build/app/outputs/flutter-apk/
  app-armeabi-v7a-release.apk   # ARM 32-bit (older Tecno/Itel)
  app-arm64-v8a-release.apk     # ARM 64-bit (most modern phones)
  app-x86_64-release.apk        # Emulator / Intel phones
```

### Run on low-memory device
```bash
# Profile mode to check memory usage
flutter run --profile
```

---

## 📡 BLE Scale Support

The app connects to any Bluetooth LE scale. Three tiers:

**Tier 1 — Plug & play (GATT 0x1808)**
- OHAUS Scout STX, Defender 6000
- Adam Equipment CBK series
- Kern PCB/PCD series
- Any scale using standard GATT Weight Measurement characteristic

**Tier 2 — Connects, custom parsing needed**
- Generic Chinese BLE scales (common in local markets)
- Custom UUID scales — add parser in `ble/ble_scale_service.dart`

**Tier 3 — Manual entry**
- Any scale without BLE — type weight directly

---

## 🌐 Backend API

### Base URL
```
https://api.wakulima.co.ke/v1
```

### Authentication
All requests require `Authorization: Bearer <token>` header.
Token obtained from `POST /auth/login`.

### Key Endpoints

| Method | Endpoint | Description |
|--------|----------|-------------|
| POST | `/auth/login` | Login → returns JWT token |
| POST | `/auth/refresh` | Refresh expired token |
| GET | `/collections` | List milk collections |
| POST | `/collections` | Record new collection |
| GET | `/farmers` | List farmers |
| POST | `/farmers` | Register new farmer |
| GET | `/sales` | List sales |
| POST | `/sales` | Create sale |
| GET | `/purchases` | List purchases |
| POST | `/purchases` | Create purchase order |
| GET | `/inventory` | List inventory items |
| POST | `/sync/bulk` | Bulk sync offline queue |

### Offline-First Flow
```
User action
    │
    ▼
Write to Isar (always, instant)
    │
    ▼
Add to SyncQueue
    │
    ▼ (when online)
SyncEngine flushes queue → POST /sync/bulk
    │
    ▼
Mark records as synced = true
```

---

## 📊 Database Schema

### MilkCollection
| Field | Type | Notes |
|-------|------|-------|
| uuid | String | UUID v4, used for API sync |
| farmerName | String | Indexed |
| farmerId | String | Farmer code |
| weightKg | double | From BLE or manual |
| pricePerKg | double | At time of collection |
| totalValue | double | weightKg × pricePerKg |
| grade | String | A / B / C |
| collectedAt | DateTime | Indexed |
| synced | bool | Indexed, used by SyncEngine |

### Farmer, Sale, Purchase, InventoryItem — see `lib/core/database/models/`

---

## 🎨 Design System

**Brand color:** `#14742A` (Deep Dairy Green)
**Accent:** `#C8930A` (Gold / Milk tone)
**Font:** Poppins (weights 400, 500, 600, 700)
**Border radius:** 12px (inputs), 16px (cards), 20px (pills)

All colors defined in `lib/core/theme/app_theme.dart` → `WakulimaColors`.

---

## 🔒 Role-Based Access

| Role | Accessible Modules |
|------|--------------------|
| `agent` | Collection, Dairy, Sales, Inventory |
| `driver` | Driver, Dispatch |
| `merchandiser` | Merchandising |
| `dispatcher` | Dispatch, Driver |
| `manager` | All except locked |
| `admin` | All including locked |

Module access is enforced in `ModuleRegistry` and optionally on the API via JWT claims.

---

## 📦 Recommended Devices

| Device | RAM | Status |
|--------|-----|--------|
| Tecno Spark 10 | 2 GB | ✅ Works great |
| Infinix Hot 12 | 2 GB | ✅ Works great |
| Samsung A05 | 4 GB | ✅ No issues |
| Itel A70 | 2 GB | ✅ Works great |
| Tecno Pop 7 (Android Go) | 2 GB | ⚠ Use foreground service |
| Samsung A03 Core | 1 GB | ⚠ Use split APK |

---

## 📄 License

Proprietary — Wakulima Dev. All rights reserved.
