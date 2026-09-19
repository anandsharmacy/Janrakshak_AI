# Flutter Production App Rebuild — Master Development Prompt

Act as a **Senior Flutter Architect and Mobile Application Engineer with 12+ years of experience** building production-grade Android and iOS applications.

We are rebuilding the **existing React/Vite web application as a real mobile application using Flutter**.

The goal is **NOT to redesign the application**.

The goal is to reproduce the existing application **as closely as technically possible**, preserving:

- UI
- UX
- navigation
- screens
- components
- workflows
- business logic
- user interactions
- animations
- colors
- typography
- spacing
- icons
- cards
- buttons
- forms
- states
- API behavior
- authentication
- loading states
- error states
- empty states
- responsive behavior

Flutter should be used as the native cross-platform implementation for Android and iOS.

---

# 1. PRIMARY OBJECTIVE

Analyze the existing React/Vite project completely and rebuild it in Flutter.

Do NOT blindly convert React syntax into Dart.

Instead:

```text
Existing React/Vite App
        ↓
Analyze architecture
        ↓
Identify screens
        ↓
Identify reusable components
        ↓
Identify navigation
        ↓
Identify state management
        ↓
Identify API/data logic
        ↓
Identify authentication
        ↓
Identify assets
        ↓
Identify animations/interactions
        ↓
Design Flutter architecture
        ↓
Implement Flutter application
```

The final Flutter application should behave as the same product, with Flutter-native architecture and production-quality code.

---

# 2. FIRST TASK — ANALYZE THE EXISTING APP

Before writing Flutter code, inspect the complete React/Vite project.

Analyze:

```text
package.json
src/
components/
pages/
layouts/
hooks/
services/
utils/
assets/
mocks/
routes/
contexts/
API integrations
authentication
configuration
environment variables
```

Create a migration map:

| React/Vite | Flutter |
|---|---|
| React Component | Widget |
| Page | Screen |
| React Router | GoRouter |
| Context | Riverpod Provider |
| Hook | Provider/Notifier/Controller |
| CSS | Theme + Widget styling |
| Tailwind | Theme + reusable styles |
| API service | Repository/DataSource |
| Local state | Riverpod state |
| localStorage | SharedPreferences/secure storage |
| SVG/Icon library | Flutter icons/custom assets |
| Web animation | Flutter animation |
| Modal | Dialog/BottomSheet |
| Toast | SnackBar |
| Browser navigation | GoRouter navigation |

---

# 3. FLUTTER STACK

Use the following stack unless the existing project requires a justified alternative.

### Framework

```text
Flutter
Dart
```

### State Management

```text
Riverpod
flutter_riverpod
```

### Navigation

```text
GoRouter
```

### Networking

```text
Dio
```

### API Models

```text
json_serializable
freezed
```

### Local Storage

Use:

```text
shared_preferences
```

for non-sensitive preferences.

Use:

```text
flutter_secure_storage
```

for:

- access tokens
- refresh tokens
- sensitive credentials

### Dependency Injection

Use Riverpod-based dependency injection.

### Backend

Connect to the project's existing backend/API.

If the backend is Supabase-based, use the official Supabase Flutter SDK where appropriate.

### Maps

Use an appropriate Flutter mapping solution based on the existing application.

### Notifications

Use:

```text
firebase_messaging
flutter_local_notifications
```

where push/local notifications are required.

### Images

Use:

```text
cached_network_image
```

for remote images.

---

# 4. PROJECT STRUCTURE

Create a scalable feature-first architecture.

