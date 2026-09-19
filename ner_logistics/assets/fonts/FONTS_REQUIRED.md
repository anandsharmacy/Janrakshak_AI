# Required Font Files

Download these font files and place them in this directory (`assets/fonts/`).

## Public Sans
Download from: https://fonts.google.com/specimen/Public+Sans
Required files:
- PublicSans-Regular.ttf    (weight 400)
- PublicSans-Medium.ttf     (weight 500)
- PublicSans-SemiBold.ttf   (weight 600)
- PublicSans-Bold.ttf       (weight 700)
- PublicSans-ExtraBold.ttf  (weight 800)

## Noto Sans
Download from: https://fonts.google.com/noto/specimen/Noto+Sans
Required files:
- NotoSans-Regular.ttf   (weight 400)
- NotoSans-Medium.ttf    (weight 500)
- NotoSans-SemiBold.ttf  (weight 600)
- NotoSans-Bold.ttf      (weight 700)

## Quick download (PowerShell)
Run from the project root:

```powershell
# Install via flutter pub (recommended)
flutter pub add google_fonts

# Or download directly from Google Fonts and rename files as above.
```

## Note
Until font files are present, the app will fall back to the system default
sans-serif. All text styles will still render with correct weights — only the
typeface will differ from the final design.
