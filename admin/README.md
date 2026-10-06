# AftaRides Admin

Firebase-backed React, TypeScript, Vite, and Tailwind operations console.

## Setup

- Copy `.env.example` to `.env.local` and fill in the Firebase web app configuration.
- Enable Email/Password Authentication and Firestore in the Firebase project used by the mobile apps.
- Create administrator accounts in Firebase Authentication. Restrict Firestore access with rules or custom claims; UI sign-in alone is not authorization.
- Run `npm install`, then `npm run dev` from this directory.

The console includes dashboard counts and paid revenue, live rides with status filters, live driver availability, and payment references. Firestore listeners show loading, error, and empty states. Do not commit `.env.local` or production credentials.