```text
mobile/
│
├── android/
├── ios/
├── web/
├── test/
├── integration_test/
│
├── assets/
│   ├── images/
│   ├── icons/
│   ├── illustrations/
│   ├── animations/
│   ├── fonts/
│   └── json/
│
├── lib/
│   │
│   ├── main.dart
│   │
│   ├── app.dart
│   │
│   ├── core/
│   │   ├── config/
│   │   │   ├── app_config.dart
│   │   │   ├── environment.dart
│   │   │   └── env.dart
│   │   │
│   │   ├── constants/
│   │   │   ├── app_constants.dart
│   │   │   ├── route_constants.dart
│   │   │   ├── asset_constants.dart
│   │   │   └── api_constants.dart
│   │   │
│   │   ├── errors/
│   │   │   ├── app_exception.dart
│   │   │   ├── failure.dart
│   │   │   └── error_handler.dart
│   │   │
│   │   ├── network/
│   │   │   ├── dio_client.dart
│   │   │   ├── api_interceptor.dart
│   │   │   └── network_info.dart
│   │   │
│   │   ├── router/
│   │   │   ├── app_router.dart
│   │   │   ├── route_names.dart
│   │   │   └── route_guards.dart
│   │   │
│   │   ├── storage/
│   │   │   ├── secure_storage.dart
│   │   │   └── local_storage.dart
│   │   │
│   │   ├── theme/
│   │   │   ├── app_theme.dart
│   │   │   ├── app_colors.dart
│   │   │   ├── app_text_styles.dart
│   │   │   ├── app_spacing.dart
│   │   │   ├── app_radius.dart
│   │   │   └── app_shadows.dart
│   │   │
│   │   ├── utils/
│   │   │   ├── validators.dart
│   │   │   ├── formatters.dart
│   │   │   ├── date_utils.dart
│   │   │   └── helpers.dart
│   │   │
│   │   └── widgets/
│   │       ├── app_button.dart
│   │       ├── app_text_field.dart
│   │       ├── app_card.dart
│   │       ├── app_loader.dart
│   │       ├── app_error.dart
│   │       ├── app_empty_state.dart
│   │       ├── app_appbar.dart
│   │       └── app_bottom_sheet.dart
│   │
│   ├── features/
│   │
│   │   ├── auth/
│   │   │   ├── data/
│   │   │   │   ├── datasources/
│   │   │   │   ├── models/
│   │   │   │   └── repositories/
│   │   │   ├── domain/
│   │   │   │   ├── entities/
│   │   │   │   ├── repositories/
│   │   │   │   └── usecases/
│   │   │   └── presentation/
│   │   │       ├── providers/
│   │   │       ├── screens/
│   │   │       └── widgets/
│   │
│   │   ├── home/
│   │   ├── dashboard/
│   │   ├── profile/
│   │   ├── settings/
│   │   ├── notifications/
│   │   └── [other_app_features]/
│   │
│   └── shared/
│       ├── models/
│       ├── enums/
│       └── widgets/
│
├── pubspec.yaml
├── analysis_options.yaml
├── .env.example
├── README.md
└── CHANGELOG.md
```

Do NOT create unnecessary folders merely for the sake of architecture. Adapt the structure to the actual application's features.

---

# 5. SCREEN INVENTORY

Before development, generate a complete screen inventory from the existing app.

For EVERY screen document:

```text
Screen Name
Route
Purpose
Entry Point
Previous Screen
Next Screens
UI Components
API Calls
State Requirements
Loading State
Error State
Empty State
User Actions
Navigation Actions
Animations
Responsive Behavior
Permissions Required
```

Example:

```text
DashboardScreen

Route:
 /dashboard

Contains:
 - AppBar
 - Summary cards
 - Map
 - Recent activity
 - Bottom navigation

API:
 GET /dashboard
 GET /notifications

States:
 loading
 success
 error
 empty

Actions:
 refresh
 open notification
 open route
 open profile
```

---

# 6. COMPONENT INVENTORY

Every reusable React component must be mapped to a Flutter widget.

Create a component matrix:

```text
React Component
        ↓
Flutter Widget
        ↓
Reusable?
        ↓
Required parameters
        ↓
Required state
        ↓
Callbacks
```

Examples:

```text
Button
Card
Modal
Dropdown
Tabs
Search Bar
Navigation Bar
Drawer
Map Widget
Status Badge
Progress Indicator
Charts
List Item
Form Field
Dialog
Bottom Sheet
```

