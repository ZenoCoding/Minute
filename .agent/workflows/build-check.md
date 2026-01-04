---
description: Build and verify the Minute macOS app compiles without errors
---

# Build Verification Workflow

// turbo-all

1. Navigate to project directory
```bash
cd /Users/tycho/Projects/Minute
```

2. Clean build folder (optional, for fresh builds)
```bash
xcodebuild clean -scheme Minute -configuration Debug -quiet
```

3. Build the project and check for errors
```bash
xcodebuild build -scheme Minute -configuration Debug -quiet 2>&1 | tail -20
```

4. If build succeeds, output will end with `BUILD SUCCEEDED`
5. If build fails, review errors and fix them

## Quick Build Check (recommended)
For fast verification after code changes:
```bash
xcodebuild build -scheme Minute -configuration Debug -quiet 2>&1 | grep -E "(error:|warning:|BUILD)"
```

This will only show errors, warnings, and the final build status.
