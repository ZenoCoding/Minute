---
description: Build a Release version of the Minute app and package it for distribution.
---
# Build Release

1.  **Clean and Build**
    ```sh
    # Clean previous builds
    xcodebuild clean -project Minute.xcodeproj -scheme Minute -configuration Release
    
    # Build for formatting (using Release config)
    xcodebuild -project Minute.xcodeproj -scheme Minute -configuration Release -derivedDataPath ./Build/DerivedData build
    ```

2.  **Package**
    ```sh
    # Create output directory
    mkdir -p ./Releases
    
    # Copy .app to Releases
    cp -R ./Build/DerivedData/Build/Products/Release/Minute.app ./Releases/Minute.app
    
    # Zip it
    cd Releases
    zip -r Minute.zip Minute.app
    ```

3.  **Completion**
    You can now send `./Releases/Minute.zip` to others.
    *Note: Since this is a specialized build, recipients may need to right-click open the app to bypass Gatekeeper strict checks depending on signing.*