Do not duplicate widgets when a reusable Flutter component can be created.

---

# 7. DESIGN SYSTEM

Recreate the existing application's visual design.

Extract and document:

### Colors

```text
Primary
Secondary
Background
Surface
Card
Text Primary
Text Secondary
Border
Success
Warning
Error
Info
```

### Typography

Document:

```text
Font Family
Font Size
Font Weight
Line Height
Letter Spacing
```

### Spacing

Create a consistent spacing scale:

```text
4
8
12
16
20
24
32
40
48
64
```

Adjust this to match the existing application.

### Radius

```text
Small
Medium
Large
Full
```

### Shadows

Recreate existing elevation/shadow behavior.

---

# 8. RESPONSIVE DESIGN

The mobile application must support:

```text
Android phones
iPhones
Small screens
Large screens
Different aspect ratios
Portrait
Landscape where appropriate
```

Do not simply copy desktop dimensions.

Convert the existing responsive web design into a mobile-first layout while preserving the visual identity.

Use:

```text
LayoutBuilder
MediaQuery
Flexible
Expanded
SafeArea
Sliver layouts
```

where appropriate.

---

# 9. NAVIGATION

Use GoRouter.

Define:

```text
Route Names
Route Paths
Nested Routes
Authentication Guards
Role Guards
Deep Links
Redirect Logic
```

Example:

```text
/
├── splash
├── login
├── register
│
└── authenticated
    ├── home
    ├── dashboard
    ├── notifications
    ├── profile
    └── settings
```

Unauthenticated users must never access protected screens.

---

# 10. STATE MANAGEMENT

Use Riverpod.

Separate:

```text
UI State
Application State
Server State
Authentication State
Persistent State
```

Example:

```text
AuthProvider
UserProvider
DashboardProvider
NotificationProvider
RouteProvider
ProfileProvider
SettingsProvider
```

Use:

```text
AsyncValue
Notifier
AsyncNotifier
StateNotifier
```

where appropriate.

Avoid excessive global state.

---

# 11. DATA LAYER

Every backend feature should use:

```text
API
 ↓
Data Source
 ↓
Repository
 ↓
Use Case
 ↓
Provider
 ↓
Screen
```

Example:

```text
Dio
 ↓
DashboardRemoteDataSource
 ↓
DashboardRepository
 ↓
GetDashboardUseCase
 ↓
DashboardProvider
 ↓
DashboardScreen
```

---

# 12. API INTEGRATION

Document every endpoint used by the existing application.

For every API provide:

```text
HTTP Method
Endpoint
Authentication
Headers
Query Parameters
Path Parameters
Request Body
Response Body
HTTP Status Codes
Error Response
Timeout
Retry behavior
```

Create typed Dart models.

Example:

```dart
class User {
  final String id;
  final String name;
  final String email;
}
```

Do not pass raw JSON throughout the UI.

---

# 13. AUTHENTICATION

Implement the same authentication workflow as the existing application.

Support as required:

```text
Login
Register
Logout
Session restoration
Token refresh
Forgot password
Reset password
Email verification
Role-based access
```

Store sensitive tokens only using secure storage.

Authentication state should survive application restart where the backend supports persistent sessions.

---

# 14. FORMS AND VALIDATION

Every form should include:

```text
Initial State
Input Validation
Keyboard Type
Input Formatting
Error Messages
Loading State
Success State
Server Errors
Submit Button State
```

Create centralized validators where possible.

---

# 15. LOADING / ERROR / EMPTY STATES

Every API-driven screen must explicitly support:

```text
Loading
Success
Empty
Error
Retry
```

Do not leave blank screens during network failures.

---

# 16. OFFLINE / NETWORK BEHAVIOR

Implement reasonable network handling.

Detect:

```text
Online
Offline
Slow connection
Request timeout
Server unavailable
```

Show appropriate user feedback.

Cache data where useful.

Do not cache sensitive data insecurely.

---

# 17. ANIMATIONS

Analyze existing web animations and reproduce their visual behavior using Flutter.

