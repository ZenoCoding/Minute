# Minute iOS sync integration

The macOS and iOS targets now opt into the same private CloudKit container,
`iCloud.com.tychoyoung.Minute`.

## Current behavior

- `MinuteModelContainerFactory` is the shared entry point for local, in-memory, and private CloudKit configurations.
- `MinuteApp` preserves `MinuteStoreLocation.resolvedURL()` while enabling CloudKit on that existing store, avoiding a second empty macOS database.
- Unsandboxed CLI/local builds (or launches with `MINUTE_DISABLE_CLOUDKIT=1`) retain the explicit local-only configuration because they cannot carry production iCloud entitlements.
- `MinuteIOSApp` uses the shared private CloudKit configuration and its platform-default local store.
- Tests use `.inMemory` and never require iCloud.
- `MinuteNotificationCoordinator` reconciles all due, incomplete tasks after local `ModelContext.didSave` notifications and `NSPersistentStoreRemoteChange` notifications. The UserNotifications adapter is conditional, so the shared source remains usable by macOS and iOS targets.

## Remaining release and device steps

The project declares the CloudKit, push-notification, background remote-notification,
and App Group entitlements in source. Xcode and the Apple Developer portal still need
to provision those capabilities for the team. Before release, back up the Mac store,
initialize and inspect the development schema in CloudKit Dashboard, verify a
Mac-to-physical-iPhone create/update/complete flow, and promote the schema to
production. Compilation and in-memory tests do not prove account provisioning,
CloudKit delivery, preserved-store migration, or widget refresh behavior on hardware.

The Xcode project file is intentionally unchanged; the target-owning task must add the iOS/widget targets and entitlements.
