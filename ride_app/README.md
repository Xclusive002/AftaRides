# ride_app

## Maps configuration

Enable Maps SDK for Android/iOS, Places API, and Directions API for a restricted Google Maps API key.

- Copy `.env.example` to `.env` and set `GOOGLE_MAPS_API_KEY` for Places and Directions requests.
- Android: set `MAPS_API_KEY` in a local Gradle properties file, such as `~/.gradle/gradle.properties`; the Android manifest reads this Gradle property.
- iOS: create the ignored `ios/Flutter/Maps.xcconfig` file with `GOOGLE_MAPS_API_KEY = your-key`; Debug and Release xcconfig files include it.
- Keep keys restricted and out of version control. Configure Firebase for the target platforms separately.

The rider home requests location permission, shows the current position, searches Nigerian Places, draws a driving route, estimates fare at ₦500 + ₦120/km, and writes requested rides to Firestore.

## Paystack test checkout

Set `PAYSTACK_PUBLIC_KEY=pk_test_…` in the ignored `.env` file. The app opens checkout when a ride reaches `completed`, charges the fare converted to kobo, and stores `paid`, `paystackReference`, `paymentStatus`, and `paidAt` on the ride after Paystack's inline success callback. This client callback is suitable for test-mode UI integration; production payments must be verified server-side with Paystack before trusting the paid flag.

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Learn Flutter](https://docs.flutter.dev/get-started/learn-flutter)
- [Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Flutter learning resources](https://docs.flutter.dev/reference/learning-resources)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.