Use:

```text
AnimatedContainer
AnimatedOpacity
TweenAnimationBuilder
Hero
PageRoute animations
AnimationController
Custom transitions
```

Avoid unnecessary animation.

Prioritize smooth 60fps interactions.

---

# 18. ASSETS

Inventory every existing:

```text
Logo
Image
SVG
Icon
Illustration
Font
Animation
Background
Avatar
```

For every asset define:

```text
Source
File Name
Flutter Location
Resolution
Usage
```

Use:

```text
assets/images/
assets/icons/
assets/fonts/
```

Update `pubspec.yaml`.

---

# 19. ICONS

Identify whether each existing icon is:

```text
Material icon
Cupertino icon
Custom SVG
Custom PNG
Third-party icon
```

Use the closest Flutter equivalent.

Do not replace important branded/custom icons with generic icons.

---

# 20. PLATFORM FEATURES

Identify any functionality requiring native integration:

```text
Camera
Gallery
GPS
Maps
Notifications
Bluetooth
Files
Microphone
Biometrics
Location
Deep links
Share
Background services
```

For each feature document:

```text
Flutter package
Android permission
iOS permission
Configuration
Fallback behavior
```

---

# 21. ANDROID CONFIGURATION

Configure:

```text
AndroidManifest.xml
Permissions
Package name
App icon
Splash screen
Deep links
Firebase
Signing configuration
Release build
ProGuard/R8
Minimum SDK
Target SDK
```

Do not hard-code production secrets.

---

# 22. IOS CONFIGURATION

Configure:

```text
Info.plist
Permissions
Bundle identifier
App icon
Launch screen
URL schemes
Firebase
Capabilities
Push notifications
Signing
Release configuration
```

---

# 23. ENVIRONMENT MANAGEMENT

Support:

```text
development
staging
production
```

Example:

```text
.env.development
.env.staging
.env.production
```

Store:

```text
API_BASE_URL
SUPABASE_URL
SUPABASE_ANON_KEY
MAP_API_KEY
```

through secure environment/configuration mechanisms.

Never commit production secrets.

---

# 24. TESTING

Create:

### Unit Tests

Test:

```text
Validators
Formatters
Business logic
Repositories
Use cases
Models
Services
```

### Widget Tests

Test:

```text
Buttons
Forms
Cards
Navigation
Loading states
Error states
Dialogs
```

### Integration Tests

Test complete flows:

```text
Launch
Login
Dashboard
Navigation
API interaction
Logout
```

---

# 25. PERFORMANCE

Optimize:

```text
Widget rebuilds
List rendering
Images
Network requests
Database/cache usage
Animations
Memory
Startup time
```

Use:

```text
const widgets
ListView.builder
Slivers where appropriate
image caching
pagination
debouncing
lazy loading
```

Avoid unnecessary rebuilds.

---

# 26. ACCESSIBILITY

Support:

```text
Semantic labels
Readable font sizes
Sufficient contrast
Touch target sizes
Screen reader navigation
Keyboard navigation where applicable
Dynamic text scaling
```

Accessibility must not significantly change the visual design.

---

# 27. SECURITY

Implement:

```text
Secure token storage
HTTPS
Certificate-safe networking where required
Input validation
Secure logout
Session expiration
Sensitive-data protection
No secrets in source code
```

Never log:

```text
Passwords
Access tokens
Refresh tokens
API secrets
Sensitive user information
```

---

# 28. ERROR HANDLING

Create centralized error handling.

Map errors such as:

```text
400 → Invalid request
401 → Unauthorized
403 → Forbidden
404 → Not found
408 → Timeout
409 → Conflict
429 → Rate limited
500 → Server error
503 → Service unavailable
```

Convert backend errors into user-friendly UI messages.

---

# 29. LOGGING

Use structured logging during development.

Examples:

```text
API request
API response
Authentication failure
Navigation failure
Database failure
Unhandled exception
```

Disable sensitive/debug logs in production.

---

# 30. APP LIFECYCLE

