# 📚 Library Management System

A professional, high-performance desktop application for managing a modern library. Built with Flutter, this system provides robust inventory tracking, member management, and advanced loan processing with multi-language support.

## ✨ Features

-   **Dashboard Action Center**: Quick Scan, Statistics, and Activity History.
-   **Advanced Inventory**: Dual-code system (Barcode + Internal ID) with dynamic abbreviations.
-   **Member Management**: Auto-generated professional Member IDs (YY0001 format).
-   **Loan System**: Efficient check-out/check-in flow with status tracking.
-   **LAN Synchronization**: Pair multiple client machines to one host via QR code for shared database access.
-   **Multi-language**: Fully localized in **English**, **French**, and **Arabic**.
-   **Data Security**: Password-protected administrative settings and automated backups.
-   **Offline First**: Powered by a robust SQLite backend with FFI performance.

## 🛠 Tech Stack

-   **Framework**: Flutter (Windows Desktop)
-   **Database**: SQLite (sqflite_common_ffi)
-   **State Management**: Provider
-   **Networking**: Shelf (Internal LAN Server) & HTTP
-   **Hardware**: Supports USB Barcode Scanners and Camera-based scanning.

## 🚀 Getting Started

### Prerequisites
-   Flutter SDK (^3.10.1)
-   Visual Studio with "Desktop development with C++" workload (for Windows build)

### Installation
1.  Clone the repository:
    ```bash
    git clone https://github.com/your-username/library_manager.git
    ```
2.  Install dependencies:
    ```bash
    flutter pub get
    ```
3.  Generate localization files:
    ```bash
    flutter gen-l10n
    ```
4.  Run the application:
    ```bash
    flutter run -d windows
    ```

## 📦 Deployment
To generate a production release:
```bash
flutter build windows --release
```
The output can be found in `build/windows/x64/runner/Release`.

## 📄 License
This project is private and intended for administrative use. See [Update Management Guide](file:///C:/Users/windows%2010/.gemini/antigravity/brain/dadbdfec-b73b-4e58-ab00-d7f52bdca168/update_management_guide.md) for maintenance instructions.
