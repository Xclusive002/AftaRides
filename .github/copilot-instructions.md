Project: ride-hailing MVP demo (Bolt/Uber style) for a Nigerian client.
Stack: Flutter (rider_app, driver_app), Firebase Auth + Firestore, Google Maps + Places + Directions, Paystack (test mode), React+TS+Vite admin.
Firestore: users/{uid}{role,name,phone}, drivers/{uid}{online,lat,lng}, rides/{id}{riderId,driverId,pickup,dropoff,status(requested|accepted|arriving|ongoing|completed),fare,paid}.
Rules: Riverpod state mgmt, feature-folder structure, null-safe, no hardcoded keys (use .env), short code, no explanations unless asked. Currency NGN.y