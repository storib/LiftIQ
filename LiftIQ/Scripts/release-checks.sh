#!/bin/bash
# release-checks.sh
# Run as an Xcode Build Phase ("Run Script") to catch security issues before release.
# Only enforced in Release configuration; skipped in Debug.

set -euo pipefail

if [ "${CONFIGURATION:-Debug}" != "Release" ]; then
    echo "note: Skipping release checks in ${CONFIGURATION:-Debug} configuration."
    exit 0
fi

ERRORS=0

# ── 1. Ensure GoogleService-Info.plist is present ──
PLIST="${BUILT_PRODUCTS_DIR}/${PRODUCT_NAME}.app/GoogleService-Info.plist"
if [ ! -f "$PLIST" ]; then
    echo "error: GoogleService-Info.plist is missing from the app bundle. Add your production Firebase config."
    ERRORS=$((ERRORS + 1))
fi

# ── 2. Reject placeholder/debug Firebase config ──
if [ -f "$PLIST" ]; then
    if grep -q "liftiq-debug" "$PLIST" 2>/dev/null; then
        echo "error: GoogleService-Info.plist contains debug project ID 'liftiq-debug'. Use production config for release."
        ERRORS=$((ERRORS + 1))
    fi
    if grep -q "000000000000" "$PLIST" 2>/dev/null; then
        echo "error: GoogleService-Info.plist contains placeholder values. Use production config for release."
        ERRORS=$((ERRORS + 1))
    fi
fi

# ── 3. Ensure PrivacyInfo.xcprivacy is in the bundle ──
PRIVACY="${BUILT_PRODUCTS_DIR}/${PRODUCT_NAME}.app/PrivacyInfo.xcprivacy"
if [ ! -f "$PRIVACY" ]; then
    echo "error: PrivacyInfo.xcprivacy is missing from the app bundle."
    ERRORS=$((ERRORS + 1))
fi

# ── 4. Check for debug print/NSLog statements in Swift source ──
# Allow os_log and Logger (structured logging), flag print() and NSLog()
SWIFT_SOURCES=$(find "${SRCROOT}/LiftIQ" -name "*.swift" -not -path "*/Tests/*" -not -path "*/.build/*")
DEBUG_PRINTS=$(echo "$SWIFT_SOURCES" | xargs grep -n '\bprint(' 2>/dev/null | grep -v '^\s*//' | grep -v 'MARK' || true)
if [ -n "$DEBUG_PRINTS" ]; then
    echo "warning: Found print() statements in release build. Consider removing:"
    echo "$DEBUG_PRINTS" | head -10
    # Warning only — uncomment next line to make it a hard error:
    # ERRORS=$((ERRORS + 1))
fi

NSLOG_CALLS=$(echo "$SWIFT_SOURCES" | xargs grep -n '\bNSLog(' 2>/dev/null | grep -v '^\s*//' || true)
if [ -n "$NSLOG_CALLS" ]; then
    echo "error: Found NSLog() statements in release build. Remove before shipping."
    echo "$NSLOG_CALLS" | head -10
    ERRORS=$((ERRORS + 1))
fi

# ── 5. Check for hardcoded API keys or secrets in Swift source ──
SECRET_PATTERNS='(api[_-]?key|secret|password|token)\s*[:=]\s*"[^"]{10,}'
HARDCODED_SECRETS=$(echo "$SWIFT_SOURCES" | xargs grep -inE "$SECRET_PATTERNS" 2>/dev/null | grep -v '^\s*//' | grep -v 'placeholder\|example\|000000' || true)
if [ -n "$HARDCODED_SECRETS" ]; then
    echo "error: Possible hardcoded secrets found in source:"
    echo "$HARDCODED_SECRETS" | head -5
    ERRORS=$((ERRORS + 1))
fi

# ── Result ──
if [ $ERRORS -gt 0 ]; then
    echo "error: Release checks failed with $ERRORS error(s). Fix the issues above before shipping."
    exit 1
fi

echo "note: All release checks passed."
exit 0
