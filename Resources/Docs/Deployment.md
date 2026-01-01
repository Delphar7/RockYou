# RockYou Deployment Guide

This guide covers deploying RockYou to TestFlight and the App Store.

## First Time Setup

### 1. App Store Connect

1. Go to [App Store Connect](https://appstoreconnect.apple.com)
2. Click **My Apps** → **+** → **New App**
3. Fill in:
   - **Platforms:** iOS, macOS (create separate entries or universal)
   - **Name:** RockYou (or your preferred display name)
   - **Primary Language:** English (US)
   - **Bundle ID:** Select `com.jtr.RockYou` from dropdown
   - **SKU:** `rockyou` (any unique identifier)
4. Click **Create**

> **Note:** watchOS apps are bundled with the iOS app - no separate App Store entry needed.

### 2. CloudKit Schema Deployment

⚠️ **Critical:** TestFlight/Production builds use the Production CloudKit environment.

1. Go to [CloudKit Dashboard](https://icloud.developer.apple.com/dashboard)
2. Select **iCloud.com.jtr.RockYou** container
3. Ensure you're in **Development** environment
4. Click **"Deploy Schema Changes..."** (bottom of left sidebar)
5. Review changes and confirm deployment
6. Wait for deployment to complete (usually seconds)

**What gets deployed:**
- Record Types: `TVPairings`
- Zones: `PairingsZone` (created per-user at runtime)
- Indexes: `data`, `recordName`

### 3. Certificates & Provisioning

Xcode usually handles this automatically with "Automatically manage signing", but verify:

1. **Xcode** → **Signing & Capabilities** for each target:
   - RockYou (iOS)
   - RockYou (macOS) 
   - RockYou Watch App
2. Ensure **Team** is set to your paid developer account
3. Ensure **Automatically manage signing** is checked
4. Resolve any provisioning errors

### 4. App Icons & Metadata

Before uploading, ensure you have:
- [ ] App icons for all sizes (iOS, macOS, watchOS)
- [ ] Screenshots (can add later for TestFlight)
- [ ] App description (can add later for TestFlight)
- [ ] Privacy policy URL (required for App Store)

---

## TestFlight

### Archive the App

#### Option A: Xcode UI

1. Select **Any iOS Device (arm64)** as destination (not a simulator)
2. **Product** → **Archive**
3. Wait for archive to complete
4. Organizer window opens automatically

#### Option B: Command Line

```bash
# iOS + watchOS
xcodebuild archive \
  -scheme "RockYou" \
  -destination "generic/platform=iOS" \
  -archivePath ./build/RockYou-iOS.xcarchive \
  -allowProvisioningUpdates

# macOS
xcodebuild archive \
  -scheme "RockYou" \
  -destination "generic/platform=macOS" \
  -archivePath ./build/RockYou-macOS.xcarchive \
  -allowProvisioningUpdates
```

### Upload to App Store Connect

#### Option A: Xcode Organizer

1. In Organizer, select your archive
2. Click **Distribute App**
3. Select **TestFlight & App Store**
4. Click **Distribute**
5. Wait for upload and processing

#### Option B: Command Line

```bash
# Export for App Store
xcodebuild -exportArchive \
  -archivePath ./build/RockYou-iOS.xcarchive \
  -exportPath ./build/export \
  -exportOptionsPlist ExportOptions.plist \
  -allowProvisioningUpdates

# Upload using altool (legacy) or xcrun
xcrun altool --upload-app \
  -f ./build/export/RockYou.ipa \
  -t ios \
  -u "your@apple.id" \
  -p "@keychain:AC_PASSWORD"
```

### Add Testers

#### Internal Testers (Immediate)
1. App Store Connect → **Users and Access**
2. Add team members with **Developer** or **App Manager** role
3. They get immediate access to all TestFlight builds

#### External Testers (Requires Review)
1. App Store Connect → Your App → **TestFlight**
2. Click **+** next to **External Groups**
3. Create group (e.g., "Beta Testers")
4. Add testers by email
5. Select build to distribute
6. Submit for **Beta App Review** (usually 24-48 hours)

### TestFlight Build Processing

After upload:
1. **Processing:** 5-30 minutes (icon appears gray)
2. **Ready:** Build appears in TestFlight tab
3. **Compliance:** Answer export compliance question (usually "No" for encryption)
4. **Distribute:** Select build for internal/external testers

### Testing CloudKit Sharing

To test sharing between accounts:
1. Install TestFlight build on Device A (Account 1)
2. Install TestFlight build on Device B (Account 2)  
3. On Device A: Configure TVs → Share
4. Send share link to Account 2
5. On Device B: Open link, accept share
6. Verify pairings sync between devices

---

## App Store Release

### Pre-Submission Checklist

- [ ] App icons complete (all sizes)
- [ ] Screenshots for all device sizes
  - iPhone 6.7" (iPhone 15 Pro Max)
  - iPhone 6.5" (iPhone 14 Plus) 
  - iPhone 5.5" (iPhone 8 Plus)
  - iPad Pro 12.9"
  - Mac screenshots
  - Apple Watch screenshots
- [ ] App description (4000 chars max)
- [ ] Keywords (100 chars max)
- [ ] Support URL
- [ ] Privacy Policy URL
- [ ] App category selected
- [ ] Age rating questionnaire completed
- [ ] Price and availability set

### Submit for Review

1. App Store Connect → Your App → **App Store** tab
2. Click **+** next to iOS/macOS App
3. Select build from dropdown
4. Fill in all required metadata
5. Answer export compliance
6. Click **Add for Review**
7. Click **Submit to App Review**

### Review Timeline

- **Typical:** 24-48 hours
- **First submission:** May take longer
- **Rejections:** Address feedback and resubmit

### Post-Release

- Monitor **Crashes** in App Store Connect
- Respond to **Reviews**
- Plan updates based on feedback

---

## Troubleshooting

### "No accounts with App Store Connect access"
- Ensure you're signed into Xcode with your paid developer Apple ID
- Check App Store Connect access under Users and Access

### "Profile doesn't include entitlement"
- Regenerate provisioning profiles in Xcode
- Or manually in Developer Portal → Profiles

### CloudKit "Permission Failure" in Production
- Ensure schema was deployed (see First Time Setup)
- Check CloudKit Dashboard → Production environment

### Watch App Missing from TestFlight
- Verify "Embed Watch Content" build phase exists
- Check archive includes Watch app in Packages folder
- See `DEV_GUIDE.md` for watch embedding details

### Build Processing Stuck
- Usually resolves in 30 minutes
- If longer, check App Store Connect status page
- Contact Apple Developer Support if >24 hours

---

## Quick Commands Reference

```bash
# Clean build
xcodebuild clean -scheme "RockYou"

# Build for testing
xcodebuild build -scheme "RockYou" -destination "generic/platform=iOS"

# Archive iOS
xcodebuild archive -scheme "RockYou" -destination "generic/platform=iOS" -archivePath ./RockYou.xcarchive

# List available simulators
xcrun simctl list devices

# Validate archive
xcrun altool --validate-app -f RockYou.ipa -t ios -u USER -p PASS
```

---

*Last updated: December 2024*