Handle:

```text
Cold start
Warm start
Background
Foreground
Network reconnect
Authentication expiry
```

Restore appropriate application state when returning from background.

---

# 31. DEEP LINKING

Where relevant, support:

```text
example://app/profile/123
example://app/route/456
```

and Android/iOS universal/app links where required.

Map deep links to GoRouter routes.

---

# 32. NOTIFICATIONS

Implement notification handling for:

```text
Foreground
Background
Terminated app
Notification tap
Deep linking from notification
```

The same notification should not trigger duplicate navigation.

---

# 33. CODE QUALITY

Follow:

```text
Dart formatting
Flutter linting
SOLID principles
Single responsibility
Reusable components
Meaningful naming
Strong typing
Null safety
No unnecessary duplication
```

Do not use:

```text
dynamic everywhere
large monolithic widgets
business logic inside build()
hard-coded API URLs
hard-coded credentials
duplicated UI code
```

---

# 34. DEVELOPMENT PHASES

## Phase 1

Analyze existing React/Vite application.

Deliver:

```text
Screen inventory
Component inventory
Route inventory
API inventory
Asset inventory
State inventory
Feature inventory
Design-system inventory
```

## Phase 2

Initialize Flutter project.

Deliver:

```text
Flutter project
Folder structure
Dependencies
Theme
Environment configuration
Routing
Core utilities
```

## Phase 3

Build reusable design system.

Deliver:

```text
Buttons
Cards
Inputs
Dialogs
Navigation
Loading
Error
Empty states
Typography
Colors
Spacing
```

## Phase 4

Implement authentication.

## Phase 5

Implement each application feature one-by-one.

For every feature:

```text
Models
Data source
Repository
Use case
Provider
Widgets
Screen
Navigation
Tests
```

## Phase 6

Integrate backend/API.

## Phase 7

Implement animations and advanced interactions.

## Phase 8

Implement offline/error handling.

## Phase 9

Testing and optimization.

## Phase 10

Android + iOS release preparation.

---

# 35. FEATURE IMPLEMENTATION RULE

For each feature, follow:

```text
Requirement
 ↓
Existing React implementation
 ↓
Flutter architecture
 ↓
Data model
 ↓
API
 ↓
Repository
 ↓
State management
 ↓
Widgets
 ↓
Screen
 ↓
Navigation
 ↓
Testing
```

Do not move to the next major feature until the current feature is functional.

---

# 36. DOCUMENTATION TO GENERATE

Create:

```text
README.md
ARCHITECTURE.md
FOLDER_STRUCTURE.md
API_DOCUMENTATION.md
SCREEN_MAPPING.md
COMPONENT_MAPPING.md
STATE_MANAGEMENT.md
ENVIRONMENT_SETUP.md
ANDROID_SETUP.md
IOS_SETUP.md
TESTING.md
DEPLOYMENT.md
```

Also create a migration document:

```text
REACT_TO_FLUTTER_MAPPING.md
```

containing the mapping between every major React component and its Flutter equivalent.

---

# 37. FINAL DELIVERABLE

The final repository should contain:

```text
Complete Flutter app
+
Complete folder architecture
+
Reusable UI components
+
All screens
+
Navigation
+
State management
+
API integration
+
Authentication
+
Assets
+
Animations
+
Error handling
+
Loading/empty states
+
Tests
+
Android configuration
+
 iOS configuration
+
Environment configuration
+
Documentation
```

The resulting Flutter application must be **production-ready, maintainable and cross-platform**, while preserving the original application's identity and functionality.

# MOST IMPORTANT RULE

**Do not redesign the application unless technically necessary.**

Treat the existing React/Vite application as the **source of truth**.

Before changing any UI, behavior, workflow, component, route or feature, verify how it works in the existing application.

The goal is:

```text
SAME PRODUCT
        +
NATIVE FLUTTER IMPLEMENTATION
        +
PRODUCTION-GRADE ARCHITECTURE
        =
FINAL MOBILE APP
```
