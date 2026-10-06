# Driver app

Flutter driver client using Firebase Authentication, Cloud Firestore, Riverpod, and Geolocator.

## Firebase setup

- Register the Android and iOS apps in the same Firebase project used by the rider app.
- Add the matching `google-services.json` under `android/app/` and `GoogleService-Info.plist` under `ios/Runner/`.
- Enable Email/Password sign-in and Cloud Firestore.
- Create driver profiles in `users/{uid}` with `role: "driver"`; the app only opens the dashboard for that role.
- Apply Firestore rules that let an authenticated driver update only their own `drivers/{uid}` presence/location, read requested rides, and update rides assigned to them.

## Driver flow

Sign in with a registered driver account. Going online requests foreground location permission and writes `drivers/{uid}` with `online`, `lat`, `lng`, `location`, heading/speed, and update timestamps every three seconds. The app listens for `rides` documents with `status: "requested"`, presents an accept/decline dialog, claims accepted rides transactionally, then advances `accepted` → `arriving` → `ongoing` → `completed` with the dashboard button.
